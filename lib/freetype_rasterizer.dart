// ═══════════════════════════════════════════════════════════════════════
// freetype_rasterizer.dart — растеризация глифов через настоящий FreeType
// (с хинтингом), вместо dart:ui/Skia.
// ═══════════════════════════════════════════════════════════════════════
//
// Мотивация: dart:ui/Skia не даёт контроля над hint-программой шрифта —
// поэтому мы имитировали "чистоту" мелких размеров через подбор ppem
// (stem calibration) и контрастную растяжку постфактум. Официальный
// конвертер CrossPoint использует FreeType напрямую (флаг
// --force-autohint), что и даёт по-настоящему подогнанные под пиксельную
// сетку штрихи. Этот файл — растеризация ТОЛЬКО через FreeType, встраиваемая
// как альтернативный бэкенд в существующий конвейер (интервалы/кернинг/
// лигатуры/упаковка в .cpfont остаются прежними, не зависят от рендерера).
//
// Структуры FT_Bitmap/FT_GlyphSlotRec и сигнатуры функций НЕ написаны
// руками — это сгенерированный ffigen-биндинг (generated_bindings.dart),
// собранный из настоящих заголовков FreeType под целевые архитектуры.
// Здесь используется только логика поверх готовых, проверенных биндингов.

import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart' as pkg_ffi;
import 'generated_bindings.dart';

/// Результат растеризации одного глифа через FreeType — совпадает по
/// смыслу полей с ConvertedGlyph из native_font_converter.dart, чтобы
/// его можно было напрямую подставить в существующий конвейер упаковки.
class FreeTypeGlyphResult {
  final int width;
  final int height;
  final int advance16; // 1/16 px fixed-point, как того требует формат .cpfont
  final int left;
  final int top; // FreeType: положительный = выше базовой линии — уже в нужной конвенции
  final Uint8List coverage; // w*h байт, 0..255 (0=фон, 255=чернила) — та же конвенция, что и наш dart:ui-путь

  FreeTypeGlyphResult({
    required this.width,
    required this.height,
    required this.advance16,
    required this.left,
    required this.top,
    required this.coverage,
  });

  static FreeTypeGlyphResult empty(int advance16) => FreeTypeGlyphResult(
        width: 0,
        height: 0,
        advance16: advance16,
        left: 0,
        top: 0,
        coverage: Uint8List(0),
      );
}

/// Загружает libfreetype.so и оборачивает низкоуровневые FFI-вызовы.
/// Один экземпляр держит открытым один "face" (одно начертание одного
/// шрифта) — для каждого стиля (regular/bold/italic/boldItalic) нужен
/// свой экземпляр, переиспользуемый на все codepoint'ы этого стиля
/// (открывать/закрывать face на каждый глиф было бы очень расточительно).
class FreeTypeRasterizer {
  static ffi.DynamicLibrary? _sharedLib;
  static FreeTypeBindings? _sharedBindings;
  static ffi.Pointer<FT_LibraryRec_>? _sharedLibraryHandle;

  late final FT_Face _face;
  late final ffi.Pointer<ffi.Uint8> _fontBytesPtr;
  bool _closed = false;

  FreeTypeRasterizer._(this._face, this._fontBytesPtr);

  /// Инициализирует (один раз на процесс) библиотеку FreeType и грузит
  /// один face из байтов шрифта. Бросает исключение, если библиотека не
  /// нашлась/не загрузилась или шрифт не распарсился — вызывающий код
  /// должен поймать это и откатиться на dart:ui-путь (safe fallback).
  static FreeTypeRasterizer load(Uint8List fontBytes) {
    if (_sharedBindings == null) {
      final lib = _openLibrary();
      final bindings = FreeTypeBindings(lib);
      final libraryHandlePtr = pkg_ffi.calloc<FT_Library>();
      final initError = bindings.FT_Init_FreeType(libraryHandlePtr);
      if (initError != 0) {
        pkg_ffi.calloc.free(libraryHandlePtr);
        throw Exception('FT_Init_FreeType failed: код $initError');
      }
      _sharedLib = lib;
      _sharedBindings = bindings;
      _sharedLibraryHandle = libraryHandlePtr.value;
      pkg_ffi.calloc.free(libraryHandlePtr);
    }

    final bindings = _sharedBindings!;
    final libraryHandle = _sharedLibraryHandle!;

    // Копируем байты шрифта в нативную память — FreeType должен иметь к
    // ним доступ всё время жизни face, а обычный Dart Uint8List может
    // быть перемещён GC, поэтому копируем в calloc-память вручную.
    final fontBytesPtr = pkg_ffi.calloc<ffi.Uint8>(fontBytes.length);
    fontBytesPtr.asTypedList(fontBytes.length).setAll(0, fontBytes);

    final facePtrPtr = pkg_ffi.calloc<FT_Face>();
    final newFaceError = bindings.FT_New_Memory_Face(
      libraryHandle,
      fontBytesPtr.cast<FT_Byte>(),
      fontBytes.length,
      0,
      facePtrPtr,
    );
    final face = facePtrPtr.value;
    pkg_ffi.calloc.free(facePtrPtr);

    if (newFaceError != 0) {
      pkg_ffi.calloc.free(fontBytesPtr);
      throw Exception('FT_New_Memory_Face failed: код $newFaceError (шрифт повреждён или формат не поддержан)');
    }

    return FreeTypeRasterizer._(face, fontBytesPtr);
  }

