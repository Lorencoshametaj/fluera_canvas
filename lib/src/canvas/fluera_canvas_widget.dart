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
import '../core/nodes/canvas_stroke_node.dart';
import '../core/nodes/layer_node.dart';
import '../core/scene_graph/canvas_node.dart';
import '../core/scene_graph/node_id.dart';
import '../drawing/brush_config.dart';
import '../rendering/native_stroke_overlay.dart';
import '../rendering/gpu/gpu_stroke_backend.dart';
import 'fluera_blend_mode.dart';
import '../rendering/optimization/spatial_index.dart';
import '../utils/uid.dart' show generateUid;
import 'selection/canvas_selection.dart';
import 'selection/selection_painter.dart';
import 'selection/transform_handles.dart';

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
    this.smooth = true,
    this.brushType = 0,
    this.pencilConfig = PencilConfig.defaults,
    this.fountainConfig = FountainPenConfig.defaults,
  }) : _cachedBounds = _computeBounds(points, baseWidth);

  /// When `true` (default), the rasteriser smooths the polyline with
  /// quadratic-bezier curves through the midpoints — eliminates kinks
  /// on diagonal free-form strokes. Set to `false` for shapes whose
  /// corners must stay sharp (rectangles, polygons, polylines that
  /// trace explicit angles): the rasteriser uses straight `lineTo`
  /// segments instead. Free-form draws and ellipses use `smooth: true`;
  /// lines and rectangles commit with `smooth: false` automatically.
  final bool smooth;

  /// Brush identifier matching the engine convention (0 = canvas-core
  /// vector default, ≥1 = a specific shader brush such as pencil, fountain
  /// pen, watercolor, marker, etc.). The free vector renderer ignores this
  /// — it's consumed only when [FlueraCanvasGpu.strokeRenderer] is
  /// registered (commercial `fluera_canvas_gpu` consumer), in which case
  /// the committed stroke is painted with the same shader pipeline as the
  /// live preview, so what you draw is what you keep.
  final int brushType;

  /// Pencil-brush tuning forwarded to the shader renderer when
  /// [brushType] selects the pencil. Ignored otherwise.
  final PencilConfig pencilConfig;

  /// Fountain-pen tuning forwarded to the shader renderer when
  /// [brushType] selects the fountain pen. Ignored otherwise.
  final FountainPenConfig fountainConfig;

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

    // If the consumer installed `fluera_canvas_gpu` AND this stroke was
    // committed with a non-default shader brush (pencil, fountain pen,
    // watercolor, …), route the commit through the same shader pipeline
    // as the live preview so the post-pen-up appearance matches what
    // the user just drew. Falls back to the vector renderer otherwise.
    final renderer = FlueraCanvasGpu.strokeRenderer;
    if (renderer != null && brushType != 0 && points.length >= 2) {
      renderer.renderStroke(
        canvas,
        points: points,
        pressures: pressures,
        color: color,
        baseWidth: baseWidth,
        smooth: smooth,
        brushType: brushType,
        pencilConfig: pencilConfig,
        fountainConfig: fountainConfig,
      );
    } else {
      _paintStrokeSegments(
        canvas,
        points,
        pressures,
        color,
        baseWidth,
        smooth: smooth,
      );
    }
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

  /// Splits [stroke] into the contiguous pieces that lie OUTSIDE the
  /// circle `(center, r²)`. Returns the surviving sub-strokes —
  /// empty list if the entire stroke is inside the circle.
  ///
  /// Handles segment/circle intersection properly: a long segment
  /// whose endpoints are both outside the circle but which crosses
  /// the circle is split into two surviving sub-segments. Without
  /// this, a rectangle drawn with 5 anchor points (one per corner)
  /// would be untouchable mid-side because no anchor point ever
  /// falls inside the eraser circle. The implementation interpolates
  /// the entry / exit points on each segment, preserving the stroke's
  /// silhouette at any point density.
  ///
  /// This is the underlying primitive used by [CanvasTool.erasePixel].
  /// Exposed publicly so consumers can build their own pixel-mode UX
  /// (e.g. lasso-to-cut, polygon-erase) without re-implementing the
  /// splitter.
  static List<CanvasStroke> splitAroundCircle(
    CanvasStroke stroke,
    Offset center,
    double radiusSquared,
  ) {
    final points = stroke.points;
    final pressures = stroke.pressures;
    final n = points.length;
    if (n == 0) return const [];

    final survivors = <CanvasStroke>[];
    List<Offset>? curPts;
    List<double>? curPrs;

    void start(Offset p, double pr) {
      curPts = <Offset>[p];
      curPrs = <double>[pr];
    }

    void appendIfDifferent(Offset p, double pr) {
      curPts ??= <Offset>[];
      curPrs ??= <double>[];
      // Avoid degenerate zero-length segments at run boundaries.
      if (curPts!.isEmpty || curPts!.last != p) {
        curPts!.add(p);
        curPrs!.add(pr);
      }
    }

    void flushRun() {
      if (curPts != null && curPts!.length >= 2) {
        survivors.add(
          CanvasStroke(
            points: List<Offset>.unmodifiable(curPts!),
            pressures: List<double>.unmodifiable(curPrs!),
            color: stroke.color,
            baseWidth: stroke.baseWidth,
            smooth: stroke.smooth,
            brushType: stroke.brushType,
            pencilConfig: stroke.pencilConfig,
            fountainConfig: stroke.fountainConfig,
          ),
        );
      }
      curPts = null;
      curPrs = null;
    }

    bool isInside(Offset p) {
      final dx = p.dx - center.dx;
      final dy = p.dy - center.dy;
      return dx * dx + dy * dy <= radiusSquared;
    }

    // Single-point strokes are pass-through (they're not normally
    // committed but we handle the edge case defensively).
    if (n == 1) return isInside(points[0]) ? const [] : [stroke];

    bool prevInside = isInside(points[0]);
    if (!prevInside) start(points[0], pressures[0]);

    for (int i = 1; i < n; i++) {
      final a = points[i - 1];
      final b = points[i];
      final pa = pressures[i - 1];
      final pb = pressures[i];
      final bInside = isInside(b);

      // Solve |a + t·(b - a) - center|² = r² for t in [0, 1].
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      final mx = a.dx - center.dx;
      final my = a.dy - center.dy;
      final A = dx * dx + dy * dy;
      final B = 2 * (mx * dx + my * dy);
      final C = mx * mx + my * my - radiusSquared;
      final disc = B * B - 4 * A * C;
      final ts = <double>[];
      if (A > 0 && disc >= 0) {
        final sq = math.sqrt(disc);
        final t1 = (-B - sq) / (2 * A);
        final t2 = (-B + sq) / (2 * A);
        if (t1 > 0 && t1 < 1) ts.add(t1);
        if (t2 > 0 && t2 < 1) ts.add(t2);
      }
      ts.sort();

      Offset lerp(double t) => Offset(a.dx + dx * t, a.dy + dy * t);
      double lerpPr(double t) => pa + (pb - pa) * t;

      if (!prevInside && !bInside) {
        if (ts.length == 2) {
          // Segment dips through the circle and exits — close the
          // current run at entry, flush, restart at exit.
          appendIfDifferent(lerp(ts[0]), lerpPr(ts[0]));
          flushRun();
          start(lerp(ts[1]), lerpPr(ts[1]));
          appendIfDifferent(b, pb);
        } else {
          // Both endpoints outside, no chord (or grazes the circle).
          appendIfDifferent(b, pb);
        }
      } else if (!prevInside && bInside) {
        // Exiting the outside-run; close at the entry point.
        if (ts.isNotEmpty) {
          appendIfDifferent(lerp(ts.first), lerpPr(ts.first));
        }
        flushRun();
      } else if (prevInside && !bInside) {
        // Entering an outside-run; start at the exit point.
        if (ts.isNotEmpty) {
          start(lerp(ts.last), lerpPr(ts.last));
        } else {
          start(b, pb);
        }
        appendIfDifferent(b, pb);
      }
      // else (both inside): no run, nothing to flush.

      prevInside = bInside;
    }

    flushRun();
    return survivors;
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

  /// Tap a node to select it; drag on empty space to marquee-select.
  /// Active selection is exposed via [FlueraCanvasState.selection] /
  /// [FlueraCanvasState.selectionListenable]. Future C2 work plugs the
  /// transform handles (move / rotate / scale / mirror) into this tool.
  select,
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
    this.eraserRadius = 32.0,
    this.showEraserPreview = true,
    this.historyCapacity = 100,
    this.enableKeyboardShortcuts = true,
    this.onStrokeCommitted,
    this.onStrokesErased,
    this.enableNativeLiveStroke = true,
    this.initialBytes,
    this.brushType = 0,
    this.pencilConfig = PencilConfig.defaults,
    this.fountainConfig = FountainPenConfig.defaults,
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

  /// Active brush identifier (0 = canvas-core vector default; ≥1 = a
  /// shader brush such as pencil, fountain pen, watercolor, marker,
  /// charcoal, oil paint, spray paint, neon glow, ink wash). The
  /// free `fluera_canvas` core ignores this — the value is forwarded
  /// to [FlueraCanvasGpu.backend.updateAndRender] (live preview) and
  /// stamped on the resulting [CanvasStroke] (committed render). When
  /// the commercial `fluera_canvas_gpu` add-on is installed, the same
  /// shader brush is used for both phases so what you draw is what
  /// you keep.
  final int brushType;

  /// Pencil-brush tuning forwarded to the shader pipeline (live + commit).
  /// Ignored when [brushType] does not select the pencil.
  final PencilConfig pencilConfig;

  /// Fountain-pen tuning forwarded to the shader pipeline (live + commit).
  /// Ignored when [brushType] does not select the fountain pen.
  final FountainPenConfig fountainConfig;

  @override
  State<FlueraCanvas> createState() => FlueraCanvasState();
}

