import 'dart:typed_data';

/// Результат парсинга GPOS: сырые данные для формирования кернинговой таблицы.
class GposKerningRaw {
  /// leftCp -> (rightCp -> kerning в font units)
  final Map<int, Map<int, int>> pairs;
  final int unitsPerEm;
  GposKerningRaw(this.pairs, this.unitsPerEm);
}

/// Парсер GPOS-таблицы OpenType шрифта для извлечения кернинговых пар.
/// Работает на чистом Dart — не требует platform channels.
class GposKerningParser {
  late final ByteData _data;

  int _unitsPerEm = 1000;
  final Map<int, int> _glyphToCodepoint = {};

  // Результат: leftCodepoint -> rightCodepoint -> kerningValue (font units)
  final Map<int, Map<int, int>> _kerningPairs = {};

  /// Парсит шрифт и извлекает кернинговые пары.
  /// [fontData] — сырые байты TTF/OTF файла.
  static GposKerningRaw extractKerning(Uint8List fontData) {
    final parser = GposKerningParser._(fontData);
    final pairs = parser._parse();
    return GposKerningRaw(pairs, parser._unitsPerEm);
  }

  GposKerningParser._(Uint8List fontData) : _data = ByteData.sublistView(fontData);

  Map<int, Map<int, int>> _parse() {
    // 1. Читаем font directory
    final numTables = _data.getUint16(4, Endian.big);

    int? headOffset;
    int? cmapOffset;
    int? gposOffset;

    for (int i = 0; i < numTables; i++) {
      final entryOffset = 12 + i * 16;
      final tag = _readTag(entryOffset);
      final offset = _data.getUint32(entryOffset + 8, Endian.big);

      switch (tag) {
        case 'head':
          headOffset = offset;
          break;
        case 'cmap':
          cmapOffset = offset;
          break;
        case 'GPOS':
          gposOffset = offset;
          break;
      }
    }

    if (headOffset == null) {
      throw Exception('head table not found');
    }

    // 2. Читаем unitsPerEm из head
    _unitsPerEm = _data.getUint16(headOffset + 18, Endian.big);

    // 3. Читаем cmap для mapping glyphID <-> codepoint
    if (cmapOffset != null) {
      _parseCmap(cmapOffset);
    }

    // 4. Читаем GPOS
    if (gposOffset != null) {
      _parseGpos(gposOffset);
    }

    return _kerningPairs;
  }

  String _readTag(int offset) {
    final bytes = <int>[];
    for (int i = 0; i < 4; i++) {
      bytes.add(_data.getUint8(offset + i));
    }
    return String.fromCharCodes(bytes);
  }

  void _parseCmap(int offset) {
    final numTables = _data.getUint16(offset + 2, Endian.big);

    for (int i = 0; i < numTables; i++) {
      final entryOffset = offset + 4 + i * 8;
      final subtableOffset = _data.getUint32(entryOffset + 4, Endian.big);

      final absOffset = offset + subtableOffset;
      final format = _data.getUint16(absOffset, Endian.big);

      if (format == 4) {
        _parseCmapFormat4(absOffset);
      } else if (format == 12) {
        _parseCmapFormat12(absOffset);
      } else if (format == 6) {
        _parseCmapFormat6(absOffset);
      }
    }
  }

  void _parseCmapFormat4(int offset) {
    final length = _data.getUint16(offset + 2, Endian.big);
    final segCount = _data.getUint16(offset + 6, Endian.big) ~/ 2;

    final endCodes = <int>[];
    for (int i = 0; i < segCount; i++) {
      endCodes.add(_data.getUint16(offset + 14 + i * 2, Endian.big));
    }

    final startCodes = <int>[];
    for (int i = 0; i < segCount; i++) {
      startCodes.add(_data.getUint16(offset + 16 + segCount * 2 + i * 2, Endian.big));
    }

    final idDeltas = <int>[];
    for (int i = 0; i < segCount; i++) {
      idDeltas.add(_data.getInt16(offset + 16 + segCount * 4 + i * 2, Endian.big));
    }

    final idRangeOffsets = <int>[];
    for (int i = 0; i < segCount; i++) {
      idRangeOffsets.add(_data.getUint16(offset + 16 + segCount * 6 + i * 2, Endian.big));
    }

    for (int seg = 0; seg < segCount; seg++) {
      final start = startCodes[seg];
      final end = endCodes[seg];
      final delta = idDeltas[seg];
      final rangeOffset = idRangeOffsets[seg];

      for (int code = start; code <= end; code++) {
        int glyphID;
        if (rangeOffset == 0) {
          glyphID = (code + delta) & 0xFFFF;
        } else {
          final glyphIndexOffset = offset + 16 + segCount * 6 + seg * 2 + rangeOffset + (code - start) * 2;
          if (glyphIndexOffset + 2 <= offset + length) {
            glyphID = _data.getUint16(glyphIndexOffset, Endian.big);
            if (glyphID != 0) {
              glyphID = (glyphID + delta) & 0xFFFF;
            }
          } else {
            continue;
          }
        }

        if (glyphID != 0) {
          _glyphToCodepoint[glyphID] = code;
        }
      }
    }
  }

