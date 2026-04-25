// ════════════════════════════════════════════════════════════════════════════
// 🎨 FlueraCanvas — production-ready infinite canvas widget.
//
//   • Pan / zoom / rotation via [InfiniteCanvasController] (physics-based)
//   • Pressure-sensitive drawing via [InfiniteCanvasGestureDetector]
//   • Native GPU live-stroke pipeline (Vulkan / Metal / OpenGL / D3D11 / WebGPU)
//   • Spatial-index-backed viewport culling → fluid 60 FPS up to ~10 k strokes
//   • Undo / redo history with configurable depth
//   • Stroke-mode eraser (undo-reversible, O(log n) hit-test via RTree)
//   • PNG export helper
//
// Everything else (scene graph transactions, tile cache, collaboration,
// advanced brushes, encrypted storage) lives in the private `fluera_engine`
// and commercial `fluera_engine_pro` packages.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:io' show Platform;
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter/scheduler.dart' show Ticker;

import './canvas_background.dart';
import './canvas_serializer.dart';
import './infinite_canvas_controller.dart';
import './infinite_canvas_gesture_detector.dart';
import '../rendering/native_stroke_overlay.dart';
import '../rendering/gpu/gpu_stroke_backend.dart';
import '../rendering/optimization/spatial_index.dart';

/// A single committed stroke — an opaque list of pressure-aware samples in
/// world coordinates plus render metadata.
///
/// Strokes are immutable by design. Use [pushStroke] to append, [undo] /
/// [redo] to manipulate history, or the eraser tool to remove.
///
/// Internally caches a [ui.Picture] of the rasterised segments so
/// repainting many committed strokes per frame is a single
/// `drawPicture` per stroke (vs N `drawLine` calls), which scales the
/// canvas to 5k–10k strokes without dropping frames.
class CanvasStroke {
  /// Points in world (canvas) coordinates.
  final List<Offset> points;

  /// Pressure values per point, normalised to [0, 1]. Must match
  /// [points.length].
  final List<double> pressures;

  /// Rendering color. Flat per-stroke for simplicity.
  final Color color;

  /// Base stroke width in world units. Pressure scales this linearly.
  final double baseWidth;

  CanvasStroke({
    required this.points,
    required this.pressures,
    required this.color,
    required this.baseWidth,
  }) : _cachedBounds = _computeBounds(points, baseWidth);

  final Rect _cachedBounds;

  /// Axis-aligned bounding rect in world coordinates, padded by a safety
  /// margin so hit-test / culling is lossless at the edge.
  Rect get bounds => _cachedBounds;

  /// Lazily-built rasterisation cache. Rebuilt on first paint, freed by
  /// [dispose] when the stroke is removed from the canvas. Vector
  /// content — scale-independent and re-usable across cameras.
  ui.Picture? _cachedPicture;

  /// Returns the cached [ui.Picture] for this stroke, building it on
  /// first access. The picture contains the stroke segments in world
  /// coordinates; the caller is responsible for setting up the camera
  /// transform on the canvas before calling `drawPicture`.
  ui.Picture picture() {
    final cached = _cachedPicture;
    if (cached != null) return cached;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _paintStrokeSegments(canvas, points, pressures, color, baseWidth);
    return _cachedPicture = recorder.endRecording();
  }

  /// Releases the cached GPU picture. Call when the stroke is no
  /// longer attached to a canvas (eraser commit, undo of a push,
  /// clear, replace) so the rasterised payload doesn't linger on the
  /// GPU. Calling [picture] afterwards is safe — it rebuilds.
  void dispose() {
    _cachedPicture?.dispose();
    _cachedPicture = null;
  }

  static Rect _computeBounds(List<Offset> points, double baseWidth) {
    if (points.isEmpty) return Rect.zero;
    double minX = points.first.dx;
    double maxX = minX;
    double minY = points.first.dy;
    double maxY = minY;
    for (int i = 1; i < points.length; i++) {
      final p = points[i];
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    // Pressure caps stroke width at ~1.2× baseWidth; half of that expands
    // the bbox on each side so hit-test never misses an edge pixel.
    final pad = baseWidth * 0.6;
    return Rect.fromLTRB(minX - pad, minY - pad, maxX + pad, maxY + pad);
  }
}

/// Tool mode for user input on [FlueraCanvas].
enum CanvasTool {
  /// Pointer commits free-form strokes to the canvas.
  draw,

  /// Pointer erases strokes it touches. Each erased stroke is pushed to the
  /// history so [undo] restores it intact (vector-preserving semantics).
  /// "Stroke-mode" eraser — removes whole strokes that the eraser circle
  /// intersects.
  erase,

  /// Like [erase] but cuts the touched portion of a stroke instead of
  /// removing the entire stroke. The stroke is subdivided into the
  /// surviving pieces. Undo restores the original stroke.
  erasePixel,

  /// Drag from A to B to commit a single straight line stroke.
  line,

  /// Drag from one corner to the opposite corner to commit a rectangle
  /// outline. The rectangle is committed as a closed stroke (5 points).
  rectangle,

  /// Drag from one corner of the bounding box to the opposite to commit
  /// an ellipse outline. The ellipse is committed as a polyline
  /// approximation (32 segments).
  ellipse,
}

/// A ready-to-use infinite canvas widget.
///
/// Typical usage:
///
/// ```dart
/// class MyPage extends StatefulWidget {
///   @override State<MyPage> createState() => _MyPageState();
/// }
///
/// class _MyPageState extends State<MyPage> {
///   final _key = GlobalKey<FlueraCanvasState>();
///   CanvasTool _tool = CanvasTool.draw;
///
///   @override
///   Widget build(BuildContext context) => Scaffold(
///     appBar: AppBar(actions: [
///       IconButton(icon: Icon(Icons.undo), onPressed: () => _key.currentState?.undo()),
///       IconButton(icon: Icon(Icons.redo), onPressed: () => _key.currentState?.redo()),
///     ]),
///     body: FlueraCanvas(key: _key, tool: _tool),
///     floatingActionButton: FloatingActionButton(
///       onPressed: () => setState(() => _tool =
///           _tool == CanvasTool.draw ? CanvasTool.erase : CanvasTool.draw),
///       child: Icon(_tool == CanvasTool.draw ? Icons.edit : Icons.cleaning_services),
///     ),
///   );
/// }
/// ```
class FlueraCanvas extends StatefulWidget {
  const FlueraCanvas({
    super.key,
    this.controller,
    this.strokeColor = const Color(0xFF1A1A1A),
    this.strokeWidth = 2.0,
    this.background = const CanvasBackground.solid(Color(0xFFFAFAFA)),
    this.tool = CanvasTool.draw,
    this.eraserRadius = 24.0,
    this.showEraserPreview = true,
    this.historyCapacity = 100,
    this.enableKeyboardShortcuts = true,
    this.onStrokeCommitted,
    this.onStrokesErased,
    this.enableNativeLiveStroke = true,
    this.initialBytes,
  });

  /// Optional external controller. If null, an internal one is created and
  /// disposed with the widget.
  final InfiniteCanvasController? controller;

  /// Color used for new strokes.
  final Color strokeColor;

  /// Base width used for new strokes (pressure will scale this 0.3×…1.2×).
  final double strokeWidth;

