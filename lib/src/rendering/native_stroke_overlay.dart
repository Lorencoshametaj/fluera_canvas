// ════════════════════════════════════════════════════════════════════════════
// 🚀 NativeStrokeOverlay — public façade for the native live-stroke pipeline
//
// Exposes the GPU-accelerated stroke renderer (Vulkan on Android, Metal on
// iOS/macOS, OpenGL on Linux, Direct3D 11 on Windows) as a composable widget.
// Points you push to [NativeStrokeOverlayController] are rendered by the
// native code path — bypassing Dart's `Canvas` for 60 FPS / minimum-latency
// live strokes.
//
// TYPICAL USAGE
//   final canvasController = InfiniteCanvasController();
//   final overlay = NativeStrokeOverlayController();
//
//   Stack(children: [
//     // 1. Your scene renderer (CustomPaint / SceneGraphRenderer).
//     YourSceneWidget(),
//     // 2. Native overlay — sits between scene and gesture detector.
//     NativeStrokeOverlay(
//       canvasController: canvasController,
//       controller: overlay,
//     ),
//     // 3. Gesture detector pushes points into the overlay.
//     InfiniteCanvasGestureDetector(
//       controller: canvasController,
//       onDrawStart: (p, pr, tx, ty) {
//         overlay.beginStroke(color: Colors.black, width: 3);
//         overlay.appendPoint(p, pressure: pr, tiltX: tx, tiltY: ty);
//       },
//       onDrawUpdate: (p, pr, tx, ty) =>
//         overlay.appendPoint(p, pressure: pr, tiltX: tx, tiltY: ty),
//       onDrawEnd: (_) => overlay.endStroke(),
//       child: const SizedBox.expand(),
//     ),
//   ]);
//
// The overlay never holds committed strokes — it only draws the *in-flight*
// one. When [endStroke] is called, the overlay clears and the caller is
// expected to persist the completed stroke in its scene graph / model.
//
// PLATFORM SUPPORT
//   iOS, Android, macOS, Linux, Windows — full native acceleration.
//   Web                                  — currently falls back to a no-op
//                                          texture (WebGPU path is available
//                                          via a separate bridge); the
//                                          caller's Dart painter still
//                                          renders the live stroke.
//   Headless tests                        — initializes to a no-op.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../canvas/infinite_canvas_controller.dart';
import '../drawing/models/pro_drawing_point.dart';
import 'gpu/gpu_stroke_backend.dart';

/// Imperative controller driving a [NativeStrokeOverlay].
///
/// Owned by the caller; pass the same instance to the widget via
/// [NativeStrokeOverlay.controller]. The controller buffers points between
/// [beginStroke] and [endStroke] calls and streams them to the native
/// renderer at native refresh rate.
class NativeStrokeOverlayController extends ChangeNotifier {
  NativeStrokeOverlayController();

  final List<ProDrawingPoint> _points = <ProDrawingPoint>[];

  Color _color = const Color(0xFF000000);
  double _strokeWidth = 3.0;
  int _brushType = 0;
  bool _drawing = false;

  // Brush tuning exposed verbatim so power users can mimic Fluera's pencil /
  // fountain pen rendering. Defaults match the engine's pencil brush.
  double pencilBaseOpacity = 0.4;
  double pencilMaxOpacity = 0.8;
  double pencilMinPressure = 0.5;
  double pencilMaxPressure = 1.2;
  double fountainThinning = 0.5;
  double fountainNibAngleDeg = 30.0;
  double fountainNibStrength = 0.35;
  double fountainPressureRate = 0.275;
  int fountainTaperEntry = 6;

  /// Whether a stroke is currently being drawn.
  bool get isDrawing => _drawing;

  /// Start a new stroke. Clears any in-flight points and pushes the new
  /// colour / width / brush parameters. [brushType] matches the engine's
  /// internal brush enum (0 = pen, 1 = pencil, 2 = fountain pen, 3 = marker,
  /// 4 = highlighter — see `ProPenType`).
  void beginStroke({
    required Color color,
    required double width,
    int brushType = 0,
  }) {
    _points.clear();
    _color = color;
    _strokeWidth = width;
    _brushType = brushType;
    _drawing = true;
    notifyListeners();
  }

  /// Append a pressure-aware sample in canvas (world) coordinates.
  void appendPoint(
    Offset position, {
    double pressure = 1.0,
    double tiltX = 0,
    double tiltY = 0,
  }) {
    if (!_drawing) return;
    _points.add(
      ProDrawingPoint(
        position: position,
        pressure: pressure.clamp(0.0, 1.0),
        timestamp: DateTime.now().millisecondsSinceEpoch,
        tiltX: tiltX,
        tiltY: tiltY,
        orientation: 0.0,
      ),
    );
    notifyListeners();
  }

