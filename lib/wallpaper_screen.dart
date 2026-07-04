import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:archive/archive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'device_profile.dart';
import 'quote_templates.dart';
import 'calendar_templates.dart';
import 'quotes_ru.dart';
import 'app_localizations.dart';

enum TemplateMode { photo, quote, calendar }

class WallpaperScreen extends StatefulWidget {
  const WallpaperScreen({super.key});

  @override
  State<WallpaperScreen> createState() => _WallpaperScreenState();
}

class _WallpaperScreenState extends State<WallpaperScreen> with WidgetsBindingObserver {
  bool _isSaving = false;
  bool _useDithering = true;
  DeviceModel _selectedModel = DeviceModel.x4;
  bool _hideControls = false;
  TemplateMode _mode = TemplateMode.photo;
  File? _selectedImage;
  ui.Image? _decodedUiImage;
  int _activeEditorTab = 0;
  double _zoom = 1.0;
  double _offsetX = 0.0;
  double _offsetY = 0.0;
  double _brightness = 0.0;
  double _contrast = 1.0;
  bool _stretchToFill = false;
  int _rotation = 0;
  late int _selectedQuoteIndex;
  int _selectedBgIndex = 0;
  DateTime _calendarDate = DateTime(DateTime.now().year, DateTime.now().month);
  bool _calendarInverted = false;
  bool _isGeneratingYear = false;
  double _yearProgress = 0.0;

  static const String _kMode = 'wp_mode';
  static const String _kModel = 'wp_model';
  static const String _kZoom = 'wp_zoom';
  static const String _kOffsetX = 'wp_offsetX';
  static const String _kOffsetY = 'wp_offsetY';
  static const String _kBrightness = 'wp_brightness';
  static const String _kContrast = 'wp_contrast';
  static const String _kStretch = 'wp_stretch';
  static const String _kDithering = 'wp_dithering';
  static const String _kRotation = 'wp_rotation';
  static const String _kQuoteIndex = 'wp_quoteIdx';
  static const String _kBgIndex = 'wp_bgIdx';
  static const String _kCalYear = 'wp_calYear';
  static const String _kCalMonth = 'wp_calMonth';
  static const String _kCalInverted = 'wp_calInv';

