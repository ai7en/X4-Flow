import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:image/image.dart' as img;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'device_profile.dart';

class EpubOptimizer {
  /// Оптимизирует картинки внутри готового EPUB файла под профиль устройства
  Future<void> optimize({
    required String inputPath,
    required String outputPath,
    required DeviceProfile profile,
    required Function(String status) onStatusUpdate,
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
    if (containerFile.content != null) {
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

    onStatusUpdate("📄 Парсинг OPF manifest...");
    final opfFile = archive.files.firstWhere(
      (f) => f.name == opfPath,
      orElse: () => ArchiveFile('', 0, []),
    );
    if (opfFile.content == null) {
      throw Exception("OPF файл не найден в EPUB");
    }

    final opfXml = XmlDocument.parse(utf8.decode(opfFile.content as List<int>));
    final manifest = opfXml.findAllElements('manifest').firstOrNull;
    if (manifest == null) {
      throw Exception("Manifest не найден в OPF");
    }

    final imageItems = <XmlElement>[];
    for (final item in manifest.findAllElements('item')) {
      final mediaType = item.getAttribute('media-type') ?? '';
      if (mediaType.startsWith('image/')) {
        imageItems.add(item);
      }
    }

    onStatusUpdate("🎨 Оптимизация ${imageItems.length} изображений под ${profile.name}...");
    
    // Базовая директория OPF для разрешения относительных путей
    final opfDir = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';

    final newArchive = Archive();
    int optimizedCount = 0;

    // Копируем mimetype ПЕРВЫМ и БЕЗ СЖАТИЯ (требование стандарта EPUB)
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

    for (final file in archive.files) {
      if (file.name == 'mimetype') continue;

      // Проверяем, является ли этот файл картинкой из manifest
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
            onStatusUpdate("✅ $href: оптимизировано (${originalBytes.length} → ${optimizedBytes.length} байт)");
            continue;
          }
        } catch (e) {
          // Если оптимизация не удалась — оставляем оригинал
        }
      }

      // Копируем файл как есть
      newArchive.addFile(
        ArchiveFile(
          file.name,
          (file.content as List<int>).length,
          file.content as List<int>,
        ),
      );
    }

    onStatusUpdate("📦 Сборка оптимизированного EPUB...");
    final newBytes = ZipEncoder().encode(newArchive);
    if (newBytes == null) throw Exception("Ошибка сборки ZIP");

    await File(outputPath).writeAsBytes(newBytes);
    onStatusUpdate("🎉 Готово! Оптимизировано $optimizedCount из ${imageItems.length} картинок");
  }

  Uint8List? _optimizeImage(Uint8List bytes, DeviceProfile profile) {
    try {
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return null;

      // Убираем альфа-канал (заменяем на белый фон)
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

      // Grayscale
      image = img.grayscale(image);

      // Ресайз под целевое устройство
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

      // Сохраняем в ОРИГИНАЛЬНОМ формате, чтобы не ломать OPF и XHTML
      if (bytes.length >= 3 &&
          bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
        // JPEG
        return Uint8List.fromList(img.encodeJpg(image, quality: 75));
      } else if (bytes.length >= 8 &&
          bytes[0] == 0x89 && bytes[1] == 0x50 &&
          bytes[2] == 0x4E && bytes[3] == 0x47) {
        // PNG
        return Uint8List.fromList(img.encodePng(image, level: 6));
      } else {
        // WebP или другое — сохраняем как JPEG
        return Uint8List.fromList(img.encodeJpg(image, quality: 75));
      }
    } catch (_) {
      return null;
    }
  }
}