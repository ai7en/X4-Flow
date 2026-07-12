import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

// ── Dynamic library loading ─────────────────────────────────────

DynamicLibrary _openLib() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libcpfont_ft.so');
  }
  if (Platform.isLinux) {
    return DynamicLibrary.open('libcpfont_ft.so');
  }
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('libcpfont_ft.dylib');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('cpfont_ft.dll');
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

final DynamicLibrary _lib = _openLib();

// ── C function signatures ──────────────────────────────────────

typedef _InitNative = Int32 Function();
typedef _InitDart = int Function();
final _init = _lib.lookupFunction<_InitNative, _InitDart>('cpft_init');

typedef _DeinitNative = Void Function();
typedef _DeinitDart = void Function();
final _deinit = _lib.lookupFunction<_DeinitNative, _DeinitDart>('cpft_deinit');

typedef _LoadFaceNative = Pointer<Void> Function(Pointer<Uint8> data, IntPtr len);
typedef _LoadFaceDart = Pointer<Void> Function(Pointer<Uint8> data, int len);
final _loadFace = _lib.lookupFunction<_LoadFaceNative, _LoadFaceDart>('cpft_load_face');

typedef _LoadFaceWithFallbackNative = Pointer<Void> Function(
    Pointer<Uint8> data, IntPtr len, Pointer<Uint8> fbData, IntPtr fbLen);
typedef _LoadFaceWithFallbackDart = Pointer<Void> Function(
    Pointer<Uint8> data, int len, Pointer<Uint8> fbData, int fbLen);
final _loadFaceWithFallback = _lib.lookupFunction<_LoadFaceWithFallbackNative, _LoadFaceWithFallbackDart>(
    'cpft_load_face_with_fallback');

typedef _DoneFaceNative = Void Function(Pointer<Void> face);
typedef _DoneFaceDart = void Function(Pointer<Void> face);
final _doneFace = _lib.lookupFunction<_DoneFaceNative, _DoneFaceDart>('cpft_done_face');

typedef _SetSizeNative = Int32 Function(Pointer<Void> face, Int32 ppem);
typedef _SetSizeDart = int Function(Pointer<Void> face, int ppem);
final _setSize = _lib.lookupFunction<_SetSizeNative, _SetSizeDart>('cpft_set_size');

typedef _GetMetricsNative = Int32 Function(
    Pointer<Void> face, Pointer<Int32> ascender, Pointer<Int32> descender, Pointer<Int32> height);
typedef _GetMetricsDart = int Function(
    Pointer<Void> face, Pointer<Int32> ascender, Pointer<Int32> descender, Pointer<Int32> height);
final _getMetrics = _lib.lookupFunction<_GetMetricsNative, _GetMetricsDart>('cpft_get_metrics');

typedef _RenderGlyphNative = Int32 Function(
    Pointer<Void> face, Uint32 cp, Pointer<Pointer<Uint8>> outBuf,
    Pointer<Int32> outW, Pointer<Int32> outH, Pointer<Int32> outPitch,
    Pointer<Int32> outLeft, Pointer<Int32> outTop, Pointer<Int32> outAdvanceX);
typedef _RenderGlyphDart = int Function(
    Pointer<Void> face, int cp, Pointer<Pointer<Uint8>> outBuf,
    Pointer<Int32> outW, Pointer<Int32> outH, Pointer<Int32> outPitch,
    Pointer<Int32> outLeft, Pointer<Int32> outTop, Pointer<Int32> outAdvanceX);
final _renderGlyph = _lib.lookupFunction<_RenderGlyphNative, _RenderGlyphDart>('cpft_render_glyph');

typedef _FreeBitmapNative = Void Function(Pointer<Uint8> buf);
typedef _FreeBitmapDart = void Function(Pointer<Uint8> buf);
final _freeBitmap = _lib.lookupFunction<_FreeBitmapNative, _FreeBitmapDart>('cpft_free_bitmap');

typedef _GetKernNative = Int32 Function(Pointer<Void> face, Uint32 leftCp, Uint32 rightCp);
typedef _GetKernDart = int Function(Pointer<Void> face, int leftCp, int rightCp);
final _getKern = _lib.lookupFunction<_GetKernNative, _GetKernDart>('cpft_get_kern');

typedef _HasGlyphNative = Int32 Function(Pointer<Void> face, Uint32 cp);
typedef _HasGlyphDart = int Function(Pointer<Void> face, int cp);
final _hasGlyph = _lib.lookupFunction<_HasGlyphNative, _HasGlyphDart>('cpft_has_glyph');

typedef _GetUpemNative = Int32 Function(Pointer<Void> face);
typedef _GetUpemDart = int Function(Pointer<Void> face);
final _getUpem = _lib.lookupFunction<_GetUpemNative, _GetUpemDart>('cpft_get_units_per_em');

typedef _GetAdvanceNative = Int32 Function(Pointer<Void> face, Uint32 cp);
typedef _GetAdvanceDart = int Function(Pointer<Void> face, int cp);
final _getAdvance = _lib.lookupFunction<_GetAdvanceNative, _GetAdvanceDart>('cpft_get_advance');

