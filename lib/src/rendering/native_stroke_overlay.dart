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
import 'package:flutter/scheduler.dart' show Ticker;

import '../canvas/infinite_canvas_controller.dart';
import '../drawing/brush_config.dart';
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

class _NativeStrokeOverlayState extends State<NativeStrokeOverlay>
    with SingleTickerProviderStateMixin {
  /// The commercial GPU backend, or `null` if the consumer didn't register
  /// one (free pub.dev core → Dart fallback path).
  GpuStrokeBackend? get _backend => FlueraCanvasGpu.backend;

  int? _textureId;
  bool _initializing = false;
  bool _available = false;
  Size? _lastPhysicalSize;
  double _lastDpr = 1.0;
  bool _wasDrawing = false;

  /// vsync-driven repaint pulse. On Impeller-Vulkan / Adreno the
  /// `Texture` widget does not get marked dirty when the underlying
  /// SurfaceProducer presents a new Vulkan frame — Flutter's compositor
  /// silently keeps showing the previous frame, which manifests as a
  /// blank canvas while strokes are happening. Driving a `setState`
  /// from a Ticker (one tick per vsync, ~60 / 120 Hz) re-mounts the
  /// `Texture` every frame so the compositor pulls the latest swap-
  /// chain image. The Ticker is started on pen-down and stopped on
  /// pen-up to avoid the 60 Hz CPU cost when nothing is drawing.
  late final Ticker _repaintTicker;
  int _repaintTick = 0;

  @override
  void initState() {
    super.initState();
    _repaintTicker = createTicker(_onRepaintTick);
    widget.controller.addListener(_onControllerTick);
    widget.canvasController.addListener(_onCameraChanged);
    // 🎯 Cold-start fix: kick the GPU backend init right after the first
    // build instead of waiting for the user's first pen-down. Without
    // this the first stroke loses its leading 4-8 sample points because
    // backend.init() is async and the pointer events arrive faster than
    // the platform-channel hop. See `_scheduleProactiveInit`.
    _scheduleProactiveInit();
  }

  // Counter for the proactive init scheduling — bounds the retry loop
  // when `_lastPhysicalSize` is not yet available because LayoutBuilder
  // hasn't run.
  int _proactiveInitRetries = 0;
  static const int _kProactiveInitMaxRetries = 8;

  void _scheduleProactiveInit() {
    if (_backend == null) return; // No GPU add-on; nothing to warm up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_textureId != null) return; // Already initialised.
      if (_lastPhysicalSize != null) {
        // First build resolved the size — fire the init now.
        _ensureInitialized(_lastPhysicalSize!, _lastDpr);
        return;
      }
      // LayoutBuilder hasn't produced a size yet; try again next frame.
      if (_proactiveInitRetries < _kProactiveInitMaxRetries) {
        _proactiveInitRetries++;
        _scheduleProactiveInit();
      }
    });
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
    _repaintTicker.dispose();
    widget.controller.removeListener(_onControllerTick);
    widget.canvasController.removeListener(_onCameraChanged);
    _backend?.dispose();
    super.dispose();
  }

  void _onRepaintTick(Duration _) {
    if (!mounted) return;
    // Empty setState: the build() method will rebuild the `Texture`
    // widget, which triggers the Impeller compositor to pull the
    // latest swap-chain image. Tick counter exists only as a witness
    // value so the build closes over a changing identity (otherwise
    // the framework can short-circuit identical rebuilds).
    setState(() => _repaintTick++);
    // Warmup countdown: stop the ticker once we've burned through the
    // post-init frame budget AND there's no active stroke driving it.
    if (_warmupTicksLeft > 0) {
      _warmupTicksLeft--;
      if (_warmupTicksLeft == 0 && !_wasDrawing && _repaintTicker.isActive) {
        _repaintTicker.stop();
      }
    }
  }

  void _ensureRepaintTickerRunning(bool drawing) {
    // Keep the ticker active for one extra frame after pen-up so the
    // committed final stroke definitely makes it onto the screen.
    if (drawing && !_repaintTicker.isActive) {
      _repaintTicker.start();
    } else if (!drawing && _repaintTicker.isActive && _warmupTicksLeft == 0) {
      // Defer the stop one frame so the compositor sees the cleared
      // surface before we go quiet again. Skipped while warmup is in
      // progress — the ticker callback owns that lifecycle.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_wasDrawing &&
            _repaintTicker.isActive &&
            _warmupTicksLeft == 0) {
          _repaintTicker.stop();
        }
      });
    }
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
      final justInitialized = _textureId == null;
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
      // 🎯 Cold-start fix: do the swap-chain warmup BEFORE replaying the
      // current buffered points. The previous order was:
      //   _pushTransform() → _onControllerTick() → backend.clear()
      // but `_onControllerTick` already pushes `bufferedPoints` to the
      // backend, so the subsequent `backend.clear()` was wiping them.
      // The new order does the warmup clear first (so the swap-chain
      // is alive and the descriptor-set cache is populated) and only
      // then drains the buffer.
      if (justInitialized) {
        // Cold-start pre-roll. Right after `init` returns a textureId
        // the Impeller-Vulkan compositor on Adreno is still showing
        // whatever the SurfaceProducer's first swap-chain image
        // happens to be (uninitialised pixels until the C++ side does
        // its first `vkQueuePresentKHR`). If we wait for the user's
        // first stroke to trigger that present, the first 4–8 sample
        // points get rendered into a swap-chain image the compositor
        // never reads.
        //
        // Calling `clear()` here forces the C++ renderer to do a
        // fully-transparent present immediately, which:
        //   1. lights up the swap-chain (the compositor now knows
        //      where to read),
        //   2. warms the Vulkan pipeline (descriptor sets, MSAA
        //      resolve, the whole shader cache),
        //   3. marks the Texture widget dirty via the next `_repaintTick`
        //      bump so the compositor re-binds the texture id to the
        //      now-populated SurfaceProducer.
        backend.clear();
        _runPostInitWarmup();
      }
      _onControllerTick();
    } finally {
      _initializing = false;
    }
  }

  /// How many vsync ticks to keep the Texture rebuilding after the
  /// first init, even with no stroke in flight. ~8 frames at 60 Hz =
  /// ~133 ms, plenty for the Impeller compositor to bind the new
  /// SurfaceProducer and pump the first present.
  static const int _kPostInitWarmupFrames = 8;
  int _warmupTicksLeft = 0;

  void _runPostInitWarmup() {
    _warmupTicksLeft = _kPostInitWarmupFrames;
    if (!_repaintTicker.isActive) {
      _repaintTicker.start();
    }
  }

  void _pushTransform() {
    final backend = _backend;
    if (backend == null || _textureId == null || _lastPhysicalSize == null) {
      return;
    }
    _lastTransformSeq = backend.setTransform(
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
      // Safety net: the proactive init in `initState` should have run by
      // now. If it didn't (e.g. LayoutBuilder still hadn't produced a
      // size after `_kProactiveInitMaxRetries` post-frame retries), kick
      // the init now on the first pen-down. The user will see the leading
      // points of this very first stroke under the Dart fallback (or lost,
      // if `fallbackToDart` is false) — but only in this fallback path.
      if (c.isDrawing && _platformSupported && _lastPhysicalSize != null) {
        _ensureInitialized(_lastPhysicalSize!, _lastDpr);
      }
      return;
    }

    final drawing = c.isDrawing;
    if (drawing && !_wasDrawing) {
      backend.clear();
      _pushTransform();
      if (kDebugMode) {
        debugPrint('[NSO] PEN-DOWN. tick=$_repaintTick '
            'points=${c.bufferedPoints.length} '
            'textureId=$_textureId');
      }
    }
    if (kDebugMode && drawing) {
      debugPrint('[NSO] tick=$_repaintTick '
          'points=${c.bufferedPoints.length}');
    }
    _wasDrawing = drawing;
    _ensureRepaintTickerRunning(drawing);

    // Drive the Texture rebuild from the data flow, not from vsync.
    // Every time a new sample lands in the buffer this listener fires
    // (`InfiniteCanvasController.bufferedPoints` is a ChangeNotifier);
    // we bump the witness key and call setState synchronously so the
    // Texture widget gets a fresh ValueKey in the SAME frame as the
    // upcoming `backend.updateAndRender`, instead of waiting for the
    // Ticker's next vsync (which is what was eating the first 4–8
    // points of every fresh stroke on Impeller-Vulkan / Adreno).
    if (drawing && mounted) {
      setState(() {
        _repaintTick++;
      });
    }

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
      pencil: PencilConfig(
        baseOpacity: c.pencilBaseOpacity,
        maxOpacity: c.pencilMaxOpacity,
        minPressure: c.pencilMinPressure,
        maxPressure: c.pencilMaxPressure,
      ),
      fountainPen: FountainPenConfig(
        thinning: c.fountainThinning,
        nibAngleDeg: c.fountainNibAngleDeg,
        nibStrength: c.fountainNibStrength,
        pressureRate: c.fountainPressureRate,
        taperEntry: c.fountainTaperEntry,
      ),
      zoomScale: widget.canvasController.scale,
      transformSeq: _lastTransformSeq,
    );
  }

  /// Latest transform sequence number returned by `backend.setTransform`.
  /// Stamped on every `updateAndRender` so the native scoreboard can drop
  /// stroke batches that were queued under an older camera matrix.
  int _lastTransformSeq = 0;

  @override
  Widget build(BuildContext context) {
    // When a commercial GPU backend is installed and initialised we mount
    // its platform view here (Texture widget for Vulkan/Metal/OpenGL/D3D11,
    // or an HtmlElementView routed by the backend for WebGPU). With no
    // backend (free pub.dev core), we return the Dart fallback painter —
    // the live stroke is still visible, just from Dart.
    final backend = _backend;
    if (backend != null && _textureId != null) {
      // Impeller-Vulkan platform-view trap: on Android the `Texture`
      // widget is composited at hardware-overlay level by the engine,
      // ABOVE every Flutter-painted widget regardless of `Stack`
      // z-order. So during drawing we mount ONLY the Dart preview —
      // the native renderer keeps receiving the stream (engine
      // commits the stroke from there on pen-up) but its swap-chain
      // output stays hidden during the live phase. On pen-up the
      // texture re-mounts.
      //
      // Importantly, the drawing branch has NO `Stack` wrapper — a
      // bare `CustomPaint` inside `SizedBox.expand` so the parent
      // `Positioned.fill` constraints flow through unchanged.
      // (StackFit.expand inside an already-expanded child sometimes
      // ends up with a zero `paint(canvas, size)` call on Adreno.)
      final tickKey = ValueKey<int>(_repaintTick);
      if (_wasDrawing) {
        return IgnorePointer(
          child: SizedBox.expand(
            child: CustomPaint(
              painter: _DartFallbackPainter(
                controller: widget.controller,
                canvasController: widget.canvasController,
              ),
            ),
          ),
        );
      }
      // Idle: mount the texture so any non-stroke surface (e.g. the
      // committed canvas the engine commits to it on pen-up) is shown.
      return IgnorePointer(
        child: Texture(key: tickKey, textureId: _textureId!),
      );
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
    if (kDebugMode) {
      debugPrint('[DartPreview] paint pts=${pts.length} '
          'color=${controller.color.toARGB32().toRadixString(16)} '
          'width=${controller.strokeWidth}');
    }
    if (pts.length < 2) {
      // Even a single point should be visible — draw a dot.
      if (pts.length == 1) {
        canvas.save();
        canvas.translate(
            canvasController.offset.dx, canvasController.offset.dy);
        canvas.scale(canvasController.scale);
        canvas.drawCircle(
          pts[0].position,
          controller.strokeWidth * 0.5,
          Paint()..color = controller.color,
        );
        canvas.restore();
      }
      return;
    }
    canvas.save();
    canvas.translate(canvasController.offset.dx, canvasController.offset.dy);
    canvas.scale(canvasController.scale);
    final paint =
        Paint()
          ..color = controller.color
          ..style = PaintingStyle.stroke
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