class FlueraCanvasState extends State<FlueraCanvas>
    with SingleTickerProviderStateMixin {
  late final InfiniteCanvasController _controller;
  late final bool _ownsController;
  late final NativeStrokeOverlayController _nativeOverlay;

  /// Committed strokes, in draw order (back-to-front).
  ///
  /// This flat list is the **hot-path mirror** of the scene graph:
  /// painter iteration, spatial-index hit-test, eraser cuts and FCV0 v1
  /// serialization all read from here in tight loops. Every mutation
  /// site MUST also update [_rootLayer] / [_activeLayer] / [_strokeToNode]
  /// via the `_addStrokeBoth` / `_removeStrokeBoth` helpers so the two
  /// representations never diverge.
  final List<CanvasStroke> _strokes = <CanvasStroke>[];

  /// Spatial index over [_strokes]. Rebuilt lazily on hit-test when stale.
  late final RTree<CanvasStroke> _spatialIndex = RTree<CanvasStroke>(
    (s) => s.bounds,
  );

  /// Scene-graph root. Always populated; in 0.6.0 (Phase A) it carries
  /// a single default [LayerNode] named "Layer 1" so the legacy
  /// strokes-only API maps cleanly into a layered model. Phase B will
  /// expose layer manipulation; Phase D will add text / image children.
  late final LayerNode _rootLayer;

  /// The layer new content is appended to. Defaults to the single
  /// "Layer 1" created in [initState]. Future `setActiveLayer(...)`
  /// (Phase B) will rotate this pointer.
  late LayerNode _activeLayer;

  /// Identity-keyed lookup from [CanvasStroke] to its scene-graph node.
  /// Lets removal find the wrapping node without an O(n) scan of every
  /// layer. Entries are dropped on stroke removal so the map size
  /// matches `_strokes.length`.
  final Map<CanvasStroke, CanvasStrokeNode> _strokeToNode =
      Map<CanvasStroke, CanvasStrokeNode>.identity();

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

  /// Active selection (canvas 0.6.0+). Mutated through [select] /
  /// [selectInRect] / [clearSelection] / [deleteSelection] and observed
  /// by [selectionListenable].
  final CanvasSelectionController _selectionController =
      CanvasSelectionController();

  /// World-space rectangle being marquee-dragged. `null` when the user
  /// is not actively dragging out a marquee. Drives the dashed outline
  /// in [_selectionPainter].
  Offset? _marqueeAnchorWorld;
  Rect? _marqueeRectWorld;
  final _CommitNotifier _marqueeTick = _CommitNotifier();

  // ── Transform gesture state (canvas 0.6.0+ Phase C2) ───────────────
  //
  // Populated by `_onDrawStart` when the user grabs a handle (or the
  // body of the bounding rect) while `tool == CanvasTool.select`, then
  // applied incrementally on every `_onDrawUpdate`, and committed to
  // history as a single `_TransformNodesOp` on `_onDrawEnd`.

  TransformMode? _transformMode;
  SelectionHandle? _transformHandle;
  Rect? _transformOriginalBounds;
  Offset? _transformAnchorWorld;
  Map<NodeId, Matrix4>? _transformBeforeMatrices;

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

  /// Stable selection-overlay painter. Created once in [initState] for
  /// the same listener-stability reasons as [_committedPainter] and
  /// [_liveStrokePainter]. Reads selection / camera / marquee state at
  /// paint time.
  late final SelectionPainter _selectionPainter;

  /// Focus node that owns keyboard shortcuts. Created lazily only when
  /// [widget.enableKeyboardShortcuts] is true.
  FocusNode? _focusNode;

  @override
  void initState() {
    super.initState();
    // Bootstrap the scene-graph: a single root carrying a default
    // "Layer 1". Doing this BEFORE anything that may push strokes
    // (initialBytes decode below) so `_addStrokeBoth` always finds an
    // active layer.
    _rootLayer = LayerNode(id: NodeId(generateUid()), name: 'Root');
    _activeLayer = LayerNode(id: NodeId(generateUid()), name: 'Layer 1');
    _rootLayer.add(_activeLayer);
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
    _selectionPainter = SelectionPainter(
      selection: () => _selectionController.value,
      controller: _controller,
      marqueeRect: () => _marqueeRectWorld,
      repaintTrigger: Listenable.merge(<Listenable>[
        _selectionController,
        _controller,
        _marqueeTick,
      ]),
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
          _internalInsertStrokeAt(_strokes.length, s);
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
    _selectionController.dispose();
    _marqueeTick.dispose();
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
    // The eraser preview circle is rendered by the committed painter,
    // which only repaints when `_commitTick` notifies. If the consumer
    // resizes the eraser via the toolbar slider, push a tick so the
    // circle redraws in real time at the new radius.
    if (oldWidget.eraserRadius != widget.eraserRadius ||
        oldWidget.showEraserPreview != widget.showEraserPreview) {
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
      case CanvasTool.select:
        return <Offset>[anchor, current];
    }
  }

  void _onDrawStart(Offset world, double pressure, double tiltX, double tiltY) {
    _focusNode?.requestFocus();
    if (widget.tool == CanvasTool.select) {
      final sel = _selectionController.value;

      // 1. If a selection exists, see if pen-down landed on one of its
      // 8 handles or the rotate handle. Take that as the highest
      // priority — handle gestures supersede tap-select / marquee.
      if (sel.isNotEmpty) {
        final handle =
            TransformMath.hitTestHandle(sel.bounds, world, _controller.scale);
        if (handle != null) {
          _beginTransform(
            mode: TransformMath.modeForHandle(handle),
            handle: handle,
            anchor: world,
            bounds: sel.bounds,
          );
          return;
        }
        // 2. Pen-down inside the bounding box → start a body-drag move
        // on the existing selection (Figma-style drag).
        if (sel.bounds.contains(world)) {
          _beginTransform(
            mode: TransformMode.move,
            handle: null,
            anchor: world,
            bounds: sel.bounds,
          );
          return;
        }
      }

      // 3. Tap-select on pen-down. The marquee will be activated by
      // the first `_onDrawUpdate` if the user actually drags — until
      // then a release-without-move counts as a tap. We also remember
      // the anchor world position so the marquee rect can be
      // reconstructed from anchor + current point on each update.
      _marqueeAnchorWorld = world;
      _marqueeRectWorld = null;
      final hit = _hitTestStrokeNode(world);
      if (hit != null) {
        _selectionController.set(_selectionFromIds(<NodeId>{hit}));
        // 4. Tap landed on a node — also enter move mode immediately
        // so the very same gesture can drag it (no second tap needed).
        _beginTransform(
          mode: TransformMode.move,
          handle: null,
          anchor: world,
          bounds: _selectionController.value.bounds,
        );
      } else {
        _selectionController.clear();
      }
      _marqueeTick.notify();
      return;
    }
    // Lock check (canvas 0.6.0+): the active layer rejects new strokes
    // and skips the eraser when locked. Pre-existing strokes still
    // render — the lock only gates new mutations.
    if (_activeLayer.isLocked) return;
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
    // Lines and rectangles need sharp corners (no quadratic-bezier
    // smoothing). Ellipses and free-form draws stay smoothed.
    final smooth =
        widget.tool != CanvasTool.line && widget.tool != CanvasTool.rectangle;
    _liveStroke.beginStroke(
      color: widget.strokeColor,
      baseWidth: widget.strokeWidth,
      smooth: smooth,
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
      // Sync brush tuning from the widget into the overlay controller so
      // the live preview honours the same values that will be stamped on
      // the resulting `CanvasStroke` at pen-up — keeps live and committed
      // visually identical when the GPU renderer is registered.
      _nativeOverlay.pencilBaseOpacity = widget.pencilConfig.baseOpacity;
      _nativeOverlay.pencilMaxOpacity = widget.pencilConfig.maxOpacity;
      _nativeOverlay.pencilMinPressure = widget.pencilConfig.minPressure;
      _nativeOverlay.pencilMaxPressure = widget.pencilConfig.maxPressure;
      _nativeOverlay.fountainThinning = widget.fountainConfig.thinning;
      _nativeOverlay.fountainNibAngleDeg = widget.fountainConfig.nibAngleDeg;
      _nativeOverlay.fountainNibStrength = widget.fountainConfig.nibStrength;
      _nativeOverlay.fountainPressureRate = widget.fountainConfig.pressureRate;
      _nativeOverlay.fountainTaperEntry = widget.fountainConfig.taperEntry;
      _nativeOverlay.beginStroke(
        color: widget.strokeColor,
        width: widget.strokeWidth,
        brushType: widget.brushType,
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
    if (widget.tool == CanvasTool.select) {
      // 1. If a transform gesture is in flight, every update extends
      // the transform — never falls through to marquee.
      if (_transformMode != null) {
        _applyTransform(world);
        return;
      }
      // 2. Otherwise the user is dragging out a marquee rect (no
      // selection at pen-down OR tapped on empty canvas).
      final anchor = _marqueeAnchorWorld;
      if (anchor == null) return;
      _marqueeRectWorld = Rect.fromPoints(anchor, world);
      _marqueeTick.notify();
      return;
    }
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
    if (widget.tool == CanvasTool.select) {
      // 1. End an in-flight transform first (drag of a handle / body).
      if (_transformMode != null) {
        _endTransform();
        _marqueeAnchorWorld = null;
        _marqueeRectWorld = null;
        _marqueeTick.notify();
        return;
      }
      // 2. Otherwise commit the marquee (if the drag exceeded a few px).
      final marquee = _marqueeRectWorld;
      if (marquee != null && marquee.shortestSide > 1.0) {
        // Marquee committed: replace the (tap-only) selection with
        // every node whose bbox intersects the dragged rect. Width <= 1
        // means a degenerate drag — treat as a tap (already handled in
        // _onDrawStart).
        final ids = _hitTestIdsInRect(marquee);
        _selectionController.set(_selectionFromIds(ids));
      }
      _marqueeAnchorWorld = null;
      _marqueeRectWorld = null;
      _marqueeTick.notify();
      return;
    }
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
      smooth: _liveStroke.smooth,
      brushType: widget.brushType,
      pencilConfig: widget.pencilConfig,
      fountainConfig: widget.fountainConfig,
    );
    if (_liveStrokeTicker.isActive) _liveStrokeTicker.stop();
    _internalInsertStrokeAt(_strokes.length, stroke);
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
    if (_marqueeAnchorWorld != null || _marqueeRectWorld != null) {
      _marqueeAnchorWorld = null;
      _marqueeRectWorld = null;
      _marqueeTick.notify();
    }
    if (_transformMode != null) {
      // Roll back to the snapshot taken at pen-down — a cancelled
      // gesture must not leave the scene with a half-applied transform.
      final before = _transformBeforeMatrices;
      if (before != null) {
        for (final entry in _strokeToNode.entries) {
          final m = before[entry.value.id];
          if (m == null) continue;
          entry.value.localTransform = m.clone();
        }
        _refreshSelectionBoundsAfterTransform();
        _commitTick.notify();
      }
      _resetTransformState();
    }
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
      _internalRemoveStroke(s);
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
      final survivors = CanvasStroke.splitAroundCircle(s, world, r2);
      // No survivors → effectively a full erase of this stroke.
      // One survivor with the same point list → no change (eraser
      // overlapped only the bounding rect padding); skip.
      if (survivors.length == 1 &&
          survivors.first.points.length == s.points.length) {
        continue;
      }
      final idx = _strokes.indexOf(s);
      if (idx < 0) continue;
      _internalRemoveStroke(s);
      // Insert survivors at the original position so Z-order is
      // preserved.
      for (int i = 0; i < survivors.length; i++) {
        _internalInsertStrokeAt(idx + i, survivors[i]);
        _pixelEraseReplacements.add(survivors[i]);
      }
      _pixelEraseOriginals.add(
        _PixelEraseRecord(original: s, index: idx, survivors: survivors),
      );
      anyChange = true;
    }
    if (anyChange) _commitTick.notify();
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
    _internalClear();
    _livePoints = null;
    _livePressures = null;
    _commitTick.notify();
    _history?.push(_ClearOp(snapshot));
  }

  /// Number of committed strokes on the canvas.
  int get strokeCount => _strokes.length;

  /// Read-only view of the committed stroke list (defensive copy).
  List<CanvasStroke> get strokes => List.unmodifiable(_strokes);

  /// Root of the scene graph. Always non-null. Contains the layer
  /// hierarchy that backs the canvas content. In 0.6.0 the root carries
  /// a single default `Layer 1` that holds every stroke; multi-layer
  /// workflows arrive in Phase B.
  ///
  /// Mutating the returned [LayerNode] directly is **unsupported** —
  /// always go through the public layer / stroke API on this state so
  /// the flat `_strokes` mirror, the spatial index and the undo stack
  /// stay in sync.
  LayerNode get rootLayer => _rootLayer;

  /// Currently-active layer. New strokes / shapes / images are appended
  /// here. Defaults to the auto-created `Layer 1`. Phase B will expose
  /// `setActiveLayer(...)` and the layer-management helpers.
  LayerNode get activeLayer => _activeLayer;

  /// Read-only ordered view (back-to-front) of every [LayerNode] under
  /// the [rootLayer]. Useful for rendering a layers panel without
  /// reaching into the scene graph internals.
  List<LayerNode> get layers => List.unmodifiable(
        _rootLayer.children.whereType<LayerNode>(),
      );

  /// Programmatically append a stroke. Pushes an undo step.
  void pushStroke(CanvasStroke stroke) {
    _internalInsertStrokeAt(_strokes.length, stroke);
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
      _internalInsertStrokeAt(_strokes.length, s);
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

  // ── Selection API (canvas 0.6.0+) ─────────────────────────────────────────

  /// Active selection snapshot. Always non-null; defaults to
  /// [CanvasSelection.empty]. Mutated through [select] / [selectInRect] /
  /// [clearSelection] / [deleteSelection] and via the built-in
  /// `CanvasTool.select` tap + marquee gestures.
  CanvasSelection get selection => _selectionController.value;

  /// Listenable that fires every time [selection] changes. Subscribe
  /// from a transform-handles overlay or a contextual toolbar to react
  /// without `setState` plumbing.
  Listenable get selectionListenable => _selectionController;

  /// Replace the active selection with the node identified by [id]. Pass
  /// `null` (or call [clearSelection]) to deselect everything. Returns
  /// `true` if [id] resolved to a known stroke node, `false` otherwise.
  bool select(NodeId? id) {
    if (id == null) {
      _selectionController.clear();
      return true;
    }
    if (!_strokeToNode.values.any((n) => n.id == id)) return false;
    _selectionController.set(_selectionFromIds(<NodeId>{id}));
    return true;
  }

  /// Select every committed stroke whose bbox intersects [worldRect].
  /// Returns the size of the resulting selection.
  int selectInRect(Rect worldRect) {
    final ids = _hitTestIdsInRect(worldRect);
    _selectionController.set(_selectionFromIds(ids));
    return ids.length;
  }

  /// Clear the selection.
  void clearSelection() => _selectionController.clear();

  /// Remove every selected stroke from the canvas as a single undoable
  /// op. Returns the number of strokes deleted (0 if the selection was
  /// empty).
  int deleteSelection() {
    final ids = _selectionController.value.ids;
    if (ids.isEmpty) return 0;
    final toRemove = <CanvasStroke>[];
    final indexes = <CanvasStroke, int>{};
    for (final entry in _strokeToNode.entries) {
      if (ids.contains(entry.value.id)) {
        final flatIdx = _strokes.indexOf(entry.key);
        if (flatIdx >= 0) {
          toRemove.add(entry.key);
          indexes[entry.key] = flatIdx;
        }
      }
    }
    if (toRemove.isEmpty) return 0;
    for (final s in toRemove) {
      _internalRemoveStroke(s);
      s.dispose();
    }
    _selectionController.clear();
    _commitTick.notify();
    _history?.push(_EraseOp(toRemove, indexes));
    if (widget.onStrokesErased != null) {
      widget.onStrokesErased!(toRemove);
    }
    return toRemove.length;
  }

  // Internal hit-test helpers used by both the public API and the
  // CanvasTool.select gesture handlers.

  CanvasSelection _selectionFromIds(Set<NodeId> ids) {
    if (ids.isEmpty) return CanvasSelection.empty;
    Rect? acc;
    for (final entry in _strokeToNode.entries) {
      if (!ids.contains(entry.value.id)) continue;
      final b = entry.key.bounds;
      acc = acc == null ? b : acc.expandToInclude(b);
    }
    return CanvasSelection(ids: ids, bounds: acc ?? Rect.zero);
  }

  /// Top-most CanvasStrokeNode whose stroke bbox contains [worldPoint],
  /// or `null` when the tap landed on empty canvas. Front-most wins
  /// (highest Z-index).
  NodeId? _hitTestStrokeNode(Offset worldPoint, {double tolerance = 4.0}) {
    final probe = Rect.fromCircle(center: worldPoint, radius: tolerance);
    final candidates = _spatialIndex.queryVisible(probe, margin: 0);
    if (candidates.isEmpty) return null;
    NodeId? best;
    int bestIdx = -1;
    for (final s in candidates) {
      // Filter to strokes inside a non-locked, visible layer.
      final node = _strokeToNode[s];
      if (node == null) continue;
      final layer = node.parent;
      if (layer is LayerNode && (!layer.isVisible || layer.isLocked)) continue;
      final idx = _strokes.indexOf(s);
      if (idx > bestIdx) {
        bestIdx = idx;
        best = node.id;
      }
    }
    return best;
  }

  Set<NodeId> _hitTestIdsInRect(Rect worldRect) {
    final candidates = _spatialIndex.queryVisible(worldRect, margin: 0);
    final out = <NodeId>{};
    for (final s in candidates) {
      final node = _strokeToNode[s];
      if (node == null) continue;
      final layer = node.parent;
      if (layer is LayerNode && (!layer.isVisible || layer.isLocked)) continue;
      out.add(node.id);
    }
    return out;
  }

  // ── Transform gesture helpers (Phase C2) ──────────────────────────────────

  void _beginTransform({
    required TransformMode mode,
    required SelectionHandle? handle,
    required Offset anchor,
    required Rect bounds,
  }) {
    final ids = _selectionController.value.ids;
    final before = <NodeId, Matrix4>{};
    for (final entry in _strokeToNode.entries) {
      if (!ids.contains(entry.value.id)) continue;
      before[entry.value.id] = entry.value.localTransform.clone();
    }
    _transformMode = mode;
    _transformHandle = handle;
    _transformAnchorWorld = anchor;
    _transformOriginalBounds = bounds;
    _transformBeforeMatrices = before;
  }

  void _applyTransform(Offset pointer, {bool modifierActive = false}) {
    final mode = _transformMode;
    final before = _transformBeforeMatrices;
    final anchor = _transformAnchorWorld;
    final bounds = _transformOriginalBounds;
    if (mode == null || before == null || anchor == null || bounds == null) {
      return;
    }
    Matrix4 delta;
    switch (mode) {
      case TransformMode.move:
        delta = TransformMath.translation(
          pointer.dx - anchor.dx,
          pointer.dy - anchor.dy,
          axisLock: modifierActive,
        );
        break;
      case TransformMode.scaleCorner:
        final r = TransformMath.cornerScale(
          originalBounds: bounds,
          grabbed: _transformHandle!,
          pointer: pointer,
          uniform: !modifierActive,
        );
        delta = TransformMath.scaleAroundAnchor(r.sx, r.sy, r.anchor);
        break;
      case TransformMode.scaleEdge:
        final r = TransformMath.edgeScale(
          originalBounds: bounds,
          grabbed: _transformHandle!,
          pointer: pointer,
        );
        delta = TransformMath.scaleAroundAnchor(r.sx, r.sy, r.anchor);
        break;
      case TransformMode.rotate:
        final theta = TransformMath.rotationDelta(
          center: bounds.center,
          anchor: anchor,
          pointer: pointer,
          snap15: modifierActive,
        );
        delta = TransformMath.rotationAroundPivot(theta, bounds.center);
        break;
    }
    for (final entry in _strokeToNode.entries) {
      final m0 = before[entry.value.id];
      if (m0 == null) continue;
      entry.value.localTransform = delta.clone()..multiply(m0);
    }
    _refreshSelectionBoundsAfterTransform();
    _commitTick.notify();
  }

  void _refreshSelectionBoundsAfterTransform() {
    final ids = _selectionController.value.ids;
    if (ids.isEmpty) return;
    Rect? acc;
    for (final entry in _strokeToNode.entries) {
      if (!ids.contains(entry.value.id)) continue;
      final b = entry.value.worldBounds;
      acc = acc == null ? b : acc.expandToInclude(b);
    }
    _selectionController.set(
      _selectionController.value.copyWith(bounds: acc ?? Rect.zero),
    );
  }

  void _endTransform() {
    final before = _transformBeforeMatrices;
    if (before == null || before.isEmpty) {
      _resetTransformState();
      return;
    }
    final after = <NodeId, Matrix4>{};
    for (final entry in _strokeToNode.entries) {
      if (!before.containsKey(entry.value.id)) continue;
      after[entry.value.id] = entry.value.localTransform.clone();
    }
    var changed = false;
    for (final id in before.keys) {
      final a = before[id]!;
      final b = after[id]!;
      for (var i = 0; i < 16; i++) {
        if (a.storage[i] != b.storage[i]) {
          changed = true;
          break;
        }
      }
      if (changed) break;
    }
    if (changed) {
      _history?.push(_TransformNodesOp(before, after));
    }
    _resetTransformState();
  }

  void _resetTransformState() {
    _transformMode = null;
    _transformHandle = null;
    _transformAnchorWorld = null;
    _transformOriginalBounds = null;
    _transformBeforeMatrices = null;
  }

  /// Mirror every selected node around the selection bounds' [axis].
  /// Pushes a single undo step. Returns the count of affected nodes
  /// (0 when the selection is empty).
  int mirrorSelection(Axis axis) {
    final sel = _selectionController.value;
    if (sel.isEmpty) return 0;
    final ids = sel.ids;
    final before = <NodeId, Matrix4>{};
    final after = <NodeId, Matrix4>{};
    final pivot =
        axis == Axis.horizontal ? sel.bounds.center.dx : sel.bounds.center.dy;
    final delta = axis == Axis.horizontal
        ? TransformMath.mirrorH(pivot)
        : TransformMath.mirrorV(pivot);
    var count = 0;
    for (final entry in _strokeToNode.entries) {
      if (!ids.contains(entry.value.id)) continue;
      before[entry.value.id] = entry.value.localTransform.clone();
      final newM = delta.clone()..multiply(entry.value.localTransform);
      entry.value.localTransform = newM;
      after[entry.value.id] = newM.clone();
      count++;
    }
    if (count > 0) {
      _refreshSelectionBoundsAfterTransform();
      _commitTick.notify();
      _history?.push(_TransformNodesOp(before, after));
    }
    return count;
  }

  /// Listenable that fires whenever the canvas commits something the
  /// committed-strokes painter cares about: new stroke, eraser, clear,
  /// undo / redo, and any layer mutation (`addLayer`, `removeLayer`,
  /// `setLayerOpacity`, …). Subscribe from a layer-panel widget to
  /// rebuild on every layer change without polling. Returned as the
  /// `Listenable` interface so external callers can only listen — the
  /// notify is called internally by the canvas.
  Listenable get layerChanges => _commitTick;

  // ── FlueraBlendMode side-table (canvas 0.6.0+) ────────────────────────────
  //
  // `LayerNode.blendMode` is typed as `ui.BlendMode` and so can only carry
  // the 17 modes Flutter exposes natively. The Photoshop-grade extended set
  // (LinearBurn, VividLight, …) lives in `FlueraBlendMode` instead — we
  // remember which extended mode a layer is on via this side-table, keyed
  // by the layer's NodeId. The committed-strokes painter consults the
  // table on every paint and forwards the extended `code` to the
  // registered `LayerCompositor`. Free core falls back to
  // `flueraMode.closestStandard` when no compositor is registered.

  final Map<NodeId, FlueraBlendMode> _extendedBlendModes = <NodeId, FlueraBlendMode>{};

  /// Lookup the active [FlueraBlendMode] for [layerId]. When the table
  /// has no entry, returns the [FlueraBlendMode] that maps to the
  /// layer's current `ui.BlendMode` so the result is always meaningful.
  FlueraBlendMode flueraBlendModeFor(LayerNode layer) {
    final ext = _extendedBlendModes[layer.id];
    if (ext != null) return ext;
    return FlueraBlendMode.fromFlutterBlendMode(layer.blendMode);
  }

  /// Set the [FlueraBlendMode] of layer [id]. Standard modes also update
  /// the underlying `LayerNode.blendMode` so the free fallback path
  /// (no GPU compositor) keeps working unchanged. Extended modes record
  /// the choice in the side-table and set `LayerNode.blendMode` to the
  /// closest standard mode as graceful degradation.
  bool setLayerFlueraBlendMode(NodeId id, FlueraBlendMode mode) {
    final layer = _findLayer(id);
    if (layer == null) return false;
    if (mode.isExtended) {
      _extendedBlendModes[id] = mode;
      // Free core fallback uses the closest standard mode if no GPU
      // compositor is registered.
      layer.blendMode = mode.closestStandard;
    } else {
      _extendedBlendModes.remove(id);
      layer.blendMode = mode.flutterBlendMode!;
    }
    _commitTick.notify();
    return true;
  }

  // ── Layer API (canvas 0.6.0+) ─────────────────────────────────────────────
  //
  // These methods expose the multi-layer model that the renderer already
  // honours via `_CommittedStrokesPainter`'s saveLayer pass. Each method is
  // a thin wrapper around the underlying [LayerNode] mutators followed by
  // `_commitTick.notify()` so the painter repaints exactly once per call.
  //
  // The state always holds at least one layer ("Layer 1" by default) — the
  // pre-0.6.0 single-flat-list semantic is preserved for consumers that
  // never call any of these methods.

  /// Append a new layer above the current top one and return it.
  ///
  /// The new layer is NOT marked active automatically — call
  /// [setActiveLayer] to redirect future strokes to it. Pass [name] to
  /// override the default `Layer N` autonumbering.
  LayerNode addLayer({
    String? name,
    double opacity = 1.0,
    BlendMode blendMode = BlendMode.srcOver,
    bool visible = true,
    bool locked = false,
  }) {
    final n = _rootLayer.children.whereType<LayerNode>().length + 1;
    final layer = LayerNode(
      id: NodeId(generateUid()),
      name: name ?? 'Layer $n',
      opacity: opacity,
      blendMode: blendMode,
      isVisible: visible,
      isLocked: locked,
    );
    _rootLayer.add(layer);
    final insertedIndex =
        _rootLayer.children.whereType<LayerNode>().toList().indexOf(layer);
    _history?.push(_AddLayerOp(layer, insertedIndex));
    _commitTick.notify();
    return layer;
  }

  /// Remove the layer with the given [id]. The last remaining layer is
  /// preserved (a canvas always has at least one layer); calling this on
  /// the active layer also moves the active marker to the previous layer.
  /// Strokes belonging to the removed layer are dropped from both the
  /// spatial index and the flat mirror so undo / persistence stays
  /// consistent. Returns `true` if a layer was actually removed.
  bool removeLayer(NodeId id) {
    final layers = _rootLayer.children.whereType<LayerNode>().toList();
    if (layers.length <= 1) return false;
    LayerNode? target;
    for (final l in layers) {
      if (l.id == id) {
        target = l;
        break;
      }
    }
    if (target == null) return false;
    // Capture per-stroke flat-list snapshots BEFORE removal so undo
    // can re-insert each stroke at its original Z-position.
    final snapshots = <_LayerStrokeSnapshot>[];
    for (final c in target.children) {
      if (c is CanvasStrokeNode) {
        final flatIdx = _strokes.indexOf(c.stroke);
        if (flatIdx >= 0) {
          snapshots.add(_LayerStrokeSnapshot(
            stroke: c.stroke,
            node: c,
            flatIndex: flatIdx,
          ));
        }
      }
    }
    final activeWasTarget = _activeLayer == target;
    final layerIndex = layers.indexOf(target);
    for (final snap in snapshots) {
      _spatialIndex.remove(snap.stroke);
      _strokes.remove(snap.stroke);
      _strokeToNode.remove(snap.stroke);
      // NOTE: we do NOT call snap.stroke.dispose() here so undo can
      // restore the stroke without losing its `ui.Picture` cache. The
      // history evictor calls dispose on the dropped op when capacity
      // is exceeded.
    }
    _rootLayer.remove(target);
    if (activeWasTarget) {
      final remaining = _rootLayer.children.whereType<LayerNode>();
      _activeLayer = remaining.last;
    }
    _history?.push(
      _RemoveLayerOp(target, layerIndex, snapshots, activeWasTarget),
    );
    _commitTick.notify();
    return true;
  }

  /// Make [id] the active layer — any subsequent stroke commit lands on it.
  /// Returns `false` if no layer with that id exists.
  bool setActiveLayer(NodeId id) {
    for (final l in _rootLayer.children.whereType<LayerNode>()) {
      if (l.id == id) {
        _activeLayer = l;
        _commitTick.notify();
        return true;
      }
    }
    return false;
  }

  /// Set the alpha multiplier of layer [id] in `[0, 1]`. Clamped.
  bool setLayerOpacity(NodeId id, double opacity) {
    final layer = _findLayer(id);
    if (layer == null) return false;
    final before = layer.opacity;
    layer.opacity = opacity;
    if (before != layer.opacity) {
      _history?.push(_LayerOpacityOp(id, before, layer.opacity));
    }
    _commitTick.notify();
    return true;
  }

  /// Toggle the visibility of layer [id]. Hidden layers skip rendering
  /// but their strokes are preserved.
  bool setLayerVisible(NodeId id, bool visible) {
    final layer = _findLayer(id);
    if (layer == null) return false;
    final before = layer.isVisible;
    layer.isVisible = visible;
    if (before != visible) {
      _history?.push(_LayerVisibleOp(id, before, visible));
    }
    _commitTick.notify();
    return true;
  }

  /// Toggle the lock flag of layer [id]. Locked layers reject new strokes
  /// and the eraser is a no-op against them.
  bool setLayerLocked(NodeId id, bool locked) {
    final layer = _findLayer(id);
    if (layer == null) return false;
    final before = layer.isLocked;
    layer.isLocked = locked;
    if (before != locked) {
      _history?.push(_LayerLockedOp(id, before, locked));
    }
    _commitTick.notify();
    return true;
  }

  /// Replace the blend mode used when compositing layer [id] over the
  /// layers below it. The free pub.dev core supports the standard
  /// `BlendMode` enum from `dart:ui`; the commercial `fluera_canvas_gpu`
  /// add-on can extend this with Photoshop-grade modes via its GPU
  /// compositor.
  bool setLayerBlendMode(NodeId id, BlendMode blendMode) {
    final layer = _findLayer(id);
    if (layer == null) return false;
    final before = layer.blendMode;
    layer.blendMode = blendMode;
    if (before != blendMode) {
      _history?.push(_LayerBlendModeOp(id, before, blendMode));
    }
    _commitTick.notify();
    return true;
  }

  /// Rename layer [id]. The name is shown by the optional layer panel UI.
  bool setLayerName(NodeId id, String name) {
    final layer = _findLayer(id);
    if (layer == null) return false;
    final before = layer.name;
    layer.name = name;
    if (before != name) {
      _history?.push(_LayerNameOp(id, before, name));
    }
    _commitTick.notify();
    return true;
  }

  /// Move layer [id] to position [newIndex] in the back-to-front list
  /// returned by [layers] (0 = bottom, last = top). Out-of-range indices
  /// are clamped. Returns `false` if no layer matches the id.
  bool reorderLayer(NodeId id, int newIndex) {
    final layers = _rootLayer.children.whereType<LayerNode>().toList();
    final fromIdx = layers.indexWhere((l) => l.id == id);
    if (fromIdx < 0) return false;
    final clamped = newIndex.clamp(0, layers.length - 1);
    if (clamped == fromIdx) return false;
    final target = layers[fromIdx];
    _rootLayer.remove(target);
    _rootLayer.insertAt(clamped, target);
    _history?.push(_ReorderLayerOp(id, fromIdx, clamped));
    _commitTick.notify();
    return true;
  }

  /// Clone layer [id], copying name (with `" copy"` suffix) and visual
  /// settings. The clone goes immediately above the source. Returns the
  /// new layer or `null` if the source id was not found. Strokes are
  /// shallow-cloned (same point + pressure data, fresh `CanvasStroke`
  /// instances so they get their own `Picture` cache).
  LayerNode? duplicateLayer(NodeId id) {
    final src = _findLayer(id);
    if (src == null) return null;
    final clone = LayerNode(
      id: NodeId(generateUid()),
      name: '${src.name} copy',
      opacity: src.opacity,
      blendMode: src.blendMode,
      isVisible: src.isVisible,
      isLocked: src.isLocked,
    );
    final srcIdx = _rootLayer.children.indexOf(src);
    _rootLayer.insertAt(srcIdx + 1, clone);
    // Clone the strokes so the duplicate is editable independently.
    for (final c in src.children) {
      if (c is CanvasStrokeNode) {
        final orig = c.stroke;
        final dup = CanvasStroke(
          points: orig.points,
          pressures: orig.pressures,
          color: orig.color,
          baseWidth: orig.baseWidth,
          smooth: orig.smooth,
          brushType: orig.brushType,
          pencilConfig: orig.pencilConfig,
          fountainConfig: orig.fountainConfig,
        );
        final node = CanvasStrokeNode(id: NodeId(generateUid()), stroke: dup);
        clone.add(node);
        _strokes.add(dup);
        _spatialIndex.insert(dup);
        _strokeToNode[dup] = node;
      }
    }
    _commitTick.notify();
    return clone;
  }

  LayerNode? _findLayer(NodeId id) {
    for (final l in _rootLayer.children.whereType<LayerNode>()) {
      if (l.id == id) return l;
    }
    return null;
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
    final disposeList = List<CanvasStroke>.from(_strokes);
    _internalClear();
    for (final s in disposeList) {
      s.dispose();
    }
    for (final s in loaded) {
      _internalInsertStrokeAt(_strokes.length, s);
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

    final Widget selectionLayer = RepaintBoundary(
      child: CustomPaint(painter: _selectionPainter, size: Size.infinite),
    );

    final Widget gestureChild = Stack(
      children: [
        Positioned.fill(child: committedLayer),
        Positioned.fill(child: selectionLayer),
        Positioned.fill(child: liveLayer),
        if (useNative)
          Positioned.fill(
            // Without this, NativeStrokeOverlay would be a "free"
            // child of the Stack — its intrinsic size would depend on
            // whatever it mounts internally (a sized Texture when GPU
            // is healthy, ZERO when the Dart preview is the only
            // child). The Dart preview path needs the overlay to fill
            // the gesture area or its CustomPaint draws into a 0×0
            // canvas — invisible — even though `paint()` runs.
            child: NativeStrokeOverlay(
              canvasController: _controller,
              controller: _nativeOverlay,
              fallbackToDart: false,
            ),
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
          if ((widget.tool == CanvasTool.erase ||
                  widget.tool == CanvasTool.erasePixel) &&
              widget.showEraserPreview) {
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
      case CanvasTool.select:
        return SystemMouseCursors.basic;
    }
  }

  // ── Internal history hooks (invoked by _CanvasOp implementations) ────────

  /// Insert [s] at [index] in the flat list AND wrap it in a
  /// `CanvasStrokeNode` appended to [_activeLayer] at the equivalent
  /// position. Keeps the spatial index, the flat mirror and the scene
  /// graph atomically consistent.
  void _internalInsertStrokeAt(int index, CanvasStroke s) {
    if (index < 0) index = 0;
    if (index > _strokes.length) index = _strokes.length;
    _strokes.insert(index, s);
    _spatialIndex.insert(s);
    final node = _strokeToNode[s] ??
        CanvasStrokeNode(id: NodeId(generateUid()), stroke: s);
    _strokeToNode[s] = node;
    // For now (Phase A) every stroke lives in the active layer at the
    // same Z-index as in the flat list. Future multi-layer work will
    // route this through a `Map<CanvasStroke, LayerNode>` to support
    // strokes across heterogeneous layers.
    if (node.parent != null && node.parent != _activeLayer) {
      // Defensive: if a stroke is being moved across layers, detach
      // first so `add` / `insertAt` doesn't trip the duplicate-id
      // assertion in GroupNode.
      (node.parent! as LayerNode).remove(node);
    }
    if (index >= _activeLayer.children.length) {
      if (node.parent != _activeLayer) _activeLayer.add(node);
    } else {
      if (node.parent == _activeLayer) {
        _activeLayer.remove(node);
      }
      _activeLayer.insertAt(index, node);
    }
  }

  void _internalRemoveStroke(CanvasStroke s) {
    _strokes.remove(s);
    _spatialIndex.remove(s);
    final node = _strokeToNode.remove(s);
    if (node != null && node.parent is LayerNode) {
      (node.parent! as LayerNode).remove(node);
    }
  }

  void _internalClear() {
    for (final s in _strokes) {
      _spatialIndex.remove(s);
    }
    _strokes.clear();
    _strokeToNode.clear();
    // Preserve layer structure (ids + visibility / opacity) — only
    // detach the stroke nodes. Phase B (layer ops) will revisit this
    // to also handle non-stroke children (text / image) once those
    // can land in the canvas.
    for (final layer in _rootLayer.children.whereType<LayerNode>()) {
      final children = List<CanvasNode>.from(layer.children);
      for (final c in children) {
        if (c is CanvasStrokeNode) layer.remove(c);
      }
    }
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
  double baseWidth, {
  bool smooth = true,
}) {
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

  // Path construction:
  //   • smooth = true  → quadratic-bezier through midpoints (default
  //     for free-form strokes; removes polyline kinks).
  //   • smooth = false → straight `lineTo` segments. Used for shapes
  //     whose corners must stay sharp (rectangles, polygons).
  final path = Path()..moveTo(points[0].dx, points[0].dy);
  if (n == 2 || !smooth) {
    for (int i = 1; i < n; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
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

    // Layer-aware paint pass (canvas 0.6.0+).
    //
    // We walk the scene graph back-to-front and, for each `LayerNode`,
    // wrap the paints of its strokes in a `saveLayer` so per-layer
    // opacity and blend mode compose correctly. The viewport spatial
    // index still tells us which strokes are on-screen — the scene
    // graph just gives us the per-layer membership and ordering.
    //
    // Fast path: when there is exactly one layer with default
    // settings (opacity = 1, srcOver, visible) we skip `saveLayer`
    // entirely and fall back to the pre-0.6.0 single `drawPicture`
    // loop — a hot path on simple notes-app workloads.
    final visibleStrokes = canvasState._spatialIndex.queryVisible(
      viewport,
      margin: 200,
    );
    final layers = canvasState._rootLayer.children.whereType<LayerNode>().toList();
    final hasNonTrivialLayer = layers.length != 1 ||
        !layers.first.isVisible ||
        layers.first.opacity != 1.0 ||
        layers.first.blendMode != ui.BlendMode.srcOver;
    if (!hasNonTrivialLayer) {
      for (final s in visibleStrokes) {
        canvas.drawPicture(s.picture());
      }
    } else {
      // Bucket the on-screen strokes by their owning layer so we paint
      // each layer in one `saveLayer` pass. The bucketing is O(N) on
      // the visible set and avoids hash lookups during the saveLayer
      // body.
      final visibleSet = <CanvasStroke, bool>{};
      for (final s in visibleStrokes) {
        visibleSet[s] = true;
      }
      // saveLayer wants a target rect; the viewport rect is the
      // smallest bound that contains every visible stroke under the
      // current camera, which is exactly what we need.
      final layerRect = viewport;
      // If the consumer registered a commercial GPU layer compositor
      // (`fluera_canvas_gpu`), delegate the per-layer composite pass to
      // it. The compositor receives a `paintStrokes` callback that
      // paints the on-screen strokes into its own offscreen surface so
      // it can apply Photoshop-grade blends, masks, etc. Falls back to
      // the built-in `Canvas.saveLayer` path when no compositor is
      // registered.
      final compositor = FlueraCanvasGpu.layerCompositor;
      for (final layer in layers) {
        if (!layer.isVisible) continue;
        // Find strokes belonging to this layer by walking its children
        // (CanvasStrokeNode → underlying CanvasStroke). The strokes are
        // small, the layers are few — linear scan is fine.
        final layerStrokes = <CanvasStroke>[];
        for (final child in layer.children) {
          if (child is CanvasStrokeNode &&
              visibleSet[child.stroke] == true) {
            layerStrokes.add(child.stroke);
          }
        }
        if (layerStrokes.isEmpty) continue;
        void paintLayer(ui.Canvas c) {
          for (final s in layerStrokes) {
            c.drawPicture(s.picture());
          }
        }
        // Resolve the FlueraBlendMode from the canvas-state side-table.
        // When the layer is on a standard mode the side-table is empty
        // and we forward `null` for `extendedBlendModeCode`; when it is
        // on an extended mode we pass the stable code so the commercial
        // compositor can dispatch to a custom shader.
        final flueraMode = canvasState.flueraBlendModeFor(layer);
        final extCode = flueraMode.isExtended ? flueraMode.code : null;
        if (compositor != null) {
          compositor.compositeLayer(
            canvas,
            opacity: layer.opacity,
            blendMode: layer.blendMode,
            layerRect: layerRect,
            paintStrokes: paintLayer,
            extendedBlendModeCode: extCode,
          );
        } else {
          final paint = Paint()
            ..color = ui.Color.fromRGBO(0, 0, 0, layer.opacity)
            ..blendMode = layer.blendMode;
          canvas.saveLayer(layerRect, paint);
          paintLayer(canvas);
          canvas.restore();
        }
      }
    }

    // Eraser hover circle — drawn last so it sits on top of strokes.
    // Shown for both stroke-mode and pixel-mode eraser tools.
    final showPreview =
        canvasState.widget.showEraserPreview &&
        (canvasState.widget.tool == CanvasTool.erase ||
            canvasState.widget.tool == CanvasTool.erasePixel) &&
        canvasState._eraserPreviewWorld != null;
    if (showPreview) {
      final preview = canvasState._eraserPreviewWorld!;
      final radiusWorld = canvasState.widget.eraserRadius / ctrl.scale;
      // Tinted fill so the user sees the area that will be cut /
      // erased. Pixel-mode tints reddish to signal "destructive" cut;
      // stroke-mode tints neutral grey.
      final isPixel = canvasState.widget.tool == CanvasTool.erasePixel;
      final fill =
          Paint()
            ..color =
                isPixel ? const Color(0x22D32F2F) : const Color(0x33000000)
            ..style = PaintingStyle.fill;
      // Ring: outer dark + inner light = double-ring "marching-ants"
      // look that stays visible on any background colour.
      final outerRing =
          Paint()
            ..color = const Color(0xCC000000)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.0 / ctrl.scale;
      final innerRing =
          Paint()
            ..color = const Color(0xCCFFFFFF)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0 / ctrl.scale;
      canvas.drawCircle(preview, radiusWorld, fill);
      canvas.drawCircle(preview, radiusWorld, outerRing);
      canvas.drawCircle(preview, radiusWorld, innerRing);
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
      smooth: strokeNotifier.smooth,
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
  bool smooth = true;

  void beginStroke({
    required Color color,
    required double baseWidth,
    bool smooth = true,
  }) {
    this.color = color;
    this.baseWidth = baseWidth;
    this.smooth = smooth;
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

// ─── Layer-aware history ops (canvas 0.6.0+) ────────────────────────────

/// Snapshot of a single stroke that lived in a layer at remove time —
/// needed by [_RemoveLayerOp] so undo can restore both the
/// `CanvasStrokeNode` (back into the resurrected layer) AND the flat
/// `_strokes` mirror at its original Z-position.
class _LayerStrokeSnapshot {
  _LayerStrokeSnapshot({
    required this.stroke,
    required this.node,
    required this.flatIndex,
  });
  final CanvasStroke stroke;
  final CanvasStrokeNode node;
  final int flatIndex;
}

class _AddLayerOp implements _CanvasOp {
  _AddLayerOp(this.layer, this.index);
  final LayerNode layer;
  final int index;

  @override
  void undo(FlueraCanvasState s) {
    s._rootLayer.remove(layer);
    if (s._activeLayer == layer) {
      final remaining = s._rootLayer.children.whereType<LayerNode>();
      s._activeLayer = remaining.last;
    }
  }

  @override
  void redo(FlueraCanvasState s) {
    s._rootLayer.insertAt(index, layer);
  }
}

class _RemoveLayerOp implements _CanvasOp {
  _RemoveLayerOp(
    this.layer,
    this.layerIndex,
    this.snapshots,
    this.activeWasTarget,
  );
  final LayerNode layer;
  final int layerIndex;
  final List<_LayerStrokeSnapshot> snapshots;
  final bool activeWasTarget;

  @override
  void undo(FlueraCanvasState s) {
    // Reattach the layer at its original Z-order. The CanvasStrokeNode
    // children are still attached to it (we never detached them on
    // remove — we just unhooked the layer from `_rootLayer` and the
    // strokes from the flat mirror).
    s._rootLayer.insertAt(layerIndex, layer);
    final sorted = List<_LayerStrokeSnapshot>.from(snapshots)
      ..sort((a, b) => a.flatIndex.compareTo(b.flatIndex));
    for (final snap in sorted) {
      final idx = snap.flatIndex.clamp(0, s._strokes.length);
      s._strokes.insert(idx, snap.stroke);
      s._spatialIndex.insert(snap.stroke);
      s._strokeToNode[snap.stroke] = snap.node;
    }
    if (activeWasTarget) s._activeLayer = layer;
  }

  @override
  void redo(FlueraCanvasState s) {
    for (final snap in snapshots) {
      s._spatialIndex.remove(snap.stroke);
      s._strokes.remove(snap.stroke);
      s._strokeToNode.remove(snap.stroke);
    }
    s._rootLayer.remove(layer);
    if (activeWasTarget) {
      final remaining = s._rootLayer.children.whereType<LayerNode>();
      s._activeLayer = remaining.last;
    }
  }
}

class _ReorderLayerOp implements _CanvasOp {
  _ReorderLayerOp(this.layerId, this.fromIndex, this.toIndex);
  final NodeId layerId;
  final int fromIndex;
  final int toIndex;

  void _move(FlueraCanvasState s, int from, int to) {
    final layers = s._rootLayer.children.whereType<LayerNode>().toList();
    if (from < 0 || from >= layers.length) return;
    final layer = layers[from];
    s._rootLayer.remove(layer);
    s._rootLayer.insertAt(to, layer);
  }

  @override
  void undo(FlueraCanvasState s) => _move(s, toIndex, fromIndex);

  @override
  void redo(FlueraCanvasState s) => _move(s, fromIndex, toIndex);
}

class _LayerVisibleOp implements _CanvasOp {
  _LayerVisibleOp(this.layerId, this.before, this.after);
  final NodeId layerId;
  final bool before;
  final bool after;

  void _set(FlueraCanvasState s, bool value) {
    final layer = s._findLayer(layerId);
    if (layer != null) layer.isVisible = value;
  }

  @override
  void undo(FlueraCanvasState s) => _set(s, before);
  @override
  void redo(FlueraCanvasState s) => _set(s, after);
}

class _LayerLockedOp implements _CanvasOp {
  _LayerLockedOp(this.layerId, this.before, this.after);
  final NodeId layerId;
  final bool before;
  final bool after;

  void _set(FlueraCanvasState s, bool value) {
    final layer = s._findLayer(layerId);
    if (layer != null) layer.isLocked = value;
  }

  @override
  void undo(FlueraCanvasState s) => _set(s, before);
  @override
  void redo(FlueraCanvasState s) => _set(s, after);
}

class _LayerOpacityOp implements _CanvasOp {
  _LayerOpacityOp(this.layerId, this.before, this.after);
  final NodeId layerId;
  final double before;
  final double after;

  void _set(FlueraCanvasState s, double value) {
    final layer = s._findLayer(layerId);
    if (layer != null) layer.opacity = value;
  }

  @override
  void undo(FlueraCanvasState s) => _set(s, before);
  @override
  void redo(FlueraCanvasState s) => _set(s, after);
}

class _LayerBlendModeOp implements _CanvasOp {
  _LayerBlendModeOp(this.layerId, this.before, this.after);
  final NodeId layerId;
  final BlendMode before;
  final BlendMode after;

  void _set(FlueraCanvasState s, BlendMode value) {
    final layer = s._findLayer(layerId);
    if (layer != null) layer.blendMode = value;
  }

  @override
  void undo(FlueraCanvasState s) => _set(s, before);
  @override
  void redo(FlueraCanvasState s) => _set(s, after);
}

class _LayerNameOp implements _CanvasOp {
  _LayerNameOp(this.layerId, this.before, this.after);
  final NodeId layerId;
  final String before;
  final String after;

  void _set(FlueraCanvasState s, String value) {
    final layer = s._findLayer(layerId);
    if (layer != null) layer.name = value;
  }

  @override
  void undo(FlueraCanvasState s) => _set(s, before);
  @override
  void redo(FlueraCanvasState s) => _set(s, after);
}

/// Coalesced transform op (Phase C2). One drag of a handle, a body
/// move, a rotate, or a `mirrorSelection` call collapses every per-node
/// `localTransform` write into a single undoable step.
class _TransformNodesOp implements _CanvasOp {
  _TransformNodesOp(Map<NodeId, Matrix4> before, Map<NodeId, Matrix4> after)
      : _before = Map<NodeId, Matrix4>.from(before),
        _after = Map<NodeId, Matrix4>.from(after);

  final Map<NodeId, Matrix4> _before;
  final Map<NodeId, Matrix4> _after;

  void _apply(FlueraCanvasState s, Map<NodeId, Matrix4> snapshots) {
    for (final entry in s._strokeToNode.entries) {
      final m = snapshots[entry.value.id];
      if (m == null) continue;
      entry.value.localTransform = m.clone();
    }
    s._refreshSelectionBoundsAfterTransform();
  }

  @override
  void undo(FlueraCanvasState s) => _apply(s, _before);

  @override
  void redo(FlueraCanvasState s) => _apply(s, _after);
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