  @override
  void initState() {
    super.initState();
    _selectedQuoteIndex = Random().nextInt(bookQuotesRu.length);
    WidgetsBinding.instance.addObserver(this);
    _loadSettings();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveSettings();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveSettings();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      final modeIdx = prefs.getInt(_kMode) ?? 0;
      if (modeIdx >= 0 && modeIdx < TemplateMode.values.length) {
        _mode = TemplateMode.values[modeIdx];
      }
      final modelIdx = prefs.getInt(_kModel) ?? 0;
      _selectedModel = modelIdx == 1 ? DeviceModel.x3 : DeviceModel.x4;
      _zoom = prefs.getDouble(_kZoom) ?? 1.0;
      _offsetX = prefs.getDouble(_kOffsetX) ?? 0.0;
      _offsetY = prefs.getDouble(_kOffsetY) ?? 0.0;
      _brightness = prefs.getDouble(_kBrightness) ?? 0.0;
      _contrast = prefs.getDouble(_kContrast) ?? 1.0;
      _stretchToFill = prefs.getBool(_kStretch) ?? false;
      _useDithering = prefs.getBool(_kDithering) ?? true;
      _rotation = prefs.getInt(_kRotation) ?? 0;
      final qIdx = prefs.getInt(_kQuoteIndex);
      if (qIdx != null) {
        _selectedQuoteIndex = qIdx;
      }
      final bgIdx = prefs.getInt(_kBgIndex);
      if (bgIdx != null && bgIdx >= 0 && bgIdx < quoteBackgrounds.length) {
        _selectedBgIndex = bgIdx;
      }
      final cYear = prefs.getInt(_kCalYear) ?? DateTime.now().year;
      final cMonth = prefs.getInt(_kCalMonth) ?? DateTime.now().month;
      _calendarDate = DateTime(cYear, cMonth);
      _calendarInverted = prefs.getBool(_kCalInverted) ?? false;
    });
  }

  Future<void> _saveSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kMode, _mode.index);
      await prefs.setInt(_kModel, _selectedModel == DeviceModel.x3 ? 1 : 0);
      await prefs.setDouble(_kZoom, _zoom);
      await prefs.setDouble(_kOffsetX, _offsetX);
      await prefs.setDouble(_kOffsetY, _offsetY);
      await prefs.setDouble(_kBrightness, _brightness);
      await prefs.setDouble(_kContrast, _contrast);
      await prefs.setBool(_kStretch, _stretchToFill);
      await prefs.setBool(_kDithering, _useDithering);
      await prefs.setInt(_kRotation, _rotation);
      await prefs.setInt(_kQuoteIndex, _selectedQuoteIndex);
      await prefs.setInt(_kBgIndex, _selectedBgIndex);
      await prefs.setInt(_kCalYear, _calendarDate.year);
      await prefs.setInt(_kCalMonth, _calendarDate.month);
      await prefs.setBool(_kCalInverted, _calendarInverted);
    } catch (e) {
      debugPrint('Ошибка сохранения настроек обоев: $e');
    }
  }

  void _randomizeQuote() {
    final langCode = Localizations.localeOf(context).languageCode;
    final quotes = getBookQuotes(langCode);
    setState(() {
      int newIndex;
      do {
        newIndex = Random().nextInt(quotes.length);
      } while (newIndex == _selectedQuoteIndex && quotes.length > 1);
      _selectedQuoteIndex = newIndex;
    });
  }

  Future<void> _selectImage() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      final bytes = await file.readAsBytes();
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      setState(() {
        _selectedImage = file;
        _decodedUiImage = frameInfo.image;
        _zoom = 1.0;
        _offsetX = 0.0;
        _offsetY = 0.0;
        _brightness = 0.0;
        _contrast = 1.0;
        _stretchToFill = false;
        _rotation = 0;
        _hideControls = false;
      });
    }
  }

  List<double> _createEinkMatrix() {
    double c = _contrast;
    double b = _brightness;
    double offset = (0.5 * (1.0 - c) + b) * 255;
    return [
      0.2126 * c, 0.7152 * c, 0.0722 * c, 0, offset,
      0.2126 * c, 0.7152 * c, 0.0722 * c, 0, offset,
      0.2126 * c, 0.7152 * c, 0.0722 * c, 0, offset,
      0,          0,          0,          1, 0,
    ];
  }

  void _drawPhotoOnCanvas(Canvas canvas, ui.Image image, DeviceProfile profile) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, profile.width.toDouble(), profile.height.toDouble()),
      Paint()..color = Colors.white,
    );
    canvas.save();
    if (_stretchToFill) {
      double scaleX = profile.width.toDouble() / image.width;
      double scaleY = profile.height.toDouble() / image.height;
      canvas.translate(profile.width / 2, profile.height / 2);
      canvas.scale(scaleX, scaleY);
      canvas.translate(-image.width / 2, -image.height / 2);
      canvas.drawImage(image, Offset.zero, Paint()..colorFilter = ColorFilter.matrix(_createEinkMatrix()));
    } else {
      final effW = (_rotation % 2 == 0) ? image.width : image.height;
      final effH = (_rotation % 2 == 0) ? image.height : image.width;
      final scaleX = profile.width.toDouble() / effW;
      final scaleY = profile.height.toDouble() / effH;
      final baseScale = scaleX < scaleY ? scaleX : scaleY;
      double screenToPhysical = profile.width.toDouble() / profile.previewWidth;
      canvas.translate(
        (profile.width / 2.0) + (_offsetX * screenToPhysical),
        (profile.height / 2.0) + (_offsetY * screenToPhysical),
      );
      canvas.rotate(_rotation * pi / 2);
      canvas.scale(baseScale * _zoom);
      canvas.translate(-image.width / 2, -image.height / 2);
      canvas.drawImage(image, Offset.zero, Paint()..colorFilter = ColorFilter.matrix(_createEinkMatrix()));
    }
    canvas.restore();
  }

  Future<Uint8List> _renderMonthBmp(DateTime monthDate, bool inverted, String langCode) async {
    final profile = deviceProfiles[_selectedModel]!;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, profile.width.toDouble(), profile.height.toDouble()));
    drawCalendarOnCanvas(canvas, profile, monthDate, inverted, langCode);
    final picture = recorder.endRecording();
    final imgUi = await picture.toImage(profile.width, profile.height);
    final byteData = await imgUi.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rgbaBytes = byteData!.buffer.asUint8List();
    var imageFromCanvas = img.Image.fromBytes(
      width: profile.width,
      height: profile.height,
      bytes: rgbaBytes.buffer,
      order: img.ChannelOrder.rgba,
    );
    img.Image grayImage = img.grayscale(imageFromCanvas);
    img.Image finalImg = _useDithering
        ? img.ditherImage(grayImage, quantizer: img.NeuralQuantizer(grayImage, numberOfColors: 16))
        : grayImage;
    return Uint8List.fromList(img.encodeBmp(finalImg));
  }

  /// 🎯 Проверка разрешений по образцу converter_screen.dart
  /// (работает и на Android 9-10, и на 11+)
  Future<bool> _checkStoragePermission(AppLocalizations loc) async {
    var storageStatus = await Permission.storage.status;
    if (!storageStatus.isGranted) {
      storageStatus = await Permission.storage.request();
    }
    var manageStatus = await Permission.manageExternalStorage.status;
    if (!manageStatus.isGranted) {
      manageStatus = await Permission.manageExternalStorage.request();
    }
    if (!storageStatus.isGranted && !manageStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.translate('converter_error_permission_hint')),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return false;
    }
    return true;
  }

  /// 🎯 Прямое сохранение в папку X4Flow/Wallpapers
  Future<void> _saveBytesToWallpapersFolder(Uint8List bytes, String fileName) async {
    final loc = AppLocalizations.of(context);
    final targetDir = Directory('/storage/emulated/0/Download/X4Flow/Wallpapers');
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final file = File('${targetDir.path}/$fileName');
    int counter = 1;
    while (await file.exists()) {
      final nameWithoutExt = fileName.substring(0, fileName.lastIndexOf('.'));
      final ext = fileName.substring(fileName.lastIndexOf('.'));
      final newFile = File('${targetDir.path}/$nameWithoutExt ($counter)$ext');
      if (!await newFile.exists()) {
        await newFile.writeAsBytes(bytes);
        return;
      }
      counter++;
    }
    await file.writeAsBytes(bytes);
  }

  Future<void> _buildAndSaveBmp() async {
    setState(() { _isSaving = true; });
    final profile = deviceProfiles[_selectedModel]!;
    final langCode = Localizations.localeOf(context).languageCode;
    final loc = AppLocalizations.of(context);
    try {
      await _saveSettings();

      if (!await _checkStoragePermission(loc)) {
        setState(() { _isSaving = false; });
        return;
      }

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, profile.width.toDouble(), profile.height.toDouble()));
      if (_mode == TemplateMode.photo && _decodedUiImage != null) {
        _drawPhotoOnCanvas(canvas, _decodedUiImage!, profile);
      } else if (_mode == TemplateMode.quote) {
        drawQuoteOnCanvas(canvas, profile, _selectedQuoteIndex, _selectedBgIndex, 42.0, langCode);
      } else if (_mode == TemplateMode.calendar) {
        drawCalendarOnCanvas(canvas, profile, _calendarDate, _calendarInverted, langCode);
      }
      final picture = recorder.endRecording();
      final imgUi = await picture.toImage(profile.width, profile.height);
      final byteData = await imgUi.toByteData(format: ui.ImageByteFormat.rawRgba);
      final rgbaBytes = byteData!.buffer.asUint8List();
      var imageFromCanvas = img.Image.fromBytes(
        width: profile.width,
        height: profile.height,
        bytes: rgbaBytes.buffer,
        order: img.ChannelOrder.rgba,
      );
      img.Image grayImage = img.grayscale(imageFromCanvas);
      img.Image finalEinkImg = _useDithering
          ? img.ditherImage(grayImage, quantizer: img.NeuralQuantizer(grayImage, numberOfColors: 16))
          : grayImage;
      final bmpBytes = Uint8List.fromList(img.encodeBmp(finalEinkImg));

      String fileName;
      if (_mode == TemplateMode.photo) {
        fileName = _useDithering
            ? 'wallpaper_${profile.width}x${profile.height}_dither.bmp'
            : 'wallpaper_${profile.width}x${profile.height}.bmp';
      } else if (_mode == TemplateMode.quote) {
        fileName = 'quote_${profile.width}x${profile.height}.bmp';
      } else {
        fileName = 'calendar_${_calendarDate.year}_${_calendarDate.month.toString().padLeft(2, '0')}_${profile.width}x${profile.height}.bmp';
      }

      await _saveBytesToWallpapersFolder(bmpBytes, fileName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Сохранено в Download/X4Flow/Wallpapers'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Ошибка создания BMP: $e');
      if (mounted) {
        final loc = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.translate('error')}: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      setState(() { _isSaving = false; });
    }
  }

  Future<void> _downloadYearCalendar() async {
    setState(() {
      _isGeneratingYear = true;
      _yearProgress = 0.0;
    });
    final profile = deviceProfiles[_selectedModel]!;
    final langCode = Localizations.localeOf(context).languageCode;
    final loc = AppLocalizations.of(context);
    final year = _calendarDate.year;
    try {
      if (!await _checkStoragePermission(loc)) {
        setState(() {
          _isGeneratingYear = false;
          _yearProgress = 0.0;
        });
        return;
      }

      final archive = Archive();
      for (int month = 1; month <= 12; month++) {
        final monthDate = DateTime(year, month);
        final bmpBytes = await _renderMonthBmp(monthDate, _calendarInverted, langCode);
        final fileName = '${year}_${month.toString().padLeft(2, '0')}.bmp';
        archive.addFile(ArchiveFile(fileName, bmpBytes.length, bmpBytes));
        setState(() {
          _yearProgress = month / 12.0;
        });
      }
      final zipBytes = Uint8List.fromList(ZipEncoder().encode(archive)!);
      final zipName = 'calendar_${year}_${profile.width}x${profile.height}.zip';

      await _saveBytesToWallpapersFolder(zipBytes, zipName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${loc.translate('wallpaper_year_success')}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Ошибка генерации календаря на год: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${loc.translate('error')}: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      setState(() {
        _isGeneratingYear = false;
        _yearProgress = 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = deviceProfiles[_selectedModel]!;
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context);
    final langCode = Localizations.localeOf(context).languageCode;
    final canSave = (_mode == TemplateMode.photo && _decodedUiImage != null) ||
        _mode == TemplateMode.quote ||
        _mode == TemplateMode.calendar;
    final isBusy = _isSaving || _isGeneratingYear;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<TemplateMode>(
              style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
              segments: [
                ButtonSegment(
                  value: TemplateMode.photo,
                  label: Text(loc.translate('wallpaper_mode_photo')),
                  icon: const Icon(Icons.image, size: 16),
                ),
                ButtonSegment(
                  value: TemplateMode.quote,
                  label: Text(loc.translate('wallpaper_mode_quote')),
                  icon: const Icon(Icons.format_quote, size: 16),
                ),
                ButtonSegment(
                  value: TemplateMode.calendar,
                  icon: const Icon(Icons.calendar_month, size: 18),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: isBusy ? null : (set) => setState(() {
                _mode = set.first;
                _hideControls = false;
              }),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${loc.translate('wallpaper_size')}: ${profile.width}x${profile.height}',
                  style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((_mode == TemplateMode.photo && _selectedImage != null) ||
                      _mode == TemplateMode.quote ||
                      _mode == TemplateMode.calendar)
                    IconButton(
                      icon: Icon(_hideControls ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                      tooltip: _hideControls ? loc.translate('wallpaper_show_controls') : loc.translate('wallpaper_hide_controls'),
                      onPressed: () => setState(() => _hideControls = !_hideControls),
                    ),
                  DropdownButton<DeviceModel>(
                    value: _selectedModel,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: DeviceModel.x4, child: Text('Xteink X4')),
                      DropdownMenuItem(value: DeviceModel.x3, child: Text('Xteink X3')),
                    ],
                    onChanged: isBusy ? null : (newModel) {
                      if (newModel != null) {
                        setState(() {
                          _selectedModel = newModel;
                          _offsetX = 0.0;
                          _offsetY = 0.0;
                          _zoom = 1.0;
                          _stretchToFill = false;
                          _rotation = 0;
                          _hideControls = false;
                        });
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 10),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: AspectRatio(
                  aspectRatio: profile.width / profile.height,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: WallpaperPainter(
                                mode: _mode,
                                image: _mode == TemplateMode.photo ? _decodedUiImage : null,
                                profile: profile,
                                zoom: _zoom,
                                offsetX: _offsetX,
                                offsetY: _offsetY,
                                brightness: _brightness,
                                contrast: _contrast,
                                stretchToFill: _stretchToFill,
                                rotation: _rotation,
                                einkMatrix: _createEinkMatrix(),
                                drawPhoto: _drawPhotoOnCanvas,
                                quoteIndex: _selectedQuoteIndex,
                                bgIndex: _selectedBgIndex,
                                calendarDate: _calendarDate,
                                calendarInverted: _calendarInverted,
                                langCode: langCode,
                              ),
                            ),
                          ),
                          Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: theme.colorScheme.primary, width: 2.5),
                                ),
                              ),
                            ),
                          ),
                          if (isBusy)
                            Container(
                              color: Colors.black.withValues(alpha: 0.54),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const CircularProgressIndicator(),
                                    const SizedBox(height: 12),
                                    if (_isGeneratingYear) ...[
                                      Text(
                                        '${loc.translate('wallpaper_year_generating')} ${(_yearProgress * 100).toInt()}%',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 8),
                                      SizedBox(
                                        width: 200,
                                        child: LinearProgressIndicator(
                                          value: _yearProgress,
                                          backgroundColor: Colors.white.withValues(alpha: 0.3),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          if (_mode == TemplateMode.photo && _decodedUiImage == null)
                            Center(child: Text(loc.translate('wallpaper_select_photo'), style: TextStyle(color: theme.colorScheme.onSurfaceVariant))),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_mode == TemplateMode.photo) ...[
            if (_selectedImage != null && !_hideControls)
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<int>(
                          style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                          segments: [
                            ButtonSegment(
                              value: 0,
                              label: Text(loc.translate('wallpaper_tab_position')),
                              icon: const Icon(Icons.crop_free, size: 16),
                            ),
                            ButtonSegment(
                              value: 1,
                              label: Text(loc.translate('wallpaper_tab_bw')),
                              icon: const Icon(Icons.tune, size: 16),
                            ),
                          ],
                          selected: {_activeEditorTab},
                          onSelectionChanged: (set) => setState(() => _activeEditorTab = set.first),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 172,
                        child: _activeEditorTab == 0
                            ? Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.center_focus_strong, size: 20),
                                        onPressed: () => setState(() {
                                          _stretchToFill = false;
                                          _zoom = 1.0;
                                          _offsetX = 0.0;
                                          _offsetY = 0.0;
                                          _rotation = 0;
                                        }),
                                        tooltip: loc.translate('wallpaper_center'),
                                        style: IconButton.styleFrom(
                                          backgroundColor: !_stretchToFill && _zoom == 1.0 && _offsetX == 0.0 && _offsetY == 0.0 && _rotation == 0
                                              ? theme.colorScheme.primaryContainer : null,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.rotate_90_degrees_ccw, size: 20),
                                        onPressed: () => setState(() => _rotation = (_rotation + 1) % 4),
                                        tooltip: loc.translate('wallpaper_rotate'),
                                        style: IconButton.styleFrom(
                                          backgroundColor: _rotation != 0 ? theme.colorScheme.primaryContainer : null,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.fit_screen, size: 20),
                                        onPressed: () => setState(() => _stretchToFill = true),
                                        tooltip: loc.translate('wallpaper_stretch'),
                                        style: IconButton.styleFrom(
                                          backgroundColor: _stretchToFill ? theme.colorScheme.primaryContainer : null,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.align_horizontal_center, size: 20),
                                        onPressed: _decodedUiImage == null ? null : () {
                                          double effW = (_rotation % 2 == 0) ? _decodedUiImage!.width.toDouble() : _decodedUiImage!.height.toDouble();
                                          double effH = (_rotation % 2 == 0) ? _decodedUiImage!.height.toDouble() : _decodedUiImage!.width.toDouble();
                                          double sx = profile.width.toDouble() / effW;
                                          double sy = profile.height.toDouble() / effH;
                                          setState(() { _stretchToFill = false; _zoom = sx / (sx < sy ? sx : sy); _offsetX = 0; _offsetY = 0; });
                                        },
                                        tooltip: loc.translate('wallpaper_align_width'),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.align_vertical_center, size: 20),
                                        onPressed: _decodedUiImage == null ? null : () {
                                          double effW = (_rotation % 2 == 0) ? _decodedUiImage!.width.toDouble() : _decodedUiImage!.height.toDouble();
                                          double effH = (_rotation % 2 == 0) ? _decodedUiImage!.height.toDouble() : _decodedUiImage!.width.toDouble();
                                          double sx = profile.width.toDouble() / effW;
                                          double sy = profile.height.toDouble() / effH;
                                          setState(() { _stretchToFill = false; _zoom = sy / (sx < sy ? sx : sy); _offsetX = 0; _offsetY = 0; });
                                        },
                                        tooltip: loc.translate('wallpaper_align_height'),
                                      ),
                                    ],
                                  ),
                                  const Divider(height: 10),
                                  if (!_stretchToFill) ...[
                                    _buildSliderRow(Icons.search, _zoom, 0.2, 4.0, (v) => setState(() => _zoom = v)),
                                    _buildSliderRow(Icons.swap_vert, _offsetY, -300, 300, (v) => setState(() => _offsetY = v)),
                                    _buildSliderRow(Icons.swap_horiz, _offsetX, -200, 200, (v) => setState(() => _offsetX = v)),
                                  ] else
                                    Expanded(
                                      child: Center(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                          child: Text(loc.translate('wallpaper_stretched_hint'),
                                              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                                              textAlign: TextAlign.center),
                                        ),
                                      ),
                                    ),
                                ],
                              )
                            : Column(
                                children: [
                                  _buildSliderRow(Icons.brightness_6, _brightness, -0.5, 0.5, (v) => setState(() => _brightness = v), color: Colors.amber),
                                  _buildSliderRow(Icons.contrast, _contrast, 0.5, 2.5, (v) => setState(() => _contrast = v), color: Colors.blue),
                                  const Spacer(),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(loc.translate('wallpaper_dithering'), style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface)),
                                        Transform.scale(scale: 0.8, child: Switch(value: _useDithering, onChanged: (v) => setState(() => _useDithering = v))),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            if (_selectedImage != null) const SizedBox(height: 12),
          ] else if (_mode == TemplateMode.quote) ...[
            if (!_hideControls)
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Builder(builder: (context) {
                              final quotes = getBookQuotes(langCode);
                              final safeIndex = _selectedQuoteIndex % quotes.length;
                              return Text(quotes[safeIndex].author,
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                                  overflow: TextOverflow.ellipsis);
                            }),
                          ),
                          IconButton(icon: const Icon(Icons.refresh, size: 20), onPressed: _randomizeQuote, tooltip: loc.translate('wallpaper_quote_random')),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Builder(builder: (context) {
                        final quotes = getBookQuotes(langCode);
                        final safeIndex = _selectedQuoteIndex % quotes.length;
                        final q = quotes[safeIndex];
                        final qChar = langCode == 'en' ? '"' : '«';
                        final qCharEnd = langCode == 'en' ? '"' : '»';
                        return Text('$qChar${q.text}$qCharEnd',
                            style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                            maxLines: 2, overflow: TextOverflow.ellipsis);
                      }),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        value: _selectedBgIndex < quoteBackgrounds.length ? _selectedBgIndex : 0,
                        decoration: InputDecoration(
                          labelText: loc.translate('wallpaper_quote_style'),
                          prefixIcon: const Icon(Icons.style_outlined, size: 20),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          isDense: true,
                        ),
                        isExpanded: true,
                        items: List.generate(quoteBackgrounds.length, (i) {
                          return DropdownMenuItem<int>(
                            value: i,
                            child: Text(quoteBackgrounds[i].name(langCode)),
                          );
                        }),
                        onChanged: isBusy ? null : (v) {
                          if (v != null) setState(() => _selectedBgIndex = v);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
          ] else if (_mode == TemplateMode.calendar) ...[
            if (!_hideControls)
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left),
                            onPressed: () => setState(() => _calendarDate = DateTime(_calendarDate.year, _calendarDate.month - 1)),
                          ),
                          Text('${getMonthNames(langCode)[_calendarDate.month - 1]} ${_calendarDate.year}',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
                          IconButton(
                            icon: const Icon(Icons.chevron_right),
                            onPressed: () => setState(() => _calendarDate = DateTime(_calendarDate.year, _calendarDate.month + 1)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => setState(() => _calendarDate = DateTime(DateTime.now().year, DateTime.now().month)),
                              icon: const Icon(Icons.today, size: 16),
                              label: Text(loc.translate('wallpaper_calendar_today')),
                              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => setState(() => _calendarInverted = !_calendarInverted),
                              icon: Icon(_calendarInverted ? Icons.invert_colors : Icons.invert_colors_off, size: 16),
                              label: Text(_calendarInverted ? loc.translate('wallpaper_calendar_black_bg') : loc.translate('wallpaper_calendar_white_bg')),
                              style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              if (_mode == TemplateMode.photo)
                Expanded(child: OutlinedButton(onPressed: isBusy ? null : _selectImage, child: Text(loc.translate('wallpaper_select_photo'))))
              else if (_mode == TemplateMode.calendar)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isBusy ? null : _downloadYearCalendar,
                    icon: const Icon(Icons.folder_zip_outlined, size: 18),
                    label: Text(loc.translate('wallpaper_year_button')),
                  ),
                )
              else
                const Spacer(),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: !canSave || isBusy ? null : _buildAndSaveBmp,
                  child: Text(loc.translate('wallpaper_save_bmp')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSliderRow(IconData icon, double value, double min, double max, ValueChanged<double> onChanged, {Color? color}) {
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          Expanded(child: Slider(value: value, min: min, max: max, onChanged: onChanged)),
        ],
      ),
    );
  }
}

