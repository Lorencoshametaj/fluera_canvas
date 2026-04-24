// ═══════════════════════════════════════════════════════════════════
// 🚀 NativeStrokeFfi — dart:ffi shared memory bridge
//
// Replaces MethodChannel for hot-path stroke commands:
//   updateAndRender, setTransform, clear
//
// Allocates a shared Float32 buffer that both Dart and native code
// read/write directly — zero serialization, zero copies.
//
// Cold-path calls (init, destroy, resize, getStats) remain on
// MethodChannel because they need async responses and lifecycle mgmt.
// ═══════════════════════════════════════════════════════════════════

import 'dart:ffi';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'package:fluera_canvas/fluera_canvas.dart';

// ─── Buffer layout constants (must match fluera_stroke_ffi.h) ─────
const int _kCmd = 0;
const int _kPointCount = 1;
const int _kColorR = 2;
const int _kColorG = 3;
const int _kColorB = 4;
const int _kColorA = 5;
const int _kStrokeWidth = 6;
const int _kTotalPoints = 7;
const int _kBrushType = 8;
const int _kPencilBase = 9;
const int _kPencilMax = 10;
const int _kPencilMinP = 11;
const int _kPencilMaxP = 12;
const int _kFountainThin = 13;
const int _kFountainAngle = 14;
const int _kFountainStr = 15;
const int _kFountainRate = 16;
const int _kFountainTaper = 17;
const int _kZoomScale = 18;
const int _kHeaderSize = 20;
const int _kTransform = 20; // 16 floats [20..35]
const int _kPoints = 36; // stride 5 starting at [36]

// Commands
const double _cmdUpdateAndRender = 1.0;
const double _cmdSetTransform = 2.0;
const double _cmdClear = 3.0;

// Max points per batch (1000 points × 5 = 5000 floats)
const int _kMaxPoints = 1000;
const int _kBufferSize = _kPoints + (_kMaxPoints * 5); // 5036 floats

// ─── Ring buffer constants (must match ring_buffer.h) ─────────────
const int _ringHead = 0;
const int _ringTail = 1;
const int _ringCapacity = 2;
const int _ringSequence = 3;
const int _ringCmd = 4;
const int _ringColorR = 5;
const int _ringColorG = 6;
const int _ringColorB = 7;
const int _ringColorA = 8;
const int _ringStrokeW = 9;
const int _ringTotalPts = 10;
const int _ringBrushType = 11;
const int _ringPencilBase = 12;
const int _ringPencilMax = 13;
const int _ringPencilMinP = 14;
const int _ringPencilMaxP = 15;
const int _ringFountThin = 16;
const int _ringFountAngle = 17;
const int _ringFountStr = 18;
const int _ringFountRate = 19;
const int _ringFountTaper = 20;
const int _ringZoomScale = 21;
const int _ringTransform = 24;
const int _ringDataStart = 40;
const int _ringDefaultCapacity = 2000;

// Ring commands
const int _ringCmdIdle = 0;
const int _ringCmdRender = 1;
const int _ringCmdTransform = 2;
const int _ringCmdClear = 3;

// ─── Native function signature ────────────────────────────────────
typedef _FlueraStrokeExecuteNative = Void Function(Pointer<Float>);
typedef _FlueraStrokeExecuteDart = void Function(Pointer<Float>);
typedef _FlueraRingExecuteNative = Void Function(Pointer<Int32>);
typedef _FlueraRingExecuteDart = void Function(Pointer<Int32>);

/// 🚀 FFI bridge for hot-path stroke rendering.
///
/// Lifecycle:
///   1. Call [init] once after the MethodChannel `init` succeeds
///   2. Use [updateAndRender], [setTransform], [clear] for zero-copy hot path
///   3. Call [dispose] when done
class NativeStrokeFfi {
  Pointer<Float>? _buffer;
  _FlueraStrokeExecuteDart? _execute;
  bool _initialized = false;

  // 🚀 Ring buffer for incremental delivery
  Pointer<Int32>? _ringBuffer;
  _FlueraRingExecuteDart? _ringExecute;
  bool _ringAvailable = false;
  int _lastPointsSent = 0; // Track how many points we've already sent
  int _ringSeqCounter = 0;

  /// Whether FFI is initialized and ready.
  bool get isInitialized => _initialized;

