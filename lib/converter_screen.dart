import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:archive/archive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'fb2_to_epub.dart';
import 'epub_optimizer.dart';
import 'device_profile.dart';
import 'app_localizations.dart';

enum ConverterMode { fb2ToEpub, optimizeEpub }

class ConverterScreen extends StatefulWidget {
  const ConverterScreen({super.key});

  @override
  State<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends State<ConverterScreen> {
  ConverterMode _mode = ConverterMode.fb2ToEpub;
  DeviceModel _selectedModel = DeviceModel.x4;
  bool _optimizeImages = false;

  List<PlatformFile> _selectedFiles = [];
  bool _isProcessing = false;
  String _currentStatus = '';
  String _currentFileName = '';
  double _overallProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
    _currentStatus = '';
  }

  String _getDisplayStatus() {
    final loc = AppLocalizations.of(context);
    if (!_isProcessing && _selectedFiles.isEmpty && _overallProgress == 0.0 && _currentFileName.isEmpty) {
      return loc.translate('converter_waiting');
    }
    if (!_isProcessing && _selectedFiles.isNotEmpty && _overallProgress == 0.0) {
      return '${loc.translate('converter_select')}: ${_selectedFiles.length}';
    }
    if (!_isProcessing && _overallProgress == 1.0 && _currentStatus.contains(':')) {
      final parts = _currentStatus.split(':');
      if (parts.length == 2 && int.tryParse(parts[1].trim()) != null) {
        return '${loc.translate('converter_success')}: ${parts[1].trim()}';
      }
    }
    return _currentStatus;
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final modelIdx = prefs.getInt('converter_model') ?? 0;
    final optimize = prefs.getBool('converter_optimize') ?? false;
    setState(() {
      _selectedModel = modelIdx == 1 ? DeviceModel.x3 : DeviceModel.x4;
      _optimizeImages = optimize;
    });
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('converter_model', _selectedModel == DeviceModel.x3 ? 1 : 0);
    await prefs.setBool('converter_optimize', _optimizeImages);
  }