  /// Mark the current stroke finished. The overlay clears the native
  /// surface and returns to the idle state. It does NOT persist the stroke —
  /// callers are responsible for committing the sample list (available via
  /// [takePoints]) to their scene graph or storage.
  void endStroke() {
    if (!_drawing) return;
    _drawing = false;
    notifyListeners();
  }

  /// Cancel an in-flight stroke without emitting it (e.g. on a second-finger
  /// gesture). Equivalent to [endStroke] + discard.
  void cancelStroke() {
    if (!_drawing && _points.isEmpty) return;
    _drawing = false;
    _points.clear();
    notifyListeners();
  }

  /// Return and clear the buffered samples. Call this from the
  /// [endStroke] path to hand ownership to your storage layer.
  List<ProDrawingPoint> takePoints() {
    final out = List<ProDrawingPoint>.unmodifiable(_points);
    _points.clear();
    return out;
  }

  /// Read-only live view of the buffered samples (for debugging / fallback
  /// Dart rendering). Do not mutate.
  List<ProDrawingPoint> get points =>
      List<ProDrawingPoint>.unmodifiable(_points);

  // Internals consumed by [NativeStrokeOverlay]. Kept public for the widget
  // to read without reaching into private state, but not intended as API.
  @protected
  Color get color => _color;
  @protected
  double get strokeWidth => _strokeWidth;
  @protected
  int get brushType => _brushType;
  @protected
  List<ProDrawingPoint> get bufferedPoints => _points;
}

/// A zero-Dart-overhead live stroke surface backed by the engine's native
/// renderer. Sits in your widget tree like any other composable and consumes
/// points from a [NativeStrokeOverlayController].
///
/// The overlay listens to [canvasController] so pan/zoom/rotation stay
/// synchronised with the Dart scene automatically.
class NativeStrokeOverlay extends StatefulWidget {
  const NativeStrokeOverlay({
    super.key,
    required this.canvasController,
    required this.controller,
    this.fallbackToDart = true,
  });

  /// Camera controller — pan/zoom/rotation from this object is forwarded to
  /// the native renderer so the live stroke stays anchored to the scene.
  final InfiniteCanvasController canvasController;

  /// Stroke controller supplying the in-flight point stream.
  final NativeStrokeOverlayController controller;

  /// If the native path is unavailable (web, headless tests, unsupported
  /// GPU), render the live stroke in Dart using a lightweight painter.
  /// Defaults to `true` so the widget is always visually correct; set to
  /// `false` if you already render the fallback elsewhere.
  final bool fallbackToDart;

  @override
  State<NativeStrokeOverlay> createState() => _NativeStrokeOverlayState();
}

class _NativeStrokeOverlayState extends State<NativeStrokeOverlay> {
  /// The commercial GPU backend, or `null` if the consumer didn't register
  /// one (free pub.dev core → Dart fallback path).
  GpuStrokeBackend? get _backend => FlueraCanvasGpu.backend;