  /// Initialize the FFI bridge.
  /// Must be called AFTER the MethodChannel `init` succeeds
  /// (native renderer must exist before we can call into it).
  bool init() {
    if (_initialized) return true;
    if (kIsWeb) return false; // Web uses js_interop, not dart:ffi

    try {
      // ── Load native library ──────────────────────────────────
      final DynamicLibrary nativeLib;
      if (Platform.isAndroid) {
        nativeLib = DynamicLibrary.open('libfluera_vk_stroke.so');
      } else if (Platform.isIOS || Platform.isMacOS) {
        nativeLib = DynamicLibrary.process(); // Statically linked
      } else if (Platform.isLinux) {
        nativeLib = DynamicLibrary.open('libfluera_gl_stroke.so');
      } else if (Platform.isWindows) {
        nativeLib = DynamicLibrary.open('fluera_d3d11_stroke.dll');
      } else {
        return false;
      }

      // ── Lookup FFI function ──────────────────────────────────
      _execute = nativeLib
          .lookup<NativeFunction<_FlueraStrokeExecuteNative>>(
              'fluera_stroke_execute')
          .asFunction<_FlueraStrokeExecuteDart>();

      // ── Allocate shared buffer ───────────────────────────────
      _buffer = calloc<Float>(_kBufferSize);
      if (_buffer == nullptr) return false;

      // Write identity transform as default
      _writeIdentityTransform();

      _initialized = true;

      // 🚀 Try ring buffer mode (incremental)
      try {
        _ringExecute = nativeLib
            .lookup<NativeFunction<_FlueraRingExecuteNative>>(
                'fluera_stroke_ring_execute')
            .asFunction<_FlueraRingExecuteDart>();

        final ringSize = _ringDataStart + (_ringDefaultCapacity * 5);
        _ringBuffer = calloc<Int32>(ringSize);
        if (_ringBuffer != nullptr) {
          _ringBuffer![_ringCapacity] = _ringDefaultCapacity;
          _ringBuffer![_ringSequence] = 0;
          _ringBuffer![_ringCmd] = _ringCmdIdle;
          _ringAvailable = true;
          debugPrint('[FlueraFFI] 🚀 Ring buffer initialized (${ringSize * 4} bytes)');
        }
      } catch (e) {
        debugPrint('[FlueraFFI] Ring buffer not available, using flat buffer: $e');
        _ringAvailable = false;
      }

      debugPrint('[FlueraFFI] Initialized (buffer=${_kBufferSize * 4} bytes)');
      return true;
    } catch (e) {
      debugPrint('[FlueraFFI] Init failed: $e');
      _initialized = false;
      return false;
    }
  }

  /// Send stroke points to the native renderer via shared memory.
  /// Zero-copy: writes directly into the shared buffer.
  void updateAndRender(
    List<ProDrawingPoint> points,
    int startIndex,
    ui.Color color,
    double strokeWidth,
    int totalPoints, {
    int brushType = 0,
    double pencilBaseOpacity = 0.4,
    double pencilMaxOpacity = 0.8,
    double pencilMinPressure = 0.5,
    double pencilMaxPressure = 1.2,
    double fountainThinning = 0.5,
    double fountainNibAngleDeg = 30.0,
    double fountainNibStrength = 0.35,
    double fountainPressureRate = 0.275,
    int fountainTaperEntry = 6,
    double zoomScale = 1.0,
  }) {
    if (!_initialized || _buffer == null || _execute == null) return;

    final newCount = points.length - startIndex;
    if (newCount < 2) return;

    // Clamp to max buffer capacity
    final count = newCount > _kMaxPoints ? _kMaxPoints : newCount;
    final buf = _buffer!;

    // ── Write header ─────────────────────────────────────────
    buf[_kCmd] = _cmdUpdateAndRender;
    buf[_kPointCount] = count.toDouble();
    buf[_kColorR] = color.r;
    buf[_kColorG] = color.g;
    buf[_kColorB] = color.b;
    buf[_kColorA] = color.a;
    buf[_kStrokeWidth] = strokeWidth;
    buf[_kTotalPoints] = totalPoints.toDouble();
    buf[_kBrushType] = brushType.toDouble();
    buf[_kPencilBase] = pencilBaseOpacity;
    buf[_kPencilMax] = pencilMaxOpacity;
    buf[_kPencilMinP] = pencilMinPressure;
    buf[_kPencilMaxP] = pencilMaxPressure;
    buf[_kFountainThin] = fountainThinning;
    buf[_kFountainAngle] = fountainNibAngleDeg;
    buf[_kFountainStr] = fountainNibStrength;
    buf[_kFountainRate] = fountainPressureRate;
    buf[_kFountainTaper] = fountainTaperEntry.toDouble();
    buf[_kZoomScale] = zoomScale;

    // ── Write points (stride 5) ──────────────────────────────
    for (int i = 0; i < count; i++) {
      final pt = points[startIndex + i];
      final off = _kPoints + i * 5;
      buf[off] = pt.position.dx;
      buf[off + 1] = pt.position.dy;
      buf[off + 2] = pt.pressure;
      buf[off + 3] = pt.tiltX;
      buf[off + 4] = pt.tiltY;
    }

    // ── Execute ──────────────────────────────────────────────
    _execute!(buf);
  }

