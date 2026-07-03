import 'package:flutter/material.dart';

class AppLocalizations {
  final Locale locale;

  AppLocalizations(this.locale);

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static final Map<String, Map<String, String>> _localizedValues = {
    'ru': {
      // Общие
      'app_title': 'X4 Flow',
      'settings': 'Настройки',
      'language': 'Язык',
      'russian': 'Русский',
      'english': 'English',
      'theme': 'Тема',
      'theme_system': 'Системная',
      'theme_light': 'Светлая',
      'theme_dark': 'Тёмная',
      'about': 'О приложении',
      'version': 'Версия',
      'close': 'Закрыть',
      'save': 'Сохранить',
      'cancel': 'Отмена',
      'ok': 'OK',
      'error': 'Ошибка',
      'success': 'Успешно',

      // Вкладки
      'tab_books': 'Книги',
      'tab_wallpapers': 'Обои',
      'tab_fonts': 'Шрифты',
      'tab_releases': 'Релизы',
      'tab_wifi': 'Wi-Fi Панель',

      // AppBar заголовки
      'title_converter': 'Конвертер книг FB2 ➔ ePUB',
      'title_wallpapers': 'Конструктор обоев Xteink',
      'title_releases': 'Релизы GitHub',
      'title_wifi': 'Подключение к Xteink',

      // Конвертер книг
      'converter_waiting': 'Ожидание выбора файлов',
      'converter_select': 'Выбрать файлы',
      'converter_convert': 'Конвертировать',
      'converter_processing': 'Обработка книги',
      'converter_success': 'Успешно сконвертировано книг',
      'converter_error_no_fb2':
          'Ни один из выбранных файлов не является .fb2 или .zip',
      'converter_error_permission': 'Отказ в доступе к памяти устройства',
      'converter_error_permission_hint':
          'Для автоматического сохранения необходимо предоставить доступ в настройках!',
      'converter_dialog_success_title': 'Успешно!',
      'converter_dialog_success_path': 'Путь к файлам',
      'converter_dialog_success_folder':
          'Внутренняя память ➔ Download ➔ Fb2Epub',
      'converter_optimize_subtitle_fb2': 'Ресайз под %w×%h, grayscale, JPEG',
      'converter_optimize_subtitle_epub': 'Обязательно для EPUB оптимизации',
      
      // 🆕 НОВЫЕ КЛЮЧИ ДЛЯ КОНВЕРТЕРА
      'converter_mode_fb2': 'FB2 ➔ EPUB',
      'converter_mode_optimize': 'Оптим. EPUB',
      'converter_target_device': 'Целевое устройство',
      'converter_optimize_images': '🎨 Оптимизировать картинки',

      // Обои
      'wallpaper_size': 'Размер',
      'wallpaper_select_photo': 'Выбрать фото',
      'wallpaper_save_bmp': 'Сохранить BMP',
      'wallpaper_mode_photo': 'Фото',
      'wallpaper_mode_quote': 'Цитата',
      'wallpaper_mode_calendar': 'Календарь',
      'wallpaper_hide_controls': 'Скрыть настройки',
      'wallpaper_show_controls': 'Показать настройки',
      'wallpaper_tab_position': 'Положение',
      'wallpaper_tab_bw': 'Настройки ЧБ',
      'wallpaper_center': 'По центру / Сброс',
      'wallpaper_rotate': 'Повернуть на 90°',
      'wallpaper_stretch': 'Растянуть по рамке (исказить)',
      'wallpaper_align_width': 'Выровнять по ширине',
      'wallpaper_align_height': 'Выровнять по высоте',
      'wallpaper_stretched_hint':
          'Изображение принудительно растянуто по рамке. Ручное позиционирование отключено.',
      'wallpaper_dithering': 'Сглаживание (Дизеринг)',
      'wallpaper_quote_random': 'Случайная цитата',
      'wallpaper_quote_style': 'Стиль (E-Ink)',
      'wallpaper_calendar_today': 'Сегодня',
      'wallpaper_calendar_black_bg': 'Чёрный фон',
      'wallpaper_calendar_white_bg': 'Белый фон',
      'wallpaper_year_button': 'Скачать год',
      'wallpaper_year_generating': 'Генерация календаря:',
      'wallpaper_year_success': 'Календарь на год сохранён в ZIP',
      'wallpaper_save_year': 'Сохранить календарь на год',

      // Релизы GitHub
      'releases_github_limits': 'Лимиты GitHub API (Опционально)',
      'releases_token_hint':
          'Если GitHub временно заблокировал ваш IP, вы можете создать бесплатный "Personal Access Token (classic)" в настройках своего профиля GitHub (раздел Developer Settings) и вставить его сюда:',
      'releases_select_repo': 'Выберите проект прошивки',
      'releases_select_version': 'Доступные версии прошивок',
      'releases_loading': 'Загрузка списка релизов...',
      'releases_available': 'Доступно релизов',
      'releases_no_bins': 'В этом репозитории не найдено .bin файлов прошивки',
      'releases_rate_limit_no_token':
          'Превышен лимит запросов к GitHub API. Попробуйте сменить IP (выкл. VPN) или добавьте GitHub Token выше.',
      'releases_rate_limit_with_token':
          'Превышен лимит даже для токена или токен введен неверно.',
      'releases_network_error': 'Ошибка сети',
      'releases_download': 'Скачивание файла прошивки...',
      'releases_downloaded': 'Скачан',
      'releases_saved': 'успешно сохранен в XteinkFirmware',
      'releases_token_saved': 'Токен сохранён и применён',
      'releases_token_deleted': 'Токен удалён',
      'releases_save_token': 'Сохранить токен и обновить',
      'releases_clear_token': 'Очистить токен',

      // Wi-Fi панель
      'wifi_preparation': 'Подготовка читалки Xteink:',
      'wifi_step1':
          '1. На читалке откройте: File Transfer ➔ Wi-Fi book upload.',
      'wifi_step2':
          '2. Подключите читалку к Wi-Fi сети (или к точке доступа смартфона).',
      'wifi_step3': '3. Смартфон должен находиться в этой же Wi-Fi сети.',
      'wifi_address_label': 'Локальный адрес веб-панели',
      'wifi_address_hint': 'crosspoint.local или IP-адрес читалки',
      'wifi_connect': 'Открыть веб-панель',  // 🎯 ИСПРАВЛЕНО: убрано "CrossInk"
      'wifi_back': 'Назад',
      'wifi_refresh': 'Обновить',
      'wifi_disconnect': 'Отключиться',

      // Конвертер шрифтов
      'title_font_converter': 'Конвертер шрифтов .cpfont',
      'font_select_files': 'Файлы шрифтов',
      'font_family_name': 'Имя семейства шрифтов',
      'font_bit_depth': 'Глубина цвета (E-Ink)',
      'font_2bit': '2-bit (4 оттенка)',
      'font_1bit': '1-bit (ч/б)',
      'font_sizes': 'Размеры шрифта',
      'font_unicode_ranges': 'Unicode-диапазоны',
      'font_range_ascii': 'ASCII (латиница)',
      'font_range_cyrillic': 'Кириллица',
      'font_range_latin': 'Латиница расширенная',
      'font_rendering_options': 'Настройки рендеринга',
      'font_convert_btn': 'Скомпилировать шрифт',
      'font_error_select': 'Выберите файл шрифта',
      'font_success': 'Шрифт сохранён',
      'font_mode_label': 'Режим конвертера:',
      'font_mode_native': 'Нативный (Dart)',
      'font_mode_webview': 'WebView (WASM)',
      'font_error_not_ttf': 'Выберите файл .ttf или .otf',
    },
    'en': {
      // General
      'app_title': 'X4 Flow',
      'settings': 'Settings',
      'language': 'Language',
      'russian': 'Русский',
      'english': 'English',
      'theme': 'Theme',
      'theme_system': 'System',
      'theme_light': 'Light',
      'theme_dark': 'Dark',
      'about': 'About',
      'version': 'Version',
      'close': 'Close',
      'save': 'Save',
      'cancel': 'Cancel',
      'ok': 'OK',
      'error': 'Error',
      'success': 'Success',

      // Tabs
      'tab_books': 'Books',
      'tab_wallpapers': 'Wallpapers',
      'tab_fonts': 'Fonts',
      'tab_releases': 'Releases',
      'tab_wifi': 'Wi-Fi Panel',

      // AppBar titles
      'title_converter': 'FB2 ➔ ePUB Converter',
      'title_wallpapers': 'Wallpaper Generator',
      'title_releases': 'GitHub Releases',
      'title_wifi': 'Xteink Connection',

      // Converter
      'converter_waiting': 'Waiting for file selection',
      'converter_select': 'Select files',
      'converter_convert': 'Convert',
      'converter_processing': 'Processing book',
      'converter_success': 'Successfully converted books',
      'converter_error_no_fb2': 'None of the selected files are .fb2 or .zip',
      'converter_error_permission': 'Storage access denied',
      'converter_error_permission_hint':
          'Access must be granted in settings for automatic saving!',
      'converter_dialog_success_title': 'Success!',
      'converter_dialog_success_path': 'File path',
      'converter_dialog_success_folder':
          'Internal storage ➔ Download ➔ Fb2Epub',
      'converter_optimize_subtitle_fb2': 'Resize to %w×%h, grayscale, JPEG',
      'converter_optimize_subtitle_epub': 'Required for EPUB optimization',
      
      // 🆕 NEW KEYS FOR CONVERTER
      'converter_mode_fb2': 'FB2 ➔ EPUB',
      'converter_mode_optimize': 'Opt. EPUB',
      'converter_target_device': 'Target device',
      'converter_optimize_images': '🎨 Optimize images',

      // Wallpapers
      'wallpaper_size': 'Size',
      'wallpaper_select_photo': 'Select photo',
      'wallpaper_save_bmp': 'Save BMP',
      'wallpaper_mode_photo': 'Photo',
      'wallpaper_mode_quote': 'Quote',
      'wallpaper_mode_calendar': 'Calendar',
      'wallpaper_hide_controls': 'Hide settings',
      'wallpaper_show_controls': 'Show settings',
      'wallpaper_tab_position': 'Position',
      'wallpaper_tab_bw': 'B&W Settings',
      'wallpaper_center': 'Center / Reset',
      'wallpaper_rotate': 'Rotate 90°',
      'wallpaper_stretch': 'Stretch to fit (distort)',
      'wallpaper_align_width': 'Align to width',
      'wallpaper_align_height': 'Align to height',
      'wallpaper_stretched_hint':
          'Image is stretched to fit. Manual positioning is disabled.',
      'wallpaper_dithering': 'Dithering',
      'wallpaper_quote_random': 'Random quote',
      'wallpaper_quote_style': 'Style (E-Ink)',
      'wallpaper_calendar_today': 'Today',
      'wallpaper_calendar_black_bg': 'Black background',
      'wallpaper_calendar_white_bg': 'White background',
      'wallpaper_year_button': 'Download year',
      'wallpaper_year_generating': 'Generating calendar:',
      'wallpaper_year_success': 'Year calendar saved to ZIP',
      'wallpaper_save_year': 'Save year calendar',

      // Font converter
      'title_font_converter': '.cpfont Font Converter',
      'font_select_files': 'Font files',
      'font_family_name': 'Font family name',
      'font_bit_depth': 'Color depth (E-Ink)',
      'font_2bit': '2-bit (4 shades)',
      'font_1bit': '1-bit (B&W)',
      'font_sizes': 'Font sizes',
      'font_unicode_ranges': 'Unicode ranges',
      'font_range_ascii': 'ASCII (Latin)',
      'font_range_cyrillic': 'Cyrillic',
      'font_range_latin': 'Latin Extended',
      'font_rendering_options': 'Rendering options',
      'font_convert_btn': 'Compile font',
      'font_error_select': 'Select font file',
      'font_success': 'Font saved',
      'font_mode_label': 'Converter mode:',
      'font_mode_native': 'Native (Dart)',
      'font_mode_webview': 'WebView (WASM)',
      'font_error_not_ttf': 'Please select .ttf or .otf file',

      // Releases
      'releases_github_limits': 'GitHub API Limits (Optional)',
      'releases_token_hint':
          'If GitHub has temporarily blocked your IP, you can create a free "Personal Access Token (classic)" in your GitHub profile settings (Developer Settings section) and paste it here:',
      'releases_select_repo': 'Select firmware project',
      'releases_select_version': 'Available firmware versions',
      'releases_loading': 'Loading releases...',
      'releases_available': 'Releases available',
      'releases_no_bins': 'No .bin firmware files found in this repository',
      'releases_rate_limit_no_token':
          'GitHub API rate limit exceeded. Try changing your IP (disable VPN) or add a GitHub Token above.',
      'releases_rate_limit_with_token':
          'Rate limit exceeded even with token or token is invalid.',
      'releases_network_error': 'Network error',
      'releases_download': 'Downloading firmware file...',
      'releases_downloaded': 'Downloaded',
      'releases_saved': 'saved to XteinkFirmware',
      'releases_token_saved': 'Token saved and applied',
      'releases_token_deleted': 'Token deleted',
      'releases_save_token': 'Save token and refresh',
      'releases_clear_token': 'Clear token',

      // Wi-Fi
      'wifi_preparation': 'Xteink reader preparation:',
      'wifi_step1':
          '1. On the reader, open: File Transfer ➔ Wi-Fi book upload.',
      'wifi_step2':
          '2. Connect the reader to Wi-Fi network (or smartphone hotspot).',
      'wifi_step3': '3. Smartphone must be on the same Wi-Fi network.',
      'wifi_address_label': 'Local web panel address',
      'wifi_address_hint': 'crosspoint.local or reader IP address',
      'wifi_connect': 'Open web panel',  // 🎯 FIXED: removed "CrossInk"
      'wifi_back': 'Back',
      'wifi_refresh': 'Refresh',
      'wifi_disconnect': 'Disconnect',
    },
  };

  String translate(String key) {
    return _localizedValues[locale.languageCode]?[key] ??
        _localizedValues['ru']![key] ??
        key;
  }
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return ['ru', 'en'].contains(locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) async {
    return AppLocalizations(locale);
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}