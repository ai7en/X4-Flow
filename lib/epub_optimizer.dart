import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:image/image.dart' as img;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'device_profile.dart';

class EpubOptimizer {
  /// Оптимизирует картинки внутри готового EPUB файла под профиль устройства.
  /// Если [coverImagePath] задан — заменяет (или добавляет) обложку.
  Future<void> optimize({
    required String inputPath,
    required String outputPath,
    required DeviceProfile profile,
    required Function(String status) onStatusUpdate,
    String? coverImagePath,
  }) async {
    onStatusUpdate("📖 Чтение EPUB файла...");
    final bytes = await File(inputPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    onStatusUpdate("🔍 Поиск OPF файла...");
    String opfPath = 'OEBPS/content.opf';
    final containerFile = archive.files.firstWhere(
      (f) => f.name == 'META-INF/container.xml',
      orElse: () => ArchiveFile('', 0, []),
    );
    if (containerFile.content != null && (containerFile.content as List<int>).isNotEmpty) {
      try {
        final containerXml = XmlDocument.parse(
          utf8.decode(containerFile.content as List<int>),
        );
        final rootfile = containerXml.findAllElements('rootfile').firstOrNull;
        if (rootfile != null) {
          opfPath = rootfile.getAttribute('full-path') ?? opfPath;
        }
      } catch (_) {}
    }

    final opfDir = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';

    onStatusUpdate("📄 Парсинг OPF...");
    final opfFile = archive.files.firstWhere(
      (f) => f.name == opfPath,
      orElse: () => ArchiveFile('', 0, []),
    );
    if (opfFile.content == null || (opfFile.content as List<int>).isEmpty) {
      throw Exception("OPF файл не найден в EPUB");
    }

    final opfXml = XmlDocument.parse(utf8.decode(opfFile.content as List<int>));
    final manifest = opfXml.findAllElements('manifest').firstOrNull;
    final metadata = opfXml.findAllElements('metadata').firstOrNull;
    final spine = opfXml.findAllElements('spine').firstOrNull;
    final guide = opfXml.findAllElements('guide').firstOrNull;
    final package = opfXml.findAllElements('package').firstOrNull;

    if (manifest == null || metadata == null || spine == null || package == null) {
      throw Exception("Некорректная структура OPF");
    }

    // --- Ищем существующую обложку в manifest ---
    // Ищем по: meta name="cover" → id, или id="cover", или href содержащий "cover"
    String? existingCoverId;
    String? existingCoverHref;
    String? existingCoverFullPath;

    // Сначала ищем по meta name="cover"
    for (final meta in metadata.findAllElements('meta')) {
      if (meta.getAttribute('name') == 'cover') {
        existingCoverId = meta.getAttribute('content');
        break;
      }
    }

    // Теперь ищем в manifest
    XmlElement? coverItem;
    for (final item in manifest.findAllElements('item')) {
      final id = item.getAttribute('id') ?? '';
      final href = item.getAttribute('href') ?? '';
      
      if (existingCoverId != null && id == existingCoverId) {
        coverItem = item;
        existingCoverHref = href;
        existingCoverFullPath = opfDir + href;
        break;
      }
      if (id.toLowerCase() == 'cover' || href.toLowerCase().contains('cover')) {
        // Запоминаем первый найденный, но продолжаем искать точное совпадение по meta
        if (coverItem == null) {
          coverItem = item;
          existingCoverId = id;
          existingCoverHref = href;
          existingCoverFullPath = opfDir + href;
        }
      }
    }

    // --- Подготовка пользовательской обложки ---
    Uint8List? userCoverBytes;
    const String newCoverHref = 'cover.jpeg';
    final String newCoverFullPath = opfDir + newCoverHref;

    if (coverImagePath != null) {
      onStatusUpdate("🖼️ Подготовка пользовательской обложки...");
      final coverBytes = await File(coverImagePath).readAsBytes();
      userCoverBytes = _optimizeImageForceJpeg(coverBytes, profile);
    }

    // --- Сборка нового архива ---
    final newArchive = Archive();
    int optimizedCount = 0;
    bool coverReplaced = false;
    final Set<String> filesToSkip = {}; // файлы которые не копируем (старая обложка)

    if (coverImagePath != null && existingCoverFullPath != null && existingCoverFullPath != newCoverFullPath) {
      // Старая обложка в другом месте — не копируем её
      filesToSkip.add(existingCoverFullPath);
    }

    // mimetype первым без сжатия
    final mimeFile = archive.files.firstWhere(
      (f) => f.name == 'mimetype',
      orElse: () => ArchiveFile(
        'mimetype',
        utf8.encode('application/epub+zip').length,
        utf8.encode('application/epub+zip'),
      ),
    );
    newArchive.addFile(
      ArchiveFile(
        'mimetype',
        (mimeFile.content as List<int>).length,
        mimeFile.content as List<int>,
      )..compress = false,
    );

    // Собираем image items для обычной оптимизации
    final imageItems = <XmlElement>[];
    for (final item in manifest.findAllElements('item')) {
      final mediaType = item.getAttribute('media-type') ?? '';
      if (mediaType.startsWith('image/')) {
        imageItems.add(item);
      }
    }

    for (final file in archive.files) {
      if (file.name == 'mimetype') continue;
      
      // Пропускаем старую обложку, если она в другом месте
      if (filesToSkip.contains(file.name)) {
        onStatusUpdate("🗑️ Удалена старая обложка: ${file.name}");
        continue;
      }

      // Замена существующей обложки на пользовательскую (если путь совпадает)
      if (coverImagePath != null && file.name == existingCoverFullPath) {
        newArchive.addFile(
          ArchiveFile(newCoverFullPath, userCoverBytes!.length, userCoverBytes),
        );
        coverReplaced = true;
        onStatusUpdate("🖼️ Обложка заменена");
        continue;
      }

      // Обычная оптимизация остальных картинок
      bool isImage = false;
      String? href;
      for (final item in imageItems) {
        final itemHref = item.getAttribute('href') ?? '';
        final fullPath = opfDir + itemHref;
        final normalizedFullPath = fullPath.replaceAll('../', '');
        if (file.name == fullPath ||
            file.name == normalizedFullPath ||
            file.name == itemHref) {
          isImage = true;
          href = itemHref;
          break;
        }
      }

      if (isImage && file.content != null) {
        try {
          final originalBytes = Uint8List.fromList(file.content as List<int>);
          final optimizedBytes = _optimizeImage(originalBytes, profile);

          if (optimizedBytes != null) {
            newArchive.addFile(
              ArchiveFile(file.name, optimizedBytes.length, optimizedBytes),
            );
            optimizedCount++;
            onStatusUpdate("✅ $href: оптимизировано");
            continue;
          }
        } catch (e) {
          // оставляем оригинал
        }
      }

      // Пропускаем старый OPF — добавим модифицированный отдельно
      if (file.name == opfPath) continue;

      // Копируем как есть
      newArchive.addFile(
        ArchiveFile(
          file.name,
          (file.content as List<int>).length,
          file.content as List<int>,
        ),
      );
    }

    // --- Модификация OPF (только если заменяем/добавляем обложку) ---
    if (coverImagePath != null) {
      // Удаляем старую meta cover
      metadata.children.removeWhere((node) {
        if (node is XmlElement) {
          return node.name.local == 'meta' && node.getAttribute('name') == 'cover';
        }
        return false;
      });

      // Удаляем ВСЕ старые cover item из manifest
      manifest.children.removeWhere((node) {
        if (node is XmlElement) {
          final id = node.getAttribute('id') ?? '';
          final href = node.getAttribute('href') ?? '';
          return node.name.local == 'item' &&
              (id == existingCoverId || 
               id.toLowerCase() == 'cover' || 
               href.toLowerCase().contains('cover'));
        }
        return false;
      });

      // Добавляем новый cover item
      manifest.children.add(XmlElement(
        XmlName('item'),
        [
          XmlAttribute(XmlName('id'), 'cover'),
          XmlAttribute(XmlName('href'), newCoverHref),
          XmlAttribute(XmlName('media-type'), 'image/jpeg'),
        ],
      ));

      // Добавляем meta cover
      metadata.children.add(XmlElement(
        XmlName('meta'),
        [
          XmlAttribute(XmlName('name'), 'cover'),
          XmlAttribute(XmlName('content'), 'cover'),
        ],
      ));

      // Обновляем guide — меняем href на новый cover
      if (guide != null) {
        for (final ref in guide.findAllElements('reference')) {
          final type = ref.getAttribute('type') ?? '';
          if (type == 'cover') {
            ref.setAttribute('href', 'titlepage.xhtml');
          }
        }
      }

      // Проверяем наличие titlepage
      bool hasTitlepage = false;
      for (final item in manifest.findAllElements('item')) {
        final href = item.getAttribute('href')?.toLowerCase() ?? '';
        if (href.contains('titlepage') || href.contains('title-page')) {
          hasTitlepage = true;
          break;
        }
      }

      if (!hasTitlepage) {
        // Добавляем titlepage.xhtml
        const titlepageContent = '''<?xml version='1.0' encoding='utf-8'?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>Cover</title></head>
<body><div><img src="cover.jpeg" alt="cover"/></div></body>
</html>''';
        final tpBytes = utf8.encode(titlepageContent);
        final tpPath = opfDir + 'titlepage.xhtml';
        newArchive.addFile(ArchiveFile(tpPath, tpBytes.length, tpBytes));

        manifest.children.add(XmlElement(
          XmlName('item'),
          [
            XmlAttribute(XmlName('id'), 'titlepage'),
            XmlAttribute(XmlName('href'), 'titlepage.xhtml'),
            XmlAttribute(XmlName('media-type'), 'application/xhtml+xml'),
          ],
        ));

        // Вставляем в начало spine
        spine.children.insert(0, XmlElement(
          XmlName('itemref'),
          [XmlAttribute(XmlName('idref'), 'titlepage')],
        ));

        // Добавляем/создаём guide
        if (guide != null) {
          // Проверим, есть ли уже cover reference
          bool hasCoverRef = false;
          for (final ref in guide.findAllElements('reference')) {
            if (ref.getAttribute('type') == 'cover') {
              hasCoverRef = true;
              break;
            }
          }
          if (!hasCoverRef) {
            guide.children.add(XmlElement(
              XmlName('reference'),
              [
                XmlAttribute(XmlName('type'), 'cover'),
                XmlAttribute(XmlName('href'), 'titlepage.xhtml'),
                XmlAttribute(XmlName('title'), 'Cover'),
              ],
            ));
          }
        } else {
          final spineIndex = package.children.indexOf(spine);
          package.children.insert(spineIndex + 1, XmlElement(
            XmlName('guide'),
            [],
            [
              XmlElement(
                XmlName('reference'),
                [
                  XmlAttribute(XmlName('type'), 'cover'),
                  XmlAttribute(XmlName('href'), 'titlepage.xhtml'),
                  XmlAttribute(XmlName('title'), 'Cover'),
                ],
              ),
            ],
          ));
        }
      }

      // Если обложки не было в архиве или была в другом месте — добавляем файл
      if (!coverReplaced) {
        newArchive.addFile(
          ArchiveFile(newCoverFullPath, userCoverBytes!.length, userCoverBytes),
        );
      }
    }

    // Сохраняем модифицированный OPF
    final modifiedOpfBytes = utf8.encode(opfXml.toXmlString(pretty: true));
    newArchive.addFile(ArchiveFile(opfPath, modifiedOpfBytes.length, modifiedOpfBytes));

    onStatusUpdate("📦 Сборка оптимизированного EPUB...");
    final newBytes = ZipEncoder().encode(newArchive);
    if (newBytes == null) throw Exception("Ошибка сборки ZIP");

    await File(outputPath).writeAsBytes(newBytes);
    onStatusUpdate("🎉 Готово! Оптимизировано $optimizedCount изображений");
  }

  Uint8List? _optimizeImage(Uint8List bytes, DeviceProfile profile) {
    try {
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return null;

      if (image.hasAlpha) {
        for (final pixel in image) {
          if (pixel.a < 255) {
            final alpha = pixel.a / 255.0;
            pixel.r = (pixel.r * alpha + 255 * (1.0 - alpha)).round();
            pixel.g = (pixel.g * alpha + 255 * (1.0 - alpha)).round();
            pixel.b = (pixel.b * alpha + 255 * (1.0 - alpha)).round();
            pixel.a = 255;
          }
        }
      }

      image = img.grayscale(image);

      if (image.width > profile.width || image.height > profile.height) {
        final widthRatio = profile.width / image.width;
        final heightRatio = profile.height / image.height;
        final ratio = widthRatio < heightRatio ? widthRatio : heightRatio;
        image = img.copyResize(
          image,
          width: (image.width * ratio).round(),
          height: (image.height * ratio).round(),
        );
      }

      if (bytes.length >= 3 &&
          bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        return Uint8List.fromList(img.encodeJpg(image, quality: 75));
      } else if (bytes.length >= 8 &&
          bytes[0] == 0x89 && bytes[1] == 0x50 &&
          bytes[2] == 0x4E && bytes[3] == 0x47) {
        return Uint8List.fromList(img.encodePng(image, level: 6));
      } else {
        return Uint8List.fromList(img.encodeJpg(image, quality: 75));
      }
    } catch (_) {
      return null;
    }
  }

  /// Принудительно сохраняет как JPEG (для пользовательской обложки)
  Uint8List _optimizeImageForceJpeg(Uint8List bytes, DeviceProfile profile) {
    try {
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return bytes;

      if (image.hasAlpha) {
        for (final pixel in image) {
          if (pixel.a < 255) {
            final alpha = pixel.a / 255.0;
            pixel.r = (pixel.r * alpha + 255 * (1.0 - alpha)).round();
            pixel.g = (pixel.g * alpha + 255 * (1.0 - alpha)).round();
            pixel.b = (pixel.b * alpha + 255 * (1.0 - alpha)).round();
            pixel.a = 255;
          }
        }
      }

      image = img.grayscale(image);

      if (image.width > profile.width || image.height > profile.height) {
        final widthRatio = profile.width / image.width;
        final heightRatio = profile.height / image.height;
        final ratio = widthRatio < heightRatio ? widthRatio : heightRatio;
        image = img.copyResize(
          image,
          width: (image.width * ratio).round(),
          height: (image.height * ratio).round(),
        );
      }

      return Uint8List.fromList(img.encodeJpg(image, quality: 80));
    } catch (_) {
      return bytes;
    }
  }
}