class WallpaperPainter extends CustomPainter {
  final TemplateMode mode;
  final ui.Image? image;
  final DeviceProfile profile;
  final double zoom;
  final double offsetX;
  final double offsetY;
  final double brightness;
  final double contrast;
  final bool stretchToFill;
  final int rotation;
  final List<double> einkMatrix;
  final void Function(Canvas, ui.Image, DeviceProfile) drawPhoto;
  final int quoteIndex;
  final int bgIndex;
  final DateTime calendarDate;
  final bool calendarInverted;
  final String langCode;

  WallpaperPainter({
    required this.mode,
    this.image,
    required this.profile,
    required this.zoom,
    required this.offsetX,
    required this.offsetY,
    required this.brightness,
    required this.contrast,
    required this.stretchToFill,
    required this.rotation,
    required this.einkMatrix,
    required this.drawPhoto,
    required this.quoteIndex,
    required this.bgIndex,
    required this.calendarDate,
    required this.calendarInverted,
    required this.langCode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double scale = size.width / profile.width;
    canvas.scale(scale);
    if (mode == TemplateMode.photo && image != null) {
      drawPhoto(canvas, image!, profile);
    } else if (mode == TemplateMode.quote) {
      drawQuoteOnCanvas(canvas, profile, quoteIndex, bgIndex, 42.0, langCode);
    } else if (mode == TemplateMode.calendar) {
      drawCalendarOnCanvas(canvas, profile, calendarDate, calendarInverted, langCode);
    }
  }

  @override
  bool shouldRepaint(covariant WallpaperPainter old) {
    return old.mode != mode ||
        old.image != image ||
        old.zoom != zoom ||
        old.offsetX != offsetX ||
        old.offsetY != offsetY ||
        old.brightness != brightness ||
        old.contrast != contrast ||
        old.stretchToFill != stretchToFill ||
        old.rotation != rotation ||
        old.quoteIndex != quoteIndex ||
        old.bgIndex != bgIndex ||
        old.calendarDate != calendarDate ||
        old.calendarInverted != calendarInverted ||
        old.langCode != langCode;
  }
}