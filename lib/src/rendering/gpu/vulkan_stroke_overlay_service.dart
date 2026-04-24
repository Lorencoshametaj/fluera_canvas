import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:fluera_canvas/fluera_canvas.dart';
import '../../drawing/input/input_predictor.dart';
import '../memory_pressure.dart';
import 'native_stroke_ffi_stub.dart'
    if (dart.library.ffi) 'native_stroke_ffi.dart';

/// 🎨 VulkanStrokeOverlayService — Dart bridge to the C++ Vulkan stroke renderer.
///
/// Manages the native texture lifecycle and sends stroke data to the GPU
/// renderer via MethodChannel. The Vulkan renderer draws into a
/// SurfaceTexture that Flutter composites via Texture(textureId:).
///
/// Usage:
///   final service = VulkanStrokeOverlayService();
///   final textureId = await service.init(width, height);
///   // Add Texture(textureId: textureId) to widget tree
///   service.updateAndRender(points, color, width);
///   service.clear(); // on pen-up
///   service.dispose();
class VulkanStrokeOverlayService {
  static const _channel = MethodChannel('fluera_canvas/native_stroke');

  int? _textureId;
  bool _initialized = false;
  bool? _available;
  int _lastSentCount = 0;

  // 🚀 #10: Monotonic stopwatch for throttle (avoids DateTime.now() GC)
  static final Stopwatch _throttleWatch = Stopwatch()..start();
  int _lastSendMs = 0;

  // 🚀 #4: Transform throttle — cache last values to skip no-ops
  double _lastScale = -1;
  double _lastOx = double.nan;
  double _lastOy = double.nan;
  double _lastRotation = double.nan;
  ui.Offset _lastCanvasOrigin = const ui.Offset(double.nan, double.nan);

  // 🚀 #6: Ring buffer diagnostics
  int _ringFallbackCount = 0;

  /// 🚀 FFI: Direct shared memory bridge for hot-path calls
  final NativeStrokeFfi _ffi = NativeStrokeFfi();

  /// 🔮 Input predictor for anti-lag rendering
  final InputPredictor _predictor = InputPredictor();

  /// 🚀 Direct CAMetalLayer overlay (iOS only)
  bool _directOverlayActive = false;

  /// Whether the direct CAMetalLayer overlay is active (iOS only).
  /// When true, strokes render directly to the display, bypassing Impeller.
  /// The widget tree should hide the Texture widget when this is true.
  bool get isDirectOverlayActive => _directOverlayActive;

  /// Flutter texture ID for use with Texture(textureId:) widget.
  int? get textureId => _textureId;

  /// Whether the Vulkan renderer is initialized and ready.
  bool get isInitialized => _initialized;

  /// Check if Vulkan stroke overlay is available on this device.
  /// Caches result after first call.
  Future<bool> get isAvailable async {
    if (_available != null) return _available!;
    try {
      _available = await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } catch (e) {
      _available = false;
    }
    return _available!;
  }

  /// Initialize the Vulkan renderer.
  /// Returns the Flutter texture ID, or null if initialization fails.
  Future<int?> init(int width, int height) async {
    try {
      final id = await _channel.invokeMethod<int>('init', {
        'width': width,
        'height': height,
      });
      if (id != null) {
        _textureId = id;
        _initialized = true;
        // 🚀 FFI: Initialize direct path after native renderer is ready
        if (_ffi.init()) {
          debugPrint('[FlueraVk] FFI hot-path active');
        } else {
          debugPrint('[FlueraVk] FFI unavailable, using MethodChannel fallback');
        }
      }
      return id;
    } catch (e) {
      debugPrint('[FlueraVk] init failed: $e');
      _initialized = false;
      return null;
    }
  }