  void _parseCmapFormat6(int offset) {
    final firstCode = _data.getUint16(offset + 6, Endian.big);
    final entryCount = _data.getUint16(offset + 8, Endian.big);

    for (int i = 0; i < entryCount; i++) {
      final code = firstCode + i;
      final glyphID = _data.getUint16(offset + 10 + i * 2, Endian.big);
      if (glyphID != 0) {
        _glyphToCodepoint[glyphID] = code;
      }
    }
  }

  void _parseCmapFormat12(int offset) {
    final numGroups = _data.getUint32(offset + 12, Endian.big);

    for (int i = 0; i < numGroups; i++) {
      final groupOffset = offset + 16 + i * 12;
      final startCharCode = _data.getUint32(groupOffset, Endian.big);
      final endCharCode = _data.getUint32(groupOffset + 4, Endian.big);
      final startGlyphID = _data.getUint32(groupOffset + 8, Endian.big);

      for (int j = 0; j <= (endCharCode - startCharCode); j++) {
        final code = startCharCode + j;
        final glyphID = startGlyphID + j;
        _glyphToCodepoint[glyphID] = code;
      }
    }
  }

  void _parseGpos(int gposOffset) {
    final lookupListOffset = _data.getUint16(gposOffset + 8, Endian.big);

    final lookupListAbs = gposOffset + lookupListOffset;
    final lookupCount = _data.getUint16(lookupListAbs, Endian.big);

    for (int i = 0; i < lookupCount; i++) {
      final lookupOffset = _data.getUint16(lookupListAbs + 2 + i * 2, Endian.big);
      final lookupAbs = lookupListAbs + lookupOffset;
      _parseLookup(lookupAbs);
    }
  }

  void _parseLookup(int offset) {
    final lookupType = _data.getUint16(offset, Endian.big);
    final subTableCount = _data.getUint16(offset + 4, Endian.big);

    for (int i = 0; i < subTableCount; i++) {
      final subTableOffset = _data.getUint16(offset + 6 + i * 2, Endian.big);
      final subTableAbs = offset + subTableOffset;

      if (lookupType == 2) {
        _parsePairPos(subTableAbs);
      } else if (lookupType == 9) {
        _parseExtensionPos(subTableAbs);
      }
    }
  }

  void _parseExtensionPos(int offset) {
    final posFormat = _data.getUint16(offset, Endian.big);
    if (posFormat != 1) return;

    final extensionLookupType = _data.getUint16(offset + 2, Endian.big);
    final extensionOffset = _data.getUint32(offset + 4, Endian.big);

    if (extensionLookupType == 2) {
      _parsePairPos(offset + extensionOffset);
    }
  }

  void _parsePairPos(int offset) {
    final posFormat = _data.getUint16(offset, Endian.big);
    final coverageOffset = _data.getUint16(offset + 2, Endian.big);
    final valueFormat1 = _data.getUint16(offset + 4, Endian.big);
    final valueFormat2 = _data.getUint16(offset + 6, Endian.big);

    final coverage = _parseCoverage(offset + coverageOffset);

    if (posFormat == 1) {
      _parsePairPosFormat1(offset, coverage, valueFormat1, valueFormat2);
    } else if (posFormat == 2) {
      _parsePairPosFormat2(offset, coverage, valueFormat1, valueFormat2);
    }
  }

  List<int> _parseCoverage(int offset) {
    final format = _data.getUint16(offset, Endian.big);
    final glyphs = <int>[];

    if (format == 1) {
      final count = _data.getUint16(offset + 2, Endian.big);
      for (int i = 0; i < count; i++) {
        glyphs.add(_data.getUint16(offset + 4 + i * 2, Endian.big));
      }
    } else if (format == 2) {
      final rangeCount = _data.getUint16(offset + 2, Endian.big);
      for (int i = 0; i < rangeCount; i++) {
        final rangeOffset = offset + 4 + i * 6;
        final startGlyph = _data.getUint16(rangeOffset, Endian.big);
        final endGlyph = _data.getUint16(rangeOffset + 2, Endian.big);
        for (int g = startGlyph; g <= endGlyph; g++) {
          glyphs.add(g);
        }
      }
    }

    return glyphs;
  }

  void _parsePairPosFormat1(int offset, List<int> coverage, int valueFormat1, int valueFormat2) {
    final pairSetCount = _data.getUint16(offset + 8, Endian.big);

    for (int i = 0; i < pairSetCount && i < coverage.length; i++) {
      final pairSetOffset = _data.getUint16(offset + 10 + i * 2, Endian.big);
      final pairSetAbs = offset + pairSetOffset;
      final pairValueCount = _data.getUint16(pairSetAbs, Endian.big);

      final leftGlyph = coverage[i];
      final leftCp = _glyphToCodepoint[leftGlyph];
      if (leftCp == null) continue;

      int recordOffset = pairSetAbs + 2;
      final value1Size = _valueRecordSize(valueFormat1);
      final value2Size = _valueRecordSize(valueFormat2);
      final recordSize = 2 + value1Size + value2Size;

      for (int j = 0; j < pairValueCount; j++) {
        final secondGlyph = _data.getUint16(recordOffset, Endian.big);
        final xAdvance = _readValueRecord(recordOffset + 2, valueFormat1);

        final rightCp = _glyphToCodepoint[secondGlyph];
        if (rightCp != null && xAdvance != 0) {
          _kerningPairs.putIfAbsent(leftCp, () => {})[rightCp] = xAdvance;
        }

        recordOffset += recordSize;
      }
    }
  }

