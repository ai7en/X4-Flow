import 'package:flutter_localizations/flutter_localizations.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app_localizations.dart';
import 'native_font_converter.dart';

// 🎯 БАЗОВОЕ ПОКРЫТИЕ — включается ВСЕГДА, не показывается как чекбокс.
// Сверено с официальной таблицей пресетов lib/EpdFont/scripts/fontconvert_sdcard.py
// (docs/sd-card-fonts.md) — профиль "reading": Latin, Greek, Cyrillic,
// math/symbol blocks, supplemental punctuation, CJK quote marks.
// --- Базовые наборы ---
  const officialReadingFictionProfile = [
    [0x0020, 0x007F], // Basic Latin (английский алфавит, цифры, базовые знаки, клавиатурный плюс/дефис)
    [0x0080, 0x00FF], // 🎯 Latin-1 Supplement — официально начинается с 0x0080, не 0x00A0
                        // (знак градуса °, кавычки-ёлочки « », параграф §, диакритика для иностранных слов)

    // --- Наша спец-добавка для правильного отображения текстов ---
    [0x0300, 0x036F], // Combining Diacritical Marks (комбинируемые знаки ударения, чтобы буквы не превращались в квадраты)

    // --- Кириллица ---
    [0x0400, 0x04FF], // Cyrillic (основной русский алфавит, буква Ё, украинские/белорусские буквы)
    [0x0500, 0x052F], // Cyrillic Supplement (дополнительные буквы для языков малых народов и редких славянских текстов)

    // --- Типографика, спецсимволы и валюты ---
    [0x2000, 0x206F], // General Punctuation (полный блок: кавычки-лапки „ “, все виды тире —, многоточие …, спецпробелы)
    [0x20A0, 0x20CF], // Currency Symbols (символы валют, включая знак рубля ₽ [0x20BD], доллар, евро и т.д.)
    [0x2100, 0x214F], // Letterlike Symbols (буквоподобные знаки, включая жизненно важный для книг знак номера № [0x2116])

    // --- Точечный хак для математики ---
    [0x2212, 0x2212], // Mathematical Minus (настоящий длинный минус для отрицательных чисел вроде −5)

    [0x3008, 0x300F], // 🎯 CJK quote marks 「」『』〈〉《》— явно упомянуты в описании официального профиля "reading"
];

// Дополнительные пресеты — используем ключи переводов для label.
// Список подогнан под "Additional Unicode Coverage" на
// crosspointreader.com/fonts. isHeavy=true — это скрипты с тысячами
// глифов (Hangul/Chinese/Japanese целиком содержат блок CJK Unified
// Ideographs, ~10-20 тысяч символов) — конвертация займёт заметно больше
// времени и даст очень большой файл, поэтому такие пресеты в UI отдельно
// подтверждаются перед включением.
class UnicodePreset {
  final String key;
  final String labelKey; // 🎯 КЛЮЧ ПЕРЕВОДА вместо хардкод-строки
  final List<List<int>> ranges;
  final bool isHeavy;
  const UnicodePreset(this.key, this.labelKey, this.ranges, {this.isHeavy = false});
}

const List<UnicodePreset> kUnicodePresets = [
  UnicodePreset('font_range_latin_ext', 'font_preset_latin_ext', [
    [0x0100, 0x024F],
  ]),
  UnicodePreset('font_range_greek', 'font_preset_greek', [
    [0x0370, 0x03FF],
  ]),
  UnicodePreset('font_range_vietnamese', 'font_preset_vietnamese', [
    [0x1E00, 0x1EFF],
  ]),
  UnicodePreset('font_range_hebrew', 'font_preset_hebrew', [
    [0x0590, 0x05FF],
  ]),
  UnicodePreset('font_range_armenian', 'font_preset_armenian', [
    [0x0530, 0x058F],
  ]),
  UnicodePreset('font_range_georgian', 'font_preset_georgian', [
    [0x10A0, 0x10FF],
  ]),
  UnicodePreset('font_range_ethiopic', 'font_preset_ethiopic', [
    [0x1200, 0x137F],
  ]),
  UnicodePreset('font_range_cherokee', 'font_preset_cherokee', [
    [0x13A0, 0x13FF],
  ]),
  UnicodePreset('font_range_tifinagh', 'font_preset_tifinagh', [
    [0x2D30, 0x2D7F],
  ]),
  UnicodePreset('font_range_thai', 'font_preset_thai', [
    [0x0E00, 0x0E7F],
  ]),
  UnicodePreset('font_range_hangul', 'font_preset_hangul', [
    [0x1100, 0x11FF], // Hangul Jamo
    [0x3130, 0x318F], // Hangul Compatibility Jamo
    [0xAC00, 0xD7A3], // Hangul Syllables (~11 172 символа!)
  ], isHeavy: true),
  UnicodePreset('font_range_chinese', 'font_preset_chinese', [
    [0x4E00, 0x9FFF], // CJK Unified Ideographs (~20 900 символов!)
  ], isHeavy: true),
  UnicodePreset('font_range_japanese', 'font_preset_japanese', [
    [0x3040, 0x309F], // Hiragana
    [0x30A0, 0x30FF], // Katakana
    [0x4E00, 0x9FFF], // Kanji — тот же блок CJK, что и китайский (~20 900!)
  ], isHeavy: true),
  UnicodePreset('font_range_symbols', 'font_preset_symbols', [
    [0x2190, 0x21FF], // Arrows (различные стрелки: влево, вправо, двойные, пунктирные и фигурные)
    [0x2200, 0x22FF], // Mathematical Operators (математические знаки: кванторы, интегралы, суммы, корни, логические операторы)
    [0x2600, 0x26FF], // Miscellaneous Symbols (разнообразные значки: погода, астрономия, карточные масти, шахматы, музыкальные ноты)
  ]),
];