  static ffi.DynamicLibrary _openLibrary() {
    // На Android SONAME собранной библиотеки — libfreetype.so (без
    // версии в имени, как и положено для jniLibs), поэтому открывается
    // по простому имени, как и любая другая bundled native-библиотека.
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libfreetype.so');
    }
    // На других платформах (тестирование на десктопе) — по возможности
    // берём системную библиотеку, если она есть.
    if (Platform.isLinux) return ffi.DynamicLibrary.open('libfreetype.so.6');
    if (Platform.isMacOS) return ffi.DynamicLibrary.open('libfreetype.dylib');
    if (Platform.isWindows) return ffi.DynamicLibrary.open('freetype.dll');
    throw UnsupportedError('FreeType не поддержан на этой платформе');
  }

  /// Устанавливает размер рендера в ПИКСЕЛЯХ (ppem) — вызывать перед
  /// каждой новой партией растеризации под конкретный renderSize/стиль.
  void setPixelSize(int ppem) {
    _sharedBindings!.FT_Set_Pixel_Sizes(_face, 0, ppem);
  }

  /// Растеризует один codepoint. loadFlags по умолчанию повторяют
  /// --force-autohint официального конвертера CrossPoint — тестер
  /// подтвердил, что результат "как у официального" именно с этим путём.
  /// Если у codepoint нет глифа в шрифте (index=0, обычно notdef) —
  /// возвращает null, чтобы вызывающий код мог трактовать это как
  /// "символа нет" (как и в dart:ui-пути).
  /// forceAutohint=false (по умолчанию теперь) — используем РОДНЫЕ хинты
  /// шрифта, если они есть. Отзыв реального тестера показал: и
  /// force-autohint, и наша stem-калибровка одинаково "мылят" именно
  /// ЗАКРУГЛЕНИЯ (дуги 'm', 'o', 'e') частично — оба метода настроены
  /// на прямые вертикальные штрихи и не думают о кривых. Автохинтер —
  /// общий эвристический хинтер, обычно уступающий по качеству
  /// вручную настроенным хинтам самого шрифта на сложных формах.
  FreeTypeGlyphResult? rasterize(int codepoint, {bool forceAutohint = false}) {
    final bindings = _sharedBindings!;

    final glyphIndex = bindings.FT_Get_Char_Index(_face, codepoint);
    if (glyphIndex == 0) return null; // символа нет в шрифте

    int loadFlags = FT_LOAD_RENDER | FT_LOAD_TARGET_LIGHT;
    if (forceAutohint) loadFlags |= FT_LOAD_FORCE_AUTOHINT;

    final loadError = bindings.FT_Load_Glyph(_face, glyphIndex, loadFlags);
    if (loadError != 0) return null;

    final slot = _face.ref.glyph;
    final bitmap = slot.ref.bitmap;
    final advance16 = ((slot.ref.advance.x) * 16 / 64.0).round().clamp(0, 65535);

    if (bitmap.rows == 0 || bitmap.width == 0) {
      // Пустой глиф (например пробел) — валидный результат с нулевым растром.
      return FreeTypeGlyphResult.empty(advance16);
    }

    final int w = bitmap.width;
    final int h = bitmap.rows;
    final int pitch = bitmap.pitch;
    final coverage = Uint8List(w * h);

    // pitch может быть отрицательным (bottom-up bitmap) — обрабатываем оба случая.
    // 🎯 Приводим UnsignedChar* к Uint8* явно: они побитово идентичны на всех
    // реальных ABI (char беззнаковый на ARM), но у Uint8* гарантированно
    // есть asTypedList()/elementAt() во всех версиях dart:ffi, а у
    // Abi-specific UnsignedChar это не хотелось проверять вслепую.
    final absPitch = pitch.abs();
    final rowBuffer = bitmap.buffer.cast<ffi.Uint8>();
    for (int y = 0; y < h; y++) {
      final int srcRow = pitch >= 0 ? y : (h - 1 - y);
      final rowPtr = rowBuffer.elementAt(srcRow * absPitch);
      final rowList = rowPtr.asTypedList(w);
      coverage.setRange(y * w, y * w + w, rowList);
    }

    return FreeTypeGlyphResult(
      width: w,
      height: h,
      advance16: advance16,
      left: slot.ref.bitmap_left,
      top: slot.ref.bitmap_top, // уже "положительный = выше базовой линии", как и ждёт формат .cpfont
      coverage: coverage,
    );
  }

  /// Освобождает face и скопированные байты шрифта. Саму библиотеку/
  /// FT_Library держим открытой на весь процесс (переиспользуется между
  /// стилями/размерами) — закрывать её не нужно между вызовами.
  void dispose() {
    if (_closed) return;
    _closed = true;
    _sharedBindings?.FT_Done_Face(_face);
    pkg_ffi.calloc.free(_fontBytesPtr);
  }
}