  /// 🚀 Send ONLY NEW points via ring buffer (incremental).
  /// Returns true if ring buffer was used, false to fall back to flat.
  bool updateAndRenderIncremental(
    List<ProDrawingPoint> points,
    ui.Color color,
    double strokeWidth,
    int totalPoints, {
    int brushType = 0,
    double pencilBaseOpacity = 0.4,
    double pencilMaxOpacity = 0.8,
    double pencilMinPressure = 0.5,
    double pencilMaxPressure = 1.2,
    double fountainThinning = 0.5,
    double fountainNibAngleDeg = 30.0,
    double fountainNibStrength = 0.35,
    double fountainPressureRate = 0.275,
    int fountainTaperEntry = 6,
    double zoomScale = 1.0,
  }) {
    if (!_ringAvailable || _ringBuffer == null || _ringExecute == null) {
      return false;
    }

    final ring = _ringBuffer!;
    final newStart = _lastPointsSent;
    final newCount = points.length - newStart;
    if (newCount <= 0) {
      // No new points — still trigger render with current data
      ring[_ringCmd] = _ringCmdRender;
      _ringExecute!(ring);
      return true;
    }

    // Write params to ring header (as float bits stored in int32)
    _ringSetFloat(ring, _ringColorR, color.r);
    _ringSetFloat(ring, _ringColorG, color.g);
    _ringSetFloat(ring, _ringColorB, color.b);
    _ringSetFloat(ring, _ringColorA, color.a);
    _ringSetFloat(ring, _ringStrokeW, strokeWidth);
    _ringSetFloat(ring, _ringTotalPts, totalPoints.toDouble());
    _ringSetFloat(ring, _ringBrushType, brushType.toDouble());
    _ringSetFloat(ring, _ringPencilBase, pencilBaseOpacity);
    _ringSetFloat(ring, _ringPencilMax, pencilMaxOpacity);
    _ringSetFloat(ring, _ringPencilMinP, pencilMinPressure);
    _ringSetFloat(ring, _ringPencilMaxP, pencilMaxPressure);
    _ringSetFloat(ring, _ringFountThin, fountainThinning);
    _ringSetFloat(ring, _ringFountAngle, fountainNibAngleDeg);
    _ringSetFloat(ring, _ringFountStr, fountainNibStrength);
    _ringSetFloat(ring, _ringFountRate, fountainPressureRate);
    _ringSetFloat(ring, _ringFountTaper, fountainTaperEntry.toDouble());
    _ringSetFloat(ring, _ringZoomScale, zoomScale);

    // Write only NEW points to ring data
    final cap = ring[_ringCapacity];
    var head = ring[_ringHead];
    final tail = ring[_ringTail];
    var space = (head >= tail) ? cap - (head - tail) - 1 : tail - head - 1;
    if (space <= 0) return false; // Ring full, fall back to flat

    final writeCount = newCount > space ? space : newCount;
    // Access the ring data as floats
    final dataPtr = ring.cast<Float>() + _ringDataStart;
    for (int i = 0; i < writeCount; i++) {
      final pt = points[newStart + i];
      final idx = (head + i) % cap;
      final off = idx * 5;
      dataPtr[off] = pt.position.dx;
      dataPtr[off + 1] = pt.position.dy;
      dataPtr[off + 2] = pt.pressure;
      dataPtr[off + 3] = pt.tiltX;
      dataPtr[off + 4] = pt.tiltY;
    }

    // Update head
    ring[_ringHead] = (head + writeCount) % cap;
    _lastPointsSent = newStart + writeCount;

    // Trigger render
    ring[_ringCmd] = _ringCmdRender;
    _ringExecute!(ring);
    return true;
  }