  String _sanitizeFileName(String name) {
    if (name.isEmpty) return '';
    String safe = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '').trim();
    safe = safe.replaceAll(RegExp(r'\s+'), ' ');
    safe = safe.replaceAll(RegExp(r'\.+$'), '');
    if (safe.length > 100) safe = safe.substring(0, 100).trimRight();
    return safe;
  }

  Future<void> _pickFiles() async {
    final loc = AppLocalizations.of(context);
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (result != null) {
        final allowedExtensions = _mode == ConverterMode.fb2ToEpub
            ? ['.fb2', '.zip']
            : ['.epub'];

        final allowedFiles = result.files.where((file) {
          final name = file.name.toLowerCase();
          return allowedExtensions.any((ext) => name.endsWith(ext));
        }).toList();

        if (allowedFiles.isEmpty) {
          final errorMsg = _mode == ConverterMode.fb2ToEpub
              ? loc.translate('converter_error_no_fb2')
              : 'None of the selected files are .epub';
          setState(() {
            _currentStatus = errorMsg;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(errorMsg), backgroundColor: Colors.orange),
            );
          }
          return;
        }

        setState(() {
          _selectedFiles = allowedFiles;
          _currentStatus =
              '${loc.translate('converter_select')}: ${_selectedFiles.length}';
          _currentFileName = '';
          _overallProgress = 0.0;
        });
      }
    } catch (e) {
      setState(() {
        _currentStatus = '${loc.translate('error')}: $e';
      });
    }
  }

  Future<void> _processFiles() async {
    if (_selectedFiles.isEmpty) return;
    final loc = AppLocalizations.of(context);
    final profile = deviceProfiles[_selectedModel]!;

    setState(() {
      _isProcessing = true;
      _overallProgress = 0.0;
    });

    try {
      // 🎯 Проверка разрешений: работает и на Android 9-10, и на 11+
      var storageStatus = await Permission.storage.status;
      if (!storageStatus.isGranted) {
        storageStatus = await Permission.storage.request();
      }

      var manageStatus = await Permission.manageExternalStorage.status;
      if (!manageStatus.isGranted) {
        manageStatus = await Permission.manageExternalStorage.request();
      }

      if (!storageStatus.isGranted && !manageStatus.isGranted) {
        setState(() {
          _currentStatus = loc.translate('converter_error_permission');
          _isProcessing = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(loc.translate('converter_error_permission_hint')),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
        return;
      }

      final targetDir = Directory('/storage/emulated/0/Download/Fb2Epub');
      if (!await targetDir.exists()) {
        await targetDir.create(recursive: true);
      }

      // Создаём файл лога только при наличии ошибок
final logFile = File('${targetDir.path}/conversion_log.txt');
bool logCreated = false;

void logWrite(String message) {
  try {
    if (!logCreated) {
      // Создаём лог только при первой ошибке
      logFile.writeAsStringSync(
        '\n========================================\n'
        '=== Конвертация: ${DateTime.now().toString()} ===\n'
        '=== Режим: ${_mode == ConverterMode.fb2ToEpub ? "FB2→EPUB" : "Оптимизация EPUB"} ===\n'
        '=== Устройство: ${profile.name} (${profile.width}x${profile.height}) ===\n'
        '=== Оптимизация: ${_optimizeImages ? "ВКЛ" : "ВЫКЛ"} ===\n'
        '========================================\n',
        mode: FileMode.append,
        flush: true,
      );
      logCreated = true;
    }
    logFile.writeAsStringSync('$message\n', mode: FileMode.append, flush: true);
  } catch (e) {
    debugPrint('Ошибка записи в лог: $e');
  }
}

int successCount = 0;
final List<String> failedFiles = [];

for (int i = 0; i < _selectedFiles.length; i++) {
  final file = _selectedFiles[i];
  setState(() {
    _currentFileName = file.name;
    _currentStatus =
        '${loc.translate('converter_processing')} ${i + 1} / ${_selectedFiles.length}';
    _overallProgress = i / _selectedFiles.length;
  });
  if (file.path == null) continue;

  try {
    if (_mode == ConverterMode.fb2ToEpub) {
      await _processFb2File(file, targetDir, profile);
    } else {
      await _processEpubFile(file, targetDir, profile);
    }
    successCount++;
    // Успех НЕ логируем
  } catch (e, stackTrace) {
    debugPrint('Ошибка обработки ${file.name}: $e');
    logWrite('❌ ОШИБКА: ${file.name}');
    logWrite('   Причина: $e');
    logWrite('   Stack trace:');
    final stackLines = stackTrace.toString().split('\n').take(10).join('\n');
    logWrite(stackLines);
    failedFiles.add(file.name);
    setState(() {
      _currentStatus = '${loc.translate('error')}: ${file.name}';
    });
  }
}

// Итоговая запись только если были ошибки
if (logCreated) {
  logWrite('----------------------------------------');
  logWrite('ИТОГО: $successCount успешно, ${failedFiles.length} с ошибками');
  logWrite('Ошибки в файлах: ${failedFiles.join(", ")}');
  logWrite('========================================\n');
}

      setState(() {
        _overallProgress = 1.0;
        _currentStatus = '${loc.translate('converter_success')}: $successCount';
      });

      if (mounted) {
        final successTitle = _mode == ConverterMode.fb2ToEpub
            ? loc.translate('converter_dialog_success_title')
            : 'Optimization complete!';
        final successFolder = _mode == ConverterMode.fb2ToEpub
            ? loc.translate('converter_dialog_success_folder')
            : 'Download/Fb2Epub (with _optimized suffix)';

        String dialogContent = '${loc.translate('converter_success')}: $successCount\n'
    '📂 ${loc.translate('converter_dialog_success_path')}:\n$successFolder';

if (failedFiles.isNotEmpty) {
  dialogContent += '\n\n❌ Errors: ${failedFiles.length}\n'
      'Details in file:\n📄 conversion_log.txt';
}

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Icon(
                  failedFiles.isEmpty ? Icons.check_circle : Icons.warning,
                  color: failedFiles.isEmpty ? Colors.green : Colors.orange,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(successTitle)),
              ],
            ),
            content: Text(
              dialogContent,
              style: const TextStyle(fontSize: 15),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedFiles = [];
                    _currentFileName = '';
                    _overallProgress = 0.0;
                    _currentStatus = loc.translate('converter_waiting');
                  });
                },
                child: Text(
                  loc.translate('ok'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() {
        _currentStatus = '${loc.translate('error')}: $e';
      });
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _processFb2File(PlatformFile file, Directory targetDir, DeviceProfile profile) async {
    String inputPath = file.path!;
    File? tempFb2File;

    if (file.name.toLowerCase().endsWith('.zip')) {
      final zipBytes = await File(file.path!).readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);
      for (final archiveFile in archive) {
        if (archiveFile.isFile &&
            archiveFile.name.toLowerCase().endsWith('.fb2')) {
          final fb2Data = archiveFile.content as List<int>;
          tempFb2File = File(
            '${Directory.systemTemp.path}/temp_${DateTime.now().millisecondsSinceEpoch}.fb2',
          );
          await tempFb2File.writeAsBytes(fb2Data);
          inputPath = tempFb2File.path;
          break;
        }
      }
      if (tempFb2File == null) {
        throw Exception("FB2 not found in ZIP");
      }
    }

    final converter = Fb2ToEpubConverter();
    final result = await converter.convert(
      inputPath: inputPath,
      optimize: _optimizeImages,
      profile: profile,
      onStatusUpdate: (statusUpdate) {
        setState(() {
          _currentStatus = statusUpdate;
        });
      },
    );

    String safeAuthor = _sanitizeFileName(result.author);
    String safeTitle = _sanitizeFileName(result.title);

    String rawName = file.name;
    if (rawName.toLowerCase().endsWith('.fb2.zip')) {
      rawName = rawName.substring(0, rawName.length - 8);
    } else if (rawName.toLowerCase().endsWith('.zip')) {
      rawName = rawName.substring(0, rawName.length - 4);
    } else if (rawName.toLowerCase().endsWith('.fb2')) {
      rawName = rawName.substring(0, rawName.length - 4);
    }
    String fallbackName = _sanitizeFileName(rawName);

    String fileName;
    if (safeTitle.isEmpty || safeTitle == 'Untitled Book') {
      fileName = '$fallbackName.epub';
    } else if (safeAuthor.isEmpty ||
        safeAuthor == 'Unknown Author' ||
        safeAuthor == 'Unknown') {
      fileName = '$safeTitle.epub';
    } else {
      fileName = '$safeTitle - $safeAuthor.epub';  // 🎯 Название - Автор
    }

    String outputPath = '${targetDir.path}/$fileName';
    int counter = 1;
    while (await File(outputPath).exists()) {
      final nameWithoutExt = fileName.substring(0, fileName.length - 5);
      outputPath = '${targetDir.path}/$nameWithoutExt ($counter).epub';
      counter++;
    }

    await File(outputPath).writeAsBytes(result.epubBytes);

    if (tempFb2File != null && await tempFb2File.exists()) {
      await tempFb2File.delete();
    }
  }

  Future<void> _processEpubFile(PlatformFile file, Directory targetDir, DeviceProfile profile) async {
    final optimizer = EpubOptimizer();

    String rawName = file.name;
    if (rawName.toLowerCase().endsWith('.epub')) {
      rawName = rawName.substring(0, rawName.length - 5);
    }
    String safeName = _sanitizeFileName(rawName);

    String outputPath = '${targetDir.path}/${safeName}_optimized.epub';
    int counter = 1;
    while (await File(outputPath).exists()) {
      outputPath = '${targetDir.path}/${safeName}_optimized ($counter).epub';
      counter++;
    }

    await optimizer.optimize(
      inputPath: file.path!,
      outputPath: outputPath,
      profile: profile,
      onStatusUpdate: (statusUpdate) {
        setState(() {
          _currentStatus = statusUpdate;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final profile = deviceProfiles[_selectedModel]!;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ConverterMode>(
              style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
              segments: [
                ButtonSegment(
                  value: ConverterMode.fb2ToEpub,
                  label: Text(loc.translate('converter_mode_fb2')),
                  icon: const Icon(Icons.menu_book, size: 16),
                ),
                ButtonSegment(
                  value: ConverterMode.optimizeEpub,
                  label: Text(loc.translate('converter_mode_optimize')),
                  icon: const Icon(Icons.auto_fix_high, size: 16),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _isProcessing
                  ? null
                  : (set) {
                      setState(() {
                        _mode = set.first;
                        _selectedFiles = [];
                        _currentFileName = '';
                        _overallProgress = 0.0;
                        _currentStatus = loc.translate('converter_waiting');
                      });
                    },
            ),
          ),
          const SizedBox(height: 12),

          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  DropdownButtonFormField<DeviceModel>(
                    value: _selectedModel,
                    decoration: InputDecoration(
                      labelText: loc.translate('converter_target_device'),
                      prefixIcon: const Icon(Icons.devices, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: DeviceModel.x4, child: Text('Xteink X4 (480×800)')),
                      DropdownMenuItem(value: DeviceModel.x3, child: Text('Xteink X3 (528×792)')),
                    ],
                    onChanged: _isProcessing
                        ? null
                        : (newModel) {
                            if (newModel != null) {
                              setState(() => _selectedModel = newModel);
                              _savePreferences();
                            }
                          },
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: Text(loc.translate('converter_optimize_images')),
                    subtitle: Text(
                      _mode == ConverterMode.fb2ToEpub
                          ? loc.translate('converter_optimize_subtitle_fb2')
                              .replaceAll('%w', profile.width.toString())
                              .replaceAll('%h', profile.height.toString())
                          : loc.translate('converter_optimize_subtitle_epub'),
                      style: const TextStyle(fontSize: 11),
                    ),
                    value: _mode == ConverterMode.optimizeEpub ? true : _optimizeImages,
                    onChanged: _isProcessing || _mode == ConverterMode.optimizeEpub
                        ? null
                        : (v) {
                            setState(() => _optimizeImages = v);
                            _savePreferences();
                          },
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isProcessing
                        ? Icons.sync
                        : (_mode == ConverterMode.fb2ToEpub
                            ? Icons.library_books
                            : Icons.auto_fix_high),
                    size: 64,
                    color: _isProcessing
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  if (_currentFileName.isNotEmpty) ...[
                    Text(
                      _currentFileName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: theme.colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                  ],
                  Text(
                    _getDisplayStatus(),
                    style: TextStyle(
                      color: _isProcessing
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (_isProcessing || _overallProgress > 0) ...[
                    LinearProgressIndicator(value: _overallProgress),
                    const SizedBox(height: 8),
                    Text(
                      '${(_overallProgress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isProcessing ? null : _pickFiles,
                  child: Text(loc.translate('converter_select')),
                ),
              ),
              if (_selectedFiles.isNotEmpty && !_isProcessing) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _processFiles,
                    child: Text(
                      _mode == ConverterMode.fb2ToEpub
                          ? loc.translate('converter_convert')
                          : 'Optimize',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}