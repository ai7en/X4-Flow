import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/services.dart';

class ConvertedGlyph {
  final int codePoint;
  final int width;
  final int height;
  final int advanceX;
  final int left;
  final int top;
  final Uint8List bitmap;

  ConvertedGlyph({
    required this.codePoint,
    required this.width,
    required this.height,
    required this.advanceX,
    required this.left,
    required this.top,
    required this.bitmap,
  });
}

class FontMetrics {
  final int advanceY;
  final int ascender;
  final int descender;

  FontMetrics({
    required this.advanceY,
    required this.ascender,
    required this.descender,
  });
}

enum FontStyle { regular, bold, italic, boldItalic }

class NativeFontConverter {
  static const String magic = 'CPFONT\x00\x00';
  static const int headerSize = 32;
  static const int styleTocSize = 32;
  static const int intervalSize = 12;
  static const int glyphSize = 16;

    Future<Map<int, Uint8List>> convert({
    required Uint8List regularFont,
    Uint8List? boldFont,
    Uint8List? italicFont,
    Uint8List? boldItalicFont,
    required String fontFamily,
    required List<int> sizes,
    required List<List<int>> intervals,
    bool is2Bit = true,
    void Function(int current, int total)? onProgress,
  }) async {
    await _registerFont(regularFont, fontFamily);
    if (boldFont != null) await _registerFont(boldFont, '$fontFamily Bold');
    if (italicFont != null) await _registerFont(italicFont, '$fontFamily Italic');
    if (boldItalicFont != null) {
      await _registerFont(boldItalicFont, '$fontFamily Bold Italic');
    }

    await Future.delayed(const Duration(milliseconds: 500));

    final activeSizes = sizes.isNotEmpty ? sizes : [12, 14, 16, 18];
    final Map<int, Uint8List> results = {};

    for (final fontSizePt in activeSizes) {
      // 🎯 ФИКС: сравнение с эталонным .cpfont от crosspointreader.com/fonts
      // показало, что при одинаковом номинальном размере (20) наш ascender
      // получался РОВНО в 2 раза меньше эталонного (21 против 42) — то есть
      // прежний коэффициент 1.05 давал вдвое меньший физический размер
      // глифов, чем ожидает устройство. 2.1 = 1.05 × 2, подобрано по точному
      // отношению эталонных метрик (42/20 = 2.1).
      final double renderSize = fontSizePt * 2.1;

      final regularGlyphs = await _rasterizeStyle(
        fontFamilyName: fontFamily,
        renderSize: renderSize,
        intervals: intervals,
        is2Bit: is2Bit,
        forceBold: false,
        forceItalic: false,
      );

      final boldGlyphs = await _rasterizeStyle(
        fontFamilyName: boldFont != null ? '$fontFamily Bold' : fontFamily,
        renderSize: renderSize,
        intervals: intervals,
        is2Bit: is2Bit,
        forceBold: boldFont == null,
        forceItalic: false,
      );

      final italicGlyphs = await _rasterizeStyle(
        fontFamilyName: italicFont != null ? '$fontFamily Italic' : fontFamily,
        renderSize: renderSize,
        intervals: intervals,
        is2Bit: is2Bit,
        forceBold: false,
        forceItalic: italicFont == null,
      );

      final boldItalicGlyphs = await _rasterizeStyle(
        fontFamilyName: boldItalicFont != null
            ? '$fontFamily Bold Italic'
            : (boldFont != null ? '$fontFamily Bold' : fontFamily),
        renderSize: renderSize,
        intervals: intervals,
        is2Bit: is2Bit,
        forceBold: boldItalicFont == null,
        forceItalic: boldItalicFont == null,
      );

      final metrics = await _computeFontMetrics(
        fontFamilyName: fontFamily,
        renderSize: renderSize,
      );

      final binaryData = _compileBinary(
        intervals: intervals,
        metrics: metrics,
        styleGlyphs: {
          FontStyle.regular: regularGlyphs,
          FontStyle.bold: boldGlyphs,
          FontStyle.italic: italicGlyphs,
          FontStyle.boldItalic: boldItalicGlyphs,
        },
        is2Bit: is2Bit,
      );

      results[fontSizePt] = binaryData;
      if (onProgress != null) {
        onProgress(activeSizes.indexOf(fontSizePt) + 1, activeSizes.length);
      }
    }

    return results;
  }

