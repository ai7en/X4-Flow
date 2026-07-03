import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'app_localizations.dart';

class TransferScreen extends StatefulWidget {
  const TransferScreen({super.key});

  @override
  State<TransferScreen> createState() => _TransferScreenState();
}

class _TransferScreenState extends State<TransferScreen> {
  late final WebViewController _controller;
  bool _showWebView = false;
  bool _isLoading = false;

  final TextEditingController _addressController =
      TextEditingController(text: 'http://crosspoint.local');

  @override
  void initState() {
    super.initState();
    _initController();
  }

  void _initController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebResourceError: ${error.description}');
          },
        ),
      );

    // 🎯 Устанавливаем обработчик выбора файлов для Android
    _setupAndroidFilePicker();
  }

  // 🎯 КЛЮЧЕВАЯ ФУНКЦИЯ: Учим WebView открывать FilePicker
  Future<void> _setupAndroidFilePicker() async {
    if (_controller.platform is AndroidWebViewController) {
      final androidController = _controller.platform as AndroidWebViewController;

      await androidController.setOnShowFileSelector(
        (FileSelectorParams params) async {
          debugPrint('📂 WebView запросил файл. Accept: ${params.acceptTypes}');

          try {
            // Используем FileType.any, чтобы Android не блокировал файлы
            final result = await FilePicker.platform.pickFiles(
              type: FileType.any,
              allowMultiple: params.mode == FileSelectorMode.openMultiple,
            );

            if (result != null && result.files.isNotEmpty) {
              final List<String> uris = [];
              final tempDir = await getTemporaryDirectory();

              for (final file in result.files) {
                if (file.path == null) continue;

                // Копируем файл во временную директорию приложения,
                // чтобы обойти ограничения Scoped Storage Android 10+
                final originalFile = File(file.path!);
                final tempFile = File('${tempDir.path}/${file.name}');
                await originalFile.copy(tempFile.path);

                uris.add(Uri.file(tempFile.path).toString());
              }

              debugPrint('✅ Выбрано файлов: ${uris.length}');
              return uris;
            }
          } catch (e) {
            debugPrint('❌ Ошибка FilePicker: $e');
          }
          return [];
        },
      );
    }
  }

  void _connect() {
    String url = _addressController.text.trim();
    if (url.isEmpty) return;

    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }

    _controller.loadRequest(Uri.parse(url));
    setState(() {
      _showWebView = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context);

    if (_showWebView) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () async {
                    if (await _controller.canGoBack()) {
                      await _controller.goBack();
                    } else {
                      setState(() => _showWebView = false);
                    }
                  },
                  tooltip: loc.translate('wifi_back'),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _controller.reload(),
                  tooltip: loc.translate('wifi_refresh'),
                ),
                Expanded(
                  child: Text(
                    _addressController.text,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
                if (_isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.redAccent),
                  onPressed: () => setState(() => _showWebView = false),
                  tooltip: loc.translate('wifi_disconnect'),
                ),
              ],
            ),
          ),
          Expanded(
            child: WebViewWidget(controller: _controller),
          ),
        ],
      );
    }

    // Стартовый экран
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            color: theme.colorScheme.primaryContainer.withOpacity(0.2),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.wifi_tethering, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        loc.translate('wifi_preparation'),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(loc.translate('wifi_step1')),
                  Text(loc.translate('wifi_step2')),
                  Text(loc.translate('wifi_step3')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _addressController,
            decoration: InputDecoration(
              labelText: loc.translate('wifi_address_label'),
              hintText: loc.translate('wifi_address_hint'),
              prefixIcon: const Icon(Icons.lan_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _connect,
            icon: const Icon(Icons.cloud_sync_outlined),
            label: Text(loc.translate('wifi_connect')),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
          ),
        ],
      ),
    );
  }
}