  /// Reset ring buffer tracking (call when starting a new stroke).
  void resetRing() {
    _lastPointsSent = 0;
    if (_ringAvailable && _ringBuffer != null) {
      _ringBuffer![_ringHead] = 0;
      _ringBuffer![_ringTail] = 0;
      // Write sequence counter to position _ringSequence (constant = 3)
      // so C++ detects new stroke and clears g_ringAccumPoints
      _ringSeqCounter++;
      _ringBuffer![_ringSequence] = _ringSeqCounter;
    }
  }

  /// Set the canvas transform matrix via shared memory.
  void setTransform(
    InfiniteCanvasController controller,
    int width,
    int height, [
    double dpr = 1.0,
    ui.Offset canvasOrigin = ui.Offset.zero,
  ]) {
    if (!_initialized || _buffer == null || _execute == null) return;

    final buf = _buffer!;
    buf[_kCmd] = _cmdSetTransform;

    final scale = controller.scale;
    final ox = controller.offset.dx;
    final oy = controller.offset.dy;
    final rotation = controller.rotation;

    final double w = width.toDouble();
    final double h = height.toDouble();
    final effectiveScale = scale * dpr;
    final effectiveOx = (ox + canvasOrigin.dx) * dpr;
    final effectiveOy = (oy + canvasOrigin.dy) * dpr;

    final cosR = rotation == 0.0 ? 1.0 : math.cos(rotation);
    final sinR = rotation == 0.0 ? 0.0 : math.sin(rotation);

    final sx = 2.0 * effectiveScale / w;
    final sy = 2.0 * effectiveScale / h;
    final tx = (2.0 * effectiveOx / w) - 1.0;
    final ty = (2.0 * effectiveOy / h) - 1.0;

    // Column-major 4×4
    buf[_kTransform]      = sx * cosR;
    buf[_kTransform + 1]  = sy * sinR;
    buf[_kTransform + 2]  = 0.0;
    buf[_kTransform + 3]  = 0.0;
    buf[_kTransform + 4]  = sx * -sinR;
    buf[_kTransform + 5]  = sy * cosR;
    buf[_kTransform + 6]  = 0.0;
    buf[_kTransform + 7]  = 0.0;
    buf[_kTransform + 8]  = 0.0;
    buf[_kTransform + 9]  = 0.0;
    buf[_kTransform + 10] = 1.0;
    buf[_kTransform + 11] = 0.0;
    buf[_kTransform + 12] = tx;
    buf[_kTransform + 13] = ty;
    buf[_kTransform + 14] = 0.0;
    buf[_kTransform + 15] = 1.0;

    _execute!(buf);
  }

  /// Clear the render target via shared memory.
  void clear() {
    if (!_initialized || _buffer == null || _execute == null) return;
    _buffer![_kCmd] = _cmdClear;
    _execute!(_buffer!);
    // Reset ring buffer tracking so next stroke starts fresh
    resetRing();
  }

  /// Dispose the shared buffer.
  void dispose() {
    if (_buffer != null) {
      calloc.free(_buffer!);
      _buffer = null;
    }
    if (_ringBuffer != null) {
      calloc.free(_ringBuffer!);
      _ringBuffer = null;
    }
    _execute = null;
    _ringExecute = null;
    _ringAvailable = false;
    _initialized = false;
    _lastPointsSent = 0;
  }

  void _writeIdentityTransform() {
    if (_buffer == null) return;
    for (int i = 0; i < 16; i++) {
      _buffer![_kTransform + i] = 0.0;
    }
    _buffer![_kTransform] = 1.0;      // m[0][0]
    _buffer![_kTransform + 5] = 1.0;  // m[1][1]
    _buffer![_kTransform + 10] = 1.0; // m[2][2]
    _buffer![_kTransform + 15] = 1.0; // m[3][3]
  }

  /// Write a double as float bits into an int32 ring buffer slot.
  void _ringSetFloat(Pointer<Int32> buf, int offset, double value) {
    final floatPtr = buf.cast<Float>() + offset;
    floatPtr.value = value;
  }
}