  Future<void> _registerFont(Uint8List fontData, String familyName) async {
    final fontLoader = FontLoader(familyName);
    fontLoader.addFont(Future.value(ByteData.sublistView(fontData)));
    await fontLoader.load();
  }

  Future<FontMetrics> _computeFontMetrics({
    required String fontFamilyName,
    required double renderSize,
  }) async {
    final paragraphStyle = ui.ParagraphStyle(
      textDirection: ui.TextDirection.ltr,
      fontFamily: fontFamilyName,
      fontSize: renderSize,
    );

    final textStyle = ui.TextStyle(
      fontFamily: fontFamilyName,
      fontSize: renderSize,
      color: const ui.Color(0xFF000000),
    );

    final pb = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(textStyle)
      ..addText('Hg');

    final paragraph = pb.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));

    final double baseline = paragraph.alphabeticBaseline;
    final double height = paragraph.height;

    return FontMetrics(
      advanceY: height.round().clamp(1, 255),
      ascender: baseline.round().clamp(-32768, 32767),
      descender: (baseline - height).round().clamp(-32768, 32767),
    );
  }

  Future<List<ConvertedGlyph>> _rasterizeStyle({
    required String fontFamilyName,
    required double renderSize,
    required List<List<int>> intervals,
    required bool is2Bit,
    required bool forceBold,
    required bool forceItalic,
  }) async {
    final List<int> codePoints = [];
    for (final interval in intervals) {
      for (int cp = interval[0]; cp <= interval[1]; cp++) {
        codePoints.add(cp);
      }
    }

    final List<ConvertedGlyph> glyphs = [];
    for (final cp in codePoints) {
      final glyph = await _rasterizeGlyph(
        cp: cp,
        fontFamily: fontFamilyName,
        renderSize: renderSize,
        is2Bit: is2Bit,
        forceBold: forceBold,
        forceItalic: forceItalic,
      );
      glyphs.add(glyph);
    }
    return glyphs;
  }

  /// 🎯 ПЕРЕПИСАНО:
  ///  1) advanceX теперь пишется в 1/16 px fixed-point (как того требует
  ///     формат — см. `adv/16` в тестовом скрипте cpfont_engine.py). Раньше
  ///     писался как обычный px, из-за чего advance был в 16 раз меньше
  ///     нужного и буквы должны были почти слипаться на устройстве.
  ///  2) Растеризация теперь обрезается по фактическому bounding box чернил
  ///     (tight crop), а не сохраняет пустой квадрат renderSize*3 целиком —
  ///     это в разы уменьшает размер .cpfont и нагрузку на RAM ESP32-C3
  ///     при парсинге на устройстве. left/top при этом стали настоящими
  ///     смещениями bbox от пера/базовой линии, а не константами (0, baseline)
  ///     на все глифы стиля.
  ///  3) Канвас рисуется с запасом по краям (margin), чтобы засечки/наклон
  ///     курсива, выходящие за пределы advance-width, не обрезались раньше
  ///     времени — обрезка по чернилам всё равно уберёт лишнее поле.
  Future<ConvertedGlyph> _rasterizeGlyph({
    required int cp,
    required String fontFamily,
    required double renderSize,
    required bool is2Bit,
    required bool forceBold,
    required bool forceItalic,
  }) async {
    final charStr = String.fromCharCode(cp);

    final textStyle = ui.TextStyle(
      fontFamily: fontFamily,
      fontSize: renderSize,
      color: const ui.Color(0xFF000000),
      fontWeight: forceBold ? ui.FontWeight.bold : ui.FontWeight.normal,
      fontStyle: forceItalic ? ui.FontStyle.italic : ui.FontStyle.normal,
    );

    final paragraphStyle = ui.ParagraphStyle(
      textDirection: ui.TextDirection.ltr,
    );

    final pb = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(textStyle)
      ..addText(charStr);

    final paragraph = pb.build()
      ..layout(const ui.ParagraphConstraints(width: double.infinity));

    final double advanceMeasured = paragraph.longestLine;
    final double lineHeight = paragraph.height;
    final double baseline = paragraph.alphabeticBaseline;
    final int advance16 = (advanceMeasured * 16).round().clamp(0, 65535);

    // Пробел и подобные — не рисуем вообще, просто продвижение пера.
    final bool isBlank = cp == 0x20 || cp == 0xA0 || charStr.trim().isEmpty;
    if (isBlank) {
      return ConvertedGlyph(
        codePoint: cp,
        width: 0,
        height: 0,
        advanceX: advance16,
        left: 0,
        top: 0,
        bitmap: Uint8List(0),
      );
    }

    // Запас по краям канваса под курсив/засечки, вылезающие за advance-width.
    final int margin = (renderSize * 0.5).ceil().clamp(4, 64);
    final int canvasW = (advanceMeasured.ceil() + margin * 2).clamp(1, 512);
    final int canvasH = (lineHeight.ceil() + margin * 2).clamp(1, 512);

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, canvasW.toDouble(), canvasH.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.drawParagraph(paragraph, ui.Offset(margin.toDouble(), margin.toDouble()));

    final picture = recorder.endRecording();
    final img = await picture.toImage(canvasW, canvasH);
    final byteData = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    picture.dispose();

    if (byteData == null) {
      return ConvertedGlyph(
        codePoint: cp,
        width: 0,
        height: 0,
        advanceX: advance16,
        left: 0,
        top: 0,
        bitmap: Uint8List(0),
      );
    }

    final buffer = byteData.buffer.asUint8List();

    // Полная серая карта канваса + поиск tight bounding box чернил.
    final gray = Uint8List(canvasW * canvasH);
    int minX = canvasW, minY = canvasH, maxX = -1, maxY = -1;
    for (int y = 0; y < canvasH; y++) {
      for (int x = 0; x < canvasW; x++) {
        final offset = (y * canvasW + x) * 4;
        final r = buffer[offset];
        final g = buffer[offset + 1];
        final b = buffer[offset + 2];
        final brightness = (r * 299 + g * 587 + b * 114) ~/ 1000;
        final ink = 255 - brightness;
        gray[y * canvasW + x] = ink;
        if (ink > 10) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }

    if (maxX < 0) {
      // Чернил нет (в шрифте нет такого глифа, или он реально пуст) —
      // не пробел, но и растра нет. Отдаём пустой глиф с advance.
      return ConvertedGlyph(
        codePoint: cp,
        width: 0,
        height: 0,
        advanceX: advance16,
        left: 0,
        top: 0,
        bitmap: Uint8List(0),
      );
    }

    final glyphWidth = (maxX - minX + 1).clamp(1, 255);
    final glyphHeight = (maxY - minY + 1).clamp(1, 255);

    List<int> cropped = List<int>.filled(glyphWidth * glyphHeight, 0);
    for (int y = 0; y < glyphHeight; y++) {
      for (int x = 0; x < glyphWidth; x++) {
        cropped[y * glyphWidth + x] = gray[(minY + y) * canvasW + (minX + x)];
      }
    }

    cropped = _applyGapFix(cropped, glyphWidth, glyphHeight);
    final Uint8List packedBitmap = _packBitmap(cropped, is2Bit);

    // left/top — смещения tight-bbox от пера (x=0) и от базовой линии,
    // с поправкой на добавленный margin канваса.
    final int left = minX - margin;
    // 🎯 ФИКС: сравнение с эталонным .cpfont показало, что знак top
    // инвертирован. Формат хранит top как расстояние от базовой линии
    // ВВЕРХ до верхнего края чернил, со знаком "+" (например у эталонной
    // буквы 'A' top=+29). Раньше здесь вычиталось наоборот (minY-baseline),
    // что для обычных букв всегда даёт отрицательное число — ровно
    // противоположный знак тому, что ждёт устройство.
    final int top = (baseline - (minY - margin)).round().clamp(-32768, 32767);

    return ConvertedGlyph(
      codePoint: cp,
      width: glyphWidth,
      height: glyphHeight,
      advanceX: advance16,
      left: left,
      top: top,
      bitmap: packedBitmap,
    );
  }

  List<int> _applyGapFix(List<int> gray, int width, int height) {
    final result = List<int>.from(gray);
    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        int idx = y * width + x;
        if (gray[idx] < 50) {
          if ((gray[idx - 1] > 200 && gray[idx + 1] > 200) ||
              (gray[idx - width] > 200 && gray[idx + width] > 200)) {
            result[idx] = 220;
          }
        }
      }
    }
    return result;
  }

  /// 🎯 ИСПРАВЛЕНО ПОВТОРНО: подтверждённая таблица из исходников прошивки
  /// (GfxRenderer.cpp) показывает, что устройство САМО инвертирует сырой
  /// байт при рендере (render = 3 - raw): raw=0x00 → рендер-значение 3
  /// → "пропустить (фон)"; raw=0x11(=3) → рендер-значение 0 → "нарисовать
  /// чёрным". То есть в ФАЙЛЕ нужно хранить ПРЯМУЮ шкалу (0=фон, 3=чернила),
  /// а не инвертированную. Прошлый фикс инвертировал её ЗАРАНЕЕ, из-за чего
  /// прошивка применяла свою инверсию поверх уже инвертированных данных —
  /// в сумме двойная инверсия давала "чёрный прямоугольник с белой буквой
  /// внутри" (фон рисовался чёрным, чернила становились прозрачными).
  Uint8List _packBitmap(List<int> gray, bool is2Bit) {
    final List<int> packed = [];
    int currentByte = 0;
    int bitsCount = 0;

    for (int alpha in gray) {
      if (is2Bit) {
        // alpha: 0 = фон/белый, 255 = максимально тёмные чернила.
        // val:   0 = фон,       3 = максимально тёмные чернила (прямая шкала).
        int val = (alpha ~/ 64).clamp(0, 3);
        currentByte = (currentByte << 2) | val;
        bitsCount += 2;
      } else {
        int bit = (alpha > 127) ? 1 : 0;
        currentByte = (currentByte << 1) | bit;
        bitsCount += 1;
      }
      if (bitsCount == 8) {
        packed.add(currentByte);
        currentByte = 0;
        bitsCount = 0;
      }
    }
    if (bitsCount > 0) {
      if (is2Bit) {
        currentByte = currentByte << ((4 - (bitsCount ~/ 2)) * 2);
      } else {
        currentByte = currentByte << (8 - bitsCount);
      }
      packed.add(currentByte);
    }
    return Uint8List.fromList(packed);
  }

  Uint8List _compileBinary({
    required List<List<int>> intervals,
    required FontMetrics metrics,
    required Map<FontStyle, List<ConvertedGlyph>> styleGlyphs,
    required bool is2Bit,
  }) {
    final int numStyles = 4;
    final int intervalCount = intervals.length;

    final Map<FontStyle, int> styleDataSizes = {};
    for (final style in FontStyle.values) {
      final glyphs = styleGlyphs[style]!;
      int bitmapsSize = 0;
      for (final g in glyphs) {
        bitmapsSize += g.bitmap.length;
      }
      final dataSize = (intervalCount * intervalSize) +
          (glyphs.length * glyphSize) +
          bitmapsSize;
      styleDataSizes[style] = dataSize;
    }

    int totalDataSize = 0;
    for (final size in styleDataSizes.values) {
      totalDataSize += size;
    }
    final int totalSize = headerSize + (numStyles * styleTocSize) + totalDataSize;

    final Uint8List buffer = Uint8List(totalSize);
    final ByteData view = ByteData.sublistView(buffer);
    int offset = 0;

    // === 1. HEADER (32 байта) ===
    for (int i = 0; i < magic.length; i++) {
      buffer[offset++] = magic.codeUnitAt(i);
    }
    // version = 4 (uint16) — байты 8-9
    view.setUint16(offset, 4, Endian.little);
    offset += 2;
    // flags — байты 10-11. Судя по всему бит 0 кодирует режим 2-bit/1-bit
    // (по аналогии с полем is2Bit в родственном формате EPDFont того же
    // семейства инструментов) — раньше здесь был жёстко прибитый 1
    // независимо от реального is2Bit, теперь привязано к параметру.
    view.setUint16(offset, is2Bit ? 1 : 0, Endian.little);
    offset += 2;
    // styleCount = 4 (uint8) — байт 12, затем 19 зарезервированных байт (13-31)
    view.setUint8(offset, numStyles);
    offset += 1;
    offset += 19;

    // === 2. STYLE TOC (4 × 32 байта) ===
    int currentDataOffset = headerSize + (numStyles * styleTocSize);
    final Map<FontStyle, int> styleOffsets = {};
    for (final style in FontStyle.values) {
      styleOffsets[style] = currentDataOffset;
      currentDataOffset += styleDataSizes[style]!;
    }

    for (final style in FontStyle.values) {
      final glyphs = styleGlyphs[style]!;

      view.setUint8(offset, style.index);
      offset += 1;
      offset += 3;
      view.setUint32(offset, intervalCount, Endian.little);
      offset += 4;
      view.setUint32(offset, glyphs.length, Endian.little);
      offset += 4;
      view.setUint8(offset, metrics.advanceY.clamp(0, 255));
      offset += 1;
      view.setInt16(offset, metrics.ascender.clamp(-32768, 32767), Endian.little);
      offset += 2;
      view.setInt16(offset, metrics.descender.clamp(-32768, 32767), Endian.little);
      offset += 2;
      view.setUint16(offset, 0, Endian.little);
      offset += 2;
      view.setUint16(offset, 0, Endian.little);
      offset += 2;
      view.setUint8(offset, 0);
      offset += 1;
      view.setUint8(offset, 0);
      offset += 1;
      view.setUint8(offset, 0);
      offset += 1;
      view.setUint32(offset, styleOffsets[style]!, Endian.little);
      offset += 4;
      offset += 4;
    }

    // === 3. ДАННЫЕ КАЖДОГО СТИЛЯ ===
    for (final style in FontStyle.values) {
      final glyphs = styleGlyphs[style]!;

      int glyphIndex = 0;
      for (final interval in intervals) {
        view.setUint32(offset, interval[0], Endian.little);
        offset += 4;
        view.setUint32(offset, interval[1], Endian.little);
        offset += 4;
        view.setUint32(offset, glyphIndex, Endian.little);
        offset += 4;
        glyphIndex += (interval[1] - interval[0] + 1);
      }

      int currentBitmapOffset = 0;
      for (final glyph in glyphs) {
        buffer[offset++] = glyph.width & 0xFF;
        buffer[offset++] = glyph.height & 0xFF;
        view.setUint16(offset, glyph.advanceX.clamp(0, 65535), Endian.little);
        offset += 2;
        view.setInt16(offset, glyph.left.clamp(-32768, 32767), Endian.little);
        offset += 2;
        view.setInt16(offset, glyph.top.clamp(-32768, 32767), Endian.little);
        offset += 2;
        view.setUint16(offset, glyph.bitmap.length.clamp(0, 65535), Endian.little);
        offset += 2;
        offset += 2;
        view.setUint32(offset, currentBitmapOffset, Endian.little);
        offset += 4;
        currentBitmapOffset += glyph.bitmap.length;
      }

      for (final glyph in glyphs) {
        buffer.setRange(offset, offset + glyph.bitmap.length, glyph.bitmap);
        offset += glyph.bitmap.length;
      }
    }

    return buffer;
  }
}
