import 'package:xml/xml.dart';
import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'device_profile.dart';

class ConversionResult {
  final Uint8List epubBytes;
  final String title;
  final String author;

  ConversionResult({
    required this.epubBytes,
    required this.title,
    required this.author,
  });
}

class TocNode {
  final String title;
  final String href;
  final int depth;
  final List<TocNode> children = [];

  TocNode({required this.title, required this.href, required this.depth});
}

class Fb2ToEpubConverter {
  static const Map<String, String> _htmlEntities = {
    'nbsp': '\u00A0', 'mdash': '\u2014', 'ndash': '\u2013',
    'laquo': '\u00AB', 'raquo': '\u00BB', 'ldquo': '\u201C', 'rdquo': '\u201D',
    'lsquo': '\u2018', 'rsquo': '\u2019', 'hellip': '\u2026',
    'bull': '\u2022', 'middot': '\u00B7', 'copy': '\u00A9', 'reg': '\u00AE',
    'trade': '\u2122', 'sect': '\u00A7', 'deg': '\u00B0', 'plusmn': '\u00B1',
    'times': '\u00D7', 'divide': '\u00F7', 'micro': '\u00B5', 'para': '\u00B6',
    'sbquo': '\u201A', 'bdquo': '\u201E', 'quot': '"', 'amp': '&',
    'lt': '<', 'gt': '>', 'apos': "'", 'iexcl': '\u00A1', 'cent': '\u00A2',
    'pound': '\u00A3', 'curren': '\u00A4', 'yen': '\u00A5', 'brvbar': '\u00A6',
    'uml': '\u00A8', 'ordf': '\u00AA', 'not': '\u00AC', 'shy': '\u00AD',
    'macr': '\u00AF', 'acute': '\u00B4', 'cedil': '\u00B8', 'ordm': '\u00BA',
    'frac14': '\u00BC', 'frac12': '\u00BD', 'frac34': '\u00BE', 'iquest': '\u00BF',
  };

  String _decodeWindows1251(Uint8List bytes) {
    final chars = List<int>.filled(bytes.length, 0);
    for (int i = 0; i < bytes.length; i++) {
      int b = bytes[i];
      if (b < 0x80) {
        chars[i] = b;
      } else if (b >= 0xC0 && b <= 0xFF) {
        chars[i] = 0x0410 + (b - 0xC0);
      } else {
        switch (b) {
          case 0xA4: chars[i] = 0x0454; break;
          case 0xA6: chars[i] = 0x0456; break;
          case 0xA7: chars[i] = 0x0457; break;
          case 0xA8: chars[i] = 0x0401; break;
          case 0xAA: chars[i] = 0x0404; break;
          case 0xAF: chars[i] = 0x0407; break;
          case 0xB2: chars[i] = 0x0406; break;
          case 0xB3: chars[i] = 0x0456; break;
          case 0xB8: chars[i] = 0x0451; break;
          case 0x91: chars[i] = 0x2018; break;
          case 0x92: chars[i] = 0x2019; break;
          case 0x93: chars[i] = 0x201C; break;
          case 0x94: chars[i] = 0x201D; break;
          case 0x96: chars[i] = 0x2013; break;
          case 0x97: chars[i] = 0x2014; break;
          default: chars[i] = b;
        }
      }
    }
    return String.fromCharCodes(chars);
  }

