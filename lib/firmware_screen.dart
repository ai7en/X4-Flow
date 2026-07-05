import 'dart:io' show Process, File, Directory;
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'app_localizations.dart';

class FirmwareScreen extends StatefulWidget {
  const FirmwareScreen({super.key});

  @override
  State<FirmwareScreen> createState() => _FirmwareScreenState();
}

class _FirmwareScreenState extends State<FirmwareScreen> {
  final Dio _dio = Dio();
  final TextEditingController _tokenController = TextEditingController();

  // 🎯 КЭШ GitHub API — чтобы не долбить API при каждом открытии
  DateTime? _lastFetchTime;
  Map<String, List<dynamic>> _cachedReleases = {};
  static const int _cacheTtlMinutes = 15;

  // 🎯 Обновленный список репозиториев экосистемы CrossPoint / Xteink
  final List<Map<String, String>> _repositories = [
    {'name': 'CrossInk (uxjulia)', 'repo': 'uxjulia/CrossInk'},
    {'name': 'Inx (obijuankenobiii)', 'repo': 'obijuankenobiii/inx'},
    {'name': 'CrossPoint Reader', 'repo': 'crosspoint-reader/crosspoint-reader'},
    {'name': 'vCodex (franssjz)', 'repo': 'franssjz/cpr-vcodex'},
    {'name': 'vcodex-fork.fb2 (alrudimgn)', 'repo': 'alrudimgn/cpr-vcodex-fork'},
    {'name': 'AALU (dawsonfi)', 'repo': 'dawsonfi/aalu'},
    {'name': 'Papyrix (bigbag)', 'repo': 'bigbag/papyrix-reader'},
  ];

  late Map<String, String> _selectedRepo;
  List<dynamic> _releases = [];
  dynamic _selectedRelease;
  List<dynamic> _binAssets = [];
  bool _isLoadingReleases = false;
  bool _isDownloading = false;
  bool _isTokenSaved = false;
  double _downloadProgress = 0.0;
  String _statusMessage = '';
  String _currentDownloadingFile = '';