  /// Send NEW stroke points to the Vulkan renderer and trigger a render.
  ///
  /// Only sends points added since the last call (incremental).
  /// The C++ renderer accumulates points internally.
  /// 🚀 Throttled to 60fps max to reduce MethodChannel overhead on long strokes.
  void updateAndRender(
    List<ProDrawingPoint> points,
    ui.Color color,
    double strokeWidth, {
    bool force = false,
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
    if (!_initialized || points.length < 2) return;

    // 🔮 Prediction DISABLED for native renderer: predicted points change
    // position every frame, and since the C++ tessellator re-tessellates the
    // ENTIRE stroke using Catmull-Rom splines, fluctuating endpoints cause
    // the whole stroke geometry to shift = visible trembling.
    // The C++ tessellator's own EMA smoothing handles latency compensation.
    final renderPoints = points;

    // 🚀 Throttle: skip if <16ms since last send (unless forced or first call)
    final now = _throttleWatch.elapsedMilliseconds;
    if (!force && _lastSendMs > 0 && (now - _lastSendMs) < 16) {
      return; // Points accumulate, will be sent in next batch
    }

    // C++ tessellates the full incoming point buffer directly (no internal accumulation).
    // Always send ALL points for correct full-stroke re-tessellation.
    const int newStart = 0;
    _lastSentCount = points.length;
    _lastSendMs = now;

    // 🚀 FFI HOT PATH: Zero-copy shared buffer write
    if (_ffi.isInitialized) {
      // 🚀 Try ring buffer (incremental — only new points)
      final ringUsed = _ffi.updateAndRenderIncremental(
        renderPoints,
        color,
        strokeWidth,
        renderPoints.length,
        brushType: brushType,
        pencilBaseOpacity: pencilBaseOpacity,
        pencilMaxOpacity: pencilMaxOpacity,
        pencilMinPressure: pencilMinPressure,
        pencilMaxPressure: pencilMaxPressure,
        fountainThinning: fountainThinning,
        fountainNibAngleDeg: fountainNibAngleDeg,
        fountainNibStrength: fountainNibStrength,
        fountainPressureRate: fountainPressureRate,
        fountainTaperEntry: fountainTaperEntry,
        zoomScale: zoomScale,
      );
      if (ringUsed) {
        _ringFallbackCount = 0; // 🚀 #6: Ring succeeded, reset counter
        return;
      }

      // 🚀 #6: Ring buffer fallback diagnostics
      _ringFallbackCount++;
      if (_ringFallbackCount == 4) {
        debugPrint('[FlueraVk] ⚠️ Ring buffer fallback 4x consecutive — '
            'consider increasing ring capacity');
      }

      // Fallback: flat buffer (all points)
      _ffi.updateAndRender(
        renderPoints,
        newStart,
        color,
        strokeWidth,
        renderPoints.length,
        brushType: brushType,
        pencilBaseOpacity: pencilBaseOpacity,
        pencilMaxOpacity: pencilMaxOpacity,
        pencilMinPressure: pencilMinPressure,
        pencilMaxPressure: pencilMaxPressure,
        fountainThinning: fountainThinning,
        fountainNibAngleDeg: fountainNibAngleDeg,
        fountainNibStrength: fountainNibStrength,
        fountainPressureRate: fountainPressureRate,
        fountainTaperEntry: fountainTaperEntry,
        zoomScale: zoomScale,
      );
      return;
    }

    // ─── FALLBACK: MethodChannel (if FFI unavailable) ────────
    final newCount = points.length - newStart;
    final flatPoints = List<double>.filled(newCount * 5, 0.0);
    for (int i = 0; i < newCount; i++) {
      final pt = points[newStart + i];
      flatPoints[i * 5] = pt.position.dx;
      flatPoints[i * 5 + 1] = pt.position.dy;
      flatPoints[i * 5 + 2] = pt.pressure;
      flatPoints[i * 5 + 3] = pt.tiltX;
      flatPoints[i * 5 + 4] = pt.tiltY;
    }

    _channel.invokeMethod('updateAndRender', {
      'points': flatPoints,
      'color': color.toARGB32(),
      'width': strokeWidth,
      'totalPoints': points.length,
      'brushType': brushType,
      'pencilBaseOpacity': pencilBaseOpacity,
      'pencilMaxOpacity': pencilMaxOpacity,
      'pencilMinPressure': pencilMinPressure,
      'pencilMaxPressure': pencilMaxPressure,
      'fountainThinning': fountainThinning,
      'fountainNibAngleDeg': fountainNibAngleDeg,
      'fountainNibStrength': fountainNibStrength,
      'fountainPressureRate': fountainPressureRate,
      'fountainTaperEntry': fountainTaperEntry,
    });
  }

  /// Set the canvas transform matrix (for pan/zoom/rotation sync).
  ///
  /// Builds a combined canvas-space → Vulkan NDC matrix.
  /// [width]/[height] are in physical pixels, [dpr] is devicePixelRatio.
  /// Canvas coordinates (logical) are scaled by dpr to match the physical
  /// pixel surface.
  void setTransform(
    InfiniteCanvasController controller,
    int width,
    int height, [
    double dpr = 1.0,
    ui.Offset canvasOrigin = ui.Offset.zero,
  ]) {
    if (!_initialized) return;

    final scale = controller.scale;
    final ox = controller.offset.dx;
    final oy = controller.offset.dy;
    final rotation = controller.rotation;

    // 🚀 #4: Skip if transform hasn't changed (< 0.001 epsilon)
    if ((scale - _lastScale).abs() < 0.001 &&
        (ox - _lastOx).abs() < 0.5 &&
        (oy - _lastOy).abs() < 0.5 &&
        (rotation - _lastRotation).abs() < 0.0001 &&
        (canvasOrigin.dx - _lastCanvasOrigin.dx).abs() < 0.5 &&
        (canvasOrigin.dy - _lastCanvasOrigin.dy).abs() < 0.5) {
      return;
    }
    _lastScale = scale;
    _lastOx = ox;
    _lastOy = oy;
    _lastRotation = rotation;
    _lastCanvasOrigin = canvasOrigin;

    // 🚀 #11: FFI path computes its own matrix — skip Dart matrix construction
    if (_ffi.isInitialized) {
      _ffi.setTransform(controller, width, height, dpr, canvasOrigin);
      return;
    }

    final double w = width.toDouble();
    final double h = height.toDouble();

    final effectiveScale = scale * dpr;
    // canvasOrigin accounts for the Metal overlay covering the full screen
    // while the canvas area starts below the toolbar.
    final effectiveOx = (ox + canvasOrigin.dx) * dpr;
    final effectiveOy = (oy + canvasOrigin.dy) * dpr;

    final cosR = _cos(rotation);
    final sinR = _sin(rotation);

    final sx = 2.0 * effectiveScale / w;
    final sy = 2.0 * effectiveScale / h;
    final tx = (2.0 * effectiveOx / w) - 1.0;
    final ty = (2.0 * effectiveOy / h) - 1.0;

    final matrix = <double>[
      sx * cosR, sy * sinR, 0.0, 0.0,
      sx * -sinR, sy * cosR, 0.0, 0.0,
      0.0, 0.0, 1.0, 0.0,
      tx, ty, 0.0, 1.0,
    ];

    _channel.invokeMethod('setTransform', {
      'matrix': matrix,
      'zoomLevel': scale,
    });
  }

  // 🚀 PERF: Fast-path for rotation=0 (most common case)
  static double _cos(double r) => r == 0.0 ? 1.0 : math.cos(r);
  static double _sin(double r) => r == 0.0 ? 0.0 : math.sin(r);

  /// Set a screen-space identity transform (no pan/zoom).
  ///
  /// Points sent to [updateAndRender] are interpreted as physical-pixel
  /// screen coordinates. Used by the PDF reader where there is no
  /// InfiniteCanvasController.
  void setScreenSpaceTransform(int width, int height, double dpr) {
    if (!_initialized) return;

    final double w = width.toDouble();
    final double h = height.toDouble();

    // Identity canvas transform: scale=1.0, offset=0.
    // ndcX = x * dpr * (2/w) - 1
    // ndcY = y * dpr * (2/h) - 1
    final sx = 2.0 * dpr / w;
    final sy = 2.0 * dpr / h;

    final matrix = <double>[
      sx,  0.0, 0.0, 0.0,
      0.0, sy,  0.0, 0.0,
      0.0, 0.0, 1.0, 0.0,
      -1.0, -1.0, 0.0, 1.0,
    ];

    _channel.invokeMethod('setTransform', {'matrix': matrix});
  }

  /// Clear the render target (transparent). Call on pen-up.
  void clear() {
    if (!_initialized) return;
    _lastSentCount = 0;
    _lastSendMs = 0;

    // 🔮 Reset predictor on stroke end (anti-stretch: discard all predictions)
    _predictor.reset();

    // 🚀 FFI HOT PATH
    if (_ffi.isInitialized) {
      _ffi.clear();
      return;
    }

    // ─── FALLBACK: MethodChannel ─────────────────────────────
    _channel.invokeMethod('clear');
  }

  // ═══════════════════════════════════════════════════════════════
  // 🚀 DIRECT CAMetalLayer OVERLAY (iOS ONLY)
  // ═══════════════════════════════════════════════════════════════

  /// Enable direct CAMetalLayer overlay for minimum-latency rendering.
  /// Call on pen-down. The overlay renders strokes directly to the display,
  /// bypassing Flutter's TextureRegistry + Impeller compositor.
  /// [opacity] controls the overlay transparency (1.0 = opaque, <1.0 = highlighter).
  Future<void> enableDirectOverlay({double opacity = 1.0}) async {
    if (!_initialized) return;
    if (!_isIOS) return; // Only available on iOS
    try {
      await _channel.invokeMethod('enableDirectOverlay', {
        'opacity': opacity,
      });
      _directOverlayActive = true;
    } catch (e) {
      debugPrint('[FlueraVk] enableDirectOverlay failed: $e');
    }
  }

  /// Disable direct overlay, falling back to CVPixelBuffer + Texture widget.
  /// Call on pen-up.
  Future<void> disableDirectOverlay() async {
    if (!_initialized) return;
    if (!_isIOS) return;
    try {
      await _channel.invokeMethod('disableDirectOverlay');
      _directOverlayActive = false;
    } catch (e) {
      debugPrint('[FlueraVk] disableDirectOverlay failed: $e');
    }
  }

  /// Whether we're running on iOS (CAMetalLayer is iOS-only).
  static bool get _isIOS {
    try {
      return Platform.isIOS;
    } catch (_) {
      return false; // Web or other
    }
  }

  /// Resize the render target.
  Future<bool> resize(int width, int height) async {
    if (!_initialized) return false;
    try {
      return await _channel.invokeMethod<bool>('resize', {
            'width': width,
            'height': height,
          }) ??
          false;
    } catch (e) {
      debugPrint('[FlueraVk] resize failed: $e');
      return false;
    }
  }

  /// 🚀 Handle memory pressure — trim native render buffers.
  /// Register this callback with [MemoryPressureHandler.registerCallback].
  void onMemoryPressure(MemoryPressureLevel level) {
    if (!_initialized) return;
    if (level == MemoryPressureLevel.normal) return;
    final nativeLevel = level == MemoryPressureLevel.critical ? 2 : 1;
    debugPrint('[FlueraVk] trimMemory(level=$nativeLevel)');
    _channel.invokeMethod('trimMemory', {'level': nativeLevel});
  }

  /// Dispose all resources.
  Future<void> dispose() async {
    if (!_initialized) return;
    _ffi.dispose(); // 🚀 Free shared buffer
    try {
      await _channel.invokeMethod('destroy');
    } catch (e) {
      debugPrint('[FlueraVk] destroy failed: $e');
    }
    _textureId = null;
    _initialized = false;
  }

  /// Get performance statistics from the Vulkan renderer.
  /// Returns null if the renderer is not initialized or stats unavailable.
  Future<VulkanStats?> getStats() async {
    if (!_initialized) return null;
    try {
      final result = await _channel.invokeMethod<Map>('getStats');
      if (result == null) return null;
      final m = Map<String, dynamic>.from(result);
      return VulkanStats(
        p50Us: (m['p50us'] as num?)?.toDouble() ?? 0,
        p90Us: (m['p90us'] as num?)?.toDouble() ?? 0,
        p99Us: (m['p99us'] as num?)?.toDouble() ?? 0,
        vertexCount: (m['vertexCount'] as num?)?.toInt() ?? 0,
        drawCalls: (m['drawCalls'] as num?)?.toInt() ?? 0,
        swapchainImages: (m['swapchainImages'] as num?)?.toInt() ?? 0,
        totalFrames: (m['totalFrames'] as num?)?.toInt() ?? 0,
        active: m['active'] as bool? ?? false,
        deviceName: m['deviceName'] as String? ?? 'N/A',
        apiVersion:
            '${m['apiMajor'] ?? 0}.${m['apiMinor'] ?? 0}.${m['apiPatch'] ?? 0}',
      );
    } catch (e) {
      debugPrint('[FlueraVk] getStats failed: $e');
      return null;
    }
  }
}

/// Performance statistics snapshot from the Vulkan renderer.
class VulkanStats {
  /// GPU frame time at the 50th percentile (microseconds).
  final double p50Us;

  /// GPU frame time at the 90th percentile (microseconds).
  final double p90Us;

  /// GPU frame time at the 99th percentile (microseconds).
  final double p99Us;

  /// Number of vertices rendered in the last frame.
  final int vertexCount;

  /// Number of draw calls in the last frame.
  final int drawCalls;

  /// Number of swapchain images.
  final int swapchainImages;

  /// Total number of frames rendered by the Vulkan pipeline.
  final int totalFrames;

  /// Whether the Vulkan renderer is actively drawing strokes.
  final bool active;

  /// GPU device name (e.g., "Adreno 730").
  final String deviceName;

  /// Vulkan API version string (e.g., "1.1.0").
  final String apiVersion;

  /// P50 frame time in milliseconds.
  double get p50Ms => p50Us / 1000.0;

  /// P90 frame time in milliseconds.
  double get p90Ms => p90Us / 1000.0;

  /// P99 frame time in milliseconds.
  double get p99Ms => p99Us / 1000.0;

  const VulkanStats({
    required this.p50Us,
    required this.p90Us,
    required this.p99Us,
    required this.vertexCount,
    required this.drawCalls,
    required this.swapchainImages,
    required this.totalFrames,
    required this.active,
    required this.deviceName,
    required this.apiVersion,
  });
}