  void _parsePairPosFormat2(int offset, List<int> coverage, int valueFormat1, int valueFormat2) {
    final classDef1Offset = _data.getUint16(offset + 8, Endian.big);
    final classDef2Offset = _data.getUint16(offset + 10, Endian.big);
    final class1Count = _data.getUint16(offset + 12, Endian.big);
    final class2Count = _data.getUint16(offset + 14, Endian.big);

    final classDef1 = _parseClassDef(offset + classDef1Offset);
    final classDef2 = _parseClassDef(offset + classDef2Offset);

    final value1Size = _valueRecordSize(valueFormat1);
    final value2Size = _valueRecordSize(valueFormat2);
    final class2RecordSize = value1Size + value2Size;
    final class1RecordSize = class2RecordSize * class2Count;

    int recordOffset = offset + 16;

    final class1Glyphs = <int, List<int>>{};
    for (final glyph in coverage) {
      final c1 = classDef1[glyph] ?? 0;
      class1Glyphs.putIfAbsent(c1, () => []).add(glyph);
    }

    final class2Glyphs = <int, List<int>>{};
    for (final entry in _glyphToCodepoint.entries) {
      final c2 = classDef2[entry.key] ?? 0;
      class2Glyphs.putIfAbsent(c2, () => []).add(entry.key);
    }

    for (int c1 = 0; c1 < class1Count; c1++) {
      final c1Glyphs = class1Glyphs[c1];
      if (c1Glyphs == null || c1Glyphs.isEmpty) {
        recordOffset += class1RecordSize;
        continue;
      }

      for (int c2 = 0; c2 < class2Count; c2++) {
        final xAdvance = _readValueRecord(recordOffset, valueFormat1);

        if (xAdvance != 0) {
          final c2Glyphs = class2Glyphs[c2];
          if (c2Glyphs != null) {
            for (final leftGlyph in c1Glyphs) {
              final leftCp = _glyphToCodepoint[leftGlyph];
              if (leftCp == null) continue;

              for (final rightGlyph in c2Glyphs) {
                final rightCp = _glyphToCodepoint[rightGlyph];
                if (rightCp != null) {
                  _kerningPairs.putIfAbsent(leftCp, () => {})[rightCp] = xAdvance;
                }
              }
            }
          }
        }

        recordOffset += class2RecordSize;
      }
    }
  }

  Map<int, int> _parseClassDef(int offset) {
    final format = _data.getUint16(offset, Endian.big);
    final result = <int, int>{};

    if (format == 1) {
      final startGlyph = _data.getUint16(offset + 2, Endian.big);
      final glyphCount = _data.getUint16(offset + 4, Endian.big);
      for (int i = 0; i < glyphCount; i++) {
        final glyphID = startGlyph + i;
        final classValue = _data.getUint16(offset + 6 + i * 2, Endian.big);
        result[glyphID] = classValue;
      }
    } else if (format == 2) {
      final rangeCount = _data.getUint16(offset + 2, Endian.big);
      for (int i = 0; i < rangeCount; i++) {
        final rangeOffset = offset + 4 + i * 6;
        final startGlyph = _data.getUint16(rangeOffset, Endian.big);
        final endGlyph = _data.getUint16(rangeOffset + 2, Endian.big);
        final classValue = _data.getUint16(rangeOffset + 4, Endian.big);
        for (int g = startGlyph; g <= endGlyph; g++) {
          result[g] = classValue;
        }
      }
    }

    return result;
  }

  int _valueRecordSize(int valueFormat) {
    int size = 0;
    for (int bit = 0; bit < 8; bit++) {
      if ((valueFormat & (1 << bit)) != 0) {
        size += 2;
      }
    }
    return size;
  }

  int _readValueRecord(int offset, int valueFormat) {
    int xAdvance = 0;
    int currentOffset = offset;

    if ((valueFormat & 0x0001) != 0) {
      currentOffset += 2;
    }
    if ((valueFormat & 0x0002) != 0) {
      currentOffset += 2;
    }
    if ((valueFormat & 0x0004) != 0) {
      xAdvance = _data.getInt16(currentOffset, Endian.big);
      currentOffset += 2;
    }
    if ((valueFormat & 0x0008) != 0) {
      currentOffset += 2;
    }
    for (int bit = 4; bit < 8; bit++) {
      if ((valueFormat & (1 << bit)) != 0) {
        currentOffset += 2;
      }
    }

    return xAdvance;
  }
}
