// ════════════════════════════════════════════════════════════════════════════
// 🎨 INFINITE CANVAS — SDK reference widget for Fluera Engine
//
// A minimal, dependency-light drawing surface built on top of the
// `fluera_engine` primitives. Showcases:
//
//   • Pan + zoom via [InfiniteCanvasController]
//   • Pressure-sensitive drawing via [InfiniteCanvasGestureDetector]
//   • In-memory stroke storage (no SceneGraph, no storage adapter)
//   • Thin [CustomPainter] rendering of live + committed strokes
//   • PNG export helper
//
// DESIGN GOALS
//   1. Show what the SDK **primitives** enable out of the box.
//   2. Stay under ~400 lines so a newcomer can read and understand it in
//      one sitting.
//   3. Introduce zero "magic" — the state flow is: gesture → callback →
//      setState → repaint.
//
// NOT SHOWN HERE (covered by other examples):
//   • Scene graph transactions and undo/redo
//   • Brush engine with texture + GPU shaders (Pro tier)
//   • Collaboration / time travel / encrypted storage
//   • Custom modules via the plugin system
//
// This widget is intentionally **copy-paste friendly**. Drop it in your app,
// bind a controller, and you have a working infinite canvas.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:io' show Platform;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Public SDK primitives — these all come from the scrubbed public barrel.
import './infinite_canvas_controller.dart';
import './infinite_canvas_gesture_detector.dart';
import '../rendering/native_stroke_overlay.dart';

/// A single committed stroke — an opaque list of pressure-aware samples in
/// world coordinates plus render metadata.
///
/// Minimal by design: real apps would wrap these into [StrokeNode]s on a
/// [SceneGraph], but this example keeps state flat to make the pipeline
/// obvious.
class CanvasStroke {
  /// Points in world (canvas) coordinates.
  final List<Offset> points;

  /// Pressure values per point, normalised to [0, 1].
  final List<double> pressures;

  /// Rendering color. Flat per-stroke for simplicity.
  final Color color;

  /// Base stroke width in world units. Pressure scales this linearly.
  final double baseWidth;

  const CanvasStroke({
    required this.points,
    required this.pressures,
    required this.color,
    required this.baseWidth,
  });
}

/// A ready-to-use infinite canvas widget.
///
/// Wire a controller from the outside if you want to drive the camera from
/// your app (programmatic pan/zoom, reset-view button, etc.). Otherwise the
/// widget creates and owns its own controller.
class FlueraCanvas extends StatefulWidget {
  const FlueraCanvas({
    super.key,
    this.controller,
    this.strokeColor = const Color(0xFF1A1A1A),
    this.strokeWidth = 2.0,
    this.background = const Color(0xFFFAFAFA),
    this.onStrokeCommitted,
    this.enableNativeLiveStroke = true,
  });

  /// Optional external controller. If null, an internal one is created and
  /// disposed with the widget.
  final InfiniteCanvasController? controller;

  /// Color used for new strokes.
  final Color strokeColor;

  /// Base width used for new strokes (pressure will scale this 0.3×…1.2×).
  final double strokeWidth;

  /// Canvas background — drawn as an infinite solid fill behind all strokes.
  final Color background;

  /// Fires every time the user lifts the pen after a stroke. Good place to
  /// persist to your own storage, push to a scene graph, sync to the network.
  final void Function(CanvasStroke stroke)? onStrokeCommitted;

  /// When `true` (default) the live stroke is rendered by the engine's
  /// GPU-accelerated native pipeline (Vulkan / Metal / OpenGL / Direct3D 11 /
  /// — web still uses the Dart painter). This gives sub-frame latency and 60+
  /// FPS on modest hardware. Committed strokes always render through the
  /// Dart painter so the feature is transparent to the rest of the widget.
  final bool enableNativeLiveStroke;

  @override
  State<FlueraCanvas> createState() => FlueraCanvasState();
}