  String _detectImageMimeType(Uint8List bytes) {
    if (bytes.length < 8) return 'application/octet-stream';
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return 'image/jpeg';
    if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return 'image/png';
    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38) return 'image/gif';
    if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
        bytes.length >= 12 &&
        bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
      return 'image/webp';
    }
    return 'application/octet-stream';
  }

  String _sanitizeXml(String input) {
    String result = input.replaceAllMapped(
      RegExp(r'&([a-zA-Z]+);'),
      (match) {
        final entityName = match.group(1)!;
        if (_htmlEntities.containsKey(entityName)) {
          return _htmlEntities[entityName]!;
        }
        return '&amp;$entityName;';
      },
    );

    result = result.replaceAllMapped(
      RegExp(r'&#(x[0-9a-fA-F]+|\d+);'),
      (match) {
        final numStr = match.group(1)!;
        try {
          int codePoint;
          if (numStr.startsWith('x') || numStr.startsWith('X')) {
            codePoint = int.parse(numStr.substring(1), radix: 16);
          } else {
            codePoint = int.parse(numStr);
          }
          if (codePoint >= 0 && codePoint <= 0x10FFFF &&
              !(codePoint >= 0xD800 && codePoint <= 0xDFFF)) {
            return String.fromCharCode(codePoint);
          }
        } catch (_) {}
        return '';
      },
    );

    result = result.replaceAllMapped(
      RegExp(r'&(?!amp;|lt;|gt;|quot;|apos;)'),
      (match) => '&amp;',
    );

    return result;
  }

  String _escapeXhtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// Достаёт href независимо от префикса namespace (href / l:href / xlink:href / ...).
  /// Старый код проверял только 'href' и буквально 'l:href', из-за чего сноски
  /// в файлах, где использовался другой префикс (например xlink:href), просто
  /// оставались без ссылки.
  String _getHref(XmlElement node) {
    for (final attr in node.attributes) {
      if (attr.name.local.toLowerCase() == 'href') {
        return attr.value;
      }
    }
    return '';
  }

  Uint8List _optimizeImageForEInk(Uint8List inputBytes, DeviceProfile profile) {
    try {
      img.Image? image = img.decodeImage(inputBytes);
      if (image == null) return inputBytes;

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

      return Uint8List.fromList(img.encodeJpg(image, quality: 75));
    } catch (_) {
      return inputBytes;
    }
  }

  /// Текст первого абзаца примечания — используется как всплывающая подсказка (title=)
  String _getFootnoteText(String noteId, List<XmlElement> notesSections) {
    for (var sec in notesSections) {
      final id = sec.getAttribute('id');
      if (id == noteId) {
        final firstP = sec.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local.toLowerCase() == 'p')
            .firstOrNull;
        if (firstP != null) {
          String text = firstP.innerText.trim();
          if (text.length > 100) {
            text = '${text.substring(0, 100)}...';
          }
          return text;
        }
        return '';
      }
    }
    return '';
  }

  /// 🎯 ГЛАВНЫЙ ФИКС СТРУКТУРЫ:
  /// _processTextContainer обрабатывает ДЕТЕЙ переданного узла и решает, во что
  /// обернуть каждого ребёнка, глядя на его localName (в т.ч. 'p' → абзац).
  /// Раньше _extractSectionContent передавал сюда сам <p> как "контейнер",
  /// из-за чего ветка `localName == 'p'` никогда не срабатывала для абзацев
  /// верхнего уровня — они не оборачивались в <p>/<div class="paragraph">
  /// целиком, а текст и вложенное форматирование (курсив, сноски и т.п.)
  /// расползались по отдельным несвязанным блокам. Теперь _extractSectionContent
  /// вызывает эту же функцию НАД самой секцией с skipTags — и диспетчеризация
  /// по тегам работает одинаково что для верхнего уровня, что для вложенных
  /// узлов (epigraph, cite, table и т.д.).
  String _processTextContainer(
    XmlNode container, {
    bool inline = false,
    List<XmlElement>? notesSections,
    Map<String, String>? sectionIdToFile,
    Map<String, String>? noteBacklinks,
    String? currentFileName,
    Set<String>? skipTags,
  }) {
    StringBuffer sb = StringBuffer();
    for (var node in container.children) {
      if (node is XmlText) {
        if (inline) {
          sb.write(_escapeXhtml(node.value));
        } else {
          final text = node.value.trim();
          if (text.isNotEmpty) {
            if (text.startsWith('—') || text.startsWith('–')) {
              sb.write('<p class="dialog">${_escapeXhtml(node.value)}</p>');
            } else {
              sb.write('<p class="paragraph">${_escapeXhtml(node.value)}</p>');
            }
          }
        }
      } else if (node is XmlElement) {
        final localName = node.name.local.toLowerCase();
        if (skipTags != null && skipTags.contains(localName)) continue;

        if (localName == 'p') {
          final innerText = node.innerText.trim();
          final cls = (innerText.startsWith('—') || innerText.startsWith('–')) ? 'dialog' : 'paragraph';
          sb.write('<p class="$cls">${_processTextContainer(node, inline: true, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)}</p>');
        } else if (localName == 'strong' || localName == 'b') {
          sb.write('<strong class="calibre10">${_processTextContainer(node, inline: true, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)}</strong>');
        } else if (localName == 'emphasis' || localName == 'i') {
          sb.write('<em class="calibre9">${_processTextContainer(node, inline: true, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)}</em>');
        } else if (localName == 'strikethrough' || localName == 'strike') {
          sb.write('<del>${_processTextContainer(node, inline: true, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)}</del>');
        } else if (localName == 'sub') {
          sb.write('<sub>${_processTextContainer(node, inline: true, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)}</sub>');
        } else if (localName == 'sup') {
          sb.write('<sup class="calibre14">${_processTextContainer(node, inline: true, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)}</sup>');
        } else if (localName == 'code') {
          sb.write('<code>${_processTextContainer(node, inline: true, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)}</code>');
        } else if (localName == 'title') {
          final paragraphs = node.children.whereType<XmlElement>().where((e) => e.name.local.toLowerCase() == 'p').toList();
          if (paragraphs.length > 1) {
            final parts = paragraphs.map((p) => _processTextContainer(p, inline: true, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)).join('<br class="calibre8"/>');
            sb.write('<h1 class="calibre2">$parts</h1>');
          } else {
            sb.write('<h1 class="calibre2">${_processTextContainer(node, inline: true, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)}</h1>');
          }
        } else if (localName == 'subtitle') {
          sb.write('<div class="subtitle">${_processTextContainer(node, inline: true, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)}</div>');
        } else if (localName == 'text-author') {
          sb.write('<p class="paragraph text-author"><em>${_processTextContainer(node, inline: true, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)}</em></p>');
        } else if (localName == 'image') {
          final href = _getHref(node);
          final cleanHref = href.replaceAll('#', '');
          if (cleanHref.isNotEmpty) {
            sb.write('<div class="calibre1"><img src="$cleanHref" alt="image" class="calibre8"/></div>');
          }
        } else if (localName == 'a') {
          final href = _getHref(node);
          final type = node.getAttribute('type') ?? '';
          if (href.isNotEmpty) {
            if (type == 'note' && href.startsWith('#')) {
              final noteId = href.substring(1).trim();
              final noteText = notesSections != null ? _getFootnoteText(noteId, notesSections) : '';
              final titleAttr = noteText.isNotEmpty ? ' title="${_escapeXhtml(noteText)}"' : '';

              // Резолвим путь к файлу примечаний, если уже известен на этот момент.
              // Если ещё нет (порядок обхода) — оставляем "#id", он будет
              // гарантированно дорезолвлен финальным проходом ниже, после того
              // как sectionIdToFile полностью построена.
              String resolvedHref = href;
              if (sectionIdToFile != null && sectionIdToFile.containsKey(noteId)) {
                resolvedHref = '${sectionIdToFile[noteId]}#$noteId';
              }

              // Запоминаем, откуда именно пришли на сноску — чтобы "стрелка назад"
              // на странице примечаний вела в правильный файл и на правильный якорь.
              final backAnchor = 'ref_$noteId';
              if (noteBacklinks != null && currentFileName != null) {
                noteBacklinks[noteId] = '$currentFileName#$backAnchor';
              }

              sb.write('<a href="$resolvedHref"$titleAttr id="$backAnchor" class="calibre12"><sup class="calibre14">${_processTextContainer(node, inline: true, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)}</sup></a>');
            } else {
              sb.write('<a href="$href">${_processTextContainer(node, inline: true, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)}</a>');
            }
          } else {
            sb.write(_processTextContainer(node, inline: true, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName));
          }
        } else if (localName == 'empty-line') {
          sb.write('<p class="calibre1" style="margin:0pt; border:0pt; height:1em"> </p>');
        } else if (localName == 'v') {
          sb.write('<p class="paragraph">${_processTextContainer(node, inline: true, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)}</p>');
        } else if (localName == 'stanza') {
          sb.write('<div class="calibre11">${_processTextContainer(node, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)}</div>');
        } else if (localName == 'poem') {
          sb.write('<div class="calibre11">${_processTextContainer(node, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)}</div>');
        } else if (localName == 'epigraph') {
          sb.write('<blockquote class="epigraph">${_processTextContainer(node, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)}</blockquote>');
        } else if (localName == 'cite') {
          sb.write('<blockquote class="cite">${_processTextContainer(node, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)}</blockquote>');
        } else if (localName == 'table') {
          sb.write('<table>${_processTable(node, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)}</table>');
        } else {
          sb.write(_processTextContainer(node, inline: inline, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName));
        }
      }
    }
    return sb.toString();
  }

  String _processTable(XmlElement table, {List<XmlElement>? notesSections, Map<String, String>? sectionIdToFile, Map<String, String>? noteBacklinks, String? currentFileName}) {
    StringBuffer sb = StringBuffer();
    for (var child in table.children.whereType<XmlElement>()) {
      final localName = child.name.local.toLowerCase();
      if (localName == 'tr') {
        sb.write('<tr>${_processTableRow(child, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)}</tr>');
      }
    }
    return sb.toString();
  }

  String _processTableRow(XmlElement tr, {List<XmlElement>? notesSections, Map<String, String>? sectionIdToFile, Map<String, String>? noteBacklinks, String? currentFileName}) {
    StringBuffer sb = StringBuffer();
    for (var child in tr.children.whereType<XmlElement>()) {
      final localName = child.name.local.toLowerCase();
      if (localName == 'th') {
        sb.write('<th>${_processTextContainer(child, inline: true, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)}</th>');
      } else if (localName == 'td') {
        sb.write('<td>${_processTextContainer(child, inline: true, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)}</td>');
      }
    }
    return sb.toString();
  }

  /// Тонкая обёртка: теперь просто прогоняет секцию через тот же диспетчер
  /// тегов, что использует _processTextContainer, только пропуская
  /// вложенные <section> (они — отдельные главы) и <title> (уже вынесен в h1).
  String _extractSectionContent(
    XmlElement section, {
    List<XmlElement>? notesSections,
    Map<String, String>? sectionIdToFile,
    Map<String, String>? noteBacklinks,
    String? currentFileName,
  }) {
    return _processTextContainer(
      section,
      notesSections: notesSections,
      sectionIdToFile: sectionIdToFile,
      noteBacklinks: noteBacklinks,
      currentFileName: currentFileName,
      skipTags: {'section', 'title'},
    );
  }

  void _buildTocTree(XmlElement section, List<TocNode> parentList, int depth, Map<int, String> sectionToFile) {
    String title = "";
    final titleEl = section.children
        .whereType<XmlElement>()
        .where((e) => e.name.local.toLowerCase() == 'title')
        .toList();
    if (titleEl.isNotEmpty) {
      title = titleEl.first.innerText.trim().replaceAll('\n', ' ');
    }

    final sectionIndex = sectionToFile.entries
        .where((e) => e.value == section.hashCode.toString())
        .firstOrNull?.key;
    if (title.isEmpty || sectionIndex == null) return;

    final fileName = 'index_split_${sectionIndex.toString().padLeft(3, '0')}.xhtml';
    final node = TocNode(title: title, href: fileName, depth: depth);
    parentList.add(node);

    for (var child in section.children.whereType<XmlElement>()) {
      if (child.name.local.toLowerCase() == 'section') {
        _buildTocTree(child, node.children, depth + 1, sectionToFile);
      }
    }
  }

  String _generateTocHtml(List<TocNode> tocTree) {
    StringBuffer sb = StringBuffer();
    sb.write('<ul class="calibre4">');
    _writeTocNodes(sb, tocTree);
    sb.write('</ul>');
    return sb.toString();
  }

  void _writeTocNodes(StringBuffer sb, List<TocNode> nodes) {
    for (final node in nodes) {
      sb.write('<li class="calibre5"><a href="${node.href}">${_escapeXhtml(node.title)}</a>');
      if (node.children.isNotEmpty) {
        sb.write('<ul class="calibre6">');
        _writeTocNodes(sb, node.children);
        sb.write('</ul>');
      }
      sb.write('</li>');
    }
  }

  String _generateNcx(List<TocNode> tocTree, String bookTitle, String uid) {
    StringBuffer navMap = StringBuffer();
    int playOrder = 1;
    int maxDepth = 1;

    void writeNodes(List<TocNode> nodes) {
      for (final node in nodes) {
        if (node.depth > maxDepth) maxDepth = node.depth;
        final id = 'toc_${playOrder}_${node.title.hashCode.abs()}';
        navMap.write('<navPoint id="$id" playOrder="$playOrder">\n');
        navMap.write('<navLabel><text>${_escapeXhtml(node.title)}</text></navLabel>\n');
        navMap.write('<content src="${node.href}"/>\n');
        if (node.children.isNotEmpty) {
          writeNodes(node.children);
        }
        navMap.write('</navPoint>\n');
        playOrder++;
      }
    }

    writeNodes(tocTree);

    return '''<?xml version='1.0' encoding='utf-8'?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1" xml:lang="rus">
<head>
<meta name="dtb:uid" content="$uid"/>
<meta name="dtb:depth" content="$maxDepth"/>
<meta name="dtb:totalPageCount" content="0"/>
<meta name="dtb:maxPageNumber" content="0"/>
</head>
<docTitle><text>${_escapeXhtml(bookTitle)}</text></docTitle>
<navMap>
$navMap</navMap>
</ncx>''';
  }

  Future<ConversionResult> convert({
    required String inputPath,
    required Function(String status) onStatusUpdate,
    bool optimize = false,
    DeviceProfile? profile,
  }) async {
    final file = File(inputPath);
    final bytes = await file.readAsBytes();
    String fb2Content;
    try {
      fb2Content = utf8.decode(bytes);
    } catch (_) {
      onStatusUpdate("Смена кодировки на Windows-1251...");
      fb2Content = _decodeWindows1251(bytes);
    }

    onStatusUpdate("🧼 Санитария XML и декодирование entities...");
    fb2Content = _sanitizeXml(fb2Content);

    onStatusUpdate("Парсинг структуры XML...");
    final document = XmlDocument.parse(fb2Content);
    final bodyElements = document.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local.toLowerCase() == 'body')
        .toList();

    if (bodyElements.isEmpty) {
      throw Exception("В структуре FB2 не найден тег <body>");
    }

    final mainBody = bodyElements.first;

    String bookTitle = "Untitled Book";
    String authorName = "Unknown Author";
    String annotation = "";
    String coverImageId = "";

    final titleInfoElements = document.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local.toLowerCase() == 'title-info')
        .toList();

    if (titleInfoElements.isNotEmpty) {
      final tInfo = titleInfoElements.first;

      final bTitle = tInfo.children
          .whereType<XmlElement>()
          .where((e) => e.name.local.toLowerCase() == 'book-title')
          .toList();
      if (bTitle.isNotEmpty) {
        bookTitle = bTitle.first.innerText.trim();
        if (bookTitle.isEmpty) bookTitle = "Untitled Book";
      }

      final annotationEls = tInfo.children
          .whereType<XmlElement>()
          .where((e) => e.name.local.toLowerCase() == 'annotation')
          .toList();
      if (annotationEls.isNotEmpty) {
        annotation = _processTextContainer(annotationEls.first);
      }

      final coverpage = tInfo.children
          .whereType<XmlElement>()
          .where((e) => e.name.local.toLowerCase() == 'coverpage')
          .toList();
      if (coverpage.isNotEmpty) {
        final coverImg = coverpage.first.children
            .whereType<XmlElement>()
            .where((e) => e.name.local.toLowerCase() == 'image')
            .toList();
        if (coverImg.isNotEmpty) {
          final href = _getHref(coverImg.first);
          coverImageId = href.replaceAll('#', '');
        }
      }

      final author = tInfo.children
          .whereType<XmlElement>()
          .where((e) => e.name.local.toLowerCase() == 'author')
          .toList();
      if (author.isNotEmpty) {
        final fName = author.first.children
            .whereType<XmlElement>()
            .where((e) => e.name.local.toLowerCase() == 'first-name')
            .toList();
        final lName = author.first.children
            .whereType<XmlElement>()
            .where((e) => e.name.local.toLowerCase() == 'last-name')
            .toList();
        final mId = author.first.children
            .whereType<XmlElement>()
            .where((e) => e.name.local.toLowerCase() == 'middle-name')
            .toList();

        final first = fName.isNotEmpty ? fName.first.innerText.trim() : '';
        final last = lName.isNotEmpty ? lName.first.innerText.trim() : '';
        final middle = mId.isNotEmpty ? mId.first.innerText.trim() : '';

        final parts = <String>[];
        if (last.isNotEmpty) parts.add(last);
        if (first.isNotEmpty) parts.add(first);
        if (middle.isNotEmpty) parts.add(middle);

        if (parts.isNotEmpty) {
          authorName = parts.join(' ');
        }
      }
    }

    // 🎯 ФИКС: определяем notes-body не по конкретным значениям name=
    // ("notes"/"comments"), а как ЛЮБОЙ <body>, идущий после первого.
    // По спецификации FB2 первый <body> без name — это основной текст,
    // всё остальное — вспомогательный контент (сноски, комментарии,
    // послесловие и т.п.), независимо от того, как он подписан.
    // Старая версия ловила только name="notes"/"comments" и на файлах
    // с другим значением (или без name вовсе) теряла секции сносок целиком,
    // из-за чего ссылки оставались нерезолвленными.
    final List<XmlElement> notesBodies = bodyElements.length > 1
        ? bodyElements.sublist(1)
        : <XmlElement>[];

    onStatusUpdate("Поиск всех глав (рекурсивно, как Calibre)...");

    final allSections = mainBody.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local.toLowerCase() == 'section')
        .toList();

    final List<XmlElement> notesSections = [];
    for (final notesBody in notesBodies) {
      notesSections.addAll(notesBody.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local.toLowerCase() == 'section')
          .toList());
    }

    // Карта section_id → имя файла (для резолва якорных ссылок, включая сноски)
    final Map<String, String> sectionIdToFile = {};
    final Map<int, String> sectionToFile = {};
    int splitIndex = 0;

    if (annotation.isNotEmpty) {
      sectionToFile[splitIndex] = 'annotation';
      splitIndex++;
    }

    for (var sec in allSections) {
      final id = sec.getAttribute('id');
      final titleEl = sec.children
          .whereType<XmlElement>()
          .where((e) => e.name.local.toLowerCase() == 'title')
          .toList();
      final textHtml = _extractSectionContent(sec);

      if (textHtml.trim().isNotEmpty || titleEl.isNotEmpty) {
        sectionToFile[splitIndex] = sec.hashCode.toString();
        if (id != null && id.isNotEmpty) {
          sectionIdToFile[id.trim()] = 'index_split_${splitIndex.toString().padLeft(3, '0')}.xhtml';
        }
        splitIndex++;
      }
    }

    // Все примечания уходят в один файл notes.xhtml (как делает Calibre)
    const String notesFileName = 'notes.xhtml';
    for (var sec in notesSections) {
      final id = sec.getAttribute('id');
      if (id != null && id.isNotEmpty) {
        sectionIdToFile[id.trim()] = notesFileName;
      }
    }

    onStatusUpdate("🌳 Построение иерархического TOC...");
    final List<TocNode> tocTree = [];
    final topLevelSections = mainBody.children
        .whereType<XmlElement>()
        .where((e) => e.name.local.toLowerCase() == 'section')
        .toList();

    for (var sec in topLevelSections) {
      _buildTocTree(sec, tocTree, 1, sectionToFile);
    }

    onStatusUpdate("Экспорт ${sectionToFile.length} глав текста...");
    List<Map<String, String>> chapters = [];
    splitIndex = 0;

    // Куда вести "стрелку назад" со страницы примечаний — noteId → "файл#якорь"
    final Map<String, String> noteBacklinks = {};

    if (annotation.isNotEmpty) {
      chapters.add({
        'title': 'Annotation',
        'fileName': 'index_split_${splitIndex.toString().padLeft(3, '0')}.xhtml',
        'content': '<h1 id="calibre_toc_1" class="calibre2">Annotation</h1>$annotation<br class="calibre1"/>',
      });
      splitIndex++;
    }

    for (var sec in allSections) {
      String chTitle = "Глава $splitIndex";
      final titleEl = sec.children
          .whereType<XmlElement>()
          .where((e) => e.name.local.toLowerCase() == 'title')
          .toList();
      if (titleEl.isNotEmpty) {
        chTitle = titleEl.first.innerText.trim().replaceAll('\n', ' ');
        if (chTitle.isEmpty) chTitle = "Глава $splitIndex";
      }

      final currentFileName = 'index_split_${splitIndex.toString().padLeft(3, '0')}.xhtml';

      String textHtml = _extractSectionContent(
        sec,
        notesSections: notesSections,
        sectionIdToFile: sectionIdToFile,
        noteBacklinks: noteBacklinks,
        currentFileName: currentFileName,
      );

      if (textHtml.trim().isNotEmpty || titleEl.isNotEmpty) {
        String finalContent = '';
        if (titleEl.isNotEmpty) {
          final paragraphs = titleEl.first.children.whereType<XmlElement>().where((e) => e.name.local.toLowerCase() == 'p').toList();
          if (paragraphs.length > 1) {
            final parts = paragraphs.map((p) => _processTextContainer(p, inline: true, notesSections: notesSections, sectionIdToFile: sectionIdToFile, noteBacklinks: noteBacklinks, currentFileName: currentFileName)).join('<br class="calibre8"/>');
            finalContent = '<h1 class="calibre2">$parts</h1>';
          } else {
            finalContent = '<h1 class="calibre2">${_escapeXhtml(chTitle)}</h1>';
          }
        }
        finalContent += textHtml;

        chapters.add({
          'title': chTitle,
          'fileName': currentFileName,
          'content': finalContent,
        });
        splitIndex++;
      }
    }

    // 🎯 Страница примечаний: один файл, все сноски внутри, у каждой рабочая
    // "стрелка назад" (ссылается на id="ref_$id", который реально проставлен
    // на исходной ссылке в тексте — в исходнике этот id нигде не выставлялся,
    // поэтому обратная ссылка была мёртвой).
    if (notesSections.isNotEmpty) {
      StringBuffer notesContent = StringBuffer();
      notesContent.write('<h1 class="calibre2">Примечания</h1>');
      notesContent.write('<hr class="calibre3"/>');

      for (var sec in notesSections) {
        final id = (sec.getAttribute('id') ?? 'unknown').trim();
        String textHtml = _extractSectionContent(
          sec,
          notesSections: notesSections,
          sectionIdToFile: sectionIdToFile,
          noteBacklinks: noteBacklinks,
          currentFileName: notesFileName,
        );

        String noteTitle = "";
        final titleEl = sec.children
            .whereType<XmlElement>()
            .where((e) => e.name.local.toLowerCase() == 'title')
            .toList();
        if (titleEl.isNotEmpty) {
          noteTitle = titleEl.first.innerText.trim();
        }

        final backHref = noteBacklinks[id];

        notesContent.write('<div class="footnote" id="$id">');
        if (backHref != null) {
          notesContent.write('<p class="footnote-backlink"><a href="$backHref">↩</a></p>');
        }
        if (noteTitle.isNotEmpty) {
          notesContent.write('<h3 class="footnote-title">${_escapeXhtml(noteTitle)}</h3>');
        }
        notesContent.write(textHtml);
        notesContent.write('<hr class="footnote-separator"/>');
        notesContent.write('</div>');
      }

      chapters.add({
        'title': 'Примечания',
        'fileName': notesFileName,
        'content': notesContent.toString(),
      });
    }

    Map<String, Map<String, dynamic>> images = {};
    final binaryElements = document.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local.toLowerCase() == 'binary')
        .toList();

    int imgCounter = 0;
    String? coverFileName;
    Map<String, String> fb2IdToEpubName = {};

    for (var bin in binaryElements) {
      final id = bin.getAttribute('id');
      if (id != null && id.isNotEmpty) {
        try {
          final base64Content = bin.innerText.replaceAll(RegExp(r'\s+'), '');
          final rawBytes = base64Decode(base64Content);

          Uint8List finalBytes = Uint8List.fromList(rawBytes);
          String mime = _detectImageMimeType(finalBytes);
          String extension = '.jpeg';
          if (mime == 'image/png') extension = '.png';
          else if (mime == 'image/gif') extension = '.gif';
          else if (mime == 'image/webp') extension = '.webp';

          String epubName;
          if (id == coverImageId) {
            epubName = 'cover$extension';
            coverFileName = epubName;

            if (optimize && profile != null) {
              finalBytes = _optimizeImageForEInk(finalBytes, profile);
              mime = 'image/jpeg';
              epubName = 'cover.jpeg';
              coverFileName = epubName;
            }
            onStatusUpdate("🎨 Обложка обработана");
          } else {
            epubName = '$imgCounter$extension';
            if (optimize && profile != null) {
              finalBytes = _optimizeImageForEInk(finalBytes, profile);
              mime = 'image/jpeg';
              epubName = '$imgCounter.jpeg';
              onStatusUpdate(
                "🎨 Оптимизация картинки $imgCounter/${binaryElements.length} под ${profile.name}...",
              );
            } else {
              onStatusUpdate(
                "Извлечение изображений ($imgCounter/${binaryElements.length})...",
              );
            }
          }

          fb2IdToEpubName[id] = epubName;
          images[epubName] = {
            'bytes': finalBytes,
            'mime': mime,
            'fb2Id': id,
          };
          imgCounter++;
        } catch (_) {}
      }
    }

    for (var ch in chapters) {
      String content = ch['content']!;
      fb2IdToEpubName.forEach((fb2Id, epubName) {
        content = content.replaceAll('../images/$fb2Id', epubName);
        content = content.replaceAll('images/$fb2Id', epubName);
        content = content.replaceAll('src="$fb2Id"', 'src="$epubName"');
        content = content.replaceAll("src='$fb2Id'", "src='$epubName'");
      });

      // 🎯 СТРАХОВОЧНЫЙ ФИНАЛЬНЫЙ ПРОХОД: к этому моменту sectionIdToFile
      // построена ПОЛНОСТЬЮ (включая все id примечаний). Даже если по какой-то
      // причине инлайн-резолвинг выше не сработал (например, сноска
      // встретилась раньше, чем её id был зарегистрирован), эта замена
      // гарантированно дорезолвит любой оставшийся "голый" href="#id"
      // в правильный "файл#id". Именно отсутствие такого гарантированного
      // прохода и было причиной того, что часть сносок никуда не вела —
      // читалка просто оставалась в текущей главе.
      sectionIdToFile.forEach((sectionId, fileName) {
        content = content.replaceAll('href="#$sectionId"', 'href="$fileName#$sectionId"');
        content = content.replaceAll("href='#$sectionId'", "href='$fileName#$sectionId'");
      });

      ch['content'] = content;
    }

    onStatusUpdate("📦 Сборка Calibre-style EPUB...");
    final archive = Archive();
    final uuid = 'urn:uuid:${DateTime.now().millisecondsSinceEpoch}';

    final mimeBytes = utf8.encode('application/epub+zip');
    archive.addFile(
      ArchiveFile('mimetype', mimeBytes.length, mimeBytes)..compress = false,
    );

    const containerXml = '''<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
<rootfiles>
<rootfile full-path="content.opf" media-type="application/oebps-package+xml"/>
</rootfiles>
</container>''';
    archive.addFile(
      ArchiveFile(
        'META-INF/container.xml',
        utf8.encode(containerXml).length,
        utf8.encode(containerXml),
      ),
    );

    const pageStylesCss = '''@page {
  margin-bottom: 5pt;
  margin-top: 5pt;
}
''';
    archive.addFile(
      ArchiveFile(
        'page_styles.css',
        utf8.encode(pageStylesCss).length,
        utf8.encode(pageStylesCss),
      ),
    );

    const stylesheetCss = '''.calibre {
  display: block;
  font-size: 1em;
  padding-left: 0;
  padding-right: 0;
  text-align: justify;
  margin: 0 5pt;
}
.calibre1 { display: block; }
.calibre2 {
  background-color: #E7E7E7;
  display: block;
  font-size: 1.66667em;
  font-style: normal;
  font-weight: bold;
  line-height: 1.2;
  text-align: left;
  margin: 0.67em 0;
  border: Black solid 1px;
}
.calibre3 {
  color: Black;
  display: block;
  height: 2px;
  margin: 0.5em auto;
  border: currentColor inset 1px;
}
.calibre4 {
  display: block;
  list-style-type: disc;
  margin-bottom: 1em;
  margin-right: 0;
  margin-top: 1em;
}
.calibre5 { display: list-item; }
.calibre6 {
  display: block;
  list-style-type: circle;
  margin-bottom: 0;
  margin-right: 0;
  margin-top: 0;
}
.calibre8 {
  display: block;
  line-height: 1.2;
  max-width: 100%;
  height: auto;
}
.calibre9 { font-style: italic; }
.calibre10 { font-weight: bold; }
.calibre11 {
  display: block;
  margin: 1em 0.2em 1em 4em;
}
.calibre12 {
  line-height: 1.2;
}
.calibre14 {
  font-size: 0.75em;
  line-height: normal;
  vertical-align: super;
}
.paragraph {
  display: block;
  margin-bottom: 0.8em;
  margin-top: 0;
  text-indent: 2em;
  text-align: justify;
}
.dialog {
  display: block;
  margin-bottom: 0.5em;
  margin-top: 0;
  text-indent: 0;
  padding-left: 1.5em;
  text-align: left;
}
.text-author {
  text-indent: 0;
  text-align: right;
  font-style: italic;
}
.subtitle {
  background-color: #F4F4F4;
  display: block;
  font-size: 1em;
  font-style: italic;
  font-weight: bold;
  text-align: center;
  margin: 1.67em 0;
  border: Gray solid 1px;
}
.epigraph {
  display: block;
  font-style: italic;
  width: 75%;
  margin: 1em 0.2em 1em 25%;
}
blockquote {
  display: block;
  font-style: italic;
  margin: 1em 2em;
}
table {
  border-collapse: collapse;
  margin: 1em 0;
  width: 100%;
}
th, td {
  border: 1px solid #999;
  padding: 0.3em 0.5em;
}
del { text-decoration: line-through; }
sub {
  vertical-align: sub;
  font-size: 0.8em;
}
img {
  max-width: 100%;
  height: auto;
}
.footnote-link {
  color: #0066cc;
  text-decoration: underline;
}
.footnote {
  display: block;
  margin: 0.5em 0;
  padding: 0.5em;
  font-size: 0.9em;
  border-bottom: 1px dashed #ccc;
}
.footnote-title {
  font-weight: bold;
  font-size: 1em;
  margin-bottom: 0.3em;
}
.footnote-backlink {
  margin: 0;
  text-align: right;
  font-size: 0.9em;
}
.footnote-backlink a {
  text-decoration: none;
  color: #0066cc;
}
.footnote-separator {
  border: 0;
  border-top: 1px dashed #ccc;
  margin: 0.5em 0;
  height: 0;
}
a {
  color: #0066cc;
  text-decoration: underline;
}
''';
    archive.addFile(
      ArchiveFile(
        'stylesheet.css',
        utf8.encode(stylesheetCss).length,
        utf8.encode(stylesheetCss),
      ),
    );

    if (coverFileName != null) {
      final titlepageContent = '''<?xml version='1.0' encoding='utf-8'?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>${_escapeXhtml(bookTitle)}</title>
<link rel="stylesheet" type="text/css" href="stylesheet.css"/>
<link rel="stylesheet" type="text/css" href="page_styles.css"/>
</head>
<body class="calibre">
<div class="calibre1">
<img src="$coverFileName" alt="cover" class="calibre8"/>
</div>
</body>
</html>''';
      archive.addFile(
        ArchiveFile(
          'titlepage.xhtml',
          utf8.encode(titlepageContent).length,
          utf8.encode(titlepageContent),
        ),
      );
    }

    for (var ch in chapters) {
      final xhtml = '''<?xml version='1.0' encoding='utf-8'?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<title>${_escapeXhtml(ch['title']!)}</title>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
<link rel="stylesheet" type="text/css" href="stylesheet.css"/>
<link rel="stylesheet" type="text/css" href="page_styles.css"/>
</head>
<body class="calibre">
<div class="calibre1">${ch['content']}</div>
</body>
</html>''';
      final contentBytes = utf8.encode(xhtml);
      archive.addFile(
        ArchiveFile(
          ch['fileName']!,
          contentBytes.length,
          contentBytes,
        ),
      );
    }

    images.forEach((name, imgData) {
      final imgBytes = imgData['bytes'] as Uint8List;
      archive.addFile(ArchiveFile(name, imgBytes.length, imgBytes));
    });

    StringBuffer manifest = StringBuffer();
    StringBuffer spine = StringBuffer();

    if (coverFileName != null) {
      manifest.write('<item id="titlepage" href="titlepage.xhtml" media-type="application/xhtml+xml"/>\n');
      spine.write('<itemref idref="titlepage"/>\n');
    }

    for (int i = 0; i < chapters.length; i++) {
      final ch = chapters[i];
      final fileId = 'id${388 - i}';
      manifest.write('<item id="$fileId" href="${ch['fileName']}" media-type="application/xhtml+xml"/>\n');
      spine.write('<itemref idref="$fileId"/>\n');
    }

    manifest.write('<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>\n');
    manifest.write('<item id="page_css" href="page_styles.css" media-type="text/css"/>\n');
    manifest.write('<item id="css" href="stylesheet.css" media-type="text/css"/>\n');

    if (coverFileName != null) {
      final coverMime = images[coverFileName]!['mime'];
      manifest.write('<item id="cover" href="$coverFileName" media-type="$coverMime"/>\n');
    }

    images.forEach((name, imgData) {
      if (name == coverFileName) return;
      final id = 'img_${imgData['fb2Id']}';
      manifest.write('<item id="$id" href="$name" media-type="${imgData['mime']}"/>\n');
    });

    String descriptionXml = "";
    if (annotation.isNotEmpty) {
      String plainAnnotation = annotation
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (plainAnnotation.length > 500) {
        plainAnnotation = '${plainAnnotation.substring(0, 500)}...';
      }
      descriptionXml = '<dc:description>${_escapeXhtml(plainAnnotation)}</dc:description>\n';
    }

    String coverMeta = "";
    if (coverFileName != null) {
      coverMeta = '<meta name="cover" content="cover"/>\n';
    }

    final opfXml = '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="uuid_id">
