// ═══════════════════════════════════════════════════════════════════
// 🌐 WebGpuStrokeOverlayService — Dart bridge to JS WebGPU renderer
//
// Mirrors VulkanStrokeOverlayService API but uses dart:js_interop
// to call into window.FlueraWebGPU.* functions.
//
// Only imported/used when kIsWeb is true.
// ═══════════════════════════════════════════════════════════════════

import 'dart:js_interop';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'package:fluera_canvas/fluera_canvas.dart';

// ─── JS interop bindings ─────────────────────────────────────────

@JS('FlueraWebGPU.isAvailable')
external bool _jsIsAvailable();

@JS('FlueraWebGPU.init')
external JSPromise<JSBoolean> _jsInit(
  web.HTMLCanvasElement canvas,
  int width,
  int height,
);

@JS('FlueraWebGPU.updateAndRender')
external void _jsUpdateAndRender(
  JSFloat32Array flatPoints,
  double colorR,
  double colorG,
  double colorB,
  double colorA,
  double strokeWidth,
  int totalPoints,
  int brushType,
  JSObject brushParams,
);

@JS('FlueraWebGPU.setTransform')
external void _jsSetTransform(JSFloat32Array matrix);

@JS('FlueraWebGPU.clear')
external void _jsClear();

@JS('FlueraWebGPU.resize')
external JSBoolean _jsResize(int width, int height);

@JS('FlueraWebGPU.destroy')
external void _jsDestroy();

/// 🌐 WebGPU stroke overlay service for web platform.
///
/// Drop-in replacement for [VulkanStrokeOverlayService] on web.
/// Uses `HtmlElementView` instead of `Texture(textureId:)`.
class WebGpuStrokeOverlayService {
  bool _initialized = false;
  bool? _available;
  int _lastSentCount = 0;
  int _lastSendTimeMs = 0;
  web.HTMLCanvasElement? _canvas;

  /// The canvas element for embedding via HtmlElementView.
  web.HTMLCanvasElement? get canvas => _canvas;

  /// Whether the WebGPU renderer is initialized and ready.
  bool get isInitialized => _initialized;

  /// Check if WebGPU is available in this browser.
  Future<bool> get isAvailable async {
    if (_available != null) return _available!;
    try {
      _available = _jsIsAvailable();
    } catch (e) {
      _available = false;
    }
    return _available!;
  }

  /// Initialize the WebGPU renderer.
  /// Creates a canvas element and initializes the GPU pipeline.
  /// Returns true on success.
  Future<bool> init(int width, int height) async {
    try {
      // Create a dedicated canvas element for WebGPU rendering
      _canvas = web.document.createElement('canvas') as web.HTMLCanvasElement;
      _canvas!.style.width = '100%';
      _canvas!.style.height = '100%';
      _canvas!.style.position = 'absolute';
      _canvas!.style.top = '0';
      _canvas!.style.left = '0';
      _canvas!.style.pointerEvents = 'none'; // Flutter handles input

      final result = await _jsInit(_canvas!, width, height).toDart;
      _initialized = result.toDart;
      return _initialized;
    } catch (e) {
      debugPrint('[FlueraWebGPU] init failed: $e');
      _initialized = false;
      return false;
    }
  }

  /// Send stroke points to the WebGPU renderer and trigger a render.
  ///
  /// Same incremental logic as VulkanStrokeOverlayService.
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
  }) {
    if (!_initialized || points.length < 2) return;

    // 🚀 Throttle: skip if <16ms since last send (unless forced)
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && _lastSendTimeMs > 0 && (now - _lastSendTimeMs) < 16) {
      return;
    }

    // Incremental: only send new points for ballpoint
    int newStart;
    if (brushType == 0 && _lastSentCount > 0) {
      newStart = (_lastSentCount - 1).clamp(0, points.length);
    } else {
      newStart = 0;
    }
    if (newStart >= points.length) return;

    final newCount = points.length - newStart;
    // Stride 5: x, y, pressure, tiltX, tiltY
    final flatPoints = List<double>.filled(newCount * 5, 0.0);
    for (int i = 0; i < newCount; i++) {
      final pt = points[newStart + i];
      flatPoints[i * 5] = pt.position.dx;
      flatPoints[i * 5 + 1] = pt.position.dy;
      flatPoints[i * 5 + 2] = pt.pressure;
      flatPoints[i * 5 + 3] = pt.tiltX;
      flatPoints[i * 5 + 4] = pt.tiltY;
    }
    _lastSentCount = points.length;
    _lastSendTimeMs = now;

    // Build brush params object
    final params = <String, Object>{
      'pencilBaseOpacity': pencilBaseOpacity,
      'pencilMaxOpacity': pencilMaxOpacity,
      'pencilMinPressure': pencilMinPressure,
      'pencilMaxPressure': pencilMaxPressure,
      'fountainThinning': fountainThinning,
      'fountainNibAngleDeg': fountainNibAngleDeg,
      'fountainNibStrength': fountainNibStrength,
      'fountainPressureRate': fountainPressureRate,
      'fountainTaperEntry': fountainTaperEntry,
    }.jsify() as JSObject;

    _jsUpdateAndRender(
      Float32List.fromList(flatPoints).toJS,
      color.r,
      color.g,
      color.b,
      color.a,
      strokeWidth,
      points.length,
      brushType,
      params,
    );
  }

  /// Set the canvas transform matrix.
  void setTransform(
    InfiniteCanvasController controller,
    int width,
    int height, [
    double dpr = 1.0,
  ]) {
    if (!_initialized) return;

    final scale = controller.scale;
    final ox = controller.offset.dx;
    final oy = controller.offset.dy;
    final rotation = controller.rotation;

    final double w = width.toDouble();
    final double h = height.toDouble();

    final effectiveScale = scale * dpr;
    final effectiveOx = ox * dpr;
    final effectiveOy = oy * dpr;

    final cosR = rotation == 0.0 ? 1.0 : math.cos(rotation);
    final sinR = rotation == 0.0 ? 0.0 : math.sin(rotation);

    // Same matrix as VulkanStrokeOverlayService.setTransform
    final sx = 2.0 * effectiveScale / w;
    final sy = 2.0 * effectiveScale / h;
    final tx = (2.0 * effectiveOx / w) - 1.0;
    final ty = (2.0 * effectiveOy / h) - 1.0;

    final matrix = Float32List.fromList([
      // Column 0
      sx * cosR, sy * sinR, 0.0, 0.0,
      // Column 1
      sx * -sinR, sy * cosR, 0.0, 0.0,
      // Column 2
      0.0, 0.0, 1.0, 0.0,
      // Column 3
      tx, ty, 0.0, 1.0,
    ]);

    _jsSetTransform(matrix.toJS);
  }

  /// Clear the render target. Call on pen-up.
  void clear() {
    if (!_initialized) return;
    _lastSentCount = 0;
    _lastSendTimeMs = 0;
    _jsClear();
  }

  /// Resize the render target.
  bool resize(int width, int height) {
    if (!_initialized) return false;
    try {
      return _jsResize(width, height).toDart;
    } catch (e) {
      debugPrint('[FlueraWebGPU] resize failed: $e');
      return false;
    }
  }

  /// Dispose all resources.
  void dispose() {
    if (!_initialized) return;
    try {
      _jsDestroy();
    } catch (e) {
      debugPrint('[FlueraWebGPU] destroy failed: $e');
    }
    _canvas = null;
    _initialized = false;
  }
}
