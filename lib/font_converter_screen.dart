import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app_localizations.dart';
import 'native_font_converter.dart';

class FontConverterScreen extends StatefulWidget {
  const FontConverterScreen({super.key});

  @override
  State<FontConverterScreen> createState() => _FontConverterScreenState();
}

class _FontConverterScreenState extends State<FontConverterScreen> {
  bool _isConverting = false;
  final TextEditingController _familyController = TextEditingController(text: 'NotoSans');

  File? _regularFile;
  File? _boldFile;
  File? _italicFile;
  File? _boldItalicFile;

  final Map<int, bool> _sizes = {12: true, 14: true, 16: true, 18: true, 20: false, 24: false};
  final Map<String, bool> _ranges = {
    'font_range_ascii': true,
    'font_range_cyrillic': true,
    'font_range_latin': false,
  };
  bool _is2Bit = true;

  final NativeFontConverter _nativeConverter = NativeFontConverter();

  Future<void> _pickFontFile(String style) async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result != null && result.files.single.path != null) {
        final String filePath = result.files.single.path!;
        final String fileName = result.files.single.name;
        final String extension = fileName.split('.').last.toLowerCase();

        if (extension == 'ttf' || extension == 'otf') {
          setState(() {
            if (style == 'regular') {
              _regularFile = File(filePath);
              String name = fileName.split('.').first;
              _familyController.text = name.replaceAll(RegExp(r'[- _]'), '');
            } else if (style == 'bold') {
              _boldFile = File(filePath);
            } else if (style == 'italic') {
              _italicFile = File(filePath);
            } else if (style == 'bolditalic') {
              _boldItalicFile = File(filePath);
            }
          });
        } else {
          _showSnackBar('Неверный формат файла! Выберите .ttf или .otf');
        }
      }
    } catch (e) {
      _showSnackBar('Ошибка выбора файла: $e');
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

  Future<void> _convertNative() async {
    if (_regularFile == null) {
      _showSnackBar('Пожалуйста, выберите хотя бы Regular шрифт (.ttf/.otf)');
      return;
    }

    final fontFamily = _familyController.text.trim();
    if (fontFamily.isEmpty) {
      _showSnackBar('Имя семейства шрифта не может быть пустым');
      return;
    }

    setState(() => _isConverting = true);

    try {
      final regularBytes = await _regularFile!.readAsBytes();
      final boldBytes = _boldFile != null ? await _boldFile!.readAsBytes() : null;
      final italicBytes = _italicFile != null ? await _italicFile!.readAsBytes() : null;
      final boldItalicBytes = _boldItalicFile != null ? await _boldItalicFile!.readAsBytes() : null;

      final activeSizes = _sizes.entries.where((e) => e.value).map((e) => e.key).toList();
      if (activeSizes.isEmpty) {
        throw Exception("Выберите хотя бы один целевой размер шрифта");
      }

      final List<List<int>> intervals = [];
      if (_ranges['font_range_ascii'] == true) intervals.add([0x0020, 0x007F]);
      if (_ranges['font_range_cyrillic'] == true) intervals.add([0x0400, 0x04FF]);
      if (_ranges['font_range_latin'] == true) {
        intervals.add([0x00A0, 0x00FF]);
        intervals.add([0x0100, 0x017F]);
      }

      await Future.delayed(const Duration(milliseconds: 300));
      _warmupFontInEngine(fontFamily);
      await Future.delayed(const Duration(milliseconds: 200));

      final resultsBySize = await _nativeConverter.convert(
        regularFont: regularBytes,
        boldFont: boldBytes,
        italicFont: italicBytes,
        boldItalicFont: boldItalicBytes,
        fontFamily: fontFamily,
        sizes: activeSizes,
        intervals: intervals,
        is2Bit: _is2Bit,
      );

      if (await Permission.manageExternalStorage.request().isGranted ||
          await Permission.storage.request().isGranted) {
        final Directory targetFontFolder = Directory('/storage/emulated/0/fonts/$fontFamily');
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

        _showSnackBar('✅ Все 4 стиля записаны в: ${targetFontFolder.path}');
      } else {
        throw Exception("Не предоставлены разрешения на запись файлов!");
      }
    } catch (e) {
      _showSnackBar('Ошибка выполнения: $e');
    } finally {
      setState(() => _isConverting = false);
    }
  }

  void _showSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(loc.translate('title_font_converter'))),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Выбор файлов шрифтов (до 4 стилей)', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => _pickFontFile('regular'),
                    icon: const Icon(Icons.file_open),
                    label: Text(_regularFile == null
                        ? 'Regular .TTF/.OTF (обязательно)'
                        : 'Regular: ${_regularFile!.path.split('/').last}'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(45)),
                  ),
                  const SizedBox(height: 8),
                  const Text('Опциональные стили (если не выбраны — симуляция):',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => _pickFontFile('bold'),
                    icon: const Icon(Icons.format_bold),
                    label: Text(_boldFile == null ? 'Bold' : _boldFile!.path.split('/').last),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickFontFile('italic'),
                    icon: const Icon(Icons.format_italic),
                    label: Text(_italicFile == null ? 'Italic' : _italicFile!.path.split('/').last),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickFontFile('bolditalic'),
                    icon: const Icon(Icons.text_fields),
                    label: Text(_boldItalicFile == null
                        ? 'Bold Italic'
                        : _boldItalicFile!.path.split('/').last),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(40)),
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
                  Text('Параметры CrossPoint', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _familyController,
                    decoration: const InputDecoration(
                      labelText: 'Font Family',
                      border: OutlineInputBorder(),
                      helperText: 'Имя папки и префикс файлов',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Размеры:', style: TextStyle(fontWeight: FontWeight.w600)),
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
                  const Text('Unicode диапазоны:', style: TextStyle(fontWeight: FontWeight.w600)),
                  CheckboxListTile(
                    title: const Text('ASCII'),
                    value: _ranges['font_range_ascii'],
                    onChanged: (v) => setState(() => _ranges['font_range_ascii'] = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  ),
                  CheckboxListTile(
                    title: const Text('Кириллица'),
                    value: _ranges['font_range_cyrillic'],
                    onChanged: (v) => setState(() => _ranges['font_range_cyrillic'] = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                  ),
                  CheckboxListTile(
                    title: const Text('Latin Extended'),
                    value: _ranges['font_range_latin'],
                    onChanged: (v) => setState(() => _ranges['font_range_latin'] = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
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
                  Text('Настройки E-Ink', style: theme.textTheme.titleMedium),
                  SwitchListTile(
                    title: const Text('2-Bit (4 оттенка серого)'),
                    value: _is2Bit,
                    onChanged: (v) => setState(() => _is2Bit = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          if (_isConverting)
            const Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 8),
                Text('Компиляция 4 стилей...'),
              ],
            )
          else
            FilledButton.icon(
              onPressed: _convertNative,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              icon: const Icon(Icons.font_download),
              label: const Text('Скомпилировать .cpfont (4 стиля)'),
            ),
        ],
      ),
    );
  }
}