<metadata xmlns:opf="http://www.idpf.org/2007/opf" xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:title>${_escapeXhtml(bookTitle)}</dc:title>
<dc:creator opf:role="aut">${_escapeXhtml(authorName)}</dc:creator>
<dc:contributor opf:role="bkp">X4 Flow</dc:contributor>
$descriptionXml<dc:identifier id="uuid_id" opf:scheme="uuid">$uuid</dc:identifier>
<dc:language>ru</dc:language>
$coverMeta</metadata>
<manifest>
$manifest</manifest>
<spine toc="ncx">
$spine</spine>
<guide>
${coverFileName != null ? '<reference type="cover" href="titlepage.xhtml" title="Cover"/>' : ''}
</guide>
</package>''';
    archive.addFile(
      ArchiveFile(
        'content.opf',
        utf8.encode(opfXml).length,
        utf8.encode(opfXml),
      ),
    );

    final ncxXml = _generateNcx(tocTree, bookTitle, uuid);
    archive.addFile(
      ArchiveFile(
        'toc.ncx',
        utf8.encode(ncxXml).length,
        utf8.encode(ncxXml),
      ),
    );

    final epubBytes = ZipEncoder().encode(archive);
    if (epubBytes == null) throw Exception("Ошибка сборки ZIP");

    return ConversionResult(
      epubBytes: Uint8List.fromList(epubBytes),
      title: bookTitle,
      author: authorName,
    );
  }
}