  @override
  void initState() {
    super.initState();
    _selectedRepo = _repositories[0];
    _loadSavedToken();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final loc = AppLocalizations.of(context);
        setState(() {
          _statusMessage = loc.translate('releases_select_repo');
        });
      }
    });
    _fetchReleases();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  /// 🎯 Определяет версию Android SDK
  Future<int> _getAndroidSdkVersion() async {
    try {
      final result = await Process.run('getprop', ['ro.build.version.sdk']);
      return int.tryParse(result.stdout.toString().trim()) ?? 30;
    } catch (_) {
      return 30; // По умолчанию Android 11+
    }
  }

  Future<void> _loadSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('github_token') ?? '';
    if (savedToken.isNotEmpty && mounted) {
      setState(() {
        _tokenController.text = savedToken;
        _isTokenSaved = true;
      });
    }
  }

  Future<void> _saveToken() async {
    final loc = AppLocalizations.of(context);
    final token = _tokenController.text.trim();
    final prefs = await SharedPreferences.getInstance();
    if (token.isEmpty) {
      await prefs.remove('github_token');
      setState(() => _isTokenSaved = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(loc.translate('releases_token_deleted')),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } else {
      await prefs.setString('github_token', token);
      setState(() => _isTokenSaved = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ ${loc.translate('releases_token_saved')}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// 🎯 УМНАЯ ЗАГРУЗКА: проверяет кэш перед сетевым запросом
  /// Если кэш свежий (< 15 минут) — отдаём его, не трогая GitHub API
  Future<void> _fetchReleases({bool forceRefresh = false}) async {
    final loc = AppLocalizations.of(context);
    final repoKey = _selectedRepo['repo']!;
    final now = DateTime.now();

    // 🎯 ПРОВЕРКА КЭША: если не принудительное обновление и кэш свежий
    if (!forceRefresh &&
        _cachedReleases.containsKey(repoKey) &&
        _lastFetchTime != null &&
        now.difference(_lastFetchTime!).inMinutes < _cacheTtlMinutes) {
      
      // Отдаём кэш — GitHub даже не узнает о запросе!
      setState(() {
        _releases = _cachedReleases[repoKey]!;
        if (_releases.isNotEmpty) {
          _selectedRelease = _releases[0];
          _extractBinAssets();
          _statusMessage = '${loc.translate('releases_available')}: ${_releases.length} (кэш ${_cacheTtlMinutes} мин)';
        } else {
          _statusMessage = loc.translate('releases_no_bins');
        }
      });
      return; // Выходим — сеть не трогаем
    }

    // 🎯 КЭШ УСТАРЕЛ или отсутствует — идём в сеть
    setState(() {
      _isLoadingReleases = true;
      _releases = [];
      _selectedRelease = null;
      _binAssets = [];
      _statusMessage = loc.translate('releases_loading');
    });

    final Map<String, dynamic> headers = {
      'User-Agent': 'Xteink-Toolkit-App',
      'Accept': 'application/vnd.github.v3+json',
    };
    final String token = _tokenController.text.trim();
    if (token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    try {
      final response = await _dio.get(
        'https://api.github.com/repos/$repoKey/releases',
        options: Options(headers: headers),
      );

      if (response.statusCode == 200 && response.data is List) {
        List<dynamic> allReleases = response.data;
        List<dynamic> filteredReleases = [];
        for (var release in allReleases) {
          var assets = release['assets'] as List<dynamic>? ?? [];
          bool hasBin = assets.any(
            (asset) => asset['name'].toString().toLowerCase().endsWith('.bin'),
          );
          if (hasBin) {
            filteredReleases.add(release);
          }
        }

        // 🎯 СОХРАНЯЕМ В КЭШ
        _cachedReleases[repoKey] = filteredReleases;
        _lastFetchTime = DateTime.now();

        setState(() {
          _releases = filteredReleases;
          if (_releases.isNotEmpty) {
            _selectedRelease = _releases[0];
            _extractBinAssets();
            _statusMessage = '${loc.translate('releases_available')}: ${_releases.length}';
          } else {
            _statusMessage = loc.translate('releases_no_bins');
          }
        });
      }
    } on DioException catch (e) {
      setState(() {
        if (e.response?.statusCode == 403) {
          _statusMessage = token.isEmpty
              ? loc.translate('releases_rate_limit_no_token')
              : loc.translate('releases_rate_limit_with_token');
        } else {
          _statusMessage = '${loc.translate('releases_network_error')}: ${e.message}';
        }
      });
    } catch (e) {
      setState(() {
        _statusMessage = '${loc.translate('error')}: $e';
      });
    } finally {
      setState(() {
        _isLoadingReleases = false;
      });
    }
  }

  void _extractBinAssets() {
    if (_selectedRelease == null) return;
    var assets = _selectedRelease['assets'] as List<dynamic>? ?? [];
    setState(() {
      _binAssets = assets
          .where((asset) => asset['name'].toString().toLowerCase().endsWith('.bin'))
          .toList();
    });
  }

  Future<void> _downloadAsset(dynamic asset) async {
    final loc = AppLocalizations.of(context);
    final fileName = asset['name'] as String;
    final downloadUrl = asset['browser_download_url'] as String;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _currentDownloadingFile = fileName;
      _statusMessage = loc.translate('releases_download');
    });

    try {
      final int sdkVersion = await _getAndroidSdkVersion();
      if (sdkVersion >= 30) {
        // === Android 11+ (API 30+): прямое сохранение через manageExternalStorage ===
        var status = await Permission.manageExternalStorage.status;
        if (!status.isGranted) {
          status = await Permission.manageExternalStorage.request();
          if (!status.isGranted) {
            setState(() {
              _statusMessage = loc.translate('converter_error_permission');
              _isDownloading = false;
            });
            return;
          }
        }

        // 🎯 НОВЫЙ ПУТЬ: Download/X4Flow/Firmwares
        final targetDir = Directory('/storage/emulated/0/Download/X4Flow/Firmwares');
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }
        final savePath = '${targetDir.path}/$fileName';

        await _dio.download(
          downloadUrl,
          savePath,
          onReceiveProgress: (received, total) {
            if (total != -1) {
              setState(() {
                _downloadProgress = received / total;
              });
            }
          },
        );

        setState(() {
          _statusMessage = '${loc.translate('releases_downloaded')}: $fileName';
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ $fileName ${loc.translate('releases_saved')}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        // === Android 9-10 (API 28-29): скачиваем во временную директорию,
        // затем предлагаем пользователю сохранить через FilePicker ===
        final tempDir = await getTemporaryDirectory();
        final tempPath = '${tempDir.path}/$fileName';

        await _dio.download(
          downloadUrl,
          tempPath,
          onReceiveProgress: (received, total) {
            if (total != -1) {
              setState(() {
                _downloadProgress = received / total;
              });
            }
          },
        );

        final tempFile = File(tempPath);
        if (!await tempFile.exists()) {
          throw Exception("Temporary file not found after download");
        }

        final bytes = await tempFile.readAsBytes();
        final saveResult = await FilePicker.platform.saveFile(
          dialogTitle: '${loc.translate('releases_downloaded')} $fileName',
          fileName: fileName,
          bytes: bytes,
        );

        try {
          await tempFile.delete();
        } catch (_) {}

        if (saveResult != null) {
          setState(() {
            _statusMessage = '${loc.translate('releases_downloaded')}: $fileName';
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ $fileName ${loc.translate('releases_saved')}'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          setState(() {
            _statusMessage = 'Save cancelled';
          });
        }
      }
    } catch (e) {
      setState(() {
        _statusMessage = '${loc.translate('error')}: $e';
      });
    } finally {
      setState(() {
        _isDownloading = false;
        _currentDownloadingFile = '';
      });
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context);

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // GitHub Token
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ExpansionTile(
              title: Text(
                loc.translate('releases_github_limits'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              leading: Icon(Icons.key_outlined, color: theme.colorScheme.primary, size: 20),
              childrenPadding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              dense: true,
              children: [
                Text(
                  loc.translate('releases_token_hint'),
                  style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tokenController,
                        obscureText: true,
                        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                        decoration: InputDecoration(
                          hintText: 'ghp_xxxxxxxxxxxx',
                          labelText: 'GitHub Token',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          suffixIcon: _tokenController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () async {
                                    _tokenController.clear();
                                    await _saveToken();
                                  },
                                  tooltip: loc.translate('releases_clear_token'),
                                )
                              : null,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isTokenSaved && _tokenController.text.trim().isNotEmpty)
                          const Icon(Icons.check_circle, color: Colors.green, size: 18),
                        if (_isTokenSaved && _tokenController.text.trim().isNotEmpty)
                          const SizedBox(width: 4),
                        IconButton.filledTonal(
                          onPressed: _isDownloading || _isLoadingReleases
                              ? null
                              : () async {
                                  await _saveToken();
                                  if (_tokenController.text.trim().isNotEmpty) {
                                    _fetchReleases(forceRefresh: true);
                                  }
                                },
                          icon: const Icon(Icons.save_outlined, size: 18),
                          tooltip: loc.translate('releases_save_token'),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Repository selector + Refresh button
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<Map<String, String>>(
                  value: _selectedRepo,
                  decoration: InputDecoration(
                    labelText: loc.translate('releases_select_repo'),
                    prefixIcon: const Icon(Icons.source_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: _repositories.map((repo) {
                    return DropdownMenuItem(value: repo, child: Text(repo['name']!));
                  }).toList(),
                  onChanged: _isDownloading || _isLoadingReleases
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() {
                              _selectedRepo = value;
                            });
                            _fetchReleases(); // Обычная загрузка (с кэшем)
                          }
                        },
                ),
              ),
              const SizedBox(width: 8),
              // 🎯 КНОПКА ПРИНУДИТЕЛЬНОГО ОБНОВЛЕНИЯ
              IconButton.filledTonal(
                onPressed: _isDownloading || _isLoadingReleases
                    ? null
                    : () => _fetchReleases(forceRefresh: true),
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Обновить (игнорировать кэш)',
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Release selector
          if (_releases.isNotEmpty) ...[
            DropdownButtonFormField<dynamic>(
              value: _selectedRelease,
              decoration: InputDecoration(
                labelText: loc.translate('releases_select_version'),
                prefixIcon: const Icon(Icons.label_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              items: _releases.map((release) {
                return DropdownMenuItem(
                  value: release,
                  child: Text(release['tag_name'] ?? release['name'] ?? 'Untitled'),
                );
              }).toList(),
              onChanged: _isDownloading || _isLoadingReleases
                  ? null
                  : (value) {
                      setState(() {
                        _selectedRelease = value;
                        _extractBinAssets();
                      });
                    },
            ),
            const SizedBox(height: 12),
          ],

          // Status card
          Card(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                children: [
                  if (_isLoadingReleases)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8.0),
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                  if (_isDownloading) ...[
                    Text(
                      '${loc.translate('releases_download')} $_currentDownloadingFile',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: theme.colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _downloadProgress),
                    const SizedBox(height: 6),
                    Text(
                      '${(_downloadProgress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(color: theme.colorScheme.onSurface),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    _statusMessage.isEmpty
                        ? loc.translate('releases_select_repo')
                        : _statusMessage,
                    style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Bin assets list
          Expanded(
            child: _binAssets.isEmpty
                ? Center(
                    child: Text(
                      _isLoadingReleases
                          ? loc.translate('releases_loading')
                          : loc.translate('releases_no_bins'),
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.builder(
                    itemCount: _binAssets.length,
                    itemBuilder: (context, index) {
                      final asset = _binAssets[index];
                      final int size = asset['size'] ?? 0;
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: Icon(Icons.developer_board, color: theme.colorScheme.primary),
                          title: Text(
                            asset['name'],
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text('📦 ${_formatSize(size)}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.file_download_outlined, color: Colors.blue),
                            onPressed: _isDownloading ? null : () => _downloadAsset(asset),
                            tooltip: 'Download .bin',
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}