  int? _textureId;
  bool _initializing = false;
  bool _available = false;
  Size? _lastPhysicalSize;
  double _lastDpr = 1.0;
  bool _wasDrawing = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerTick);
    widget.canvasController.addListener(_onCameraChanged);
  }

  @override
  void didUpdateWidget(covariant NativeStrokeOverlay old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onControllerTick);
      widget.controller.addListener(_onControllerTick);
    }
    if (old.canvasController != widget.canvasController) {
      old.canvasController.removeListener(_onCameraChanged);
      widget.canvasController.addListener(_onCameraChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerTick);
    widget.canvasController.removeListener(_onCameraChanged);
    _backend?.dispose();
    super.dispose();
  }

  bool get _platformSupported {
    if (_backend == null) return false;
    if (kIsWeb) return true;
    try {
      return Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isLinux ||
          Platform.isWindows;
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensureInitialized(Size physical, double dpr) async {
    if (!_platformSupported) return;
    if (_initializing) return;
    final backend = _backend;
    if (backend == null) return;
    if (_textureId != null &&
        _lastPhysicalSize == physical &&
        _lastDpr == dpr) {
      return;
    }

    _initializing = true;
    try {
      _available = await backend.isAvailable;
      if (!_available) return;
      if (_textureId == null) {
        final id = await backend.init(
          physical.width.toInt(),
          physical.height.toInt(),
        );
        if (!mounted) return;
        if (id == null) {
          _available = false;
          return;
        }
        setState(() {
          _textureId = id;
          _lastPhysicalSize = physical;
          _lastDpr = dpr;
        });
      } else if (_lastPhysicalSize != physical) {
        await backend.resize(physical.width.toInt(), physical.height.toInt());
        _lastPhysicalSize = physical;
        _lastDpr = dpr;
      }
      _pushTransform();
      _onControllerTick();
    } finally {
      _initializing = false;
    }
  }

  void _pushTransform() {
    final backend = _backend;
    if (backend == null || _textureId == null || _lastPhysicalSize == null) {
      return;
    }
    backend.setTransform(
      widget.canvasController,
      _lastPhysicalSize!.width.toInt(),
      _lastPhysicalSize!.height.toInt(),
      _lastDpr,
    );
  }

  void _onCameraChanged() {
    if (_textureId == null) return;
    _pushTransform();
  }

  bool get _isReady => _textureId != null;

  void _onControllerTick() {
    final backend = _backend;
    final c = widget.controller;

    if (backend == null) {
      // No GPU add-on installed — NativeStrokeOverlay is a no-op; the
      // parent widget renders the live stroke via its Dart painter.
      return;
    }

    if (!_isReady) {
      if (c.isDrawing && _platformSupported && _lastPhysicalSize != null) {
        _ensureInitialized(_lastPhysicalSize!, _lastDpr);
      }
      return;
    }

    final drawing = c.isDrawing;
    if (drawing && !_wasDrawing) {
      backend.clear();
      _pushTransform();
    }
    _wasDrawing = drawing;

    if (!drawing && c.bufferedPoints.isEmpty) {
      backend.clear();
      return;
    }
    if (c.bufferedPoints.length < 2) return;

    backend.updateAndRender(
      c.bufferedPoints,
      c.color,
      c.strokeWidth,
      force: true,
      brushType: c.brushType,
      pencilBaseOpacity: c.pencilBaseOpacity,
      pencilMaxOpacity: c.pencilMaxOpacity,
      pencilMinPressure: c.pencilMinPressure,
      pencilMaxPressure: c.pencilMaxPressure,
      fountainThinning: c.fountainThinning,
      fountainNibAngleDeg: c.fountainNibAngleDeg,
      fountainNibStrength: c.fountainNibStrength,
      fountainPressureRate: c.fountainPressureRate,
      fountainTaperEntry: c.fountainTaperEntry,
      zoomScale: widget.canvasController.scale,
    );
  }

  @override
  Widget build(BuildContext context) {
    // When a commercial GPU backend is installed and initialised we mount
    // its platform view here (Texture widget for Vulkan/Metal/OpenGL/D3D11,
    // or an HtmlElementView routed by the backend for WebGPU). With no
    // backend (free pub.dev core), we return the Dart fallback painter —
    // the live stroke is still visible, just from Dart.
    final backend = _backend;
    if (backend != null && _textureId != null) {
      if (backend.usesPlatformView) {
        // Backend prefers an HtmlElementView / custom widget: it must
        // expose a builder via a subclass or via a static hook. For
        // simplicity the backend publishes a widget getter; if none is
        // supplied we fall back to Texture.
        return IgnorePointer(child: Texture(textureId: _textureId!));
      }
      return IgnorePointer(child: Texture(textureId: _textureId!));
    }
    return _layoutProbe(showFallback: widget.fallbackToDart);
  }

  Widget _layoutProbe({bool showFallback = false}) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final dpr = MediaQuery.of(ctx).devicePixelRatio;
        final size = constraints.biggest;
        if (_platformSupported && size.isFinite && !size.isEmpty) {
          _lastPhysicalSize = Size(size.width * dpr, size.height * dpr);
          _lastDpr = dpr;
        }
        if (showFallback) {
          return IgnorePointer(
            child: CustomPaint(
              painter: _DartFallbackPainter(
                controller: widget.controller,
                canvasController: widget.canvasController,
              ),
              size: Size.infinite,
            ),
          );
        }
        return const SizedBox.expand();
      },
    );
  }
}

class _DartFallbackPainter extends CustomPainter {
  _DartFallbackPainter({
    required this.controller,
    required this.canvasController,
  }) : super(repaint: Listenable.merge([controller, canvasController]));

  final NativeStrokeOverlayController controller;
  final InfiniteCanvasController canvasController;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = controller.bufferedPoints;
    if (pts.length < 2) return;
    canvas.save();
    canvas.translate(canvasController.offset.dx, canvasController.offset.dy);
    canvas.scale(canvasController.scale);
    final paint =
        Paint()
          ..color = controller.color
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    for (int i = 1; i < pts.length; i++) {
      final avg = (pts[i - 1].pressure + pts[i].pressure) * 0.5;
      paint.strokeWidth = controller.strokeWidth * (0.3 + avg * 0.9);
      canvas.drawLine(pts[i - 1].position, pts[i].position, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DartFallbackPainter old) => true;
}
