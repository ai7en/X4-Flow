import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_localizations.dart';

class SettingsScreen extends StatefulWidget {
  final ValueChanged<Locale> onLocaleChanged;
  final ValueChanged<ThemeMode> onThemeChanged;

  const SettingsScreen({
    super.key,
    required this.onLocaleChanged,
    required this.onThemeChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _currentLanguage = 'ru';
  int _themeModeIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentLanguage = prefs.getString('language') ?? 'ru';
      _themeModeIndex = prefs.getInt('themeMode') ?? 0;
    });
  }

  Future<void> _changeLanguage(String lang) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('language', lang);
  setState(() => _currentLanguage = lang);
  final newLocale = Locale(lang);
  widget.onLocaleChanged(newLocale);
  
  // 🎯 Ждём следующий кадр, чтобы MaterialApp успел перестроиться
  if (mounted) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    });
  }
}

  Future<void> _changeTheme(int modeIndex) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', modeIndex);
    setState(() => _themeModeIndex = modeIndex);

    widget.onThemeChanged(ThemeMode.values[modeIndex]);

    final loc = AppLocalizations.of(context);
    final messages = ['theme_system', 'theme_light', 'theme_dark'];
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.translate(messages[modeIndex])),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.translate('settings')),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // Язык — SegmentedButton (там короткие слова, влезает)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.language, color: theme.colorScheme.primary, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        loc.translate('language'),
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'ru',
                        label: Text(loc.translate('russian')),
                        icon: const Text('🇷🇺', style: TextStyle(fontSize: 20)),
                      ),
                      ButtonSegment(
                        value: 'en',
                        label: Text(loc.translate('english')),
                        icon: const Text('🇬🇧', style: TextStyle(fontSize: 20)),
                      ),
                    ],
                    selected: {_currentLanguage},
                    onSelectionChanged: (set) => _changeLanguage(set.first),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 🎯 Тема — теперь DropdownButtonFormField
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.palette, color: theme.colorScheme.primary, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        loc.translate('theme'),
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: _themeModeIndex,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 0,
                        child: Row(
                          children: [
                            const Icon(Icons.brightness_auto, size: 20),
                            const SizedBox(width: 12),
                            Text(loc.translate('theme_system')),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 1,
                        child: Row(
                          children: [
                            const Icon(Icons.light_mode, size: 20),
                            const SizedBox(width: 12),
                            Text(loc.translate('theme_light')),
                          ],
                        ),
                      ),
                      DropdownMenuItem(
                        value: 2,
                        child: Row(
                          children: [
                            const Icon(Icons.dark_mode, size: 20),
                            const SizedBox(width: 12),
                            Text(loc.translate('theme_dark')),
                          ],
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) _changeTheme(value);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // О приложении
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info, color: theme.colorScheme.primary, size: 24),
                      const SizedBox(width: 12),
                      Text(
                        loc.translate('about'),
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(loc.translate('version'),
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                      const Text('1.0.3', style: TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}