/// Парсит строку вида "(0x2900-0x29FF),(0x2E00-0x2EFF)" в список диапазонов.
List<List<int>> parseCustomRanges(String input) {
  final result = <List<int>>[];
  final regex = RegExp(r'0[xX]([0-9a-fA-F]+)\s*-\s*0[xX]([0-9a-fA-F]+)');
  for (final match in regex.allMatches(input)) {
    try {
      final start = int.parse(match.group(1)!, radix: 16);
      final end = int.parse(match.group(2)!, radix: 16);
      if (start <= end && end <= 0x10FFFF) {
        result.add([start, end]);
      }
    } catch (_) {}
  }
  return result;
}

/// Объединяет диапазоны так, чтобы не рассылать на растеризацию одни и те
/// же codepoint'ы дважды.
void addRangeIfNotCovered(List<List<int>> intervals, List<int> range) {
  final alreadyCovered = intervals.any(
    (existing) => existing[0] <= range[0] && existing[1] >= range[1],
  );
  if (!alreadyCovered) {
    intervals.add(range);
  }
}

/// Сортирует интервалы по startCodePoint и объединяет перекрывающиеся
/// или смежные диапазоны.
List<List<int>> mergeAndSortIntervals(List<List<int>> intervals) {
  if (intervals.isEmpty) return intervals;
  final sorted = List<List<int>>.from(intervals)
    ..sort((a, b) => a[0].compareTo(b[0]));
  final merged = <List<int>>[List<int>.from(sorted[0])];
  for (int i = 1; i < sorted.length; i++) {
    final current = sorted[i];
    final last = merged.last;
    if (last[1] + 1 >= current[0]) {
      if (current[1] > last[1]) {
        last[1] = current[1];
      }
    } else {
      merged.add(List<int>.from(current));
    }
  }
  return merged;
}

class FontConverterScreen extends StatefulWidget {
  const FontConverterScreen({super.key});

  @override
  State<FontConverterScreen> createState() => _FontConverterScreenState();
}

class _FontConverterScreenState extends State<FontConverterScreen> {
  bool _isConverting = false;
  double _fontProgress = 0.0;
  final TextEditingController _familyController = TextEditingController(text: 'NotoSans');
  final TextEditingController _customRangesController = TextEditingController();
  File? _regularFile;
  File? _boldFile;
  File? _italicFile;
  File? _boldItalicFile;

  // 🆕 Размеры 8–31 с шагом 1 (по умолчанию 12–18 включительно)
  final Map<int, bool> _sizes = {
    for (int i = 8; i <= 31; i++) i: (i >= 12 && i <= 18),
  };

  final Map<String, bool> _ranges = {
    for (final preset in kUnicodePresets) preset.key: preset.key == 'font_range_cyrillic',
  };
  bool _is2Bit = true;
  bool _stemCalibrate = false; // 🆕 Stem calibration toggle
  bool _useFreeType = false; // 🆕 FreeType rasterizer toggle (настоящий хинтинг)
  bool _sizesExpanded = true;   // 🆕 Состояние спойлера размеров
  bool _unicodeExpanded = false; // 🆕 Состояние спойлера Unicode

  String? _previewRegularFamily;
  String? _previewBoldFamily;
  String? _previewItalicFamily;
  String? _previewBoldItalicFamily;
  bool _previewLoading = false;