// ── Dart wrapper class ─────────────────────────────────────────

class CpFontFreeType {
  static bool _initialized = false;

  static void init() {
    if (_initialized) return;
    final rc = _init();
    if (rc != 0) throw Exception('cpft_init failed: $rc');
    _initialized = true;
  }

  static void deinit() {
    _deinit();
    _initialized = false;
  }

  final Pointer<Void> _face;
  bool _disposed = false;

  CpFontFreeType._(this._face);

  factory CpFontFreeType.load(Uint8List bytes, {Uint8List? fallbackBytes}) {
    init();
    final ptr = calloc<Uint8>(bytes.length);
    ptr.asTypedList(bytes.length).setAll(0, bytes);

    Pointer<Void> face;
    if (fallbackBytes != null && fallbackBytes.isNotEmpty) {
      final fbPtr = calloc<Uint8>(fallbackBytes.length);
      fbPtr.asTypedList(fallbackBytes.length).setAll(0, fallbackBytes);
      face = _loadFaceWithFallback(ptr, bytes.length, fbPtr, fallbackBytes.length);
      calloc.free(fbPtr);
    } else {
      face = _loadFace(ptr, bytes.length);
    }
    calloc.free(ptr);

    if (face == nullptr) {
      throw Exception('cpft_load_face failed');
    }
    return CpFontFreeType._(face);
  }

  void dispose() {
    if (_disposed) return;
    _doneFace(_face);
    _disposed = true;
  }

  void setSize(int ppem) {
    _check();
    final rc = _setSize(_face, ppem);
    if (rc != 0) throw Exception('cpft_set_size failed: $rc');
  }

  FontMetrics get metrics {
    _check();
    final asc = calloc<Int32>();
    final desc = calloc<Int32>();
    final h = calloc<Int32>();
    try {
      final rc = _getMetrics(_face, asc, desc, h);
      if (rc != 0) throw Exception('cpft_get_metrics failed: $rc');
      return FontMetrics(
        ascender: asc.value,
        descender: desc.value,
        height: h.value,
      );
    } finally {
      calloc.free(asc);
      calloc.free(desc);
      calloc.free(h);
    }
  }

  GlyphBitmap? renderGlyph(int cp) {
    _check();
    final outBuf = calloc<Pointer<Uint8>>();
    final outW = calloc<Int32>();
    final outH = calloc<Int32>();
    final outPitch = calloc<Int32>();
    final outLeft = calloc<Int32>();
    final outTop = calloc<Int32>();
    final outAdv = calloc<Int32>();
    try {
      final rc = _renderGlyph(
        _face, cp,
        outBuf, outW, outH, outPitch,
        outLeft, outTop, outAdv,
      );
      if (rc != 0) {
        // Error 5 = Invalid_Argument, usually means glyph not found
        // Return null so caller can handle gracefully
        return null;
      }

      final w = outW.value;
      final h = outH.value;
      if (w == 0 || h == 0) {
        // Empty glyph (e.g. space, or glyph not in font)
        // Don't free - C side didn't allocate for w==0,h==0
        return GlyphBitmap(
          width: 0,
          height: 0,
          left: outLeft.value,
          top: outTop.value,
          advanceX: outAdv.value,
          buffer: Uint8List(0),
        );
      }

      final bufPtr = outBuf.value;
      final pitch = outPitch.value;
      final size = w * h;
      final bytes = Uint8List(size);
      bytes.setAll(0, bufPtr.asTypedList(size));
      _freeBitmap(bufPtr);

      return GlyphBitmap(
        width: w,
        height: h,
        left: outLeft.value,
        top: outTop.value,
        advanceX: outAdv.value,
        buffer: bytes,
      );
    } finally {
      calloc.free(outBuf);
      calloc.free(outW);
      calloc.free(outH);
      calloc.free(outPitch);
      calloc.free(outLeft);
      calloc.free(outTop);
      calloc.free(outAdv);
    }
  }

  bool hasGlyph(int cp) {
    _check();
    return _hasGlyph(_face, cp) != 0;
  }

  int getKern(int leftCp, int rightCp) {
    _check();
    return _getKern(_face, leftCp, rightCp);
  }

  int get unitsPerEm => _getUpem(_face);

  int getAdvance(int cp) {
    _check();
    return _getAdvance(_face, cp);
  }

  void _check() {
    if (_disposed) throw StateError('CpFontFreeType already disposed');
  }
}

class FontMetrics {
  final int ascender;
  final int descender;
  final int height;
  FontMetrics({required this.ascender, required this.descender, required this.height});

  int get ascenderPx => (ascender + 32) >> 6;
  int get descenderPx => descender >> 6;
  int get heightPx => (height + 32) >> 6;
}

class GlyphBitmap {
  final int width;
  final int height;
  final int left;
  final int top;
  final int advanceX;
  final Uint8List buffer;

  GlyphBitmap({
    required this.width,
    required this.height,
    required this.left,
    required this.top,
    required this.advanceX,
    required this.buffer,
  });
}