  /// Canvas background — solid color, grid, dotted, or lined paper.
  /// Use `CanvasBackground.solid(color)` for a plain fill.
  final CanvasBackground background;

  /// Currently active input tool. Switching tool mid-gesture cancels the
  /// in-flight action.
  final CanvasTool tool;

  /// Hit-test radius in **screen** pixels for [CanvasTool.erase]. A stroke
  /// is erased when any of its segments sits within this distance of the
  /// pointer.
  final double eraserRadius;

  /// When `true` (default) and [tool] is [CanvasTool.erase], shows a
  /// translucent circle under the pointer so the user sees the eraser's
  /// effective radius. On touch devices only during active press; on
  /// desktop also tracks the hovering mouse.
  final bool showEraserPreview;

  /// Maximum number of operations kept in the undo history. Oldest entries
  /// are dropped first. Set to `0` to disable history entirely.
  final int historyCapacity;

  /// When `true` (default), binds common keyboard shortcuts inside the
  /// canvas focus scope:
  ///   • Ctrl/Cmd + Z → undo
  ///   • Ctrl/Cmd + Shift + Z → redo
  ///   • Ctrl/Cmd + Y → redo
  ///   • Delete / Backspace → clear
  final bool enableKeyboardShortcuts;

  /// Fires every time the user lifts the pen after drawing a stroke.
  final void Function(CanvasStroke stroke)? onStrokeCommitted;

  /// Fires when the eraser tool removes one or more strokes. The argument
  /// is the unmodifiable list of strokes erased in this gesture (can be
  /// re-ordered if the user erases multiple in a single swipe).
  final void Function(List<CanvasStroke> strokes)? onStrokesErased;

  /// When `true` (default) the live stroke is rendered by the native GPU
  /// pipeline (Vulkan / Metal / OpenGL / Direct3D 11 / WebGPU). Gives
  /// sub-frame latency and 60 + FPS on modest hardware. Committed strokes
  /// always render through the Dart painter, so the feature is transparent
  /// to the rest of the widget.
  final bool enableNativeLiveStroke;

  /// Optional initial scene, supplied as bytes produced by
  /// [FlueraCanvasState.toBytes]. When non-null the strokes are decoded
  /// and inserted into the canvas inside `initState` — BEFORE the first
  /// build / paint — so the very first frame already shows the
  /// committed strokes. This is the right way to restore a persisted
  /// canvas; calling `loadFromBytes` on the State after the first frame
  /// can leave the [RepaintBoundary] cached layer stale on
  /// Impeller-Vulkan / Adreno (the second paint is silently coalesced).
  final Uint8List? initialBytes;

  @override
  State<FlueraCanvas> createState() => FlueraCanvasState();
}

class FlueraCanvasState extends State<FlueraCanvas>
    with SingleTickerProviderStateMixin {
  late final InfiniteCanvasController _controller;
  late final bool _ownsController;
  late final NativeStrokeOverlayController _nativeOverlay;

  /// Committed strokes, in draw order (back-to-front).
  final List<CanvasStroke> _strokes = <CanvasStroke>[];

  /// Spatial index over [_strokes]. Rebuilt lazily on hit-test when stale.
  late final RTree<CanvasStroke> _spatialIndex = RTree<CanvasStroke>(
    (s) => s.bounds,
  );

  /// Undo / redo stacks. `null` when [widget.historyCapacity] <= 0.
  _CanvasHistory? _history;

  /// Current in-progress stroke (null when the user isn't drawing).
  List<Offset>? _livePoints;
  List<double>? _livePressures;

  /// Strokes erased in the current erase gesture (committed to history on
  /// pen-up so a whole swipe becomes a single undo step).
  final Set<CanvasStroke> _erasedThisGesture = <CanvasStroke>{};

  /// Last eraser position in world coords — used to paint the hover circle.
  /// `null` when the eraser shouldn't be rendered (hover-off, other tool).
  Offset? _eraserPreviewWorld;

  /// Live-stroke state holder. Owns points, pressures, color and width
  /// for the in-progress stroke. `super(repaint: _liveStroke)` on
  /// [_liveStrokePainter] routes every `forceRepaint()` call straight to
  /// `markNeedsPaint` on the RenderCustomPaint, bypassing widget rebuilds.
  final _LiveStrokeNotifier _liveStroke = _LiveStrokeNotifier();

  /// Notifier fired when the committed stroke list changes (commit /
  /// erase / clear / undo / redo / load). Drives repaint of the
  /// committed painter via `super(repaint: ...)`. Camera changes are
  /// merged in separately so panning/zooming also repaints. Using a
  /// dedicated notifier (instead of triggering a parent `setState`)
  /// keeps the widget tree stable during a gesture — committed
  /// strokes don't get rebuilt on every vsync of the live-stroke
  /// ticker, which is what allows the canvas to scale to 5k–10k
  /// committed strokes.
  final _CommitNotifier _commitTick = _CommitNotifier();

  /// Stable committed-strokes painter. Created once in [initState] and
  /// reused for the lifetime of the State; reads `_strokes`,
  /// `_spatialIndex`, camera state, background and eraser preview
  /// directly from the State at paint time.
  late final _CommittedStrokesPainter _committedPainter;

  /// Vsync-driven ticker that runs ONLY while a draw gesture is active.
  /// On Impeller-Vulkan / Adreno (and possibly other) profile builds the
  /// rendering pipeline coalesces all `setState` / `markNeedsPaint`
  /// calls between pen-down and pen-up into a single frame at pen-up,
  /// making the live stroke invisible mid-gesture. Calling
  /// `setState(() {})` from the ticker callback (which fires on every
  /// vsync) bypasses that coalescing — the dirty mark sits inside an
  /// already-running frame callback rather than being raised by a
  /// pointer event handler, so the framework processes it normally and
  /// build / layout / paint run as expected. The ticker is started in
  /// `_onDrawStart` (draw tool, Dart-only path) and stopped in
  /// `_onDrawEnd` / `_onDrawCancel`, so there is no idle-time cost.
  late final Ticker _liveStrokeTicker;

  /// Stable painter instance. Created ONCE in [initState] and reused for
  /// the lifetime of the State. Recreating the painter on every parent
  /// build (which is what happens with the standard `CustomPaint(painter:
  /// _LiveStrokePainter(...))` idiom) caused the listener subscription on
  /// `super(repaint: ...)` to be silently dropped on Impeller-Vulkan /
  /// Adreno after the first commit `setState`, leaving stroke 2+
  /// invisible. Keeping the same instance across every build means the
  /// subscription is registered once and stays active forever.
  late final _LiveStrokePainter _liveStrokePainter;

  /// Focus node that owns keyboard shortcuts. Created lazily only when
  /// [widget.enableKeyboardShortcuts] is true.
  FocusNode? _focusNode;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? InfiniteCanvasController();
    // Camera changes trigger committed repaint via _commitTick (the
    // _CommittedStrokesPainter listens to merge(_commitTick,
    // _controller)). The legacy `_onCameraChanged` setState is gone —
    // the stable painter pulls camera state directly at paint time.
    _nativeOverlay = NativeStrokeOverlayController();
    // Native path is only possible when:
    //   1. the consumer hasn't opted out via `enableNativeLiveStroke: false`,
    //   2. the current platform has a native backend build, AND
    //   3. a commercial GPU backend (`fluera_canvas_gpu`) is registered at
    //      app boot (free pub.dev consumers don't have one).
    // Without (3) the canvas must render the live stroke in Dart so the
    // user actually sees their ink — otherwise the painter skips live
    // points (assumes Texture handles them) and nothing appears.
    _useNative =
        widget.enableNativeLiveStroke &&
        _nativePlatformSupported &&
        FlueraCanvasGpu.backend != null;
    _liveStrokePainter = _LiveStrokePainter(
      strokeNotifier: _liveStroke,
      controller: _controller,
    );
    _committedPainter = _CommittedStrokesPainter(
      canvasState: this,
      repaintTrigger: Listenable.merge(<Listenable>[_commitTick, _controller]),
    );
    _liveStrokeTicker = createTicker((_) {
      // Tick while either a draw gesture or an erase gesture is in
      // progress — the erase preview circle relies on the ticker to
      // track the pointer in real time on Impeller-Vulkan / Adreno.
      if (mounted) setState(() {});
    });
    if (widget.historyCapacity > 0) {
      _history = _CanvasHistory(capacity: widget.historyCapacity);
    }
    if (widget.enableKeyboardShortcuts) {
      _focusNode = FocusNode(debugLabel: 'FlueraCanvas');
    }
    final initial = widget.initialBytes;
    if (initial != null && initial.isNotEmpty) {
      try {
        final loaded = CanvasSerializer.decodeBytes(initial);
        for (final s in loaded) {
          _strokes.add(s);
          _spatialIndex.insert(s);
        }
      } catch (_) {
        // Corrupt bytes — start with empty canvas.
      }
    }
  }

