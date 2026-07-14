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
      'tab_wifi': 'Wi-Fi',

      // AppBar заголовки
      'title_converter': 'Конвертер книг FB2 ➔ ePUB',
      'title_wallpapers': 'Конструктор обоев Xteink',
      'title_font_converter': 'Конвертер шрифтов .cpfont',
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
          'Внутренняя память ➔ Download ➔ X4Flow ➔ Books',
      'converter_optimize_subtitle_fb2': 'Ресайз под %w×%h, grayscale, JPEG',
      'converter_optimize_subtitle_epub': 'Обязательно для EPUB оптимизации',
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
      'releases_saved': 'успешно сохранен в Download/X4Flow/Firmwares',
      'releases_token_saved': 'Токен сохранён и применён',
      'releases_token_deleted': 'Токен удалён',
      'releases_save_token': 'Сохранить токен и обновить',
      'releases_clear_token': 'Очистить токен',
      'releases_cache_info': 'кэш',
      'releases_cache_minutes': 'мин',

      // Wi-Fi панель
      'wifi_preparation': 'Подготовка читалки Xteink:',
      'wifi_step1':
          '1. На читалке откройте: File Transfer ➔ Wi-Fi book upload.',
      'wifi_step2':
          '2. Подключите читалку к Wi-Fi сети (или к точке доступа смартфона).',
      'wifi_step3': '3. Смартфон должен находиться в этой же Wi-Fi сети.',
      'wifi_address_label': 'Локальный адрес веб-панели',
      'wifi_address_hint': 'crosspoint.local или IP-адрес читалки',
      'wifi_connect': 'Подключить',
      'wifi_back': 'Назад',
      'wifi_refresh': 'Обновить',
      'wifi_disconnect': 'Отключиться',

      // Конвертер шрифтов
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
      'font_converting': 'Компиляция шрифтов...',
      'font_progress': 'Обработка размера',
      'font_files_section': 'Выбор файлов шрифтов (до 4 стилей)',
      'font_regular_required': 'Regular .TTF/.OTF (обязательно)',
      'font_regular_selected': 'Regular: ',
      'font_optional_styles': 'Опциональные стили (если не выбраны — симуляция):',
      'font_bold': 'Bold',
      'font_italic': 'Italic',
      'font_bold_italic': 'Bold Italic',
      'font_crosspoint_params': 'Параметры шрифта',  // 🆕 переименовано
      'font_family_label': 'Font Family',
      'font_family_helper': 'Имя папки и префикс файлов',
      'font_sizes_label': 'Размеры:',
      'font_unicode_label': 'Unicode диапазоны:',
      'font_base_coverage_tooltip':
          'Базовое покрытие (профиль "Reading (Fiction)": ASCII, Latin-1, основная типографика — тире/кавычки/троеточие) включено всегда и не показано отдельным пунктом.',
      'font_custom_ranges_label': 'Дополнительные диапазоны (опционально)',
      'font_custom_ranges_helper':
          'Через запятую, например: (0x2900-0x29FF),(0x2E00-0x2EFF)',
      'font_eink_settings': 'Настройки E-Ink',
      'font_2bit_title': '2-Bit (4 оттенка серого)',
      'font_compiling_progress': 'Компиляция: ',
      'font_compile_button': 'Скомпилировать .cpfont',
      'font_preview': 'Предпросмотр',
      'font_preview_hint':
          'Так же на устройстве синтезируются начертания, для которых не загружен отдельный файл — можно свериться заранее.',
      'font_synthetic': ' (синтетика)',
      'font_error_no_regular': 'Пожалуйста, выберите хотя бы Regular шрифт (.ttf/.otf)',
      'font_error_empty_family': 'Имя семейства шрифта не может быть пустым',
      'font_error_wrong_format': 'Неверный формат файла! Выберите .ttf или .otf',
      'font_error_pick': 'Ошибка выбора файла: ',
      'font_error_preview': 'Не удалось загрузить шрифт для превью: ',
      'font_error_no_size': 'Выберите хотя бы один целевой размер шрифта',
      'font_success_message': '✅ Все стили записаны в: ',
      'font_error_convert': 'Ошибка выполнения: ',
      'font_preset_cyrillic': 'Кириллица',
      'font_preset_latin_ext': 'Латиница расширенная (европейские языки)',
      'font_preset_greek': 'Греческий',
      'font_preset_symbols': 'Символы и стрелки',
      'font_range_latin_ext': 'Латиница расширенная (европейские языки)',
      'font_range_greek': 'Греческий',
      'font_range_symbols': 'Символы и стрелки',
      // 🆕 Новые пресеты Unicode (по списку crosspointreader.com/fonts)
      'font_preset_vietnamese': 'Вьетнамский',
      'font_preset_hebrew': 'Иврит',
      'font_preset_armenian': 'Армянский',
      'font_preset_georgian': 'Грузинский',
      'font_preset_ethiopic': 'Эфиопский (амхарский и др.)',
      'font_preset_cherokee': 'Чероки',
      'font_preset_tifinagh': 'Тифинаг',
      'font_preset_thai': 'Тайский',
      'font_preset_hangul': 'Хангыль (корейский)',
      'font_preset_chinese': 'Китайский (упрощённый)',
      'font_preset_japanese': 'Японский',
      'font_preset_heavy_warning':
          'Тысячи глифов — конвертация займёт заметно больше времени, файл будет большим',
      'font_preset_heavy_dialog_title': 'Большой набор символов',
      'font_preset_heavy_dialog_body':
          'Этот скрипт содержит несколько тысяч символов (иероглифы/слоги). Конвертация может занять много времени, а итоговый файл шрифта будет значительно больше обычного. Продолжить?',
      'font_cancel': 'Отмена',
      'font_confirm': 'Продолжить',
      // 🆕 Stem calibration & sections
      'font_stem_calibration': 'Калибровка штриха',
      'font_stem_calibration_subtitle':
          'Подбирает размер рендеринга для чистых штрихов на E-Ink (рекомендуется для мелких кеглей)',
      'font_sizes_section': 'Размеры шрифта',
      'font_unicode_section': 'Диапазоны Unicode',
      'font_use_freetype': 'Растеризация через FreeType',
      'font_use_freetype_subtitle': 'Настоящий хинтинг шрифта (как у официального конвертера) вместо приближения через dart:ui',

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
      'tab_wifi': 'Wi-Fi',

      // AppBar titles
      'title_converter': 'FB2 ➔ ePUB Converter',
      'title_wallpapers': 'Wallpaper Generator',
      'title_font_converter': '.cpfont Font Converter',
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
          'Internal storage ➔ Download ➔ X4Flow ➔ Books',
      'converter_optimize_subtitle_fb2': 'Resize to %w×%h, grayscale, JPEG',
      'converter_optimize_subtitle_epub': 'Required for EPUB optimization',
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
      'font_converting': 'Compiling fonts...',
      'font_progress': 'Processing size',
      'font_files_section': 'Font files (up to 4 styles)',
      'font_regular_required': 'Regular .TTF/.OTF (required)',
      'font_regular_selected': 'Regular: ',
      'font_optional_styles': 'Optional styles (if not selected — simulated):',
      'font_bold': 'Bold',
      'font_italic': 'Italic',
      'font_bold_italic': 'Bold Italic',
      'font_crosspoint_params': 'Font parameters',  // 🆕 renamed
      'font_family_label': 'Font Family',
      'font_family_helper': 'Folder name and file prefix',
      'font_sizes_label': 'Sizes:',
      'font_unicode_label': 'Unicode ranges:',
      'font_base_coverage_tooltip':
          'Base coverage ("Reading (Fiction)" profile: ASCII, Latin-1, basic typography — dashes/quotes/ellipsis) is always included and not shown separately.',
      'font_custom_ranges_label': 'Additional ranges (optional)',
      'font_custom_ranges_helper':
          'Comma-separated, e.g.: (0x2900-0x29FF),(0x2E00-0x2EFF)',
      'font_eink_settings': 'E-Ink settings',
      'font_2bit_title': '2-Bit (4 shades of gray)',
      'font_compiling_progress': 'Compiling: ',
      'font_compile_button': 'Compile .cpfont',
      'font_preview': 'Preview',
      'font_preview_hint':
          'Also on device, styles without separate files are synthesized — you can check in advance.',
      'font_synthetic': ' (synthetic)',
      'font_error_no_regular': 'Please select at least a Regular font (.ttf/.otf)',
      'font_error_empty_family': 'Font family name cannot be empty',
      'font_error_wrong_format': 'Wrong file format! Select .ttf or .otf',
      'font_error_pick': 'File selection error: ',
      'font_error_preview': 'Failed to load font for preview: ',
      'font_error_no_size': 'Select at least one target font size',
      'font_success_message': '✅ All styles saved to: ',
      'font_error_convert': 'Execution error: ',
      'font_preset_cyrillic': 'Cyrillic',
      'font_preset_latin_ext': 'Latin Extended (European languages)',
      'font_preset_greek': 'Greek',
      'font_preset_symbols': 'Symbols and arrows',
      'font_range_latin_ext': 'Latin Extended (European languages)',
      'font_range_greek': 'Greek',
      'font_range_symbols': 'Symbols and arrows',
      // 🆕 New Unicode presets (matching crosspointreader.com/fonts list)
      'font_preset_vietnamese': 'Vietnamese',
      'font_preset_hebrew': 'Hebrew',
      'font_preset_armenian': 'Armenian',
      'font_preset_georgian': 'Georgian',
      'font_preset_ethiopic': 'Ethiopic (Amharic, etc.)',
      'font_preset_cherokee': 'Cherokee',
      'font_preset_tifinagh': 'Tifinagh',
      'font_preset_thai': 'Thai',
      'font_preset_hangul': 'Hangul (Korean)',
      'font_preset_chinese': 'Chinese (Simplified)',
      'font_preset_japanese': 'Japanese',
      'font_preset_heavy_warning':
          'Thousands of glyphs — conversion will take noticeably longer, the file will be large',
      'font_preset_heavy_dialog_title': 'Large character set',
      'font_preset_heavy_dialog_body':
          'This script contains several thousand characters (ideographs/syllables). Conversion may take a long time, and the resulting font file will be significantly larger than usual. Continue?',
      'font_cancel': 'Cancel',
      'font_confirm': 'Continue',
      'font_use_freetype': 'FreeType rasterization',
      'font_use_freetype_subtitle': 'Real font hinting (like the official converter) instead of the dart:ui approximation',

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
      'releases_saved': 'saved to Download/X4Flow/Firmwares',
      'releases_token_saved': 'Token saved and applied',
      'releases_token_deleted': 'Token deleted',
      'releases_save_token': 'Save token and refresh',
      'releases_clear_token': 'Clear token',
      'releases_cache_info': 'cache',
      'releases_cache_minutes': 'min',

      // Wi-Fi
      'wifi_preparation': 'Xteink reader preparation:',
      'wifi_step1':
          '1. On the reader, open: File Transfer ➔ Wi-Fi book upload.',
      'wifi_step2':
          '2. Connect the reader to Wi-Fi network (or smartphone hotspot).',
      'wifi_step3': '3. Smartphone must be on the same Wi-Fi network.',
      'wifi_address_label': 'Local web panel address',
      'wifi_address_hint': 'crosspoint.local or reader IP address',
      'wifi_connect': 'Connect',
      'wifi_back': 'Back',
      'wifi_refresh': 'Refresh',
      'wifi_disconnect': 'Disconnect',

      // 🆕 Stem calibration & sections
      'font_stem_calibration': 'Stem calibration',
      'font_stem_calibration_subtitle':
          'Picks render size for crisp stems on E-Ink (recommended for small sizes)',
      'font_sizes_section': 'Font sizes',
      'font_unicode_section': 'Unicode ranges',
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