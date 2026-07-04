import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'converter_screen.dart';
import 'wallpaper_screen.dart';
import 'font_converter_screen.dart';
import 'firmware_screen.dart';
import 'transfer_screen.dart';
import 'app_localizations.dart';
import 'settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const XteinkApp());
}

class XteinkApp extends StatefulWidget {
  const XteinkApp({super.key});

  @override
  State<XteinkApp> createState() => _XteinkAppState();
}

class _XteinkAppState extends State<XteinkApp> {
  ThemeMode _themeMode = ThemeMode.system;
  Locale _locale = const Locale('ru');

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('themeMode') ?? 0;
    final lang = prefs.getString('language') ?? 'ru';
    setState(() {
      _themeMode = ThemeMode.values[themeIndex];
      _locale = Locale(lang);
    });
  }

  void _updateLocale(Locale newLocale) {
    setState(() => _locale = newLocale);
  }

  void _updateThemeMode(ThemeMode newMode) {
    setState(() => _themeMode = newMode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      themeMode: _themeMode,
      locale: _locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ru'),
        Locale('en'),
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
      ),
      home: MainHomeScreen(
        onLocaleChanged: _updateLocale,
        onThemeChanged: _updateThemeMode,
      ),
    );
  }
}

class MainHomeScreen extends StatefulWidget {
  final ValueChanged<Locale> onLocaleChanged;
  final ValueChanged<ThemeMode> onThemeChanged;
  const MainHomeScreen({
    super.key,
    required this.onLocaleChanged,
    required this.onThemeChanged,
  });

  @override
  State<MainHomeScreen> createState() => _MainHomeScreenState();
}

class _MainHomeScreenState extends State<MainHomeScreen> {
  int _currentIndex = 0;
  final List<Widget> _screens = const [
    ConverterScreen(),
    WallpaperScreen(),
    FontConverterScreen(), // 🎯 ДОБАВЛЕНО: шрифты теперь в навигации
    FirmwareScreen(),
    TransferScreen(),
  ];

  String _getAppBarTitle(AppLocalizations loc) {
    switch (_currentIndex) {
      case 0:
        return loc.translate('title_converter');
      case 1:
        return loc.translate('title_wallpapers');
      case 2:
        return loc.translate('title_font_converter'); // 🎯 НОВЫЙ заголовок
      case 3:
        return loc.translate('tab_releases');
      case 4:
        return loc.translate('title_wifi');
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _getAppBarTitle(loc),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          // 🎯 УБРАНА пасхалка - теперь обычная кнопка настроек
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(
                    onLocaleChanged: widget.onLocaleChanged,
                    onThemeChanged: widget.onThemeChanged,
                  ),
                ),
              );
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: theme.colorScheme.outlineVariant.withOpacity(0.4),
            height: 1,
          ),
        ),
      ),
      backgroundColor: theme.colorScheme.background,
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() => _currentIndex = index);
        },
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        height: 70,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.library_books_outlined),
            selectedIcon: const Icon(Icons.library_books),
            label: loc.translate('tab_books'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.image_outlined),
            selectedIcon: const Icon(Icons.image),
            label: loc.translate('tab_wallpapers'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.text_fields_outlined),
            selectedIcon: const Icon(Icons.text_fields),
            label: loc.translate('tab_fonts'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.cloud_download_outlined),
            selectedIcon: const Icon(Icons.cloud_download),
            label: loc.translate('tab_releases'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.wifi_outlined),
            selectedIcon: const Icon(Icons.wifi),
            label: loc.translate('tab_wifi'),
          ),
        ],
      ),
    );
  }
}