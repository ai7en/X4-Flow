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
const List<List<int>> kBaseCoverage = [
  [0x0020, 0x007F],
  [0x00A0, 0x00FF],
  [0x2010, 0x2027],
];

// Дополнительные пресеты — используем ключи переводов для label
class UnicodePreset {
  final String key;
  final String labelKey; // 🎯 КЛЮЧ ПЕРЕВОДА вместо хардкод-строки
  final List<List<int>> ranges;
  const UnicodePreset(this.key, this.labelKey, this.ranges);
}

const List<UnicodePreset> kUnicodePresets = [
  UnicodePreset('font_range_cyrillic', 'font_preset_cyrillic', [
    [0x0400, 0x04FF],
  ]),
  UnicodePreset('font_range_latin_ext', 'font_preset_latin_ext', [
    [0x0100, 0x024F],
  ]),
  UnicodePreset('font_range_greek', 'font_preset_greek', [
    [0x0370, 0x03FF],
  ]),
  UnicodePreset('font_range_symbols', 'font_preset_symbols', [
    [0x2190, 0x21FF],
    [0x2200, 0x22FF],
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
  final Map<int, bool> _sizes = {
  8: false, 10: false, 12: true, 14: true, 16: true, 18: true,
  20: false, 22: false, 24: false, 26: false, 28: false, 30: false,
};
  final Map<String, bool> _ranges = {
    for (final preset in kUnicodePresets) preset.key: preset.key == 'font_range_cyrillic',
  };
  bool _is2Bit = true;
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
    for (final base in kBaseCoverage) {
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
                Text(loc.translate('font_sizes_label'), style: const TextStyle(fontWeight: FontWeight.w600)),
                Wrap(
                  spacing: 8,
                  children: _sizes.keys.map((size) {
                    return FilterChip(
                      label: Text('$size pt'),
                      selected: _sizes[size]!,
                      onSelected: (val) => setState(() => _sizes[size] = val),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(loc.translate('font_unicode_label'), style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(width: 6),
                    Tooltip(
                      message: loc.translate('font_base_coverage_tooltip'),
                      child: Icon(Icons.info_outline, size: 16, color: theme.colorScheme.outline),
                    ),
                  ],
                ),
                for (final preset in kUnicodePresets)
                  CheckboxListTile(
                    title: Text(loc.translate(preset.labelKey)),
                    value: _ranges[preset.key],
                    onChanged: (v) => setState(() => _ranges[preset.key] = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _customRangesController,
                  decoration: InputDecoration(
                    labelText: loc.translate('font_custom_ranges_label'),
                    border: const OutlineInputBorder(),
                    helperText: loc.translate('font_custom_ranges_helper'),
                  ),
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