  /// Matches `NativeStrokeOverlay._platformSupported`. Every platform now has
  /// a native GPU path: Vulkan (Android), Metal (iOS/macOS), OpenGL (Linux),
  /// D3D11 (Windows), WebGPU (web). Each ships with the `fluera_canvas`
  /// package — no companion dependency needed.
  static bool get _nativePlatformSupported {
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

  late final bool _useNative;

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    _nativeOverlay.dispose();
    _focusNode?.dispose();
    _liveStroke.dispose();
    _liveStrokeTicker.dispose();
    _commitTick.dispose();
    for (final s in _strokes) {
      s.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FlueraCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Tool switched mid-gesture: cancel any in-flight draw / erase.
    if (oldWidget.tool != widget.tool) {
      _onDrawCancel();
      _eraserPreviewWorld = null;
      _commitTick.notify();
    }
    if (oldWidget.background != widget.background) {
      _commitTick.notify();
    }
    if (oldWidget.historyCapacity != widget.historyCapacity) {
      if (widget.historyCapacity > 0) {
        _history =
            (_history ?? _CanvasHistory(capacity: widget.historyCapacity))
              ..capacity = widget.historyCapacity;
      } else {
        _history = null;
      }
    }
    if (oldWidget.enableKeyboardShortcuts != widget.enableKeyboardShortcuts) {
      if (widget.enableKeyboardShortcuts && _focusNode == null) {
        _focusNode = FocusNode(debugLabel: 'FlueraCanvas');
      } else if (!widget.enableKeyboardShortcuts) {
        _focusNode?.dispose();
        _focusNode = null;
      }
    }
  }

  // ── Drawing callbacks ─────────────────────────────────────────────────────
  //
  // IMPORTANT: [InfiniteCanvasGestureDetector] already applies
  // `controller.screenToCanvas(...)` before invoking these callbacks, so the
  // [Offset] parameter is CANVAS / WORLD space. Do NOT transform it again —
  // doing so was a bug that placed both the native live stroke and the
  // committed strokes at the wrong position after any zoom / pan.

  /// Anchor point for shape tools (line / rectangle / ellipse). The
  /// shape is built from this anchor to the current pointer position
  /// every onDrawUpdate.
  Offset? _shapeAnchor;

  /// Number of segments used to approximate an ellipse. 32 gives a
  /// smooth outline without too many points.
  static const int _kEllipseSegments = 32;

  /// Builds the polyline points representing a line / rectangle /
  /// ellipse drag from `anchor` to `current`. The points are then
  /// stored in `_livePoints` and rendered by the live painter exactly
  /// like a free-form stroke.
  static List<Offset> _buildShapePoints(
    CanvasTool tool,
    Offset anchor,
    Offset current,
  ) {
    switch (tool) {
      case CanvasTool.line:
        return <Offset>[anchor, current];
      case CanvasTool.rectangle:
        // 5-point closed polygon (last == first).
        return <Offset>[
          Offset(anchor.dx, anchor.dy),
          Offset(current.dx, anchor.dy),
          Offset(current.dx, current.dy),
          Offset(anchor.dx, current.dy),
          Offset(anchor.dx, anchor.dy),
        ];
      case CanvasTool.ellipse:
        final cx = (anchor.dx + current.dx) * 0.5;
        final cy = (anchor.dy + current.dy) * 0.5;
        final rx = (current.dx - anchor.dx).abs() * 0.5;
        final ry = (current.dy - anchor.dy).abs() * 0.5;
        final pts = <Offset>[];
        for (int i = 0; i <= _kEllipseSegments; i++) {
          final t = i / _kEllipseSegments * 2 * math.pi;
          pts.add(Offset(cx + rx * math.cos(t), cy + ry * math.sin(t)));
        }
        return pts;
      // Defensive — these should never be passed in.
      case CanvasTool.draw:
      case CanvasTool.erase:
      case CanvasTool.erasePixel:
        return <Offset>[anchor, current];
    }
  }

  void _onDrawStart(Offset world, double pressure, double tiltX, double tiltY) {
    _focusNode?.requestFocus();
    if (widget.tool == CanvasTool.erase ||
        widget.tool == CanvasTool.erasePixel) {
      _erasedThisGesture.clear();
      _eraserPreviewWorld = world;
      _commitTick.notify();
      _eraseAt(world);
      // Start the vsync ticker so the eraser preview circle keeps
      // tracking the pointer in real time on Impeller-Vulkan / Adreno.
      if (!_liveStrokeTicker.isActive) {
        _liveStrokeTicker.start();
      }
      return;
    }
    _liveStroke.beginStroke(
      color: widget.strokeColor,
      baseWidth: widget.strokeWidth,
    );
    if (widget.tool == CanvasTool.line ||
        widget.tool == CanvasTool.rectangle ||
        widget.tool == CanvasTool.ellipse) {
      _shapeAnchor = world;
      _livePoints = _buildShapePoints(widget.tool, world, world);
      _livePressures = List<double>.filled(_livePoints!.length, 1.0);
      _liveStroke.setStroke(_livePoints!, _livePressures!);
      if (!_liveStrokeTicker.isActive) _liveStrokeTicker.start();
      return;
    }
    _livePoints = <Offset>[world];
    _livePressures = <double>[pressure];
    _liveStroke.setStroke(_livePoints!, _livePressures!);
    if (!_useNative && !_liveStrokeTicker.isActive) {
      _liveStrokeTicker.start();
    }
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

  void _onDrawUpdate(
    Offset world,
    double pressure,
    double tiltX,
    double tiltY,
  ) {
    if (widget.tool == CanvasTool.erase ||
        widget.tool == CanvasTool.erasePixel) {
      _eraserPreviewWorld = world;
      _commitTick.notify();
      _eraseAt(world);
      return;
    }
    if (widget.tool == CanvasTool.line ||
        widget.tool == CanvasTool.rectangle ||
        widget.tool == CanvasTool.ellipse) {
      final anchor = _shapeAnchor;
      if (anchor == null) return;
      _livePoints = _buildShapePoints(widget.tool, anchor, world);
      _livePressures = List<double>.filled(_livePoints!.length, 1.0);
      _liveStroke.setStroke(_livePoints!, _livePressures!);
      return;
    }
    if (_livePoints == null) return;
    _livePoints!.add(world);
    _livePressures!.add(pressure);
    _liveStroke.forceRepaint();
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
    if (widget.tool == CanvasTool.erase ||
        widget.tool == CanvasTool.erasePixel) {
      if (_liveStrokeTicker.isActive) _liveStrokeTicker.stop();
      if (_erasedThisGesture.isNotEmpty || _pixelEraseOriginals.isNotEmpty) {
        final erased = _erasedThisGesture.toList(growable: false);
        if (widget.tool == CanvasTool.erasePixel) {
          _history?.push(
            _PixelEraseOp(_pixelEraseOriginals, _pixelEraseReplacements),
          );
        } else {
          _history?.push(_EraseOp(erased, _lastEraseIndexes));
        }
        _erasedThisGesture.clear();
        _lastEraseIndexes.clear();
        _pixelEraseOriginals.clear();
        _pixelEraseReplacements.clear();
        if (erased.isNotEmpty) widget.onStrokesErased?.call(erased);
      }
      return;
    }
    if (_useNative && widget.tool == CanvasTool.draw) {
      _nativeOverlay.endStroke();
      _nativeOverlay.takePoints();
    }
    _shapeAnchor = null;
    if (_livePoints == null || _livePoints!.length < 2) {
      if (_liveStrokeTicker.isActive) _liveStrokeTicker.stop();
      _livePoints = null;
      _livePressures = null;
      _liveStroke.clear();
      return;
    }
    final stroke = CanvasStroke(
      points: List<Offset>.unmodifiable(_livePoints!),
      pressures: List<double>.unmodifiable(_livePressures!),
      color: widget.strokeColor,
      baseWidth: widget.strokeWidth,
    );
    if (_liveStrokeTicker.isActive) _liveStrokeTicker.stop();
    _strokes.add(stroke);
    _spatialIndex.insert(stroke);
    _livePoints = null;
    _livePressures = null;
    _commitTick.notify();
    _liveStroke.clear();
    _history?.push(_AddOp(stroke, _strokes.length - 1));
    widget.onStrokeCommitted?.call(stroke);
  }

  void _onDrawCancel() {
    if (widget.enableNativeLiveStroke) _nativeOverlay.cancelStroke();
    if (_liveStrokeTicker.isActive) _liveStrokeTicker.stop();
    _livePoints = null;
    _livePressures = null;
    _liveStroke.clear();
    _erasedThisGesture.clear();
    _lastEraseIndexes.clear();
  }

  // ── Erase logic ──────────────────────────────────────────────────────────

  /// Maps stroke → its original index at erase time. Lets us re-insert at
  /// the correct Z-order on undo.
  final Map<CanvasStroke, int> _lastEraseIndexes = <CanvasStroke, int>{};

  /// Pixel-mode erase bookkeeping for the current gesture: original
  /// strokes that were split, paired with the surviving sub-strokes.
  /// Used by [_PixelEraseOp] to undo the cut.
  final List<_PixelEraseRecord> _pixelEraseOriginals = <_PixelEraseRecord>[];

  /// Surviving sub-strokes inserted during the current pixel-erase
  /// gesture, in insertion order. On undo they are removed and the
  /// originals re-inserted.
  final List<CanvasStroke> _pixelEraseReplacements = <CanvasStroke>[];

  void _eraseAt(Offset world) {
    if (widget.tool == CanvasTool.erasePixel) {
      _eraseAtPixel(world);
      return;
    }
    final radiusWorld = widget.eraserRadius / _controller.scale;
    final probe = Rect.fromCircle(center: world, radius: radiusWorld);
    final candidates = _spatialIndex.queryVisible(probe, margin: 0);
    final r2 = radiusWorld * radiusWorld;
    final toErase = <CanvasStroke>[];
    for (final s in candidates) {
      if (_erasedThisGesture.contains(s)) continue;
      if (_strokeIntersectsCircle(s, world, r2)) {
        toErase.add(s);
      }
    }
    if (toErase.isEmpty) return;
    for (final s in toErase) {
      final idx = _strokes.indexOf(s);
      if (idx < 0) continue;
      _strokes.removeAt(idx);
      _spatialIndex.remove(s);
      s.dispose();
      _erasedThisGesture.add(s);
      _lastEraseIndexes[s] = idx;
    }
    _commitTick.notify();
  }

  /// Pixel-mode erase: instead of removing whole strokes, split each
  /// stroke that the eraser touches and keep the surviving pieces.
  /// Per-update cost is O(k · m) where k = strokes intersecting the
  /// eraser circle (typically <10) and m = points per stroke. Combined
  /// with the spatial-index viewport cull this stays well below 1ms
  /// for typical scenes.
  void _eraseAtPixel(Offset world) {
    final radiusWorld = widget.eraserRadius / _controller.scale;
    final probe = Rect.fromCircle(center: world, radius: radiusWorld);
    final candidates = _spatialIndex.queryVisible(probe, margin: 0);
    final r2 = radiusWorld * radiusWorld;
    bool anyChange = false;
    for (final s in List<CanvasStroke>.from(candidates)) {
      if (!_strokeIntersectsCircle(s, world, r2)) continue;
      final survivors = _splitStrokeAroundCircle(s, world, r2);
      // No survivors → effectively a full erase of this stroke.
      // One survivor with the same point list → no change (eraser
      // overlapped only the bounding rect padding); skip.
      if (survivors.length == 1 &&
          survivors.first.points.length == s.points.length) {
        continue;
      }
      final idx = _strokes.indexOf(s);
      if (idx < 0) continue;
      _strokes.removeAt(idx);
      _spatialIndex.remove(s);
      // Insert survivors at the original position so Z-order is
      // preserved.
      for (int i = 0; i < survivors.length; i++) {
        _strokes.insert(idx + i, survivors[i]);
        _spatialIndex.insert(survivors[i]);
        _pixelEraseReplacements.add(survivors[i]);
      }
      _pixelEraseOriginals.add(
        _PixelEraseRecord(original: s, index: idx, survivors: survivors),
      );
      anyChange = true;
    }
    if (anyChange) _commitTick.notify();
  }

  /// Splits [stroke] into the contiguous pieces whose points fall
  /// outside the circle (center, r²). Returns the surviving
  /// sub-strokes — empty list if the entire stroke was inside the
  /// circle.
  static List<CanvasStroke> _splitStrokeAroundCircle(
    CanvasStroke stroke,
    Offset center,
    double r2,
  ) {
    final points = stroke.points;
    final pressures = stroke.pressures;
    final n = points.length;
    if (n == 0) return const [];

    final survivors = <CanvasStroke>[];
    List<Offset>? curPts;
    List<double>? curPrs;

    void flushRun() {
      if (curPts != null && curPts!.length >= 2) {
        survivors.add(
          CanvasStroke(
            points: List<Offset>.unmodifiable(curPts!),
            pressures: List<double>.unmodifiable(curPrs!),
            color: stroke.color,
            baseWidth: stroke.baseWidth,
          ),
        );
      }
      curPts = null;
      curPrs = null;
    }

    for (int i = 0; i < n; i++) {
      final inside = _dist2(points[i], center) <= r2;
      if (inside) {
        flushRun();
      } else {
        curPts ??= <Offset>[];
        curPrs ??= <double>[];
        curPts!.add(points[i]);
        curPrs!.add(pressures[i]);
      }
    }
    flushRun();
    return survivors;
  }

  static bool _strokeIntersectsCircle(
    CanvasStroke s,
    Offset center,
    double r2,
  ) {
    final pts = s.points;
    if (pts.isEmpty) return false;
    if (pts.length == 1) {
      return _dist2(pts.first, center) <= r2;
    }
    for (int i = 1; i < pts.length; i++) {
      if (_segmentDist2(pts[i - 1], pts[i], center) <= r2) return true;
    }
    return false;
  }

  static double _dist2(Offset a, Offset b) {
    final dx = a.dx - b.dx;
    final dy = a.dy - b.dy;
    return dx * dx + dy * dy;
  }

  static double _segmentDist2(Offset a, Offset b, Offset p) {
    final abx = b.dx - a.dx;
    final aby = b.dy - a.dy;
    final apx = p.dx - a.dx;
    final apy = p.dy - a.dy;
    final denom = abx * abx + aby * aby;
    if (denom == 0) return _dist2(a, p);
    double t = (apx * abx + apy * aby) / denom;
    if (t < 0) t = 0;
    if (t > 1) t = 1;
    final dx = a.dx + t * abx - p.dx;
    final dy = a.dy + t * aby - p.dy;
    return dx * dx + dy * dy;
  }

  // ── Public API ───────────────────────────────────────────────────────────

  /// Remove every committed stroke. Pushes a single undo step.
  /// Note: snapshot strokes are NOT picture-disposed here — they live on
  /// in the undo history and may be re-inserted; their pictures are
  /// freed only if the history evicts them.
  void clear() {
    if (_strokes.isEmpty) return;
    final snapshot = List<CanvasStroke>.from(_strokes);
    _strokes.clear();
    for (final s in snapshot) {
      _spatialIndex.remove(s);
    }
    _livePoints = null;
    _livePressures = null;
    _commitTick.notify();
    _history?.push(_ClearOp(snapshot));
  }

  /// Number of committed strokes on the canvas.
  int get strokeCount => _strokes.length;

  /// Read-only view of the committed stroke list (defensive copy).
  List<CanvasStroke> get strokes => List.unmodifiable(_strokes);

  /// Programmatically append a stroke. Pushes an undo step.
  void pushStroke(CanvasStroke stroke) {
    _strokes.add(stroke);
    _spatialIndex.insert(stroke);
    _commitTick.notify();
    _history?.push(_AddOp(stroke, _strokes.length - 1));
    widget.onStrokeCommitted?.call(stroke);
  }

  /// Programmatically append a batch of strokes in one frame.
  void pushStrokes(Iterable<CanvasStroke> strokes) {
    final batch = strokes.toList();
    if (batch.isEmpty) return;
    final indexes = <int>[];
    for (final s in batch) {
      indexes.add(_strokes.length);
      _strokes.add(s);
      _spatialIndex.insert(s);
    }
    _commitTick.notify();
    _history?.push(_AddBatchOp(batch, indexes));
    if (widget.onStrokeCommitted != null) {
      for (final s in batch) {
        widget.onStrokeCommitted!(s);
      }
    }
  }

  /// Undo the most recent undoable operation (draw, erase, clear, or
  /// programmatic push). Returns `true` if something was undone.
  bool undo() {
    final op = _history?.popUndo();
    if (op == null) return false;
    op.undo(this);
    _commitTick.notify();
    return true;
  }

  /// Redo the last undone operation. Returns `true` if something was redone.
  bool redo() {
    final op = _history?.popRedo();
    if (op == null) return false;
    op.redo(this);
    _commitTick.notify();
    return true;
  }

  /// True if there is at least one undoable operation on the stack.
  bool get canUndo => (_history?.canUndo) ?? false;

  /// True if there is at least one redoable operation on the stack.
  bool get canRedo => (_history?.canRedo) ?? false;

  /// Number of operations currently on the undo stack.
  int get historyLength => _history?.undoLength ?? 0;

  /// Listenable that fires whenever the committed-stroke list changes
  /// (commit, erase, clear, undo, redo, programmatic load, tool change,
  /// background change). Lets a toolbar UI rebuild itself without
  /// having to plumb [onStrokeCommitted] / [onStrokesErased] +
  /// `setState` into the consumer State. Subscribe with
  /// `ListenableBuilder` or `addListener`. Read-only — do not call
  /// `notifyListeners` from outside.
  Listenable get historyListenable => _commitTick;

  /// Empty both undo and redo stacks without mutating the scene.
  void clearHistory() => _history?.clear();

  /// Return the first stroke (top-to-bottom Z-order) whose outline sits
  /// within [tolerance] world units of [worldPoint], or `null` if none.
  /// O(log n) via the spatial index.
  CanvasStroke? strokeAt(Offset worldPoint, {double tolerance = 4.0}) {
    final probe = Rect.fromCircle(center: worldPoint, radius: tolerance);
    final candidates = _spatialIndex.queryVisible(probe, margin: 0);
    if (candidates.isEmpty) return null;
    final t2 = tolerance * tolerance;
    // Iterate candidates in reverse insertion order so the front-most hit
    // wins (matches painter back-to-front ordering).
    CanvasStroke? best;
    int bestIdx = -1;
    for (final s in candidates) {
      if (!_strokeIntersectsCircle(s, worldPoint, t2)) continue;
      final idx = _strokes.indexOf(s);
      if (idx > bestIdx) {
        bestIdx = idx;
        best = s;
      }
    }
    return best;
  }

  /// All strokes whose bounding rect intersects [worldRect]. O(log n + k).
  List<CanvasStroke> strokesInRect(Rect worldRect) {
    return _spatialIndex.queryVisible(worldRect, margin: 0);
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  /// Serialize the current stroke list to a compact little-endian byte
  /// array. Persist this with the storage of your choice (files, Hive,
  /// SQLite blob, REST upload, …). Restore later via [loadFromBytes].
  ///
  /// Only the flat stroke list is serialized — camera, history and the
  /// background pattern are runtime state and are NOT included.
  Uint8List toBytes() => CanvasSerializer.encodeBytes(_strokes);

  /// Replace the current scene with the strokes decoded from [bytes].
  /// The undo history is cleared. Throws [FormatException] on bad input.
  void loadFromBytes(Uint8List bytes) {
    final loaded = CanvasSerializer.decodeBytes(bytes);
    _replaceStrokes(loaded);
  }

  /// Serialize the current stroke list to a JSON string. Larger than
  /// [toBytes] but diff-friendly and human-readable.
  String toJson() => CanvasSerializer.encodeJson(_strokes);

  /// Replace the current scene with the strokes decoded from [source].
  /// The undo history is cleared. Throws [FormatException] on bad input.
  void loadFromJson(String source) {
    final loaded = CanvasSerializer.decodeJson(source);
    _replaceStrokes(loaded);
  }

  void _replaceStrokes(List<CanvasStroke> loaded) {
    for (final s in _strokes) {
      _spatialIndex.remove(s);
      s.dispose();
    }
    _strokes
      ..clear()
      ..addAll(loaded);
    for (final s in loaded) {
      _spatialIndex.insert(s);
    }
    _livePoints = null;
    _livePressures = null;
    _commitTick.notify();
    _history?.clear();
  }

  /// Rasterize the current canvas (all strokes) into a PNG byte array sized
  /// [width]×[height] pixels. Respects the current camera for WYSIWYG export.
  Future<ui.Image> renderToImage({
    required int width,
    required int height,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // Reuse the same paint logic the live painter uses, but iterate
    // every committed stroke (no viewport cull — the export must
    // contain everything).
    canvas.drawRect(
      Offset.zero & Size(width.toDouble(), height.toDouble()),
      Paint()..color = widget.background.fill,
    );
    canvas.save();
    canvas.translate(_controller.offset.dx, _controller.offset.dy);
    canvas.scale(_controller.scale);
    widget.background.paint(canvas, Rect.largest, _controller.scale);
    for (final s in _strokes) {
      canvas.drawPicture(s.picture());
    }
    canvas.restore();
    final picture = recorder.endRecording();
    return picture.toImage(width, height);
  }

  Rect _viewportFromSize(Size size) {
    if (!size.isFinite || size.isEmpty) return Rect.largest;
    final tl = _controller.screenToCanvas(Offset.zero);
    final br = _controller.screenToCanvas(Offset(size.width, size.height));
    return Rect.fromLTRB(
      tl.dx < br.dx ? tl.dx : br.dx,
      tl.dy < br.dy ? tl.dy : br.dy,
      tl.dx > br.dx ? tl.dx : br.dx,
      tl.dy > br.dy ? tl.dy : br.dy,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final useNative = _useNative && widget.tool == CanvasTool.draw;

    // Both painters are STABLE INSTANCES created in [initState] — never
    // rebuilt across parent setState. CustomPaint sees the same painter
    // identity across builds, skips listener swap, and the rendering
    // pipeline keeps working through the live-stroke ticker without
    // touching the committed subtree. Repaints are driven by
    // listenables: `_commitTick` + `_controller` for committed,
    // `_liveStroke` + `_controller` for live.
    //
    // The committed layer sits inside a [RepaintBoundary] so its
    // compositing layer is cached on the GPU as a texture. While the
    // live stroke repaints every vsync during a gesture, the rasterizer
    // blits the committed texture (O(1)) instead of re-executing every
    // committed stroke's `drawPicture` per frame. This is what gets the
    // canvas from ~30ms / 20 strokes down to <2ms regardless of the
    // committed count, as long as no commit / camera change happens
    // mid-gesture (which is the common case while drawing).
    final Widget committedLayer = RepaintBoundary(
      child: CustomPaint(painter: _committedPainter, size: Size.infinite),
    );

    // No RepaintBoundary: on Impeller-Vulkan / Adreno its cached
    // compositing layer was suppressing markNeedsPaint propagation to
    // the rasterizer (verified via diagnostic prints — the painter's
    // listener fired hundreds of times per stroke yet `paint()` ran
    // only at pen-down and pen-up). Without the RepaintBoundary the
    // _RenderCustomPaint dirty mark propagates up to the next ancestor
    // boundary (which is the Stack / Scaffold root) and Flutter
    // schedules a paint every frame as expected.
    final Widget liveLayer =
        useNative
            ? const SizedBox.shrink()
            : CustomPaint(painter: _liveStrokePainter, size: Size.infinite);

    final Widget gestureChild = Stack(
      children: [
        Positioned.fill(child: committedLayer),
        Positioned.fill(child: liveLayer),
        if (useNative)
          NativeStrokeOverlay(
            canvasController: _controller,
            controller: _nativeOverlay,
            fallbackToDart: false,
          ),
      ],
    );

    Widget detector = InfiniteCanvasGestureDetector(
      controller: _controller,
      onDrawStart: _onDrawStart,
      onDrawUpdate: _onDrawUpdate,
      onDrawEnd: _onDrawEnd,
      onDrawCancel: _onDrawCancel,
      child: gestureChild,
    );

    // Desktop cursor + eraser-hover preview. On mobile (Android / iOS) we
    // do NOT attach MouseRegion at all — stylus hover fires onHover
    // continuously and any setState would rebuild the tree on every
    // frame, invalidating the gesture arena before pointer-down is
    // claimed → touch events stop reaching the canvas.
    final isDesktopLike =
        kIsWeb ||
        (() {
          try {
            return Platform.isLinux || Platform.isWindows || Platform.isMacOS;
          } catch (_) {
            return false;
          }
        })();
    if (isDesktopLike) {
      detector = MouseRegion(
        cursor: _mouseCursor,
        onHover: (e) {
          if (widget.tool == CanvasTool.erase && widget.showEraserPreview) {
            _eraserPreviewWorld = _controller.screenToCanvas(e.localPosition);
            _commitTick.notify();
          }
        },
        onExit: (_) {
          if (_eraserPreviewWorld != null) {
            _eraserPreviewWorld = null;
            _commitTick.notify();
          }
        },
        child: detector,
      );
    }

    final bool attachShortcuts =
        widget.enableKeyboardShortcuts && _focusNode != null && isDesktopLike;
    if (!attachShortcuts) {
      return detector;
    }
    return _KeyboardShortcuts(
      focusNode: _focusNode!,
      onUndo: undo,
      onRedo: redo,
      onClear: clear,
      child: detector,
    );
  }

  MouseCursor get _mouseCursor {
    switch (widget.tool) {
      case CanvasTool.draw:
      case CanvasTool.line:
      case CanvasTool.rectangle:
      case CanvasTool.ellipse:
        return SystemMouseCursors.precise;
      case CanvasTool.erase:
      case CanvasTool.erasePixel:
        return SystemMouseCursors.none; // preview circle *is* the cursor
    }
  }

  // ── Internal history hooks (invoked by _CanvasOp implementations) ────────

  void _internalRemoveStroke(CanvasStroke s) {
    _strokes.remove(s);
    _spatialIndex.remove(s);
  }

  void _internalInsertStrokeAt(int index, CanvasStroke s) {
    if (index < 0) index = 0;
    if (index > _strokes.length) index = _strokes.length;
    _strokes.insert(index, s);
    _spatialIndex.insert(s);
  }

  void _internalClear() {
    for (final s in _strokes) {
      _spatialIndex.remove(s);
    }
    _strokes.clear();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter — iterates only strokes returned by the spatial index query, so
// the per-frame cost scales with on-screen content, not the total scene.
// ─────────────────────────────────────────────────────────────────────────────

void _paintStrokeSegments(
  Canvas canvas,
  List<Offset> points,
  List<double> pressures,
  Color color,
  double baseWidth,
) {
  final n = points.length;
  if (n < 2) return;

  // Single-pass strategy: one Path per stroke, drawn with one stroke
  // width derived from the average pressure. Pressure-band rendering
  // (multiple paths at different widths overlapping) was attempted
  // earlier but produced visible "bumps" on the stroke edge wherever
  // adjacent segments crossed a band boundary — a 3 %–5 % width step
  // is sub-pixel for thin strokes but clearly visible at the slider's
  // upper end (16 px @ 1× zoom, more after zoom-in). Using a single
  // width keeps the silhouette perfectly continuous; pressure
  // variation along the stroke is sacrificed but is hardly noticeable
  // at typical SDK widths. Power users who need true variable-width
  // ink can plug in the commercial `fluera_engine` brushes.
  double pressureSum = 0;
  for (int i = 0; i < n; i++) {
    pressureSum += pressures[i];
  }
  final avgPressure = pressureSum / n;
  final strokeWidth = baseWidth * (0.3 + avgPressure * 0.9);

  // Quadratic-bezier smoothing: each interior point becomes the
  // control point and the curve passes through the midpoint between
  // consecutive samples. Result is C¹-continuous, tightly tracks the
  // polyline, and removes the polyline kinks that show up between
  // sparsely-sampled stylus points (= the "humps" on diagonal strokes).
  final path = Path()..moveTo(points[0].dx, points[0].dy);
  if (n == 2) {
    path.lineTo(points[1].dx, points[1].dy);
  } else {
    for (int i = 1; i < n - 1; i++) {
      final ctrl = points[i];
      final end = Offset(
        (points[i].dx + points[i + 1].dx) * 0.5,
        (points[i].dy + points[i + 1].dy) * 0.5,
      );
      path.quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);
    }
    path.lineTo(points[n - 1].dx, points[n - 1].dy);
  }

  final paint =
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = strokeWidth;
  canvas.drawPath(path, paint);
}

/// Paints background + committed strokes + eraser preview circle.
/// STABLE INSTANCE: created once in [FlueraCanvasState.initState] and
/// reused across every parent rebuild — the painter pulls live state
/// (strokes, camera, viewport, background, eraser preview) directly
/// from the [FlueraCanvasState] reference at paint time. Repainting
/// is driven by the [Listenable] passed to `super(repaint:)`, which
/// is a merge of `_commitTick` (fires on commit / erase / clear /
/// undo / redo / load) and the camera controller.
///
/// Per-stroke fast-path: each [CanvasStroke] caches a [ui.Picture] of
/// its rasterised segments (built lazily in [CanvasStroke.picture]).
/// Drawing a committed stroke is therefore a single `drawPicture`
/// call, scaling cleanly to thousands of strokes when combined with
/// the spatial-index viewport cull.
class _CommittedStrokesPainter extends CustomPainter {
  _CommittedStrokesPainter({
    required this.canvasState,
    required Listenable repaintTrigger,
  }) : super(repaint: repaintTrigger);

  final FlueraCanvasState canvasState;

  @override
  void paint(Canvas canvas, Size size) {
    final ctrl = canvasState._controller;
    final background = canvasState.widget.background;

    // Base fill (screen space so zero-cost even at extreme zoom).
    canvas.drawRect(Offset.zero & size, Paint()..color = background.fill);

    canvas.save();
    canvas.translate(ctrl.offset.dx, ctrl.offset.dy);
    canvas.scale(ctrl.scale);

    final viewport = canvasState._viewportFromSize(size);

    // Background pattern painted in world space so it stays anchored to
    // the canvas origin.
    background.paint(canvas, viewport, ctrl.scale);

    final visible = canvasState._spatialIndex.queryVisible(
      viewport,
      margin: 200,
    );
    for (final s in visible) {
      canvas.drawPicture(s.picture());
    }

    // Eraser hover circle — drawn last so it sits on top of strokes.
    final showPreview =
        canvasState.widget.showEraserPreview &&
        canvasState.widget.tool == CanvasTool.erase &&
        canvasState._eraserPreviewWorld != null;
    if (showPreview) {
      final preview = canvasState._eraserPreviewWorld!;
      final radiusWorld = canvasState.widget.eraserRadius / ctrl.scale;
      final fill =
          Paint()
            ..color = const Color(0x22000000)
            ..style = PaintingStyle.fill;
      final ring =
          Paint()
            ..color = const Color(0x66000000)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / ctrl.scale;
      canvas.drawCircle(preview, radiusWorld, fill);
      canvas.drawCircle(preview, radiusWorld, ring);
    }

    canvas.restore();
  }

  // Stable instance + super(repaint:) — the framework calls
  // shouldRepaint when the painter widget is updated, but here the
  // painter never changes so we always return false. Repaints are
  // driven via the repaint listenable.
  @override
  bool shouldRepaint(covariant _CommittedStrokesPainter old) => false;
}

/// Paints ONLY the live stroke. Permanently mounted in the widget tree
/// AND has a STABLE INSTANCE for the lifetime of the [FlueraCanvas]
/// state. The instance is created once in `initState` and reused across
/// every parent rebuild — that way the listener subscription set up by
/// `super(repaint: ...)` is never re-registered, which is what was
/// breaking stroke 2+ on Impeller-Vulkan / Adreno (every commit
/// `setState` would create a fresh painter instance and the old/new
/// listener swap on the [RenderCustomPaint] would silently drop the
/// subscription).
///
/// Render parameters that change at runtime (color, width, camera) are
/// fetched at paint time:
///   • color / baseWidth: from the notifier (set in `_onDrawStart`)
///   • cameraOffset / cameraScale: read live from the [InfiniteCanvasController]
///
/// `super(repaint:)` listens to BOTH the stroke notifier and the camera
/// controller so pan/zoom while drawing repaints the live stroke too.
class _LiveStrokePainter extends CustomPainter {
  _LiveStrokePainter({required this.strokeNotifier, required this.controller})
    : super(
        repaint: Listenable.merge(<Listenable>[strokeNotifier, controller]),
      );

  final _LiveStrokeNotifier strokeNotifier;
  final InfiniteCanvasController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = strokeNotifier.points;
    final prs = strokeNotifier.pressures;
    if (pts.length < 2 || prs.length != pts.length) return;
    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(controller.scale);
    _paintStrokeSegments(
      canvas,
      pts,
      prs,
      strokeNotifier.color,
      strokeNotifier.baseWidth,
    );
    canvas.restore();
  }

  // The painter instance is stable; repaint is driven entirely by
  // `super(repaint:)`. Returning false here avoids spurious extra paints
  // when CustomPaint sees the same painter instance across builds.
  @override
  bool shouldRepaint(covariant _LiveStrokePainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// _LiveStrokeNotifier — owns ALL live-stroke render state (points,
// pressures, color, width). ChangeNotifier over mutable fields;
// `forceRepaint()` is called after each in-place mutation and notifies
// the painter listening via super(repaint: notifier). Marks
// RenderCustomPaint dirty at the RenderObject level, bypassing widget
// rebuilds entirely. Color and width are notifier-owned (not widget
// args of the painter) so the painter instance can be stable across
// the lifetime of the State — see the comment on [_liveStrokePainter].
// ─────────────────────────────────────────────────────────────────────────────

/// Lightweight notifier for committed-strokes invalidation. Exposes
/// [notify] publicly because the State drives notifications imperatively
/// (after `_strokes` mutations) — `notifyListeners` on `ChangeNotifier`
/// is `@protected` and can't be called from outside the subclass.
class _CommitNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

class _LiveStrokeNotifier extends ChangeNotifier {
  List<Offset> points = const <Offset>[];
  List<double> pressures = const <double>[];
  Color color = const Color(0xFF000000);
  double baseWidth = 1.0;

  void beginStroke({required Color color, required double baseWidth}) {
    this.color = color;
    this.baseWidth = baseWidth;
  }

  void setStroke(List<Offset> pts, List<double> prs) {
    points = pts;
    pressures = prs;
    notifyListeners();
  }

  /// Explicit notify after in-place add() on [points] / [pressures].
  void forceRepaint() => notifyListeners();

  void clear() {
    points = const <Offset>[];
    pressures = const <double>[];
    notifyListeners();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Keyboard shortcuts — Ctrl/Cmd + Z | Shift+Z | Y, Delete / Backspace.
// ─────────────────────────────────────────────────────────────────────────────

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

class _ClearIntent extends Intent {
  const _ClearIntent();
}

class _KeyboardShortcuts extends StatelessWidget {
  const _KeyboardShortcuts({
    required this.focusNode,
    required this.onUndo,
    required this.onRedo,
    required this.onClear,
    required this.child,
  });

  final FocusNode focusNode;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClear;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isMac = !kIsWeb && (Platform.isMacOS || Platform.isIOS);
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.keyZ, control: !isMac, meta: isMac):
            const _UndoIntent(),
        SingleActivator(
              LogicalKeyboardKey.keyZ,
              control: !isMac,
              meta: isMac,
              shift: true,
            ):
            const _RedoIntent(),
        SingleActivator(LogicalKeyboardKey.keyY, control: !isMac, meta: isMac):
            const _RedoIntent(),
        const SingleActivator(LogicalKeyboardKey.delete): const _ClearIntent(),
        const SingleActivator(LogicalKeyboardKey.backspace):
            const _ClearIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _UndoIntent: CallbackAction<_UndoIntent>(
            onInvoke: (_) {
              onUndo();
              return null;
            },
          ),
          _RedoIntent: CallbackAction<_RedoIntent>(
            onInvoke: (_) {
              onRedo();
              return null;
            },
          ),
          _ClearIntent: CallbackAction<_ClearIntent>(
            onInvoke: (_) {
              onClear();
              return null;
            },
          ),
        },
        child: Focus(
          focusNode: focusNode,
          // IMPORTANT: do NOT autofocus. Auto-grabbing focus at build
          // time races against the gesture arena on Impeller-Vulkan and
          // can drop the first pointer-down event reaching the canvas
          // (touch/stylus never triggers onDrawStart). Focus is requested
          // on-demand inside `_onDrawStart` when the canvas is first
          // tapped — that's the natural moment for keyboard shortcuts
          // to become active anyway.
          child: child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// History (undo / redo) — lightweight command pattern.
// ─────────────────────────────────────────────────────────────────────────────

abstract class _CanvasOp {
  void undo(FlueraCanvasState s);
  void redo(FlueraCanvasState s);
}

class _AddOp implements _CanvasOp {
  _AddOp(this.stroke, this.index);
  final CanvasStroke stroke;
  final int index;

  @override
  void undo(FlueraCanvasState s) => s._internalRemoveStroke(stroke);

  @override
  void redo(FlueraCanvasState s) => s._internalInsertStrokeAt(index, stroke);
}

class _AddBatchOp implements _CanvasOp {
  _AddBatchOp(this.strokes, this.indexes);
  final List<CanvasStroke> strokes;
  final List<int> indexes;

  @override
  void undo(FlueraCanvasState s) {
    for (final stroke in strokes) {
      s._internalRemoveStroke(stroke);
    }
  }

  @override
  void redo(FlueraCanvasState s) {
    for (int i = 0; i < strokes.length; i++) {
      s._internalInsertStrokeAt(indexes[i], strokes[i]);
    }
  }
}

class _EraseOp implements _CanvasOp {
  _EraseOp(this.strokes, Map<CanvasStroke, int> indexes)
    : indexes = Map.of(indexes);
  final List<CanvasStroke> strokes;
  final Map<CanvasStroke, int> indexes;

  @override
  void undo(FlueraCanvasState s) {
    // Re-insert in ascending original-index order so the Z-order is
    // reconstructed faithfully.
    final sorted = List<CanvasStroke>.from(strokes)
      ..sort((a, b) => (indexes[a] ?? 0).compareTo(indexes[b] ?? 0));
    for (final stroke in sorted) {
      s._internalInsertStrokeAt(indexes[stroke] ?? 0, stroke);
    }
  }

  @override
  void redo(FlueraCanvasState s) {
    for (final stroke in strokes) {
      s._internalRemoveStroke(stroke);
    }
  }
}

class _ClearOp implements _CanvasOp {
  _ClearOp(this.snapshot);
  final List<CanvasStroke> snapshot;

  @override
  void undo(FlueraCanvasState s) {
    for (int i = 0; i < snapshot.length; i++) {
      s._internalInsertStrokeAt(i, snapshot[i]);
    }
  }

  @override
  void redo(FlueraCanvasState s) => s._internalClear();
}

/// Bookkeeping entry for a single original stroke that was split by
/// the pixel-mode eraser. Captures where the original was and which
/// sub-strokes replaced it so undo can reverse the cut exactly.
class _PixelEraseRecord {
  _PixelEraseRecord({
    required this.original,
    required this.index,
    required this.survivors,
  });
  final CanvasStroke original;
  final int index;
  final List<CanvasStroke> survivors;
}

class _PixelEraseOp implements _CanvasOp {
  _PixelEraseOp(List<_PixelEraseRecord> records, List<CanvasStroke> survivors)
    : _records = List<_PixelEraseRecord>.from(records),
      _survivors = List<CanvasStroke>.from(survivors);
  final List<_PixelEraseRecord> _records;
  final List<CanvasStroke> _survivors;

  @override
  void undo(FlueraCanvasState s) {
    // Remove every survivor that was inserted during the erase
    // gesture, then re-insert the originals at their captured Z-order.
    for (final survivor in _survivors) {
      s._internalRemoveStroke(survivor);
    }
    final sorted = List<_PixelEraseRecord>.from(_records)
      ..sort((a, b) => a.index.compareTo(b.index));
    for (final r in sorted) {
      s._internalInsertStrokeAt(r.index, r.original);
    }
  }

  @override
  void redo(FlueraCanvasState s) {
    for (final r in _records) {
      s._internalRemoveStroke(r.original);
    }
    for (final survivor in _survivors) {
      // Append at end — exact mid-list position is non-trivial after
      // multiple ops; Z-order is approximated.
      s._internalInsertStrokeAt(s._strokes.length, survivor);
    }
  }
}

class _CanvasHistory {
  _CanvasHistory({required this.capacity});
  int capacity;
  final List<_CanvasOp> _undo = <_CanvasOp>[];
  final List<_CanvasOp> _redo = <_CanvasOp>[];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get undoLength => _undo.length;

  void push(_CanvasOp op) {
    _undo.add(op);
    _redo.clear();
    while (_undo.length > capacity) {
      _undo.removeAt(0);
    }
  }

  _CanvasOp? popUndo() {
    if (_undo.isEmpty) return null;
    final op = _undo.removeLast();
    _redo.add(op);
    return op;
  }

  _CanvasOp? popRedo() {
    if (_redo.isEmpty) return null;
    final op = _redo.removeLast();
    _undo.add(op);
    return op;
  }

  void clear() {
    _undo.clear();
    _redo.clear();
  }
}