  final NativeFontConverter _nativeConverter = NativeFontConverter();

  Future<void> _pickFontFile(String style) async {
    final loc = AppLocalizations.of(context);
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result != null && result.files.single.path != null) {
        final String filePath = result.files.single.path!;
        final String fileName = result.files.single.name;
        final String extension = fileName.split('.').last.toLowerCase();
        if (extension == 'ttf' || extension == 'otf') {
          final file = File(filePath);
          setState(() {
            if (style == 'regular') {
              _regularFile = file;
              String name = fileName.split('.').first;
              _familyController.text = name.replaceAll(RegExp(r'[- _]'), '');
            } else if (style == 'bold') {
              _boldFile = file;
            } else if (style == 'italic') {
              _italicFile = file;
            } else if (style == 'bolditalic') {
              _boldItalicFile = file;
            }
          });
          await _registerPreviewFont(style, file);
        } else {
          _showSnackBar(loc.translate('font_error_wrong_format'));
        }
      }
    } catch (e) {
      _showSnackBar('${loc.translate('font_error_pick')}$e');
    }
  }

  Future<void> _registerPreviewFont(String style, File file) async {
    final loc = AppLocalizations.of(context);
    setState(() => _previewLoading = true);
    try {
      final bytes = await file.readAsBytes();
      final family = 'preview_${style}_${DateTime.now().microsecondsSinceEpoch}';
      final loader = FontLoader(family);
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      if (!mounted) return;
      setState(() {
        switch (style) {
          case 'regular':
            _previewRegularFamily = family;
            break;
          case 'bold':
            _previewBoldFamily = family;
            break;
          case 'italic':
            _previewItalicFamily = family;
            break;
          case 'bolditalic':
            _previewBoldItalicFamily = family;
            break;
        }
      });
    } catch (e) {
      _showSnackBar('${loc.translate('font_error_preview')}$e');
    } finally {
      if (mounted) setState(() => _previewLoading = false);
    }
  }

  void _warmupFontInEngine(String fontFamily) {
    final pb = ui.ParagraphBuilder(ui.ParagraphStyle(
      fontFamily: fontFamily,
      fontSize: 24,
    ));
    pb.addText('Abc123_АБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдежзийклмнопрстуфхцчшщъыьэюя');
    final paragraph = pb.build();
    paragraph.layout(const ui.ParagraphConstraints(width: 1000));
  }

  List<List<int>> _buildIntervals() {
    final List<List<int>> intervals = [];
    for (final base in officialReadingFictionProfile) {
      addRangeIfNotCovered(intervals, base);
    }
    for (final preset in kUnicodePresets) {
      if (_ranges[preset.key] == true) {
        for (final r in preset.ranges) {
          addRangeIfNotCovered(intervals, r);
        }
      }
    }
    for (final r in parseCustomRanges(_customRangesController.text)) {
      addRangeIfNotCovered(intervals, r);
    }
    return mergeAndSortIntervals(intervals);
  }

  Future<void> _convertNative() async {
    final loc = AppLocalizations.of(context);
    if (_regularFile == null) {
      _showSnackBar(loc.translate('font_error_no_regular'));
      return;
    }
    final fontFamily = _familyController.text.trim();
    if (fontFamily.isEmpty) {
      _showSnackBar(loc.translate('font_error_empty_family'));
      return;
    }
    setState(() {
      _isConverting = true;
      _fontProgress = 0.0;
    });
    try {
      final regularBytes = await _regularFile!.readAsBytes();
      final boldBytes = _boldFile != null ? await _boldFile!.readAsBytes() : null;
      final italicBytes = _italicFile != null ? await _italicFile!.readAsBytes() : null;
      final boldItalicBytes = _boldItalicFile != null ? await _boldItalicFile!.readAsBytes() : null;

      final activeSizes = _sizes.entries.where((e) => e.value).map((e) => e.key).toList();
      if (activeSizes.isEmpty) {
        throw Exception(loc.translate('font_error_no_size'));
      }

      final intervals = _buildIntervals();

      await Future.delayed(const Duration(milliseconds: 300));
      _warmupFontInEngine(fontFamily);
      await Future.delayed(const Duration(milliseconds: 200));

      final resultsBySize = await _nativeConverter.convert(
        onProgress: (current, total) {
          setState(() => _fontProgress = current / total);
        },
        regularFont: regularBytes,
        boldFont: boldBytes,
        italicFont: italicBytes,
        boldItalicFont: boldItalicBytes,
        fontFamily: fontFamily,
        sizes: activeSizes,
        intervals: intervals,
        is2Bit: _is2Bit,
        stemCalibrate: _stemCalibrate, // 🆕
        useFreeType: _useFreeType, // 🆕
      );

      var storageStatus = await Permission.storage.status;
      if (!storageStatus.isGranted) {
        storageStatus = await Permission.storage.request();
      }
      var manageStatus = await Permission.manageExternalStorage.status;
      if (!manageStatus.isGranted) {
        manageStatus = await Permission.manageExternalStorage.request();
      }
      if (storageStatus.isGranted || manageStatus.isGranted) {
        final Directory targetFontFolder = Directory('/storage/emulated/0/Download/X4Flow/Fonts/$fontFamily');
        if (!await targetFontFolder.exists()) {
          await targetFontFolder.create(recursive: true);
        }

        for (var entry in resultsBySize.entries) {
          final int size = entry.key;
          final Uint8List cpfontData = entry.value;
          final String fileName = "${fontFamily}_$size.cpfont";
          final File outputFile = File('${targetFontFolder.path}/$fileName');
          await outputFile.writeAsBytes(cpfontData);
        }
        _showSnackBar('${loc.translate('font_success_message')}${targetFontFolder.path}');
      } else {
        throw Exception("Не предоставлены разрешения на запись файлов!");
      }
    } catch (e) {
      _showSnackBar('${loc.translate('font_error_convert')}$e');
    } finally {
      setState(() => _isConverting = false);
    }
  }

  void _showSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Widget _buildPreviewCard(ThemeData theme) {
    final loc = AppLocalizations.of(context);
    if (_previewRegularFamily == null && !_previewLoading) {
      return const SizedBox.shrink();
    }
    final langCode = Localizations.localeOf(context).languageCode;
    final sample = langCode == 'ru'
        ? 'Съешь ещё этих мягких французских булок, да выпей чаю — «идеи»…'
        : 'The quick brown fox jumps over the lazy dog. 0123456789 — "quotes"…';

    Widget styledLine(String labelKey, String? family, {FontWeight? weight, ui.FontStyle? style}) {
      final effectiveFamily = family ?? _previewRegularFamily;
      final syntheticNote = family == null && effectiveFamily != null ? loc.translate('font_synthetic') : '';
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${loc.translate(labelKey)}$syntheticNote', style: theme.textTheme.labelSmall),
            Text(
              sample,
              style: TextStyle(
                fontFamily: effectiveFamily,
                fontWeight: weight,
                fontStyle: style,
                fontSize: 18,
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(loc.translate('font_preview'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              loc.translate('font_preview_hint'),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            if (_previewLoading) const LinearProgressIndicator(),
            if (_previewRegularFamily != null) ...[
              styledLine('font_regular', _previewRegularFamily),
              styledLine('font_bold', _previewBoldFamily, weight: FontWeight.bold),
              styledLine('font_italic', _previewItalicFamily, style: ui.FontStyle.italic),
              styledLine(
                'font_bold_italic',
                _previewBoldItalicFamily,
                weight: FontWeight.bold,
                style: ui.FontStyle.italic,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16.0),
      children: [
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.translate('font_files_section'), style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _pickFontFile('regular'),
                  icon: const Icon(Icons.file_open),
                  label: Text(_regularFile == null
                      ? loc.translate('font_regular_required')
                      : '${loc.translate('font_regular_selected')}${_regularFile!.path.split('/').last}'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(45)),
                ),
                const SizedBox(height: 8),
                Text(loc.translate('font_optional_styles'),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => _pickFontFile('bold'),
                  icon: const Icon(Icons.format_bold),
                  label: Text(_boldFile == null ? loc.translate('font_bold') : _boldFile!.path.split('/').last),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickFontFile('italic'),
                  icon: const Icon(Icons.format_italic),
                  label: Text(_italicFile == null ? loc.translate('font_italic') : _italicFile!.path.split('/').last),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pickFontFile('bolditalic'),
                  icon: const Icon(Icons.text_fields),
                  label: Text(_boldItalicFile == null
                      ? loc.translate('font_bold_italic')
                      : _boldItalicFile!.path.split('/').last),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _buildPreviewCard(theme),
        const SizedBox(height: 12),
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.translate('font_crosspoint_params'), style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: _familyController,
                  decoration: InputDecoration(
                    labelText: loc.translate('font_family_label'),
                    border: const OutlineInputBorder(),
                    helperText: loc.translate('font_family_helper'),
                  ),
                ),
                const SizedBox(height: 16),

                // 🆕 Размеры под ExpansionTile (спойлер) — ровная широкая сетка
                ExpansionTile(
                  title: Text(loc.translate('font_sizes_section')),
                  initiallyExpanded: _sizesExpanded,
                  onExpansionChanged: (v) => setState(() => _sizesExpanded = v),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  children: [
                    GridView.count(
                      crossAxisCount: 4,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 1.6,
                      children: _sizes.keys.map((size) {
                        final selected = _sizes[size]!;
                        return _SizeChip(
                          size: size,
                          selected: selected,
                          onTap: () => setState(() => _sizes[size] = !selected),
                        );
                      }).toList(),
                    ),
                  ],
                ),

                const Divider(),

                // 🆕 Unicode ranges под ExpansionTile (спойлер)
                ExpansionTile(
                  title: Row(
                    children: [
                      Text(loc.translate('font_unicode_section')),
                      const SizedBox(width: 6),
                      Tooltip(
                        message: loc.translate('font_base_coverage_tooltip'),
                        child: Icon(Icons.info_outline, size: 16, color: theme.colorScheme.outline),
                      ),
                    ],
                  ),
                  initiallyExpanded: _unicodeExpanded,
                  onExpansionChanged: (v) => setState(() => _unicodeExpanded = v),
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  children: [
                    for (final preset in kUnicodePresets)
                      CheckboxListTile(
                        title: Text(loc.translate(preset.labelKey)),
                        subtitle: preset.isHeavy
                            ? Text(
                                loc.translate('font_preset_heavy_warning'),
                                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
                              )
                            : null,
                        value: _ranges[preset.key],
                        onChanged: (v) async {
                          if (v == true && preset.isHeavy) {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: Text(loc.translate('font_preset_heavy_dialog_title')),
                                content: Text(loc.translate('font_preset_heavy_dialog_body')),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(false),
                                    child: Text(loc.translate('font_cancel')),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.of(ctx).pop(true),
                                    child: Text(loc.translate('font_confirm')),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) return;
                          }
                          setState(() => _ranges[preset.key] = v ?? false);
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                      child: TextField(
                        controller: _customRangesController,
                        decoration: InputDecoration(
                          labelText: loc.translate('font_custom_ranges_label'),
                          border: const OutlineInputBorder(),
                          helperText: loc.translate('font_custom_ranges_helper'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(loc.translate('font_eink_settings'), style: theme.textTheme.titleMedium),
                SwitchListTile(
                  title: Text(loc.translate('font_2bit_title')),
                  value: _is2Bit,
                  onChanged: (v) => setState(() => _is2Bit = v),
                ),
                // 🆕 Stem calibration toggle
                SwitchListTile(
                  title: Text(loc.translate('font_stem_calibration')),
                  subtitle: Text(loc.translate('font_stem_calibration_subtitle')),
                  value: _stemCalibrate,
                  onChanged: _useFreeType
                      ? null // FreeType сам решает эту задачу — калибровка dart:ui тут не нужна
                      : (v) => setState(() => _stemCalibrate = v),
                ),
                // 🆕 FreeType toggle — настоящий хинтинг вместо приближения
                // через подбор размера + контраст. Выключает Stem calibration,
                // т.к. они решают одну и ту же проблему разными способами.
                SwitchListTile(
                  title: Text(loc.translate('font_use_freetype')),
                  subtitle: Text(loc.translate('font_use_freetype_subtitle')),
                  value: _useFreeType,
                  onChanged: (v) => setState(() {
                    _useFreeType = v;
                    if (v) _stemCalibrate = false;
                  }),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (_isConverting)
          Column(
            children: [
              LinearProgressIndicator(value: _fontProgress > 0 ? _fontProgress : null),
              const SizedBox(height: 8),
              Text('${loc.translate('font_compiling_progress')}${(_fontProgress * 100).toStringAsFixed(0)}%'),
            ],
          )
        else
          FilledButton.icon(
            onPressed: _convertNative,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            icon: const Icon(Icons.font_download),
            label: Text(loc.translate('font_compile_button')),
          ),
      ],
    );
  }
}

/// 🆕 Кастомная кнопка размера — широкая, с выровненным текстом
class _SizeChip extends StatelessWidget {
  final int size;
  final bool selected;
  final VoidCallback onTap;

  const _SizeChip({
    required this.size,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest.withOpacity(0.4),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : theme.colorScheme.outline.withOpacity(0.35),
              width: 1.2,
            ),
          ),
          child: Text(
            '$size',
            style: TextStyle(
              fontSize: 15,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected
                  ? theme.colorScheme.onPrimaryContainer
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}