class FlueraCanvasState extends State<FlueraCanvas>
    with SingleTickerProviderStateMixin {
  late final InfiniteCanvasController _controller;
  late final bool _ownsController;
  late final NativeStrokeOverlayController _nativeOverlay;

  /// Committed strokes, in draw order.
  final List<CanvasStroke> _strokes = <CanvasStroke>[];

  /// Current in-progress stroke (null when the user isn't drawing).
  List<Offset>? _livePoints;
  List<double>? _livePressures;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? InfiniteCanvasController();
    // Redraw whenever the camera (pan/zoom) changes — strokes are in world
    // coords so the painter recomputes positions against the new transform.
    _controller.addListener(_onCameraChanged);
    _nativeOverlay = NativeStrokeOverlayController();
    _useNative = widget.enableNativeLiveStroke && _nativePlatformSupported;
  }

  /// Matches `NativeStrokeOverlay._platformSupported`. On Linux / Windows /
  /// web the native path is skipped — the live stroke is drawn by the main
  /// Dart painter exactly like the committed strokes.
  static bool get _nativePlatformSupported {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
    } catch (_) {
      return false;
    }
  }

  late final bool _useNative;

  @override
  void dispose() {
    _controller.removeListener(_onCameraChanged);
    if (_ownsController) _controller.dispose();
    _nativeOverlay.dispose();
    super.dispose();
  }

  void _onCameraChanged() {
    if (!mounted) return;
    setState(() {});
  }

  // ── Drawing callbacks ─────────────────────────────────────────────────────

  /// Screen-space position → world-space (undoes camera transform).
  Offset _screenToWorld(Offset screen) {
    final inv = 1.0 / _controller.scale;
    return Offset(
      (screen.dx - _controller.offset.dx) * inv,
      (screen.dy - _controller.offset.dy) * inv,
    );
  }

  void _onDrawStart(Offset screen, double pressure, double tiltX, double tiltY) {
    final world = _screenToWorld(screen);
    setState(() {
      _livePoints = <Offset>[world];
      _livePressures = <double>[pressure];
    });
    if (_useNative) {
      _nativeOverlay.beginStroke(
        color: widget.strokeColor,
        width: widget.strokeWidth,
      );
      _nativeOverlay.appendPoint(
        world,
        pressure: pressure,
        tiltX: tiltX,
        tiltY: tiltY,
      );
    }
  }

  void _onDrawUpdate(Offset screen, double pressure, double tiltX, double tiltY) {
    if (_livePoints == null) return;
    final world = _screenToWorld(screen);
    setState(() {
      _livePoints!.add(world);
      _livePressures!.add(pressure);
    });
    if (_useNative) {
      _nativeOverlay.appendPoint(
        world,
        pressure: pressure,
        tiltX: tiltX,
        tiltY: tiltY,
      );
    }
  }

  void _onDrawEnd(Offset _) {
    if (_useNative) {
      _nativeOverlay.endStroke();
      _nativeOverlay.takePoints();
    }
    if (_livePoints == null || _livePoints!.length < 2) {
      setState(() {
        _livePoints = null;
        _livePressures = null;
      });
      return;
    }
    final stroke = CanvasStroke(
      points: List<Offset>.unmodifiable(_livePoints!),
      pressures: List<double>.unmodifiable(_livePressures!),
      color: widget.strokeColor,
      baseWidth: widget.strokeWidth,
    );
    setState(() {
      _strokes.add(stroke);
      _livePoints = null;
      _livePressures = null;
    });
    widget.onStrokeCommitted?.call(stroke);
  }

  void _onDrawCancel() {
    if (widget.enableNativeLiveStroke) _nativeOverlay.cancelStroke();
    setState(() {
      _livePoints = null;
      _livePressures = null;
    });
  }

  // ── Public API: clear / undo / export ─────────────────────────────────────

  /// Remove every committed stroke. Camera position is preserved.
  void clear() {
    setState(() {
      _strokes.clear();
      _livePoints = null;
      _livePressures = null;
    });
  }

  /// Remove the most recent committed stroke.
  bool undoLastStroke() {
    if (_strokes.isEmpty) return false;
    setState(() {
      _strokes.removeLast();
    });
    return true;
  }

  /// Number of committed strokes on the canvas.
  int get strokeCount => _strokes.length;

  /// Programmatically append a stroke to the canvas. Skips gesture pipeline
  /// entirely — useful for replays, procedural content, or wire-format
  /// deserialization.
  void pushStroke(CanvasStroke stroke) {
    setState(() {
      _strokes.add(stroke);
    });
    widget.onStrokeCommitted?.call(stroke);
  }

  /// Programmatically append a batch of strokes in one frame.
  void pushStrokes(Iterable<CanvasStroke> strokes) {
    final batch = strokes.toList();
    if (batch.isEmpty) return;
    setState(() {
      _strokes.addAll(batch);
    });
    if (widget.onStrokeCommitted != null) {
      for (final s in batch) {
        widget.onStrokeCommitted!(s);
      }
    }
  }

  /// Read-only view of the committed stroke list (defensive copy).
  List<CanvasStroke> get strokes => List.unmodifiable(_strokes);

  /// Rasterize the current canvas (all strokes) into a PNG byte array sized
  /// [width]×[height] pixels. Respects the current camera for WYSIWYG export.
  ///
  /// Note: this example uses the stock Flutter `ui.PictureRecorder`. For
  /// high-performance production exports, the fluera_engine_pro package
  /// ships a GPU-accelerated `ExportPipeline`.
  Future<ui.Image> renderToImage({
    required int width,
    required int height,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final painter = _InfiniteCanvasPainter(
      strokes: _strokes,
      livePoints: null, // don't include in-flight strokes in exports
      livePressures: null,
      baseWidth: widget.strokeWidth,
      liveColor: widget.strokeColor,
      cameraOffset: _controller.offset,
      cameraScale: _controller.scale,
      background: widget.background,
    );
    painter.paint(canvas, Size(width.toDouble(), height.toDouble()));
    final picture = recorder.endRecording();
    return picture.toImage(width, height);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // When the native overlay is active, hide the Dart-side live stroke
    // so the two don't double-paint. The native Texture is toggled on
    // pen-down / off on pen-up inside NativeStrokeOverlay (Fluera
    // pattern). On pen-up the committed stroke is already in _strokes,
    // rendered by the Dart painter — the transition is seamless.
    final useNative = _useNative;
    final scenePainter = _InfiniteCanvasPainter(
      strokes: _strokes,
      livePoints: useNative ? null : _livePoints,
      livePressures: useNative ? null : _livePressures,
      baseWidth: widget.strokeWidth,
      liveColor: widget.strokeColor,
      cameraOffset: _controller.offset,
      cameraScale: _controller.scale,
      background: widget.background,
    );

    return InfiniteCanvasGestureDetector(
      controller: _controller,
      onDrawStart: _onDrawStart,
      onDrawUpdate: _onDrawUpdate,
      onDrawEnd: _onDrawEnd,
      onDrawCancel: _onDrawCancel,
      child: useNative
          ? Stack(
              children: [
                CustomPaint(painter: scenePainter, size: Size.infinite),
                Positioned.fill(
                  child: NativeStrokeOverlay(
                    canvasController: _controller,
                    controller: _nativeOverlay,
                    fallbackToDart: false,
                  ),
                ),
              ],
            )
          : CustomPaint(painter: scenePainter, size: Size.infinite),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter — thin, no caching, no LOD. For production workloads involving
// thousands of strokes, use fluera_engine_pro's tile-cached renderer.
// ─────────────────────────────────────────────────────────────────────────────

class _InfiniteCanvasPainter extends CustomPainter {
  _InfiniteCanvasPainter({
    required this.strokes,
    required this.livePoints,
    required this.livePressures,
    required this.baseWidth,
    required this.liveColor,
    required this.cameraOffset,
    required this.cameraScale,
    required this.background,
  });

  final List<CanvasStroke> strokes;
  final List<Offset>? livePoints;
  final List<double>? livePressures;
  final double baseWidth;
  final Color liveColor;
  final Offset cameraOffset;
  final double cameraScale;
  final Color background;

  @override
  void paint(Canvas canvas, Size size) {
    // Background fill.
    canvas.drawRect(Offset.zero & size, Paint()..color = background);

    // Apply camera transform once, so stroke coordinates can stay in world space.
    canvas.save();
    canvas.translate(cameraOffset.dx, cameraOffset.dy);
    canvas.scale(cameraScale);

    for (final s in strokes) {
      _paintStroke(canvas, s.points, s.pressures, s.color, s.baseWidth);
    }
    if (livePoints != null && livePressures != null && livePoints!.length >= 2) {
      _paintStroke(canvas, livePoints!, livePressures!, liveColor, baseWidth);
    }

    canvas.restore();
  }

  void _paintStroke(
    Canvas canvas,
    List<Offset> points,
    List<double> pressures,
    Color color,
    double baseWidth,
  ) {
    // Render each segment with a pressure-proportional width. Simple and
    // good enough for an MVP; production engines use stamping/tesselation.
    final paint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (int i = 1; i < points.length; i++) {
      final avg = (pressures[i - 1] + pressures[i]) * 0.5;
      paint.strokeWidth = baseWidth * (0.3 + avg * 0.9);
      canvas.drawLine(points[i - 1], points[i], paint);
    }
  }

  @override
  bool shouldRepaint(covariant _InfiniteCanvasPainter old) {
    // Conservative: any state change triggers repaint. FlueraCanvas.setState
    // already throttles this to real updates.
    return old.strokes != strokes ||
        old.livePoints != livePoints ||
        old.livePressures != livePressures ||
        old.cameraOffset != cameraOffset ||
        old.cameraScale != cameraScale ||
        old.background != background;
  }
}
