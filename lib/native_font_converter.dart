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

/// Один "кандидат" на стандартную латинскую лигатуру: пара кодовых точек →
/// результирующая кодовая точка лигатуры (стандартный блок Unicode
/// "Alphabetic Presentation Forms", U+FB00-FB06). Порядок важен: ffi/ffl
/// зависят от того, что "ff" (U+FB00) уже принята для этого стиля — так
/// повторяется greedy-алгоритм устройства (сначала f+f→ff, потом ff+i→ffi).
class LigatureCandidate {
  final int leftCp;
  final int rightCp;
  final int resultCp;
  const LigatureCandidate(this.leftCp, this.rightCp, this.resultCp);
}

const List<LigatureCandidate> kLigatureCandidates = [
  LigatureCandidate(0x0066, 0x0066, 0xFB00), // f + f = ff
  LigatureCandidate(0x0066, 0x0069, 0xFB01), // f + i = fi
  LigatureCandidate(0x0066, 0x006C, 0xFB02), // f + l = fl
  LigatureCandidate(0xFB00, 0x0069, 0xFB03), // ff + i = ffi
  LigatureCandidate(0xFB00, 0x006C, 0xFB04), // ff + l = ffl
  LigatureCandidate(0x0073, 0x0074, 0xFB06), // s + t = st
];

class LigatureEntry {
  final int pair; // (leftCp << 16) | rightCp
  final int ligatureCp;
  LigatureEntry(this.pair, this.ligatureCp);
}

/// Список "проблемных" пар букв, для которых обычно нужен кернинг —
/// расширяемый набор типичных случаев (латиница + кириллица). Ничего не
/// парсим из таблиц шрифта — просто рендерим пару и одиночные буквы через
/// dart:ui (Skia сам применяет реальный кернинг шрифта при layout, если он
/// в нём есть) и берём РАЗНИЦУ между шириной пары и суммой одиночных ширин
/// как готовую кернинг-коррекцию.
const List<List<int>> kKerningPairCandidates = [
  // Латиница
  [0x41, 0x56], [0x56, 0x41], // AV VA
  [0x41, 0x57], [0x57, 0x41], // AW WA
  [0x4C, 0x54], [0x54, 0x41], // LT TA
  [0x54, 0x65], [0x54, 0x6F], // Te To
  [0x59, 0x6F], [0x57, 0x65], [0x54, 0x72], // Yo We Tr
  // Кириллица
  [0x413, 0x410], [0x422, 0x410], [0x410, 0x422], // ГА ТА АТ
  [0x410, 0x423], [0x423, 0x410], // АУ УА
  [0x413, 0x415], [0x420, 0x410], [0x410, 0x420], // ГЕ РА АР
  [0x412, 0x410], [0x410, 0x412], // ВА АВ
  [0x422, 0x420], [0x420, 0x422], // ТР РТ
  [0x42C, 0x41E], // ЬО
];

class KerningClassEntry {
  final int codepoint;
  final int classId; // 1-based, 0 зарезервирован как "нет класса"
  KerningClassEntry(this.codepoint, this.classId);
}

/// Итог измерения кернинга для одного стиля: отсортированные по codepoint
/// таблицы левых/правых классов + плоская матрица поправок (int8,
/// leftClassCount × rightClassCount, matrix[(lc-1)*rightCount+(rc-1)]).
class KerningResult {
  final List<KerningClassEntry> leftClasses;
  final List<KerningClassEntry> rightClasses;
  final List<int> matrix;
  final int leftClassCount;
  final int rightClassCount;
  KerningResult({
    required this.leftClasses,
    required this.rightClasses,
    required this.matrix,
    required this.leftClassCount,
    required this.rightClassCount,
  });

  static KerningResult empty() => KerningResult(
        leftClasses: [],
        rightClasses: [],
        matrix: [],
        leftClassCount: 0,
        rightClassCount: 0,
      );
}

/// Результат растеризации одного стиля: глифы + итоговые интервалы
/// (пользовательские + отдельные интервалы под принятые лигатуры, если
/// у этого конкретного шрифта/начертания нашлись соответствующие глифы)
/// + сама таблица лигатурных пар для TOC этого стиля.
class StyleRasterResult {
  final List<ConvertedGlyph> glyphs;
  final List<List<int>> intervals;
  final List<LigatureEntry> ligatures;
  final KerningResult kerning;
  StyleRasterResult({
    required this.glyphs,
    required this.intervals,
    required this.ligatures,
    required this.kerning,
  });
}

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

    // Грубая оценка общего объёма работы для прогресс-бара: размеры × 4
    // начертания × число кодовых точек (лигатуры — единицы штук, ими можно
    // пренебречь в оценке). Реальный счётчик обновляется по ходу растеризации.
    int totalCodePoints = 0;
    for (final interval in intervals) {
      totalCodePoints += (interval[1] - interval[0] + 1);
    }
    final int totalWork = activeSizes.length * 4 * (totalCodePoints > 0 ? totalCodePoints : 1);
    int doneWork = 0;
    void bumpProgress() {
      doneWork++;
      onProgress?.call(doneWork, totalWork);
    }

    for (final fontSizePt in activeSizes) {
      // 🎯 ФИКС: сравнение с эталонным .cpfont от crosspointreader.com/fonts
      // показало, что при одинаковом номинальном размере (20) наш ascender
      // получался РОВНО в 2 раза меньше эталонного (21 против 42) — то есть
      // прежний коэффициент 1.05 давал вдвое меньший физический размер
      // глифов, чем ожидает устройство. 2.1 = 1.05 × 2, подобрано по точному
      // отношению эталонных метрик (42/20 = 2.1).
      final double renderSize = fontSizePt * 2.1;

      final regularResult = await _rasterizeStyle(
        fontFamilyName: fontFamily,
        renderSize: renderSize,
        intervals: intervals,
        is2Bit: is2Bit,
        forceBold: false,
        forceItalic: false,
        onGlyphDone: bumpProgress,
      );

      final boldResult = await _rasterizeStyle(
        fontFamilyName: boldFont != null ? '$fontFamily Bold' : fontFamily,
        renderSize: renderSize,
        intervals: intervals,
        is2Bit: is2Bit,
        forceBold: boldFont == null,
        forceItalic: false,
        onGlyphDone: bumpProgress,
      );

      final italicResult = await _rasterizeStyle(
        fontFamilyName: italicFont != null ? '$fontFamily Italic' : fontFamily,
        renderSize: renderSize,
        intervals: intervals,
        is2Bit: is2Bit,
        forceBold: false,
        forceItalic: italicFont == null,
        onGlyphDone: bumpProgress,
      );

      final boldItalicResult = await _rasterizeStyle(
        fontFamilyName: boldItalicFont != null
            ? '$fontFamily Bold Italic'
            : (boldFont != null ? '$fontFamily Bold' : fontFamily),
        renderSize: renderSize,
        intervals: intervals,
        is2Bit: is2Bit,
        forceBold: boldItalicFont == null,
        forceItalic: boldItalicFont == null,
        onGlyphDone: bumpProgress,
      );

      final metrics = await _computeFontMetrics(
        fontFamilyName: fontFamily,
        renderSize: renderSize,
      );

      final binaryData = _compileBinary(
        metrics: metrics,
        styleResults: {
          FontStyle.regular: regularResult,
          FontStyle.bold: boldResult,
          FontStyle.italic: italicResult,
          FontStyle.boldItalic: boldItalicResult,
        },
        is2Bit: is2Bit,
      );

      results[fontSizePt] = binaryData;
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

  Future<StyleRasterResult> _rasterizeStyle({
  required String fontFamilyName,
  required double renderSize,
  required List<List<int>> intervals,
  required bool is2Bit,
  required bool forceBold,
  required bool forceItalic,
  void Function()? onGlyphDone,
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
    onGlyphDone?.call();
  }

  // 🎯 ЛИГАТУРЫ
  final List<ConvertedGlyph> ligatureGlyphs = [];
  final List<LigatureEntry> ligatures = [];
  final Set<int> acceptedLigatureCps = {};
  
  for (final cand in kLigatureCandidates) {
    final leftIsBasicChar = cand.leftCp < 0xFB00;
    if (!leftIsBasicChar && !acceptedLigatureCps.contains(cand.leftCp)) {
      continue;
    }
    if (codePoints.contains(cand.resultCp)) continue;
    
    final g = await _rasterizeGlyph(
      cp: cand.resultCp,
      fontFamily: fontFamilyName,
      renderSize: renderSize,
      is2Bit: is2Bit,
      forceBold: forceBold,
      forceItalic: forceItalic,
    );
    if (g.width == 0 && g.height == 0) continue;
    
    ligatureGlyphs.add(g);
    acceptedLigatureCps.add(cand.resultCp);
    ligatures.add(LigatureEntry((cand.leftCp << 16) | cand.rightCp, cand.resultCp));
  }

  // 🎯 ОБЪЕДИНЯЕМ: основные глифы + лигатуры
  final allGlyphs = [...glyphs, ...ligatureGlyphs];
  
  // 🎯 СОЗДАЁМ интервалы с учётом лигатур
  final List<List<int>> finalIntervals = List.of(intervals);
  for (final ligCp in acceptedLigatureCps) {
    finalIntervals.add([ligCp, ligCp]);
  }
  
  // 🎯 СОРТИРУЕМ интервалы И глифы синхронно
  final sortedPairs = <MapEntry<List<int>, List<ConvertedGlyph>>>[];
  int glyphIdx = 0;
  for (final interval in finalIntervals) {
    final count = interval[1] - interval[0] + 1;
    final intervalGlyphs = allGlyphs.sublist(glyphIdx, glyphIdx + count);
    sortedPairs.add(MapEntry(interval, intervalGlyphs));
    glyphIdx += count;
  }
  
  // Сортируем по startCodePoint
  sortedPairs.sort((a, b) => a.key[0].compareTo(b.key[0]));
  
  // Восстанавливаем отсортированные интервалы и глифы
  final sortedIntervals = sortedPairs.map((e) => e.key).toList();
  final sortedGlyphs = sortedPairs.expand((e) => e.value).toList();

  final kerning = _measureKerning(
    fontFamilyName: fontFamilyName,
    renderSize: renderSize,
    forceBold: forceBold,
    forceItalic: forceItalic,
  );

  return StyleRasterResult(
    glyphs: sortedGlyphs,
    intervals: sortedIntervals,
    ligatures: ligatures,
    kerning: kerning,
  );
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
  /// Измеряет реальный кернинг шрифта для набора "проблемных" пар через
  /// сравнение ширины пары (после layout, т.е. с учётом shaping/GPOS,
  /// который Skia применяет сама) с суммой ширин одиночных букв. Разница —
  /// это и есть готовая кернинг-коррекция в пикселях данного renderSize,
  /// без необходимости парсить таблицы шрифта вручную.
  KerningResult _measureKerning({
    required String fontFamilyName,
    required double renderSize,
    required bool forceBold,
    required bool forceItalic,
  }) {
    double measureAdvance(String s) {
      final textStyle = ui.TextStyle(
        fontFamily: fontFamilyName,
        fontSize: renderSize,
        color: const ui.Color(0xFF000000),
        fontWeight: forceBold ? ui.FontWeight.bold : ui.FontWeight.normal,
        fontStyle: forceItalic ? ui.FontStyle.italic : ui.FontStyle.normal,
      );
      final pb = ui.ParagraphBuilder(ui.ParagraphStyle(textDirection: ui.TextDirection.ltr))
        ..pushStyle(textStyle)
        ..addText(s);
      final p = pb.build()..layout(const ui.ParagraphConstraints(width: double.infinity));
      return p.longestLine;
    }

    final Map<int, double> singleAdvanceCache = {};
    double singleAdvance(int cp) {
      return singleAdvanceCache.putIfAbsent(cp, () => measureAdvance(String.fromCharCode(cp)));
    }

    final Map<int, int> leftClassOf = {};
    final Map<int, int> rightClassOf = {};
    final List<List<int>> measuredDeltas = []; // [leftCp, rightCp, delta]

    for (final pair in kKerningPairCandidates) {
      final leftCp = pair[0];
      final rightCp = pair[1];
      final together = measureAdvance(
        String.fromCharCode(leftCp) + String.fromCharCode(rightCp),
      );
      final apart = singleAdvance(leftCp) + singleAdvance(rightCp);
      final delta = (together - apart).round();
      if (delta == 0) continue; // нет заметной коррекции — не тратим место в таблице

      if (!leftClassOf.containsKey(leftCp)) {
        leftClassOf[leftCp] = leftClassOf.length + 1; // 1-based
      }
      if (!rightClassOf.containsKey(rightCp)) {
        rightClassOf[rightCp] = rightClassOf.length + 1;
      }
      measuredDeltas.add([leftCp, rightCp, delta.clamp(-128, 127)]);
    }

    if (measuredDeltas.isEmpty) {
      return KerningResult.empty();
    }

    final int leftCount = leftClassOf.length;
    final int rightCount = rightClassOf.length;
    final List<int> matrix = List<int>.filled(leftCount * rightCount, 0);
    for (final d in measuredDeltas) {
      final lc = leftClassOf[d[0]]!;
      final rc = rightClassOf[d[1]]!;
      matrix[(lc - 1) * rightCount + (rc - 1)] = d[2];
    }

    final leftClasses = leftClassOf.entries
        .map((e) => KerningClassEntry(e.key, e.value))
        .toList()
      ..sort((a, b) => a.codepoint.compareTo(b.codepoint));
    final rightClasses = rightClassOf.entries
        .map((e) => KerningClassEntry(e.key, e.value))
        .toList()
      ..sort((a, b) => a.codepoint.compareTo(b.codepoint));

    return KerningResult(
      leftClasses: leftClasses,
      rightClasses: rightClasses,
      matrix: matrix,
      leftClassCount: leftCount,
      rightClassCount: rightCount,
    );
  }

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
    required FontMetrics metrics,
    required Map<FontStyle, StyleRasterResult> styleResults,
    required bool is2Bit,
  }) {
    final int numStyles = 4;

    final Map<FontStyle, int> styleDataSizes = {};
    for (final style in FontStyle.values) {
      final result = styleResults[style]!;
      int bitmapsSize = 0;
      for (final g in result.glyphs) {
        bitmapsSize += g.bitmap.length;
      }
      // Порядок блока данных стиля: intervals → glyph table → kernLeft →
      // kernRight → kernMatrix → ligatures(8 байт/запись) → bitmaps.
      final ligBytes = result.ligatures.length * 8;
      final kernLeftBytes = result.kerning.leftClasses.length * 3;
      final kernRightBytes = result.kerning.rightClasses.length * 3;
      final kernMatrixBytes = result.kerning.matrix.length; // 1 байт (int8) на ячейку
      final dataSize = (result.intervals.length * intervalSize) +
          (result.glyphs.length * glyphSize) +
          kernLeftBytes +
          kernRightBytes +
          kernMatrixBytes +
          ligBytes +
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
      final result = styleResults[style]!;

      view.setUint8(offset, style.index);
      offset += 1;
      offset += 3;
      view.setUint32(offset, result.intervals.length, Endian.little);
      offset += 4;
      view.setUint32(offset, result.glyphs.length, Endian.little);
      offset += 4;
      view.setUint8(offset, metrics.advanceY.clamp(0, 255));
      offset += 1;
      view.setInt16(offset, metrics.ascender.clamp(-32768, 32767), Endian.little);
      offset += 2;
      view.setInt16(offset, metrics.descender.clamp(-32768, 32767), Endian.little);
      offset += 2;
      view.setUint16(offset, result.kerning.leftClasses.length.clamp(0, 65535), Endian.little); // kernLeft count
      offset += 2;
      view.setUint16(offset, result.kerning.rightClasses.length.clamp(0, 65535), Endian.little); // kernRight count
      offset += 2;
      view.setUint8(offset, result.kerning.leftClassCount.clamp(0, 255)); // kernLeftClasses
      offset += 1;
      view.setUint8(offset, result.kerning.rightClassCount.clamp(0, 255)); // kernRightClasses
      offset += 1;
      view.setUint8(offset, result.ligatures.length.clamp(0, 255)); // 🎯 теперь реальное число лигатур
      offset += 1;
      view.setUint32(offset, styleOffsets[style]!, Endian.little);
      offset += 4;
      offset += 4;
    }

    // === 3. ДАННЫЕ КАЖДОГО СТИЛЯ ===
    for (final style in FontStyle.values) {
      final result = styleResults[style]!;
      final glyphs = result.glyphs;

      int glyphIndex = 0;
      for (final interval in result.intervals) {
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

      // 🎯 КЕРНИНГ: kernLeftClasses/kernRightClasses — отсортированные по
      // codepoint записи {codepoint: u16 LE, classId: u8} (3 байта каждая),
      // затем kernMatrix — плоский int8[leftCount*rightCount]. Формат
      // подтверждён по реальному PR прошивки (#873).
      for (final entry in result.kerning.leftClasses) {
        view.setUint16(offset, entry.codepoint, Endian.little);
        offset += 2;
        view.setUint8(offset, entry.classId);
        offset += 1;
      }
      for (final entry in result.kerning.rightClasses) {
        view.setUint16(offset, entry.codepoint, Endian.little);
        offset += 2;
        view.setUint8(offset, entry.classId);
        offset += 1;
      }
      for (final v in result.kerning.matrix) {
        view.setInt8(offset, v);
        offset += 1;
      }

      // 🎯 ЛИГАТУРЫ: 8 байт на запись — pair (u32 LE, (leftCp<<16)|rightCp)
      // + ligatureCp (u32 LE). Формат подтверждён по реальному PR прошивки
      // (#873, "Support for kerning and ligatures").
      for (final lig in result.ligatures) {
        view.setUint32(offset, lig.pair, Endian.little);
        offset += 4;
        view.setUint32(offset, lig.ligatureCp, Endian.little);
        offset += 4;
      }

      for (final glyph in glyphs) {
        buffer.setRange(offset, offset + glyph.bitmap.length, glyph.bitmap);
        offset += glyph.bitmap.length;
      }
    }

    return buffer;
  }
}
