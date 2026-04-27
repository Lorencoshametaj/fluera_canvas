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
import '../core/models/digital_text_element.dart';
import '../core/nodes/canvas_stroke_node.dart';
import '../core/nodes/group_node.dart';
import '../core/nodes/image_node.dart';
import '../core/nodes/layer_node.dart';
import '../core/nodes/shape_node.dart';
import '../core/nodes/text_node.dart';
import 'tools/text_editor.dart';
import '../core/scene_graph/canvas_node.dart';
import '../core/scene_graph/node_id.dart';
import '../rendering/canvas/digital_text_painter.dart';
import '../rendering/canvas/image_node_painter.dart';
import '../rendering/optimization/dirty_region_tracker.dart';
import '../rendering/optimization/layer_picture_cache.dart';
import '../drawing/brush_config.dart';
import '../drawing/filters/one_euro_filter.dart' show OneEuroFilter;
import '../rendering/native_stroke_overlay.dart';
import '../rendering/gpu/gpu_stroke_backend.dart';
import 'fluera_blend_mode.dart';
import '../rendering/optimization/spatial_index.dart';
import '../utils/platform_guard.dart' show PlatformGuard;
import '../utils/uid.dart' show generateUid;
import 'edge_pan_controller.dart';
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

  /// API element `CanvasStroke`.
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

  /// Lossless JSON serialization of every field that affects the
  /// rasterised appearance — points, pressures, color, base width,
  /// smooth flag, brush type, plus the shader tuning configs when they
  /// deviate from defaults. Round-trips exactly through [fromJson].
  ///
  /// Used by `fluera_canvas_gpu` time-travel to persist canvas
  /// mutations as compressed JSONL events.
  Map<String, dynamic> toJson() {
    final n = points.length;
    final xs = List<double>.filled(n, 0);
    final ys = List<double>.filled(n, 0);
    for (int i = 0; i < n; i++) {
      xs[i] = points[i].dx;
      ys[i] = points[i].dy;
    }
    final out = <String, dynamic>{
      'x': xs,
      'y': ys,
      'p': pressures,
      'c': color.toARGB32(),
      'w': baseWidth,
    };
    if (!smooth) out['s'] = false;
    if (brushType != 0) out['bt'] = brushType;
    if (pencilConfig != PencilConfig.defaults) {
      out['pc'] = {
        'bo': pencilConfig.baseOpacity,
        'mo': pencilConfig.maxOpacity,
        'mn': pencilConfig.minPressure,
        'mx': pencilConfig.maxPressure,
      };
    }
    if (fountainConfig != FountainPenConfig.defaults) {
      out['fc'] = {
        'th': fountainConfig.thinning,
        'na': fountainConfig.nibAngleDeg,
        'ns': fountainConfig.nibStrength,
        'pr': fountainConfig.pressureRate,
        'te': fountainConfig.taperEntry,
      };
    }
    return out;
  }

  /// Inverse of [toJson]. Throws [FormatException] on malformed input
  /// (mismatched array lengths). Tolerates missing optional fields by
  /// substituting defaults.
  static CanvasStroke fromJson(Map<String, dynamic> map) {
    final xs = (map['x'] as List).cast<num>();
    final ys = (map['y'] as List).cast<num>();
    final ps = (map['p'] as List).cast<num>();
    if (xs.length != ys.length || xs.length != ps.length) {
      throw const FormatException('Stroke arrays length mismatch.');
    }
    return CanvasStroke(
      points: List<Offset>.unmodifiable([
        for (int i = 0; i < xs.length; i++)
          Offset(xs[i].toDouble(), ys[i].toDouble()),
      ]),
      pressures: List<double>.unmodifiable(ps.map((e) => e.toDouble())),
      color: Color((map['c'] as num).toInt()),
      baseWidth: (map['w'] as num).toDouble(),
      smooth: (map['s'] as bool?) ?? true,
      brushType: (map['bt'] as int?) ?? 0,
      pencilConfig:
          map['pc'] is Map<String, dynamic>
              ? PencilConfig(
                baseOpacity: ((map['pc'] as Map)['bo'] as num).toDouble(),
                maxOpacity: ((map['pc'] as Map)['mo'] as num).toDouble(),
                minPressure: ((map['pc'] as Map)['mn'] as num).toDouble(),
                maxPressure: ((map['pc'] as Map)['mx'] as num).toDouble(),
              )
              : PencilConfig.defaults,
      fountainConfig:
          map['fc'] is Map<String, dynamic>
              ? FountainPenConfig(
                thinning: ((map['fc'] as Map)['th'] as num).toDouble(),
                nibAngleDeg: ((map['fc'] as Map)['na'] as num).toDouble(),
                nibStrength: ((map['fc'] as Map)['ns'] as num).toDouble(),
                pressureRate: ((map['fc'] as Map)['pr'] as num).toDouble(),
                taperEntry: ((map['fc'] as Map)['te'] as num).toInt(),
              )
              : FountainPenConfig.defaults,
    );
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
      final pts = curPts;
      final prs = curPrs;
      curPts = null;
      curPrs = null;
      if (pts == null || pts.length < 2) return;
      // Drop micro-survivors: tiny fragments of < 3 world-px total
      // arc length that the eraser produces along the cut boundary.
      // These would otherwise litter the scene graph as
      // visually-imperceptible "dots" that still cost a spatial-index
      // entry and a layer-cache invalidation. 3 px matches the smoothing
      // pipeline's `targetSpacing`.
      double arcLen = 0.0;
      for (var i = 1; i < pts.length; i++) {
        final dx = pts[i].dx - pts[i - 1].dx;
        final dy = pts[i].dy - pts[i - 1].dy;
        arcLen += math.sqrt(dx * dx + dy * dy);
        if (arcLen >= 3.0) break;
      }
      if (arcLen < 3.0) return;
      survivors.add(
        CanvasStroke(
          points: List<Offset>.unmodifiable(pts),
          pressures: List<double>.unmodifiable(prs!),
          color: stroke.color,
          baseWidth: stroke.baseWidth,
          smooth: stroke.smooth,
          brushType: stroke.brushType,
          pencilConfig: stroke.pencilConfig,
          fountainConfig: stroke.fountainConfig,
        ),
      );
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

  /// Imperative tool — the gesture pipeline is a no-op for this value.
  /// The image entry point is `FlueraImageTool.pickAndCommit(context,
  /// state)` which opens the platform-native picker and commits an
  /// [ImageNode] on the active layer. The enum value exists so the
  /// toolbar can show a dedicated segment / button for it.
  image,

  /// Tap empty canvas to drop a fresh `TextNode` and open the live
  /// editor on it; tap an existing `TextNode` to re-enter editing.
  /// The editor is `FlueraTextEditor` — a Material `TextField`
  /// overlay above the canvas that commits via
  /// `FlueraCanvasState.updateTextElement` on Done / blur / Esc.
  text,

  /// Free-form selection: the user drags an arbitrary path across
  /// the canvas; on pen-up every selectable node whose
  /// `worldBounds.center` falls inside the closed path is
  /// selected. Concave shapes work as expected (vs the marquee
  /// tool, which is rectangular only). Sibling of [select].
  lasso,
}

/// Bounds source for [FlueraCanvasState.renderToImage].
///
/// The canvas is infinite, so a single "render to PNG" semantics is
/// not enough — different consumers need different rasterisation
/// regions. This enum picks the world-space rect.
enum FlueraExportBounds {
  /// WYSIWYG export of what the user currently sees on screen
  /// (the legacy 0.5.0+ behaviour). Output dimensions = the explicit
  /// `width × height` (in logical pixels) passed to `renderToImage`.
  /// Camera transform (pan / zoom / rotate) is baked in.
  viewport,

  /// Export the union of every visible node's `worldBounds`. Output
  /// dimensions are auto-computed from the content size scaled by
  /// `pixelRatio`. Ignores `width` / `height`. Returns a 1×1
  /// sentinel image when the canvas is empty.
  allContent,

  /// Export the bounding rect of the current selection. Returns a
  /// 1×1 sentinel image when nothing is selected.
  selection,

  /// Export an explicit world-space rect (passed via the `region`
  /// parameter of `renderToImage`). Useful for "export this slice"
  /// flows or scripted rendering.
  custom,
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
  /// API element `FlueraCanvas`.
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
    this.onStrokeNodeCommitted,
    this.onStrokesErased,
    this.onNodesDeleted,
    this.enableNativeLiveStroke = true,
    this.initialBytes,
    this.brushType = 0,
    this.pencilConfig = PencilConfig.defaults,
    this.fountainConfig = FountainPenConfig.defaults,
    this.simplifyEpsilon = 0,
    this.snapToGrid = 0,
    this.smartGuidesEnabled = false,
    this.smartGuidesTolerancePx = 6,
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

  /// Same trigger as [onStrokeCommitted] but also carries the
  /// [NodeId] of the freshly-created `CanvasStrokeNode` so listeners
  /// can follow up with imperative ops on that node — e.g. the
  /// commercial `fluera_canvas_gpu` shape-recognition pipeline calls
  /// `state.replaceStrokeWithShape(nodeId, …)` from this hook.
  final void Function(CanvasStroke stroke, NodeId nodeId)?
      onStrokeNodeCommitted;

  /// Fires when the eraser tool removes one or more strokes. The argument
  /// is the unmodifiable list of strokes erased in this gesture (can be
  /// re-ordered if the user erases multiple in a single swipe).
  final void Function(List<CanvasStroke> strokes)? onStrokesErased;

  /// Fires when [FlueraCanvasState.deleteSelection] removes one or more
  /// nodes (strokes, images, future text-shape additions). 0.7.0+
  /// addition — generalises [onStrokesErased] which fires only for
  /// the pen-eraser path. The argument is an unmodifiable list of
  /// every removed `CanvasNode`. `onStrokesErased` keeps firing in
  /// parallel with the stroke subset so 0.5.0 / 0.6.0 consumers
  /// don't need to migrate.
  final void Function(List<CanvasNode> nodes)? onNodesDeleted;

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

  /// Douglas-Peucker tolerance (in world pixels) applied to every
  /// stroke at pen-up before commit.
  ///
  /// **Default `0`** — disabled. The committed stroke uses the same
  /// raw point list the live painter renders during the drag, so what
  /// the user sees while drawing is exactly what gets persisted (no
  /// shape change at pen-up). Recommended for note-taking,
  /// handwriting, and any UX that prizes input fidelity.
  ///
  /// Set `0.5` to opt into Douglas-Peucker simplification (~40-60%
  /// point reduction with sub-pixel visual difference). Trades a tiny
  /// pen-up shape shift for smaller `.fcv` files, less RAM, and
  /// faster spatial-index queries. Higher values (1.0–2.0) are
  /// aggressive — useful for ultra-low RAM scenarios at the cost of
  /// mild corner rounding.
  ///
  /// ```dart
  /// FlueraCanvas(simplifyEpsilon: 0.5); // opt-in compression
  /// ```
  final double simplifyEpsilon;

  /// Grid snap step (in world pixels). When > 0 and a selection is
  /// being translated via the body-drag move, the dragged frame's
  /// closest anchor (corners + edges + centre, 9 candidates) snaps
  /// to the nearest multiple of [snapToGrid] within
  /// [smartGuidesTolerancePx] / scale. Default `0` (disabled).
  ///
  /// Typical values: `8` (compact), `16` (standard design-tool grid),
  /// `24` (looser). Hold Shift while dragging to bypass the snap.
  ///
  /// ```dart
  /// FlueraCanvas(snapToGrid: 16, smartGuidesEnabled: true);
  /// ```
  final double snapToGrid;

  /// When `true`, drag-to-move on a selection scans every other
  /// visible selectable node and snaps the dragged frame's anchors
  /// to the closest matching anchor on a nearby node (Figma-style
  /// alignment). Magenta dashed guide lines render via the selection
  /// painter while a snap is locked. Default `false`.
  ///
  /// Hold Shift while dragging to bypass guides for a single drag
  /// without reconfiguring the widget.
  final bool smartGuidesEnabled;

  /// Logical-px tolerance band around an anchor for both
  /// [snapToGrid] and [smartGuidesEnabled]. The world-space
  /// threshold is `smartGuidesTolerancePx / camera.scale`, so the
  /// snap "feels" the same at every zoom level. Default `6`.
  final double smartGuidesTolerancePx;

  @override
  State<FlueraCanvas> createState() => FlueraCanvasState();
}

/// API element `class`.
class FlueraCanvasState extends State<FlueraCanvas>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final InfiniteCanvasController _controller;
  late final bool _ownsController;
  late final NativeStrokeOverlayController _nativeOverlay;

  /// Read-only access to the camera controller. Exposed so multi-page
  /// export pickers (and any consumer overlay that needs to follow
  /// the camera) can subscribe without reaching into the private
  /// `_controller` field. Mutating the controller from outside the
  /// canvas is supported — it already exposes its own setters.
  InfiniteCanvasController get controller => _controller;

  /// World-space union of `worldBounds` of every selectable node in
  /// every visible layer. `Rect.zero` when the canvas is empty.
  /// Useful for "fit-to-content" camera animations and for the
  /// `FlueraExportBounds.allContent` mode of [renderToImage]. O(N)
  /// on the selectable index.
  Rect get contentBoundsWorld {
    Rect? acc;
    for (final node in _selectableNodes.values) {
      final parent = node.parent;
      if (parent is LayerNode && !parent.isVisible) continue;
      final b = node.worldBounds;
      if (b.isEmpty) continue;
      acc = acc == null ? b : acc.expandToInclude(b);
    }
    return acc ?? Rect.zero;
  }

  /// World-space union of `worldBounds` of every node in the current
  /// selection. `Rect.zero` when the selection is empty. Useful for
  /// the `FlueraExportBounds.selection` mode of [renderToImage].
  Rect get selectionBoundsWorld {
    final sel = _selectionController.value;
    if (sel.isEmpty) return Rect.zero;
    Rect? acc;
    for (final id in sel.ids) {
      final node = _selectableNodes[id];
      if (node == null) continue;
      final b = node.worldBounds;
      if (b.isEmpty) continue;
      acc = acc == null ? b : acc.expandToInclude(b);
    }
    return acc ?? Rect.zero;
  }

  /// Logical size of the canvas viewport (the area `FlueraCanvas` is
  /// laid out into), in screen pixels. Captured by the inner
  /// [LayoutBuilder] on every layout pass — `Size.zero` until the
  /// first frame ships.
  ///
  /// Useful for computing screen-space → world-space drops that need
  /// to land *inside the canvas viewport*, not at the centre of the
  /// surrounding `MediaQuery.size` (which on phones / bottom sheets
  /// can fall outside the canvas itself).
  Size get viewportSize => _gestureViewportSize;

  /// World-space coordinate of the centre of the visible viewport
  /// right now. Equivalent to
  /// `controller.screenToCanvas(Offset(viewportSize.width / 2,
  /// viewportSize.height / 2))`. Returns `Offset.zero` when the
  /// canvas has not laid out yet.
  Offset get viewportCenterWorld {
    final s = _gestureViewportSize;
    if (s.isEmpty) return Offset.zero;
    return _controller.screenToCanvas(Offset(s.width / 2, s.height / 2));
  }

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

  /// O(1) index from a node's [NodeId] to the [CanvasNode] itself.
  /// Source-of-truth for selection / transform / hit-test on any
  /// selectable scene-graph node — strokes today, images now (0.7.0),
  /// future text / shape additions land here without touching the
  /// rest of the pipeline. Kept in sync with [_strokeToNode] +
  /// [_rootLayer]'s image children via the same insertion / removal
  /// helpers (`_internalInsertStrokeAt`, `_internalRemoveStroke`,
  /// `addImageNode`, `_AddLayerChildOp`, `_RemoveLayerOp`,
  /// `_rebuildStrokesFromLayers`).
  final Map<NodeId, CanvasNode> _selectableNodes = <NodeId, CanvasNode>{};

  /// Pre-computed Z-order index (DFS order across [_rootLayer]). Used
  /// by `_hitTestNode` to break ties when multiple nodes contain the
  /// pen-down point — front-most wins (max value). Recomputed every
  /// time the selectable index is mutated; O(N) walk during a full
  /// rebuild, O(1) lookup at query time.
  final Map<NodeId, int> _zOrderIndex = <NodeId, int>{};

  /// Highest Z-stamp currently issued. Maintained incrementally so
  /// `_registerSelectable` can hand out the next stamp in O(1)
  /// instead of folding over `_zOrderIndex.values` every insert.
  /// `_rebuildSelectableIndex` resets it during DFS so the counter
  /// stays bounded across long sessions; single-node mutations
  /// just bump it.
  int _maxZ = -1;

  /// Subset of [_selectableNodes] containing only nodes that are NOT
  /// CanvasStrokeNode (today: ImageNodes; future: text / shape).
  /// Lets `_hitTestNode` and `_hitTestIdsInRect` skip the full
  /// selectable-index scan when looking for non-stroke candidates —
  /// strokes go through the spatial-index RTree, this set is the
  /// fast path for everything else. Typically <100 entries on a real
  /// canvas, vs N (potentially thousands) of strokes.
  final Set<NodeId> _nonStrokeSelectableIds = <NodeId>{};

  /// Counter of how many nodes currently have a non-identity
  /// `localTransform`. While 0, the committed painter can blit
  /// `s.picture()` directly without paying the per-stroke
  /// `_strokeToNode[s]` map lookup — the >99% common case on
  /// notes-app workloads. Maintained by transform op apply / revert
  /// paths.
  int _nodesWithTransform = 0;

  /// IDs of nodes whose `localTransform` is currently non-identity.
  /// The spatial-index RTree is keyed on each stroke's pre-transform
  /// `bounds`; once a stroke is moved/rotated the RTree query at the
  /// new position misses it. The hit-test path skips RTree results
  /// from this set and instead intersects the worldBounds (which IS
  /// transform-aware) of every entry. Maintained alongside
  /// [_nodesWithTransform] — invariants: `_transformedNodeIds.length
  /// == _nodesWithTransform`.
  final Set<NodeId> _transformedNodeIds = <NodeId>{};

  /// Undo / redo stacks. `null` when [widget.historyCapacity] <= 0.
  _CanvasHistory? _history;

  /// Current in-progress stroke (null when the user isn't drawing).
  List<Offset>? _livePoints;
  List<double>? _livePressures;

  /// Strokes erased in the current erase gesture (committed to history on
  /// pen-up so a whole swipe becomes a single undo step).
  final Set<CanvasStroke> _erasedThisGesture = <CanvasStroke>{};

  /// Annotation strokes (image-parented) erased in the current
  /// stroke-mode gesture. Pushed into the [_EraseOp] on pen-up so undo
  /// re-attaches each one to its host image at the original index.
  final List<_AnnotationEraseRecord> _erasedAnnotationsThisGesture =
      <_AnnotationEraseRecord>[];

  /// Annotation strokes (image-parented) split by the pixel-mode
  /// eraser in the current gesture. Pushed into the [_PixelEraseOp]
  /// on pen-up so undo can stitch the original back together.
  final List<_PixelAnnotationEraseRecord> _pixelEraseAnnotationOriginals =
      <_PixelAnnotationEraseRecord>[];

  /// Last eraser position in world coords — used to paint the hover circle.
  /// `null` when the eraser shouldn't be rendered (hover-off, other tool).
  Offset? _eraserPreviewWorld;

  /// Last eraser position consumed by [_eraseAt] during the active
  /// gesture. Used to interpolate sub-steps between two pointer
  /// samples on fast drags so the eraser circle "stamps" continuously
  /// along the path instead of leaving uncut gaps. Reset to `null` on
  /// pen-up and on tool change.
  Offset? _lastEraseAppliedWorld;

  /// Pen pressure (0..1) of the last [_eraseAt] sample. Used to
  /// linearly interpolate the eraser radius across the sub-stamps
  /// between two pointer samples — without this, every intermediate
  /// stamp would adopt the current sample's pressure and the
  /// pressure-modulated radius would jump in discrete steps instead
  /// of varying smoothly along the swept segment.
  double _lastErasePressure = 1.0;

  /// Adaptive smoother applied to every raw point as it arrives from
  /// the pointer pipeline (pen / touch / stylus). Same filter the
  /// commercial fluera_engine uses (`minCutoff = 1.0`, `beta = 0.007`)
  /// — kills the sub-pixel tremor every digitiser produces while
  /// staying responsive on fast strokes. Reinitialised at every
  /// pen-down so each stroke starts from a clean state.
  OneEuroFilter? _oneEuroFilter;

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

  /// Free-form lasso path being dragged out by the user with
  /// `tool == CanvasTool.lasso`. World coords. Reused as the
  /// marquee `_marqueeTick` listenable for paint repaints (the
  /// selection painter draws either the rect outline or the lasso
  /// polyline depending on which is non-null).
  List<Offset>? _lassoPathWorld;

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

  /// Snapshot of the selection's [CanvasSelection.frameTransform] at
  /// `_beginTransform`. Used by [_applyTransform] to express
  /// scale/rotate deltas in the OBB's local frame so handles drag
  /// the rotated corners (not the AABB corners). Identity when the
  /// selection is multi-node or the single node has no rotation.
  Matrix4? _transformOriginalFrame;

  /// Smart-guide lines emitted by the most recent move tick when
  /// `widget.smartGuidesEnabled == true`. The selection painter
  /// reads this on every paint and renders dashed alignment lines.
  /// Cleared on transform end / cancel and at the start of any
  /// non-move gesture.
  List<SmartGuideLine> _activeGuides = const <SmartGuideLine>[];

  /// Public read-only view of [_activeGuides] for the selection
  /// painter. Empty list = nothing to render. Updated on every
  /// move tick.
  List<SmartGuideLine> get activeSmartGuides => _activeGuides;

  /// Cached list of nodes the active transform applies to. Computed
  /// once at `_beginTransform` so the per-frame `_applyTransform`
  /// inner loop is O(S) on the selected set (typically 1–10) instead
  /// of O(N) on every node in the canvas. Cleared on transform end /
  /// cancel along with the rest of the snapshot. Type-agnostic
  /// `CanvasNode` so future text / shape selections plug in without
  /// touching the transform code path.
  List<CanvasNode>? _transformTargets;

  /// Last gesture-area size measured by the build's `LayoutBuilder`
  /// — used by [_edgePan] to know where the edges are.
  Size _gestureViewportSize = Size.zero;

  /// Edge-pan auto-scroll while dragging selection / future image
  /// drag / lasso completion. Lazy-initialised on first need so the
  /// host widget pays no ticker / vsync cost when no edge-pan-aware
  /// gesture is running.
  EdgePanController? _edgePan;

  /// Last screen-space pointer position fed to [_edgePan]. The
  /// edge-pan ticker fires every vsync while the pointer is in the
  /// edge band — but the screen pointer doesn't move during that
  /// time, only the camera does. We re-derive the world-space
  /// pointer from this saved screen value on every tick so the
  /// in-flight transform keeps tracking the new viewport.
  Offset? _lastSelectPointerScreen;

  /// Whether the modifier (shift) was held when the current select
  /// transform began. Recomputing the transform on every edge-pan
  /// tick must honour the same semantics as the originating drag.
  /// 0.6.0 ships without keyboard-modifier wiring; the field stays
  /// `false` and tracks the public default (uniform corner scale,
  /// no axis-lock move). A future keyboard-aware build can promote
  /// this to a mutable field without touching the call sites.
  final bool _transformModifierActive = false;

  /// Lazily build (and reuse) the edge-pan controller.
  EdgePanController _ensureEdgePan() {
    return _edgePan ??= EdgePanController(
      controller: _controller,
      vsync: this,
      onTick: (_) {
        // Camera moved this frame. The screen pointer is unchanged
        // (the user isn't moving) but the world coord under it has
        // shifted — re-derive the world coord, then re-run whichever
        // gesture is active so it keeps tracking the new viewport.
        final screen = _lastSelectPointerScreen;
        if (screen == null) return;
        final world = _controller.screenToCanvas(screen);
        if (_transformMode != null) {
          _applyTransform(world, modifierActive: _transformModifierActive);
        } else if (_marqueeAnchorWorld != null) {
          _marqueeRectWorld = Rect.fromPoints(_marqueeAnchorWorld!, world);
          _marqueeTick.notify();
        }
      },
    );
  }

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

  /// Tracks the world-space rectangles invalidated since the last
  /// paint pass. Phase 2 (0.9.0) wire-up: every stroke / image /
  /// text / annotation mutation marks its bbox dirty here.
  /// Phase 3 (LayerPictureCache) consults the tracker to invalidate
  /// only the affected layer caches instead of rebuilding all of
  /// them. The painter clears it at the end of each paint pass.
  final DirtyRegionTracker _dirtyTracker = DirtyRegionTracker();

  /// Mark [worldBounds] as dirty. No-op when the rect is empty.
  /// Convenience wrapper around [_dirtyTracker.markDirty] that's
  /// invoked from every mutation site so wire-up changes one helper
  /// instead of dozens of call-sites.
  void _markDirty(Rect worldBounds) {
    if (worldBounds.isEmpty) return;
    _dirtyTracker.markDirty(worldBounds);
  }

  /// Per-layer content version, bumped on every mutation that
  /// touches the layer's children (insert / remove / transform / Z
  /// reorder). [LayerPictureCache] gates re-rasterization on this
  /// number — a layer whose version hasn't changed since the last
  /// paint reuses its cached `ui.Picture`. Public via
  /// [layerContentVersion] so external GPU compositors / debuggers
  /// can plug in.
  final Map<NodeId, int> _layerVersions = <NodeId, int>{};

  /// Process-wide picture cache for stable layers. Wired
  /// infrastructurally in 0.9.0 (instance + version bumping +
  /// public invalidate API ready); the committed-strokes painter
  /// loop is scheduled to consume it in 0.9.1 once the multi-layer
  /// composite path (saveLayer + GPU compositor + layer mask +
  /// backdrop recorder) is refactored to record into a per-layer
  /// PictureRecorder safely.
  final LayerPictureCache _layerPictureCache = LayerPictureCache();

  /// Bump the version of [layerId]. Idempotent for unknown layers
  /// (they get their first version on next access). Invalidates the
  /// cached picture immediately so the next paint records a fresh
  /// one.
  void _bumpLayerVersion(NodeId layerId) {
    _layerVersions[layerId] = (_layerVersions[layerId] ?? 0) + 1;
    _layerPictureCache.invalidate(layerId.value);
  }

  /// Read-only view of the per-layer content versions. Useful for
  /// GPU consumers that want to gate their own caches off the same
  /// counter.
  @visibleForTesting
  Map<NodeId, int> get layerContentVersion =>
      Map<NodeId, int>.unmodifiable(_layerVersions);

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
    // Memory-pressure observer (0.9.0): drop GPU caches when the OS
    // reports low memory so the host app stays alive instead of
    // being reaped by the kernel.
    WidgetsBinding.instance.addObserver(this);
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
      activeBlendMode: () => _activeLayer.blendMode,
      activeOpacity: () => _activeLayer.opacity,
      // `_commitTick` fires on every layer-state mutation
      // (`setLayerBlendMode`, `setLayerOpacity`, `setActiveLayer`,
      // …) so toggling those settings while a stroke is in flight
      // refreshes the live preview.
      layerSettingsTrigger: _commitTick,
    );
    _committedPainter = _CommittedStrokesPainter(
      canvasState: this,
      repaintTrigger: Listenable.merge(<Listenable>[_commitTick, _controller]),
    );
    _selectionPainter = SelectionPainter(
      selection: () => _selectionController.value,
      controller: _controller,
      marqueeRect: () => _marqueeRectWorld,
      lassoPath: () => _lassoPathWorld,
      smartGuides: () => _activeGuides,
      repaintTrigger: Listenable.merge(<Listenable>[
        _selectionController,
        _controller,
        _marqueeTick,
      ]),
    );
    _liveStrokeTicker = createTicker((_) {
      // Tick while a draw / erase / select gesture is in progress —
      // works around the Impeller-Vulkan / Adreno coalescing of
      // `setState` / `markNeedsPaint` calls inside pointer-event
      // handlers.
      //
      // For `tool == select` we ONLY need the selection painter to
      // tick — strokes are painted by the committed painter (driven by
      // `_commitTick`), and a full `setState({})` would also trigger
      // every `ListenableBuilder` ancestor (e.g. `FlueraLayerPanel`).
      // A targeted `_marqueeTick.notify()` is enough and ~10× cheaper.
      if (!mounted) return;
      if (widget.tool == CanvasTool.select) {
        _marqueeTick.notify();
      } else {
        setState(() {});
      }
    });
    if (widget.historyCapacity > 0) {
      _history = _CanvasHistory(capacity: widget.historyCapacity, state: this);
    }
    if (widget.enableKeyboardShortcuts) {
      _focusNode = FocusNode(debugLabel: 'FlueraCanvas');
    }
    final initial = widget.initialBytes;
    if (initial != null && initial.isNotEmpty) {
      try {
        // Layer-aware decode (0.6.1+): restore the full hierarchy and
        // the extended-blend-mode side-table from FCV0 v2 / v3. v1
        // files surface as a single synthetic layer.
        final result = CanvasSerializer.decodeBytesFull(initial);
        _replaceWithLayers(result.root, result.extendedCodes);
        _hydrateImageBlobs(result.imageBlobs);
      } catch (_) {
        // Corrupt bytes — start with empty canvas.
      }
    }
  }

  /// Matches `NativeStrokeOverlay._platformSupported`. Every platform now has
  /// a native GPU path: Vulkan (Android), Metal (iOS/macOS), OpenGL (Linux),
  /// D3D11 (Windows), WebGPU (web). Each ships with the `fluera_canvas`
  /// package — no companion dependency needed.
  static bool get _nativePlatformSupported =>
      kIsWeb ||
      PlatformGuard.isAndroid ||
      PlatformGuard.isIOS ||
      PlatformGuard.isMacOS ||
      PlatformGuard.isLinux ||
      PlatformGuard.isWindows;

  late final bool _useNative;

  /// OS-level low-memory event. Drop everything that's safe to
  /// regenerate on demand: cached `ui.Picture` per layer, per-stroke
  /// rasterizer caches, dirty-region accumulator. The image bytes
  /// cache is preserved (re-decoding on the next paint would stall
  /// the gesture loop), but unreferenced ImageNode handles are
  /// already cleaned by the history evictor.
  @override
  void didHaveMemoryPressure() {
    _layerPictureCache.invalidateAll();
    _dirtyTracker.reset();
    for (final s in _strokes) {
      s.dispose();
    }
    super.didHaveMemoryPressure();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _layerPictureCache.dispose();
    _dirtyTracker.dispose();
    if (_ownsController) _controller.dispose();
    _nativeOverlay.dispose();
    _focusNode?.dispose();
    _liveStroke.dispose();
    _liveStrokeTicker.dispose();
    _commitTick.dispose();
    _selectionController.dispose();
    _marqueeTick.dispose();
    _edgePan?.dispose();
    for (final s in _strokes) {
      s.dispose();
    }
    _disposeAllMasks();
    super.dispose();
  }

  /// Free every image in [_layerMasks] and clear the map. Used by
  /// [_replaceWithLayers] (load) and [dispose] (state teardown). The
  /// state owns the mask images per the [setLayerMask] contract — no
  /// other holder is allowed to dispose them.
  void _disposeAllMasks() {
    for (final img in _layerMasks.values) {
      img.dispose();
    }
    _layerMasks.clear();
  }

  @override
  void didUpdateWidget(covariant FlueraCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    // `_commitTick` has subscribers (e.g. `FlueraLayerPanel`'s
    // `ListenableBuilder` on `layerChanges`) that schedule rebuilds.
    // Firing it synchronously from `didUpdateWidget` violates the
    // "no markNeedsBuild during build" invariant, so we defer every
    // notify to the post-frame callback.
    var notifyAfterFrame = false;
    if (oldWidget.tool != widget.tool) {
      _onDrawCancel();
      _eraserPreviewWorld = null;
      notifyAfterFrame = true;
    }
    if (oldWidget.background != widget.background) {
      notifyAfterFrame = true;
    }
    // The eraser preview circle is rendered by the committed painter,
    // which only repaints when `_commitTick` notifies. If the consumer
    // resizes the eraser via the toolbar slider, push a tick so the
    // circle redraws in real time at the new radius.
    if (oldWidget.eraserRadius != widget.eraserRadius ||
        oldWidget.showEraserPreview != widget.showEraserPreview) {
      notifyAfterFrame = true;
    }
    if (notifyAfterFrame) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _commitTick.notify();
      });
    }
    if (oldWidget.historyCapacity != widget.historyCapacity) {
      if (widget.historyCapacity > 0) {
        _history =
            (_history ??
                  _CanvasHistory(capacity: widget.historyCapacity, state: this))
              ..capacity = widget.historyCapacity
              ..state = this;
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
      case CanvasTool.text:
      case CanvasTool.lasso:
      case CanvasTool.select:
      case CanvasTool.image:
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
        // Hit-test handles in the OBB's local frame so rotated images
        // pick up grabs at their visually-rotated corners (not at the
        // axis-aligned AABB corners, which are off-OBB after a turn).
        final localPointer = _worldToFrameLocal(world, sel.frameTransform);
        final handle = TransformMath.hitTestHandle(
          sel.frameRect,
          localPointer,
          _controller.scale,
        );
        if (handle != null) {
          _beginTransform(
            mode: TransformMath.modeForHandle(handle),
            handle: handle,
            anchor: world,
            bounds: sel.frameRect,
            frame: sel.frameTransform.clone(),
          );
          // Vsync ticker forces real-time repaints during the drag —
          // without it Impeller-Vulkan / Adreno coalesces the
          // `_selectionController.set` notify into a single frame at
          // pen-up, freezing the bounding rect + handles mid-gesture.
          if (!_liveStrokeTicker.isActive) _liveStrokeTicker.start();
          return;
        }
        // 2. Pen-down inside the bounding box → start a body-drag move
        // on the existing selection (Figma-style drag). For rotated
        // single-node selections, "inside" means inside the OBB —
        // tested in local frame so the AABB excess doesn't catch
        // empty corner triangles.
        if (sel.frameRect.contains(localPointer)) {
          _beginTransform(
            mode: TransformMode.move,
            handle: null,
            anchor: world,
            bounds: sel.frameRect,
            frame: sel.frameTransform.clone(),
          );
          if (!_liveStrokeTicker.isActive) _liveStrokeTicker.start();
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
      final hit = _hitTestNode(world);
      if (hit != null) {
        _selectionController.set(_selectionFromIds(<NodeId>{hit}));
        // 4. Tap landed on a node — also enter move mode immediately
        // so the very same gesture can drag it (no second tap needed).
        final freshSel = _selectionController.value;
        _beginTransform(
          mode: TransformMode.move,
          handle: null,
          anchor: world,
          bounds: freshSel.frameRect,
          frame: freshSel.frameTransform.clone(),
        );
      } else {
        _selectionController.clear();
      }
      _marqueeTick.notify();
      // Start the vsync ticker so marquee outline + handle drag update
      // in real time on Impeller-Vulkan / Adreno (same workaround the
      // draw / erase tools use — pointer-event `notify()` calls are
      // otherwise coalesced into a single paint at pen-up). Idempotent.
      if (!_liveStrokeTicker.isActive) _liveStrokeTicker.start();
      return;
    }
    // Lock check (canvas 0.6.0+): the active layer rejects new strokes
    // and skips the eraser when locked. Pre-existing strokes still
    // render — the lock only gates new mutations.
    if (_activeLayer.isLocked) return;
    if (widget.tool == CanvasTool.text) {
      // Tap on an existing TextNode → re-enter editing on it.
      // Tap on empty canvas → drop a fresh TextNode at world and
      // open the editor immediately. Either path goes through
      // FlueraTextEditor so undo / redo and history are uniform.
      final hit = _hitTestNode(world);
      final hitNode = hit != null ? _selectableNodes[hit] : null;
      if (hitNode is TextNode) {
        FlueraTextEditor.start(this, existing: hit);
      } else {
        FlueraTextEditor.start(
          this,
          worldPosition: world,
          color: widget.strokeColor,
        );
      }
      return;
    }
    if (widget.tool == CanvasTool.lasso) {
      // Same handle / body priority chain as `tool == select`, so a
      // post-lasso selection behaves identically to a marquee one:
      // tap a handle → resize / rotate, tap inside the bbox → drag,
      // tap outside → start a new lasso (clearing the old selection).
      final sel = _selectionController.value;
      if (sel.isNotEmpty) {
        final localPointer = _worldToFrameLocal(world, sel.frameTransform);
        final handle = TransformMath.hitTestHandle(
          sel.frameRect,
          localPointer,
          _controller.scale,
        );
        if (handle != null) {
          _beginTransform(
            mode: TransformMath.modeForHandle(handle),
            handle: handle,
            anchor: world,
            bounds: sel.frameRect,
            frame: sel.frameTransform.clone(),
          );
          if (!_liveStrokeTicker.isActive) _liveStrokeTicker.start();
          return;
        }
        if (sel.frameRect.contains(localPointer)) {
          _beginTransform(
            mode: TransformMode.move,
            handle: null,
            anchor: world,
            bounds: sel.frameRect,
            frame: sel.frameTransform.clone(),
          );
          if (!_liveStrokeTicker.isActive) _liveStrokeTicker.start();
          return;
        }
        // Tap outside the bbox → user wants a fresh lasso. Drop the
        // previous selection so the new lasso owns the next one.
        _selectionController.clear();
        _marqueeTick.notify();
      }
      _lassoPathWorld = <Offset>[world];
      _marqueeTick.notify();
      if (!_liveStrokeTicker.isActive) _liveStrokeTicker.start();
      return;
    }
    if (widget.tool == CanvasTool.erase ||
        widget.tool == CanvasTool.erasePixel) {
      _erasedThisGesture.clear();
      _eraserPreviewWorld = world;
      _lastEraseAppliedWorld = null;
      _lastErasePressure = pressure.clamp(0.0, 1.0);
      _commitTick.notify();
      _eraseAt(world, pressure);
      // Start the vsync ticker so the eraser preview circle keeps
      // tracking the pointer in real time on Impeller-Vulkan / Adreno.
      if (!_liveStrokeTicker.isActive) {
        _liveStrokeTicker.start();
      }
      return;
    }
    // Auto-clear selection when starting any draw / shape gesture
    // (Notability / Goodnotes-style modal UX). Eraser tools are
    // exempt — they don't visually overlap the selection frame.
    if (_selectionController.value.isNotEmpty) {
      _selectionController.clear();
      _marqueeTick.notify();
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
    // Reinitialise the per-stroke OneEuroFilter and pre-filter the
    // pen-down sample (the first call returns the raw point because
    // there is no prior sample to derive velocity from).
    _oneEuroFilter = OneEuroFilter(minCutoff: 1.0, beta: 0.007);
    final filteredStart = _oneEuroFilter!.filter(
      world,
      DateTime.now().millisecondsSinceEpoch,
    );
    _livePoints = <Offset>[filteredStart];
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
    if (widget.tool == CanvasTool.lasso) {
      // If `_onDrawStart` upgraded this gesture to a transform on the
      // existing selection (handle drag / body drag), every update
      // extends that transform — never appends to the lasso path.
      if (_transformMode != null) {
        _applyTransform(world, modifierActive: _transformModifierActive);
        return;
      }
      final path = _lassoPathWorld;
      if (path == null) return;
      // Append only when the pointer moved meaningfully — caps the
      // path length on slow drags. ~2 world-px granularity.
      final last = path.last;
      final dx = world.dx - last.dx;
      final dy = world.dy - last.dy;
      if (dx * dx + dy * dy >= 4) {
        path.add(world);
        _marqueeTick.notify();
      }
      return;
    }
    if (widget.tool == CanvasTool.select) {
      // 1. If a transform gesture is in flight, every update extends
      // the transform — never falls through to marquee.
      if (_transformMode != null) {
        _applyTransform(world, modifierActive: _transformModifierActive);
        // Feed the edge-pan controller the screen-space pointer so it
        // can scroll the canvas when the user drags toward an edge.
        // The screen pos is stable until pen-up; we save it for the
        // controller's onTick to re-derive the world coord after
        // each camera move.
        final screen = _controller.canvasToScreen(world);
        _lastSelectPointerScreen = screen;
        _ensureEdgePan().update(
          pointerScreen: screen,
          viewportSize: _gestureViewportSize,
        );
        return;
      }
      // 2. Otherwise the user is dragging out a marquee rect (no
      // selection at pen-down OR tapped on empty canvas).
      final anchor = _marqueeAnchorWorld;
      if (anchor == null) return;
      _marqueeRectWorld = Rect.fromPoints(anchor, world);
      _marqueeTick.notify();
      // Marquee drags also benefit from edge-pan — the user dragging
      // a selection rect toward an edge expects the canvas to scroll
      // so they can include strokes outside the current viewport.
      final screen = _controller.canvasToScreen(world);
      _lastSelectPointerScreen = screen;
      _ensureEdgePan().update(
        pointerScreen: screen,
        viewportSize: _gestureViewportSize,
      );
      return;
    }
    if (widget.tool == CanvasTool.erase ||
        widget.tool == CanvasTool.erasePixel) {
      _eraserPreviewWorld = world;
      // Apply the cut FIRST, then notify — the painter must read the
      // updated `_strokes` (and the freshly-invalidated layer-picture
      // cache) when it repaints. Notifying before mutating schedules
      // a repaint against a stale snapshot, which on Impeller-Vulkan
      // can be silently coalesced into the post-mutation tick and
      // make the eraser feel one stamp behind during fast drags.
      _eraseAt(world, pressure);
      _commitTick.notify();
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
    // Adaptive smoothing on every raw sample. OneEuroFilter is
    // velocity-aware: tight smoothing at low speeds (kills tremor when
    // writing slowly) and loose filtering on fast strokes (preserves
    // input fidelity). Same pipeline the commercial fluera_engine uses.
    final filteredWorld =
        _oneEuroFilter?.filter(
          world,
          DateTime.now().millisecondsSinceEpoch,
        ) ??
        world;
    _livePoints!.add(filteredWorld);
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

  /// Returns `true` when [nodeBounds] should be considered selected by
  /// a lasso closed over [lassoPath] (with [lassoBounds] = the lasso
  /// path's own bounding rect, precomputed once per pen-up).
  ///
  /// Strict containment: the node's centre OR any corner of its bounds
  /// must lie inside the closed polygon. The previous catch-all
  /// `lassoBounds.overlaps(nodeBounds)` fallback caused over-selection
  /// — e.g. a "C"-shaped lasso whose AABB engulfed a stroke sitting in
  /// the open mouth of the C would mark the stroke selected even
  /// though no point of it was ever encircled. Removed for parity with
  /// Photoshop / Procreate / Figma. The cheap bbox overlap is still
  /// used as an early reject to skip the expensive `Path.contains`
  /// ray-casting for nodes nowhere near the lasso.
  bool _lassoHitsNode(ui.Path lassoPath, Rect lassoBounds, Rect nodeBounds) {
    if (!lassoBounds.overlaps(nodeBounds)) return false;
    if (lassoPath.contains(nodeBounds.center)) return true;
    if (lassoPath.contains(nodeBounds.topLeft)) return true;
    if (lassoPath.contains(nodeBounds.topRight)) return true;
    if (lassoPath.contains(nodeBounds.bottomLeft)) return true;
    if (lassoPath.contains(nodeBounds.bottomRight)) return true;
    return false;
  }

  void _onDrawEnd(Offset _) {
    if (widget.tool == CanvasTool.lasso) {
      if (_liveStrokeTicker.isActive) _liveStrokeTicker.stop();
      // If this gesture was upgraded to a transform in `_onDrawStart`,
      // close it through the transform pipeline instead of trying to
      // resolve a (non-existent) lasso path.
      if (_transformMode != null) {
        _endTransform();
        _marqueeTick.notify();
        return;
      }
      final path = _lassoPathWorld;
      _lassoPathWorld = null;
      if (path != null && path.length >= 3) {
        // Close the path and pick every selectable node that the
        // lasso encloses or crosses. Photoshop / Procreate parity:
        // a node is selected if its centre falls inside the lasso,
        // OR any of its bounds corners is inside, OR its bounds
        // rect intersects the lasso's own bounds (catches large
        // nodes that "span" the lasso without any anchor falling
        // inside the path).
        final uiPath = ui.Path()..addPolygon(path, true);
        final lassoBounds = uiPath.getBounds();
        final ids = <NodeId>{};
        for (final entry in _selectableNodes.entries) {
          final node = entry.value;
          final parent = node.parent;
          if (parent is LayerNode && (!parent.isVisible || parent.isLocked)) {
            continue;
          }
          if (_lassoHitsNode(uiPath, lassoBounds, node.worldBounds)) {
            ids.add(entry.key);
          }
        }
        _selectionController.set(_selectionFromIds(ids));
      }
      _marqueeTick.notify();
      return;
    }
    if (widget.tool == CanvasTool.select) {
      // (helper used by the lasso hit-test above lives next to the
      //  rest of the selection plumbing further down — see
      //  `_lassoHitsNode`.)
      // Gesture is over — stop the vsync ticker that was kicked on
      // pen-down. No more forced frames needed.
      if (_liveStrokeTicker.isActive) _liveStrokeTicker.stop();
      _edgePan?.stop();
      _lastSelectPointerScreen = null;
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
      _lastEraseAppliedWorld = null;
      if (_erasedThisGesture.isNotEmpty ||
          _pixelEraseOriginals.isNotEmpty ||
          _erasedAnnotationsThisGesture.isNotEmpty ||
          _pixelEraseAnnotationOriginals.isNotEmpty) {
        final erased = _erasedThisGesture.toList(growable: false);
        if (widget.tool == CanvasTool.erasePixel) {
          _history?.push(
            _PixelEraseOp(
              _pixelEraseOriginals,
              _pixelEraseReplacements,
              annotationRecords: _pixelEraseAnnotationOriginals,
            ),
          );
        } else {
          _history?.push(
            _EraseOp(
              erased,
              _lastEraseIndexes,
              annotations: _erasedAnnotationsThisGesture,
            ),
          );
        }
        _erasedThisGesture.clear();
        _lastEraseIndexes.clear();
        _pixelEraseOriginals.clear();
        _pixelEraseReplacements.clear();
        _erasedAnnotationsThisGesture.clear();
        _pixelEraseAnnotationOriginals.clear();
        if (erased.isNotEmpty) widget.onStrokesErased?.call(erased);
      }
      return;
    }
    if (_useNative && widget.tool == CanvasTool.draw) {
      _nativeOverlay.endStroke();
      _nativeOverlay.takePoints();
    }
    _shapeAnchor = null;
    _oneEuroFilter = null; // discard the per-stroke smoother state
    // Empty input: nothing to commit.
    if (_livePoints == null || _livePoints!.isEmpty) {
      if (_liveStrokeTicker.isActive) _liveStrokeTicker.stop();
      _livePoints = null;
      _livePressures = null;
      _liveStroke.clear();
      return;
    }
    // Single-point stroke (pen-down + pen-up without moving). Synthesise
    // a 2-point "dot" stroke so the user gets visible ink (a round cap)
    // instead of a silent commit-then-vanish. Skip for tools that mean
    // something different on a tap (line / rect / ellipse → no shape on
    // a single point) and for shape tools whose corners must stay sharp.
    if (_livePoints!.length == 1 &&
        (widget.tool == CanvasTool.draw ||
            widget.tool == CanvasTool.ellipse)) {
      final p = _livePoints!.first;
      final pr = _livePressures!.first;
      // 0.01 px offset is invisible but lets `drawPath` materialise the
      // round-cap circle that gives the dot its shape.
      _livePoints!.add(Offset(p.dx + 0.01, p.dy));
      _livePressures!.add(pr);
    } else if (_livePoints!.length < 2) {
      if (_liveStrokeTicker.isActive) _liveStrokeTicker.stop();
      _livePoints = null;
      _livePressures = null;
      _liveStroke.clear();
      return;
    }
    final raw = CanvasStroke(
      points: List<Offset>.unmodifiable(_livePoints!),
      pressures: List<double>.unmodifiable(_livePressures!),
      color: widget.strokeColor,
      baseWidth: widget.strokeWidth,
      smooth: _liveStroke.smooth,
      brushType: widget.brushType,
      pencilConfig: widget.pencilConfig,
      fountainConfig: widget.fountainConfig,
    );
    // Apply Douglas-Peucker simplification BEFORE the split + commit.
    // Default eps 0.5 trims 40-60% of redundant points without
    // visible difference; consumers can opt out via `simplifyEpsilon
    // = 0`. Image-annotation split + spatial-index insert all then
    // operate on the smaller point list — RAM, paint cost, and hit
    // -test latency all scale down with point count.
    final stroke = _maybeSimplify(raw);
    if (_liveStrokeTicker.isActive) _liveStrokeTicker.stop();
    _commitDrawnStroke(stroke);
    _livePoints = null;
    _livePressures = null;
    _commitTick.notify();
    _liveStroke.clear();
    widget.onStrokeCommitted?.call(stroke);
    final node = _strokeToNode[stroke];
    if (node != null) widget.onStrokeNodeCommitted?.call(stroke, node.id);
  }

  /// Route the freshly-committed stroke to one or more containers:
  /// every contiguous run of points fully inside the SAME front-most
  /// image becomes a child of that image's `annotations` (in
  /// Run Douglas-Peucker on [raw]'s points using
  /// `widget.simplifyEpsilon`; the kept indices double as the
  /// pressure index source so the pressure curve stays aligned
  /// (no interpolation, no precision drift). Returns the original
  /// stroke when the simplifier is disabled (`epsilon == 0`), the
  /// stroke is too short to simplify, or no point can be dropped.
  CanvasStroke _maybeSimplify(CanvasStroke raw) {
    final eps = widget.simplifyEpsilon;
    if (eps <= 0 || raw.points.length < 4) return raw;
    final keep = _dpKeepIndices(raw.points, eps);
    if (keep.length == raw.points.length) return raw;
    final pts = <Offset>[for (final i in keep) raw.points[i]];
    final prs = <double>[for (final i in keep) raw.pressures[i]];
    return CanvasStroke(
      points: List<Offset>.unmodifiable(pts),
      pressures: List<double>.unmodifiable(prs),
      color: raw.color,
      baseWidth: raw.baseWidth,
      smooth: raw.smooth,
      brushType: raw.brushType,
      pencilConfig: raw.pencilConfig,
      fountainConfig: raw.fountainConfig,
    );
  }

  /// Iterative Douglas-Peucker that returns the *kept indices* of
  /// [points], so callers can pull matching pressures (or any other
  /// per-point side-table) at the same indices without losing
  /// alignment. Always keeps the first and last index.
  List<int> _dpKeepIndices(List<Offset> points, double eps) {
    final n = points.length;
    if (n < 3) return List<int>.generate(n, (i) => i);
    final keep = List<bool>.filled(n, false);
    keep[0] = true;
    keep[n - 1] = true;
    final stack = <(int, int)>[(0, n - 1)];
    while (stack.isNotEmpty) {
      final (lo, hi) = stack.removeLast();
      if (hi - lo < 2) continue;
      final a = points[lo];
      final b = points[hi];
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      final lenSq = dx * dx + dy * dy;
      double maxDist = 0;
      int maxI = -1;
      for (int i = lo + 1; i < hi; i++) {
        final p = points[i];
        double dist;
        if (lenSq == 0) {
          final ex = p.dx - a.dx;
          final ey = p.dy - a.dy;
          dist = math.sqrt(ex * ex + ey * ey);
        } else {
          final num = ((p.dx - a.dx) * dy - (p.dy - a.dy) * dx).abs();
          dist = num / math.sqrt(lenSq);
        }
        if (dist > maxDist) {
          maxDist = dist;
          maxI = i;
        }
      }
      if (maxDist > eps && maxI > lo && maxI < hi) {
        keep[maxI] = true;
        stack.add((lo, maxI));
        stack.add((maxI, hi));
      }
    }
    final out = <int>[];
    for (int i = 0; i < n; i++) {
      if (keep[i]) out.add(i);
    }
    return out;
  }

  /// image-local coords); every other run becomes a free child of the
  /// active layer (in world coords). When the stroke doesn't cross
  /// any image boundary at all the legacy fast path runs — single
  /// `_AddOp` push, no batch overhead.
  ///
  /// Shape tools (line / rectangle / ellipse) bypass the split: their
  /// geometry is meant to be a single rigid figure and slicing it at
  /// arbitrary image boundaries produces visually broken half-shapes.
  /// They commit as one free stroke regardless of overlap.
  void _commitDrawnStroke(CanvasStroke stroke) {
    final isShape =
        widget.tool == CanvasTool.line ||
        widget.tool == CanvasTool.rectangle ||
        widget.tool == CanvasTool.ellipse;
    if (isShape) {
      _internalInsertStrokeAt(_strokes.length, stroke);
      _history?.push(_AddOp(stroke, _strokes.length - 1));
      return;
    }
    final routed = _splitStrokeAcrossImages(stroke);
    if (routed.length == 1 && routed.first.target == null) {
      // Fast path: no image overlap, behaves exactly like 0.7.0.
      _internalInsertStrokeAt(_strokes.length, stroke);
      _history?.push(_AddOp(stroke, _strokes.length - 1));
      return;
    }

    final segments = <_SplitSegment>[];
    for (final r in routed) {
      if (r.target == null) {
        final idx = _strokes.length;
        _internalInsertStrokeAt(idx, r.stroke);
        // After insert the node is registered; pull it back out so we
        // can replay redo with the same instance.
        final node = _strokeToNode[r.stroke];
        if (node == null) continue;
        segments.add(
          _SplitSegment(
            stroke: r.stroke,
            node: node,
            target: null,
            layerIndex: idx,
          ),
        );
      } else {
        final node = CanvasStrokeNode(
          id: NodeId(generateUid()),
          stroke: r.stroke,
        );
        r.target!.annotations.add(node);
        segments.add(
          _SplitSegment(
            stroke: r.stroke,
            node: node,
            target: r.target,
            layerIndex: null,
          ),
        );
      }
    }
    if (segments.isNotEmpty) {
      _history?.push(_SplitStrokeOp(segments));
    }
  }

  /// Walk the stroke point-by-point and split it at every image
  /// boundary crossing. Returns 1+ records describing where each piece
  /// belongs. World→image-local mapping is computed once per candidate
  /// image so the per-point classification stays cheap.
  List<({CanvasStroke stroke, ImageNode? target})> _splitStrokeAcrossImages(
    CanvasStroke source,
  ) {
    // Gather candidate images on the *active layer* whose worldBounds
    // overlap the stroke's bbox. Restricting to the active layer
    // matches the "draw on the layer you're on" mental model — a
    // stroke committed while Layer 2 is active never binds to an
    // image sitting on Layer 1, even when their bounds overlap on
    // screen. Hidden / locked active layers are gated upstream by
    // `_onDrawStart`, so we don't re-check those flags here.
    final candidates = <_ImageHitFrame>[];
    for (final id in _nonStrokeSelectableIds) {
      final node = _selectableNodes[id];
      if (node is! ImageNode) continue;
      if (!identical(node.parent, _activeLayer)) continue;
      if (!node.worldBounds.overlaps(source.bounds)) continue;
      candidates.add(_ImageHitFrame.forNode(node, _zOrderIndex[id] ?? 0));
    }
    if (candidates.isEmpty) {
      return [(stroke: source, target: null)];
    }
    // Higher Z first — front-most image wins when the point sits inside
    // multiple overlapping bitmaps.
    candidates.sort((a, b) => b.z.compareTo(a.z));

    // Classify every point: which container does it belong to?
    final n = source.points.length;
    final containers = List<ImageNode?>.filled(n, null);
    for (int i = 0; i < n; i++) {
      final wp = source.points[i];
      for (final c in candidates) {
        if (c.contains(wp)) {
          containers[i] = c.node;
          break;
        }
      }
    }

    // Sweep into runs of same-container. Re-emit each run as its own
    // CanvasStroke. World coords for free runs; image-local coords
    // (computed via the image's inverse transform) for image runs.
    final runs = <({CanvasStroke stroke, ImageNode? target})>[];
    int i = 0;
    while (i < n) {
      final container = containers[i];
      int j = i + 1;
      while (j < n && containers[j] == container) {
        j++;
      }
      // Need at least 2 points to draw a segment. Singletons are dropped
      // — they'd render as a zero-length segment anyway.
      if (j - i >= 2) {
        final pts = <Offset>[];
        final prs = <double>[];
        if (container == null) {
          for (int k = i; k < j; k++) {
            pts.add(source.points[k]);
            prs.add(source.pressures[k]);
          }
        } else {
          // Map each world point through the image's inverse transform
          // so the resulting stroke draws correctly under the image's
          // own paint stack.
          final inv =
              candidates
                  .firstWhere((c) => identical(c.node, container))
                  .worldToLocal;
          for (int k = i; k < j; k++) {
            final wp = source.points[k];
            final lp = MatrixUtils.transformPoint(inv, wp);
            pts.add(lp);
            prs.add(source.pressures[k]);
          }
        }
        final seg = CanvasStroke(
          points: List<Offset>.unmodifiable(pts),
          pressures: List<double>.unmodifiable(prs),
          color: source.color,
          baseWidth: source.baseWidth,
          smooth: source.smooth,
          brushType: source.brushType,
          pencilConfig: source.pencilConfig,
          fountainConfig: source.fountainConfig,
        );
        runs.add((stroke: seg, target: container));
      }
      i = j;
    }
    if (runs.isEmpty) {
      // Defensive: should never happen for n>=2 strokes, but make sure
      // we always commit *something*. Fall back to the original path.
      return [(stroke: source, target: null)];
    }
    return runs;
  }

  void _onDrawCancel() {
    if (widget.enableNativeLiveStroke) _nativeOverlay.cancelStroke();
    if (_liveStrokeTicker.isActive) _liveStrokeTicker.stop();
    _edgePan?.stop();
    _lastSelectPointerScreen = null;
    _livePoints = null;
    _livePressures = null;
    _lassoPathWorld = null;
    _liveStroke.clear();
    _erasedThisGesture.clear();
    _erasedAnnotationsThisGesture.clear();
    _lastEraseIndexes.clear();
    _pixelEraseOriginals.clear();
    _pixelEraseReplacements.clear();
    _pixelEraseAnnotationOriginals.clear();
    if (_marqueeAnchorWorld != null || _marqueeRectWorld != null) {
      _marqueeAnchorWorld = null;
      _marqueeRectWorld = null;
      _marqueeTick.notify();
    }
    if (_transformMode != null) {
      // Roll back to the snapshot taken at pen-down — a cancelled
      // gesture must not leave the scene with a half-applied transform.
      final before = _transformBeforeMatrices;
      final targets = _transformTargets;
      if (before != null && targets != null) {
        for (final node in targets) {
          final m = before[node.id];
          if (m == null) continue;
          _writeLocalTransform(node, m.clone());
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

  void _eraseAt(Offset world, double pressure) {
    // Pressure-modulated radius: linear ramp from 40 % (precision /
    // soft touch) to 100 % (firm press) of the nominal radius. At
    // pressure 1.0 (the default for finger / non-pressure-aware
    // pointers) the behaviour is identical to pre-0.9.x.
    final p = pressure.clamp(0.0, 1.0);
    final baseRadius = widget.eraserRadius / _controller.scale;
    final currentRadius = baseRadius * (0.4 + 0.6 * p);

    // Sub-step between the previous sample and the current one to
    // avoid "dot trail" gaps on fast drags. Without this, points of
    // an underlying stroke that fall between two pointer samples
    // are not tested against the eraser circle and survive even when
    // the user visually swept right over them.
    final last = _lastEraseAppliedWorld;
    if (last != null) {
      final lastP = _lastErasePressure.clamp(0.0, 1.0);
      final lastRadius = baseRadius * (0.4 + 0.6 * lastP);
      final dx = world.dx - last.dx;
      final dy = world.dy - last.dy;
      final dist = math.sqrt(dx * dx + dy * dy);
      // Half-(min)-radius stamping is the standard brush-engine
      // cadence — every point along the swept segment lies within
      // half of either stamp's radius, so nothing slips through the
      // gaps even when the radius is shrinking under variable pen
      // pressure.
      final minRadius = math.min(lastRadius, currentRadius);
      final step = math.max(minRadius * 0.5, 0.5);
      if (dist > step) {
        final n = (dist / step).floor();
        // Velocity boost: when the cursor jumps far between samples
        // (slow input pipeline / fast drag) inflate intermediate
        // stamps slightly to cover residual gaps. Cap at 1.4× to
        // avoid noticeable over-erase on pen-up/down jumps.
        final velocityFactor =
            (dist / (step * 8.0)).clamp(1.0, 1.4);
        for (int i = 1; i <= n; i++) {
          final t = i / (n + 1);
          final mid = Offset(last.dx + dx * t, last.dy + dy * t);
          // Linearly interpolate pressure → radius across the swept
          // segment. With pressure-aware modulation enabled this
          // gives a smooth taper from `lastRadius` to `currentRadius`.
          final midRadius =
              (lastRadius + (currentRadius - lastRadius) * t) *
              velocityFactor;
          _eraseAtSinglePoint(mid, midRadius);
        }
      }
    }
    _eraseAtSinglePoint(world, currentRadius);
    _lastEraseAppliedWorld = world;
    _lastErasePressure = p;
  }

  /// Apply the eraser tool at exactly [world] — single stamp, no
  /// interpolation. Routes to either pixel-mode (split surrounding
  /// strokes) or stroke-mode (drop whole strokes) per current tool.
  void _eraseAtSinglePoint(Offset world, double radiusWorld) {
    if (widget.tool == CanvasTool.erasePixel) {
      _eraseAtPixelStamp(world, radiusWorld);
      return;
    }
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
    bool anyChange = false;
    if (toErase.isNotEmpty) {
      for (final s in toErase) {
        final idx = _strokes.indexOf(s);
        if (idx < 0) continue;
        _internalRemoveStroke(s);
        s.dispose();
        _erasedThisGesture.add(s);
        _lastEraseIndexes[s] = idx;
      }
      anyChange = true;
    }
    // Annotation pass: walk every visible image whose worldBounds
    // touches the eraser probe and erase any annotation stroke whose
    // image-local geometry intersects the circle. The eraser preview
    // and stroke-mode UX is identical from the user's POV — they don't
    // need to know whether a stroke was free or image-parented.
    if (_eraseAnnotationsAt(world, radiusWorld)) {
      anyChange = true;
    }
    if (anyChange) _commitTick.notify();
  }

  /// Stroke-mode erase pass that targets annotation strokes parented
  /// to ImageNodes. Returns `true` when at least one annotation got
  /// removed in this tick — the caller bumps the commit notifier.
  bool _eraseAnnotationsAt(Offset world, double radiusWorld) {
    bool changed = false;
    final probe = Rect.fromCircle(center: world, radius: radiusWorld);
    for (final id in _nonStrokeSelectableIds) {
      final node = _selectableNodes[id];
      if (node is! ImageNode) continue;
      if (node.annotations.isEmpty) continue;
      final parent = node.parent;
      if (parent is LayerNode && (!parent.isVisible || parent.isLocked)) {
        continue;
      }
      if (!node.worldBounds.overlaps(probe)) continue;
      final frame = _ImageHitFrame.forNode(node, 0);
      // Project the eraser centre into image-local coords. The
      // eraser radius doesn't transform cleanly under non-uniform
      // scale, so for the MVP we approximate with `radiusWorld` —
      // accurate when the image is unscaled (the common case) and a
      // few pixels off otherwise. Good enough for the first cut.
      final centerLocal = MatrixUtils.transformPoint(frame.worldToLocal, world);
      final r2Local = radiusWorld * radiusWorld;
      final toErase = <CanvasStrokeNode>[];
      for (final ann in node.annotations) {
        if (_erasedThisGesture.contains(ann.stroke)) continue;
        if (!ann.stroke.bounds.inflate(radiusWorld).contains(centerLocal)) {
          // Cheap reject: skip strokes whose padded bbox doesn't
          // contain the centre.
          continue;
        }
        if (_strokeIntersectsCircle(ann.stroke, centerLocal, r2Local)) {
          toErase.add(ann);
        }
      }
      for (final ann in toErase) {
        final idx = node.annotations.indexOf(ann);
        if (idx < 0) continue;
        node.annotations.removeAt(idx);
        _erasedThisGesture.add(ann.stroke);
        _erasedAnnotationsThisGesture.add(
          _AnnotationEraseRecord(node: node, ann: ann, index: idx),
        );
        ann.stroke.dispose();
        changed = true;
      }
    }
    return changed;
  }

  /// Pixel-mode erase: instead of removing whole strokes, split each
  /// stroke that the eraser touches and keep the surviving pieces.
  /// Per-update cost is O(k · m) where k = strokes intersecting the
  /// eraser circle (typically <10) and m = points per stroke. Combined
  /// with the spatial-index viewport cull this stays well below 1ms
  /// for typical scenes. As of 0.7.2 the same cut runs against image
  /// annotation strokes via `_pixelEraseAnnotationsAt`.
  ///
  /// Single-stamp variant — [_eraseAt] interpolates multiple stamps
  /// along the swept segment for fast drags.
  void _eraseAtPixelStamp(Offset world, double radiusWorld) {
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
    if (_pixelEraseAnnotationsAt(world, radiusWorld)) {
      anyChange = true;
    }
    if (anyChange) _commitTick.notify();
  }

  /// Pixel-mode pass over annotation strokes parented to ImageNodes.
  /// Mirrors `_eraseAtPixel` but operates in image-local coords so the
  /// circle hits the right pixels even on rotated / scaled images.
  /// Returns `true` when at least one annotation was split.
  bool _pixelEraseAnnotationsAt(Offset world, double radiusWorld) {
    bool changed = false;
    final probe = Rect.fromCircle(center: world, radius: radiusWorld);
    for (final id in _nonStrokeSelectableIds) {
      final node = _selectableNodes[id];
      if (node is! ImageNode) continue;
      if (node.annotations.isEmpty) continue;
      final parent = node.parent;
      if (parent is LayerNode && (!parent.isVisible || parent.isLocked)) {
        continue;
      }
      if (!node.worldBounds.overlaps(probe)) continue;
      final frame = _ImageHitFrame.forNode(node, 0);
      // Project the eraser into image-local coords. Same MVP caveat
      // as `_eraseAnnotationsAt`: radius doesn't transform under
      // non-uniform scale but is accurate for the unscaled common case.
      final centerLocal = MatrixUtils.transformPoint(frame.worldToLocal, world);
      final r2Local = radiusWorld * radiusWorld;
      // Snapshot the list — splitting mutates `node.annotations`.
      final snapshot = List<CanvasStrokeNode>.from(node.annotations);
      for (final ann in snapshot) {
        if (!_strokeIntersectsCircle(ann.stroke, centerLocal, r2Local)) {
          continue;
        }
        final survivors = CanvasStroke.splitAroundCircle(
          ann.stroke,
          centerLocal,
          r2Local,
        );
        // No effective change — skip to avoid noise in the undo stack.
        if (survivors.length == 1 &&
            survivors.first.points.length == ann.stroke.points.length) {
          continue;
        }
        final idx = node.annotations.indexOf(ann);
        if (idx < 0) continue;
        node.annotations.removeAt(idx);
        final survivorNodes = <CanvasStrokeNode>[];
        for (int i = 0; i < survivors.length; i++) {
          final sn = CanvasStrokeNode(
            id: NodeId(generateUid()),
            stroke: survivors[i],
          );
          node.annotations.insert(idx + i, sn);
          survivorNodes.add(sn);
        }
        _pixelEraseAnnotationOriginals.add(
          _PixelAnnotationEraseRecord(
            node: node,
            original: ann,
            index: idx,
            survivors: survivorNodes,
          ),
        );
        changed = true;
      }
    }
    return changed;
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
  List<LayerNode> get layers =>
      List.unmodifiable(_rootLayer.children.whereType<LayerNode>());

  /// Programmatically append a stroke. Pushes an undo step.
  void pushStroke(CanvasStroke stroke) {
    _internalInsertStrokeAt(_strokes.length, stroke);
    _commitTick.notify();
    _history?.push(_AddOp(stroke, _strokes.length - 1));
    widget.onStrokeCommitted?.call(stroke);
    final node = _strokeToNode[stroke];
    if (node != null) widget.onStrokeNodeCommitted?.call(stroke, node.id);
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
    final cb = widget.onStrokeCommitted;
    final nodeCb = widget.onStrokeNodeCommitted;
    if (cb != null || nodeCb != null) {
      for (final s in batch) {
        cb?.call(s);
        if (nodeCb != null) {
          final node = _strokeToNode[s];
          if (node != null) nodeCb(s, node.id);
        }
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
    if (!_selectableNodes.containsKey(id)) return false;
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
    // Build per-node snapshots BEFORE mutating anything so the undo
    // op can restore each node at its original layer / Z position.
    final snapshots = <_DeletedNodeSnapshot>[];
    final removedNodes = <CanvasNode>[];
    final erasedStrokes = <CanvasStroke>[];
    for (final id in ids) {
      final node = _selectableNodes[id];
      if (node == null) continue;
      final parent = node.parent;
      if (parent is! LayerNode) continue;
      final childIdx = parent.children.indexOf(node);
      if (childIdx < 0) continue;
      int? flatIdx;
      if (node is CanvasStrokeNode) {
        flatIdx = _strokes.indexOf(node.stroke);
        if (flatIdx < 0) flatIdx = null;
        erasedStrokes.add(node.stroke);
      }
      snapshots.add(
        _DeletedNodeSnapshot(
          node: node,
          layerId: parent.id,
          childIndex: childIdx,
          flatStrokeIndex: flatIdx,
        ),
      );
      removedNodes.add(node);
    }
    if (snapshots.isEmpty) return 0;
    // Apply removals.
    for (final snap in snapshots) {
      if (snap.isStroke) {
        final stroke = (snap.node as CanvasStrokeNode).stroke;
        _internalRemoveStroke(stroke);
        // NOTE: stroke.dispose() is intentionally skipped — the
        // undo op needs the cached `ui.Picture` to redraw the
        // resurrected node. The history evictor calls dispose
        // when capacity is exceeded.
      } else {
        final parent = snap.node.parent;
        if (parent is LayerNode) parent.remove(snap.node);
        _unregisterSelectable(snap.node.id);
      }
    }
    _selectionController.clear();
    _commitTick.notify();
    _history?.push(_DeleteNodesOp(snapshots));
    // Backwards-compat callback fired with stroke-only subset.
    if (widget.onStrokesErased != null && erasedStrokes.isNotEmpty) {
      widget.onStrokesErased!(erasedStrokes);
    }
    if (widget.onNodesDeleted != null) {
      widget.onNodesDeleted!(List<CanvasNode>.unmodifiable(removedNodes));
    }
    return snapshots.length;
  }

  // Internal hit-test helpers used by both the public API and the
  // CanvasTool.select gesture handlers.

  CanvasSelection _selectionFromIds(Set<NodeId> ids) {
    if (ids.isEmpty) return CanvasSelection.empty;
    Rect? acc;
    for (final id in ids) {
      final node = _selectableNodes[id];
      if (node == null) continue;
      // `worldBounds` is transform-aware: for stroke nodes whose
      // `localTransform` is non-identity (e.g. after `mirrorSelection`)
      // the cached `stroke.bounds` would be the pre-transform geometry.
      // The selectable index entry is the source of truth, hand its
      // worldBounds to the bounding-rect accumulator so the painted
      // selection frame is always pixel-correct.
      final b = node.worldBounds;
      acc = acc == null ? b : acc.expandToInclude(b);
    }
    return CanvasSelection(
      ids: ids,
      bounds: acc ?? Rect.zero,
      frameRect: _frameRectFromIds(ids, acc ?? Rect.zero),
      frameTransform: _frameTransformFromIds(ids),
    );
  }

  /// Local-space rect of the OBB outline. For a single-node selection
  /// this is the node's `localBounds`; for multi-node (or single
  /// un-rotated nodes) it falls back to [worldAabb] so the painter
  /// renders an axis-aligned rect.
  Rect _frameRectFromIds(Set<NodeId> ids, Rect worldAabb) {
    if (ids.length != 1) return worldAabb;
    final node = _selectableNodes[ids.first];
    if (node == null || node.isIdentityTransform) return worldAabb;
    return node.localBounds;
  }

  /// Local-to-world transform of the OBB outline. Identity for
  /// multi-node / un-rotated single-node selections.
  Matrix4 _frameTransformFromIds(Set<NodeId> ids) {
    if (ids.length != 1) return Matrix4.identity();
    final node = _selectableNodes[ids.first];
    if (node == null || node.isIdentityTransform) return Matrix4.identity();
    return node.localTransform.clone();
  }

  /// Top-most selectable node whose `worldBounds` contains
  /// [worldPoint], or `null` when the tap landed on empty canvas.
  /// Front-most wins via `_zOrderIndex` (DFS-order, last child of the
  /// last layer = highest Z). Strokes consult the spatial-index RTree
  /// (O(log n + k)); image / future text-shape nodes are scanned
  /// linearly from `_selectableNodes` (typically <100, fine).
  NodeId? _hitTestNode(Offset worldPoint, {double tolerance = 4.0}) {
    NodeId? best;
    int bestZ = -1;

    // Stroke candidates via the RTree (fast path). The RTree is keyed
    // on each stroke's *pre-transform* `bounds`, so a stroke moved or
    // rotated via `_applyTransform` is queried at its old position
    // here; we skip those and pick them up in the transform-aware
    // pass below.
    final probe = Rect.fromCircle(center: worldPoint, radius: tolerance);
    final strokeCandidates = _spatialIndex.queryVisible(probe, margin: 0);
    for (final s in strokeCandidates) {
      final node = _strokeToNode[s];
      if (node == null) continue;
      if (_transformedNodeIds.contains(node.id)) continue;
      final parent = node.parent;
      if (parent is LayerNode && (!parent.isVisible || parent.isLocked)) {
        continue;
      }
      final z = _zOrderIndex[node.id] ?? -1;
      if (z > bestZ) {
        bestZ = z;
        best = node.id;
      }
    }

    // Non-stroke candidates: iterate ONLY the non-stroke subset
    // (typically <100 entries) instead of every selectable node
    // (potentially thousands of strokes filtered+continued). The
    // predicate stays type-agnostic so future text / shape nodes
    // plug in via the same `_nonStrokeSelectableIds` set.
    for (final id in _nonStrokeSelectableIds) {
      final node = _selectableNodes[id];
      if (node == null) continue;
      final parent = node.parent;
      if (parent is LayerNode && (!parent.isVisible || parent.isLocked)) {
        continue;
      }
      if (!node.worldBounds.contains(worldPoint)) continue;
      final z = _zOrderIndex[id] ?? -1;
      if (z > bestZ) {
        bestZ = z;
        best = id;
      }
    }

    // Transform-aware pass for nodes whose `localTransform` moved them
    // off their indexed position. Iterates only the (typically tiny)
    // set of transformed nodes and uses `worldBounds` — which honours
    // the live transform — for containment.
    for (final id in _transformedNodeIds) {
      final node = _selectableNodes[id];
      if (node == null) continue;
      // Already covered by the non-stroke loop above; skip to avoid
      // double work.
      if (_nonStrokeSelectableIds.contains(id)) continue;
      final parent = node.parent;
      if (parent is LayerNode && (!parent.isVisible || parent.isLocked)) {
        continue;
      }
      if (!node.worldBounds.contains(worldPoint)) continue;
      final z = _zOrderIndex[id] ?? -1;
      if (z > bestZ) {
        bestZ = z;
        best = id;
      }
    }
    return best;
  }

  /// Every selectable node whose `worldBounds` overlaps [worldRect].
  /// Used by marquee-drag (`tool == select`) and the public
  /// `selectInRect` API.
  Set<NodeId> _hitTestIdsInRect(Rect worldRect) {
    final out = <NodeId>{};

    // Strokes via the RTree. Skip transformed strokes — their indexed
    // bounds are at the pre-transform position and the
    // transform-aware pass below picks them up at the visual one.
    final strokeCandidates = _spatialIndex.queryVisible(worldRect, margin: 0);
    for (final s in strokeCandidates) {
      final node = _strokeToNode[s];
      if (node == null) continue;
      if (_transformedNodeIds.contains(node.id)) continue;
      final parent = node.parent;
      if (parent is LayerNode && (!parent.isVisible || parent.isLocked)) {
        continue;
      }
      out.add(node.id);
    }

    // Non-stroke nodes: iterate ONLY the non-stroke subset.
    for (final id in _nonStrokeSelectableIds) {
      final node = _selectableNodes[id];
      if (node == null) continue;
      final parent = node.parent;
      if (parent is LayerNode && (!parent.isVisible || parent.isLocked)) {
        continue;
      }
      if (!node.worldBounds.overlaps(worldRect)) continue;
      out.add(id);
    }

    // Transform-aware pass for moved/rotated strokes.
    for (final id in _transformedNodeIds) {
      final node = _selectableNodes[id];
      if (node == null) continue;
      if (_nonStrokeSelectableIds.contains(id)) continue;
      final parent = node.parent;
      if (parent is LayerNode && (!parent.isVisible || parent.isLocked)) {
        continue;
      }
      if (!node.worldBounds.overlaps(worldRect)) continue;
      out.add(id);
    }
    return out;
  }

  // ── Transform gesture helpers (Phase C2) ──────────────────────────────────

  void _beginTransform({
    required TransformMode mode,
    required SelectionHandle? handle,
    required Offset anchor,
    required Rect bounds,
    Matrix4? frame,
  }) {
    final ids = _selectionController.value.ids;
    final before = <NodeId, Matrix4>{};
    final targets = <CanvasNode>[];
    // Iterate the unified selectable index — picks up strokes AND
    // images (and any future selectable node type) that are part of
    // the current selection.
    for (final id in ids) {
      final node = _selectableNodes[id];
      if (node == null) continue;
      before[id] = node.localTransform.clone();
      targets.add(node);
    }
    _transformMode = mode;
    _transformHandle = handle;
    _transformAnchorWorld = anchor;
    _transformOriginalBounds = bounds;
    _transformOriginalFrame = frame ?? Matrix4.identity();
    _transformBeforeMatrices = before;
    _transformTargets = targets;
  }

  /// Map a world-space pointer into the OBB's local frame so handle
  /// hit-tests and scale math operate on the un-rotated rect.
  /// `frame` is identity for multi-node / un-rotated selections, in
  /// which case this is a no-op.
  Offset _worldToFrameLocal(Offset world, Matrix4 frame) {
    if (frame.isIdentity()) return world;
    final inv = Matrix4.inverted(frame);
    return MatrixUtils.transformPoint(inv, world);
  }

  /// Express a local-space delta `D` in world space by conjugating
  /// through the OBB frame: `frame × D × frame⁻¹`. When `frame` is
  /// identity this is a no-op (returns `D` unchanged), so the
  /// multi-node / un-rotated path stays bit-for-bit identical to the
  /// pre-OBB behaviour.
  Matrix4 _conjugateFrame(Matrix4 localDelta, Matrix4 frame) {
    if (frame.isIdentity()) return localDelta;
    final inv = Matrix4.inverted(frame);
    return frame.clone()
      ..multiply(localDelta)
      ..multiply(inv);
  }

  void _applyTransform(Offset pointer, {bool modifierActive = false}) {
    final mode = _transformMode;
    final before = _transformBeforeMatrices;
    final anchor = _transformAnchorWorld;
    final bounds = _transformOriginalBounds;
    final frame = _transformOriginalFrame ?? Matrix4.identity();
    if (mode == null || before == null || anchor == null || bounds == null) {
      return;
    }
    // Move stays in world space — translation commutes with the OBB
    // frame and the user expects the body-drag to follow the pointer
    // directly. Scale / rotate operate in the OBB's *local* frame so
    // grabbing a corner of a rotated image scales along the image's
    // own axes instead of the screen's. The local-space delta is then
    // re-expressed in world space via `frame × delta_local × frame⁻¹`
    // before being pre-multiplied onto each target's `localTransform`.
    Matrix4 delta;
    switch (mode) {
      case TransformMode.move:
        var dx = pointer.dx - anchor.dx;
        var dy = pointer.dy - anchor.dy;
        if (modifierActive) {
          // Axis-lock: snap to dominant axis (Shift convention).
          if (dx.abs() >= dy.abs()) {
            dy = 0;
          } else {
            dx = 0;
          }
        }
        // Snap-to-grid + smart guides apply ONLY for body-drag move
        // (no handle), and only when the underlying selection has at
        // least one node — both gated below by `_computeMoveSnap`.
        // Skip when modifier (axis-lock) is active so the user has a
        // clean override path.
        if (!modifierActive) {
          final snap = _computeMoveSnap(dx, dy, bounds, frame);
          dx = snap.dx;
          dy = snap.dy;
        } else {
          _activeGuides = const <SmartGuideLine>[];
        }
        delta = TransformMath.translation(dx, dy);
        break;
      case TransformMode.scaleCorner:
        final localPointer = _worldToFrameLocal(pointer, frame);
        final r = TransformMath.cornerScale(
          originalBounds: bounds,
          grabbed: _transformHandle!,
          pointer: localPointer,
          uniform: !modifierActive,
        );
        final localDelta = TransformMath.scaleAroundAnchor(
          r.sx,
          r.sy,
          r.anchor,
        );
        delta = _conjugateFrame(localDelta, frame);
        break;
      case TransformMode.scaleEdge:
        final localPointer = _worldToFrameLocal(pointer, frame);
        final r = TransformMath.edgeScale(
          originalBounds: bounds,
          grabbed: _transformHandle!,
          pointer: localPointer,
        );
        final localDelta = TransformMath.scaleAroundAnchor(
          r.sx,
          r.sy,
          r.anchor,
        );
        delta = _conjugateFrame(localDelta, frame);
        break;
      case TransformMode.rotate:
        // Rotation is around the visual center of the OBB. Using the
        // local-frame pivot keeps the math identical to the AABB
        // case when frame is identity.
        final localAnchor = _worldToFrameLocal(anchor, frame);
        final localPointer = _worldToFrameLocal(pointer, frame);
        final theta = TransformMath.rotationDelta(
          center: bounds.center,
          anchor: localAnchor,
          pointer: localPointer,
          snap15: modifierActive,
        );
        final localDelta = TransformMath.rotationAroundPivot(
          theta,
          bounds.center,
        );
        delta = _conjugateFrame(localDelta, frame);
        break;
    }
    // Iterate the cached selection set (S items, typically 1-10)
    // rather than the entire scene's stroke map (N items). Big perf
    // win on canvases with thousands of strokes.
    final targets = _transformTargets;
    if (targets != null) {
      for (final node in targets) {
        final m0 = before[node.id];
        if (m0 == null) continue;
        // Funnel through `_writeLocalTransform` so the painter
        // fast-path counter (`_nodesWithTransform`) stays in sync
        // with the identity / non-identity transition.
        _writeLocalTransform(node, delta.clone()..multiply(m0));
      }
    }
    _refreshSelectionBoundsAfterTransform();
    _commitTick.notify();
  }

  void _refreshSelectionBoundsAfterTransform() {
    final ids = _selectionController.value.ids;
    if (ids.isEmpty) return;
    Rect? acc;
    // Prefer the cached transform-target list when a gesture is in
    // flight (O(S)); fall back to the full map only when called from
    // a non-gesture context (e.g. mirrorSelection invoked via toolbar).
    final targets = _transformTargets;
    if (targets != null) {
      for (final node in targets) {
        final b = node.worldBounds;
        acc = acc == null ? b : acc.expandToInclude(b);
      }
    } else {
      // Non-gesture context (e.g. `mirrorSelection` invoked via the
      // toolbar). Walk the full selectable index — type-agnostic, so
      // image / future text-shape nodes contribute to the bounding
      // rect just like strokes do.
      for (final id in ids) {
        final node = _selectableNodes[id];
        if (node == null) continue;
        final b = node.worldBounds;
        acc = acc == null ? b : acc.expandToInclude(b);
      }
    }
    final aabb = acc ?? Rect.zero;
    _selectionController.set(
      _selectionController.value.copyWith(
        bounds: aabb,
        frameRect: _frameRectFromIds(ids, aabb),
        frameTransform: _frameTransformFromIds(ids),
      ),
    );
  }

  /// Apply snap-to-grid + smart-guides correction to a raw move
  /// delta `(dx, dy)`. Returns the (possibly-shifted) delta. Side
  /// effect: writes [_activeGuides] with the visual lines to draw
  /// while the snap is locked. Both behaviours are gated by the
  /// widget props; with both off this is a no-op that just clears
  /// the guides.
  Offset _computeMoveSnap(double dx, double dy, Rect bounds, Matrix4 frame) {
    final wantsGrid = widget.snapToGrid > 0;
    final wantsGuides = widget.smartGuidesEnabled;
    if (!wantsGrid && !wantsGuides) {
      _activeGuides = const <SmartGuideLine>[];
      return Offset(dx, dy);
    }
    // Compute the dragged frame's 9 anchor points in world space
    // AFTER the raw delta, so snap math operates on the proposed
    // post-drag position.
    Offset toWorld(Offset local) {
      final shifted = Offset(local.dx + dx, local.dy + dy);
      if (frame.isIdentity()) return shifted;
      return MatrixUtils.transformPoint(frame, shifted);
    }

    final anchorsWorld = <Offset>[
      toWorld(bounds.topLeft),
      toWorld(Offset(bounds.center.dx, bounds.top)),
      toWorld(bounds.topRight),
      toWorld(Offset(bounds.right, bounds.center.dy)),
      toWorld(bounds.bottomRight),
      toWorld(Offset(bounds.center.dx, bounds.bottom)),
      toWorld(bounds.bottomLeft),
      toWorld(Offset(bounds.left, bounds.center.dy)),
      toWorld(bounds.center),
    ];

    final tolerance = widget.smartGuidesTolerancePx / _controller.scale;
    var snapDx = 0.0;
    var snapDy = 0.0;
    var bestX = tolerance;
    var bestY = tolerance;
    final guides = <SmartGuideLine>[];

    // ── Grid snap ────────────────────────────────────────────────
    if (wantsGrid) {
      final g = widget.snapToGrid;
      for (final a in anchorsWorld) {
        final gx = (a.dx / g).round() * g;
        final gy = (a.dy / g).round() * g;
        final dxToGrid = gx - a.dx;
        final dyToGrid = gy - a.dy;
        if (dxToGrid.abs() < bestX) {
          bestX = dxToGrid.abs();
          snapDx = dxToGrid;
        }
        if (dyToGrid.abs() < bestY) {
          bestY = dyToGrid.abs();
          snapDy = dyToGrid;
        }
      }
    }

    // ── Smart guides ─────────────────────────────────────────────
    if (wantsGuides) {
      // Don't align against the nodes that ARE the dragged selection.
      final selectedIds = _selectionController.value.ids;
      // Collect every visible non-selected node's 9 anchors.
      final candidateAnchors = <Offset>[];
      // Track the bbox extents so we can clip the guide line to a
      // reasonable on-screen range (no infinite lines).
      var minY = double.infinity;
      var maxY = double.negativeInfinity;
      var minX = double.infinity;
      var maxX = double.negativeInfinity;
      for (final entry in _selectableNodes.entries) {
        if (selectedIds.contains(entry.key)) continue;
        final node = entry.value;
        final parent = node.parent;
        if (parent is LayerNode && (!parent.isVisible || parent.isLocked)) {
          continue;
        }
        final wb = node.worldBounds;
        if (wb.isEmpty) continue;
        candidateAnchors.add(wb.topLeft);
        candidateAnchors.add(Offset(wb.center.dx, wb.top));
        candidateAnchors.add(wb.topRight);
        candidateAnchors.add(Offset(wb.right, wb.center.dy));
        candidateAnchors.add(wb.bottomRight);
        candidateAnchors.add(Offset(wb.center.dx, wb.bottom));
        candidateAnchors.add(wb.bottomLeft);
        candidateAnchors.add(Offset(wb.left, wb.center.dy));
        candidateAnchors.add(wb.center);
        if (wb.top < minY) minY = wb.top;
        if (wb.bottom > maxY) maxY = wb.bottom;
        if (wb.left < minX) minX = wb.left;
        if (wb.right > maxX) maxX = wb.right;
      }

      Offset? matchX;
      Offset? matchY;
      for (final my in anchorsWorld) {
        for (final other in candidateAnchors) {
          final ddx = other.dx - my.dx;
          final ddy = other.dy - my.dy;
          if (ddx.abs() < bestX) {
            bestX = ddx.abs();
            snapDx = ddx;
            matchX = other;
          }
          if (ddy.abs() < bestY) {
            bestY = ddy.abs();
            snapDy = ddy;
            matchY = other;
          }
        }
      }

      // Emit guide lines for the chosen alignments. The guide
      // extends across the bbox of all candidate nodes plus the
      // dragged selection.
      if (matchX != null) {
        guides.add(
          SmartGuideLine(
            axis: Axis.vertical,
            position: matchX.dx,
            rangeStart: math.min(minY.isFinite ? minY : matchX.dy, matchX.dy),
            rangeEnd: math.max(maxY.isFinite ? maxY : matchX.dy, matchX.dy),
          ),
        );
      }
      if (matchY != null) {
        guides.add(
          SmartGuideLine(
            axis: Axis.horizontal,
            position: matchY.dy,
            rangeStart: math.min(minX.isFinite ? minX : matchY.dx, matchY.dx),
            rangeEnd: math.max(maxX.isFinite ? maxX : matchY.dx, matchY.dx),
          ),
        );
      }
    }

    _activeGuides = guides;
    return Offset(dx + snapDx, dy + snapDy);
  }

  void _endTransform() {
    final before = _transformBeforeMatrices;
    final targets = _transformTargets;
    if (before == null || before.isEmpty || targets == null) {
      _resetTransformState();
      return;
    }
    // Build `after` snapshot from the cached target list — O(S), not
    // O(N). Same for the change-detection loop below.
    final after = <NodeId, Matrix4>{};
    for (final node in targets) {
      after[node.id] = node.localTransform.clone();
    }
    var changed = false;
    for (final id in before.keys) {
      final a = before[id]!;
      final b = after[id];
      if (b == null) continue;
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
    _transformOriginalFrame = null;
    _transformBeforeMatrices = null;
    _transformTargets = null;
    _activeGuides = const <SmartGuideLine>[];
  }

  /// Clone every selected node, offset by [offset] (default 20×20
  /// world px), append to the active layer, replace the selection
  /// with the clones. Single undo step (stack of `_AddLayerChildOp`
  /// pushes coalesced via the history's atomic batch). Returns the
  /// number of duplicated nodes (0 when the selection is empty).
  ///
  /// Bound to **Ctrl/Cmd+D** by default.
  ///
  /// ```dart
  /// canvasKey.currentState?.duplicateSelection();
  /// // …or with a custom offset:
  /// canvasKey.currentState?.duplicateSelection(offset: const Offset(40, 0));
  /// ```
  int duplicateSelection({Offset offset = const Offset(20, 20)}) {
    final sel = _selectionController.value;
    if (sel.isEmpty) return 0;
    final ids = sel.ids.toList(growable: false);
    final clones = <CanvasNode>[];
    for (final id in ids) {
      final node = _selectableNodes[id];
      if (node == null) continue;
      final clone = node.cloneInternal();
      // Offset the clone via translation. Compose `T(offset) ·
      // node.localTransform` so the clone sits next to the original
      // in world space regardless of the source's own transform.
      final t =
          Matrix4.identity()..translateByDouble(offset.dx, offset.dy, 0, 1);
      clone.localTransform = t..multiply(clone.localTransform);
      clone.invalidateTransformCache();
      clones.add(clone);
    }
    if (clones.isEmpty) return 0;

    // Route every clone through the appropriate add-* helper so the
    // selectable index, history and notify-tick all stay in sync.
    final newIds = <NodeId>{};
    for (final clone in clones) {
      if (clone is CanvasStrokeNode) {
        _strokeToNode[clone.stroke] = clone;
        _internalInsertStrokeAt(_strokes.length, clone.stroke);
        _history?.push(_AddOp(clone.stroke, _strokes.length - 1));
      } else if (clone is ImageNode) {
        addImageNode(clone);
      } else if (clone is TextNode) {
        addTextNode(clone);
      } else {
        // Generic CanvasNode — direct attach + history.
        final index = _activeLayer.children.length;
        _activeLayer.add(clone);
        _registerSelectable(clone);
        _history?.push(_AddLayerChildOp(clone, _activeLayer.id, index));
      }
      newIds.add(clone.id);
    }
    _bumpLayerVersion(_activeLayer.id);
    _selectionController.set(_selectionFromIds(newIds));
    _commitTick.notify();
    return clones.length;
  }

  /// Move [id]'s scene-graph node to the END of its parent layer's
  /// children list — top of the Z-stack within that layer. No-op
  /// when [id] is unknown or already at the end. Single undo step.
  ///
  /// ```dart
  /// for (final id in canvasKey.currentState!.selection.ids) {
  ///   canvasKey.currentState!.bringToFront(id);
  /// }
  /// ```
  bool bringToFront(NodeId id) => _reorderChildToEdge(id, toFront: true);

  /// Move [id]'s scene-graph node to the START of its parent layer's
  /// children list — bottom of the Z-stack within that layer. No-op
  /// when [id] is unknown or already at the start. Single undo step.
  ///
  /// ```dart
  /// canvasKey.currentState?.sendToBack(stickerId);
  /// ```
  bool sendToBack(NodeId id) => _reorderChildToEdge(id, toFront: false);

  bool _reorderChildToEdge(NodeId id, {required bool toFront}) {
    final node = _selectableNodes[id];
    if (node == null) return false;
    final parent = node.parent;
    if (parent is! LayerNode) return false;
    final idx = parent.children.indexOf(node);
    if (idx < 0) return false;
    final targetIdx = toFront ? parent.children.length - 1 : 0;
    if (idx == targetIdx) return false;
    parent.remove(node);
    if (toFront) {
      parent.add(node);
    } else {
      parent.insertAt(0, node);
    }
    _markDirty(node.worldBounds);
    _bumpLayerVersion(parent.id);
    _rebuildSelectableIndex();
    _history?.push(_ReorderChildOp(id, parent.id, idx, toFront));
    _commitTick.notify();
    return true;
  }

  /// Wrap every selected node in a fresh [GroupNode], attached to
  /// the layer at the position of the front-most selected node.
  /// The new group becomes the active selection so the user can
  /// immediately drag / rotate / scale the bundle as one unit.
  /// Single undo step. Returns the group's id, or `null` when the
  /// selection is empty / single-node / spans multiple layers.
  ///
  /// Tap on any group member afterwards selects the group as a
  /// single unit (Figma / Sketch convention). Use [ungroupSelection]
  /// to break the bundle apart.
  ///
  /// ```dart
  /// // user has 3 strokes selected via marquee or shift-click
  /// final groupId = canvasKey.currentState?.groupSelection();
  /// ```
  NodeId? groupSelection() {
    final sel = _selectionController.value;
    if (sel.length < 2) return null;
    // Snapshot every selected node + its parent layer + its index.
    // We require all selected nodes to share the same layer (cross-
    // layer grouping would silently move children around).
    final entries = <_GroupMember>[];
    LayerNode? sharedLayer;
    int frontMostIdx = -1;
    for (final id in sel.ids) {
      final node = _selectableNodes[id];
      if (node == null) continue;
      final parent = node.parent;
      if (parent is! LayerNode) return null;
      sharedLayer ??= parent;
      if (!identical(parent, sharedLayer)) return null;
      final idx = parent.children.indexOf(node);
      if (idx < 0) return null;
      entries.add(_GroupMember(node: node, parent: parent, index: idx));
      if (idx > frontMostIdx) frontMostIdx = idx;
    }
    if (sharedLayer == null || entries.isEmpty) return null;

    // Promote `sharedLayer` to non-null for the rest of the body —
    // null was only possible before any entry was processed and
    // we've already returned early in that case.
    final layer = sharedLayer;
    // Sort by current index (descending) so we remove from the END
    // first — keeps the indices we still need stable.
    entries.sort((a, b) => b.index.compareTo(a.index));
    for (final e in entries) {
      layer.remove(e.node);
    }
    // Re-evaluate front-most slot after removals — `frontMostIdx`
    // may now exceed the layer length.
    final insertAt = frontMostIdx.clamp(0, layer.children.length);

    final group = GroupNode(id: NodeId(generateUid()), name: 'Group');
    // Re-add children in their original Z-order (entries was sorted
    // desc; iterate ascending so first child is bottom of group's
    // own Z-stack — preserves the visual Z within the group).
    for (final e in entries.reversed) {
      group.add(e.node);
    }
    if (insertAt >= layer.children.length) {
      layer.add(group);
    } else {
      layer.insertAt(insertAt, group);
    }

    _bumpLayerVersion(layer.id);
    _markDirty(group.worldBounds);
    _rebuildSelectableIndex();
    _selectionController.set(_selectionFromIds({group.id}));
    _history?.push(
      _GroupOp(
        group: group,
        layer: layer,
        members: entries,
        insertedAt: insertAt,
      ),
    );
    _commitTick.notify();
    return group.id;
  }

  /// For every selected [GroupNode], move its children back to the
  /// parent layer at the group's index, preserving their relative
  /// Z-order, then remove the now-empty group. Selection swings to
  /// the freed children. No-op when no group is selected. Single
  /// undo step covers every group ungrouped in one call.
  int ungroupSelection() {
    final sel = _selectionController.value;
    if (sel.isEmpty) return 0;
    final ops = <_UngroupOp>[];
    final freedIds = <NodeId>{};
    var count = 0;
    for (final id in sel.ids) {
      final node = _selectableNodes[id];
      if (node is! GroupNode) continue;
      final layer = node.parent;
      if (layer is! LayerNode) continue;
      final groupIdx = layer.children.indexOf(node);
      if (groupIdx < 0) continue;
      // Snapshot children BEFORE we mutate. Then properly DETACH
      // each child from the group (clears the group's id index +
      // child.parent ref) so re-parenting under the layer doesn't
      // leave the group with stale bookkeeping. The undo path
      // re-adds them to the still-allocated `node` group, which
      // would otherwise hit a "duplicate child id" assert.
      final snapshot = List<CanvasNode>.from(node.children);
      for (final c in snapshot) {
        node.remove(c);
      }
      layer.remove(node);
      // Re-insert children into the layer at the group's slot.
      // Snapshot is in original Z-order; iterate ascending so the
      // first child ends up at `groupIdx` (bottom of the freed
      // bundle), preserving relative Z within the group.
      for (int i = 0; i < snapshot.length; i++) {
        layer.insertAt(groupIdx + i, snapshot[i]);
        freedIds.add(snapshot[i].id);
      }
      ops.add(
        _UngroupOp(
          group: node,
          layer: layer,
          groupIndex: groupIdx,
          formerChildIds: snapshot.map((c) => c.id).toList(),
        ),
      );
      _bumpLayerVersion(layer.id);
      count++;
    }
    if (count == 0) return 0;
    _rebuildSelectableIndex();
    if (freedIds.isNotEmpty) {
      _selectionController.set(_selectionFromIds(freedIds));
    } else {
      _selectionController.clear();
    }
    _history?.push(_UngroupBatchOp(ops));
    _commitTick.notify();
    return count;
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
    final delta =
        axis == Axis.horizontal
            ? TransformMath.mirrorH(pivot)
            : TransformMath.mirrorV(pivot);
    var count = 0;
    // Iterate the unified selectable index — picks up strokes,
    // images, and any future selectable node type that's part of the
    // current selection.
    for (final id in ids) {
      final node = _selectableNodes[id];
      if (node == null) continue;
      before[id] = node.localTransform.clone();
      final newM = delta.clone()..multiply(node.localTransform);
      _writeLocalTransform(node, newM);
      after[id] = newM.clone();
      count++;
    }
    if (count > 0) {
      _refreshSelectionBoundsAfterTransform();
      _commitTick.notify();
      _history?.push(_TransformNodesOp(before, after));
    }
    return count;
  }

  // ── Image API (Phase D) ───────────────────────────────────────────────────

  /// Append [node] to the active layer as a single undoable step.
  /// Use `FlueraImageTool.pickAndCommit(...)` for the typical
  /// "open file picker → decode → commit" flow; this method is the
  /// imperative seam underneath it, also useful for paste / drag-drop /
  /// network-image workflows.
  ImageNode addImageNode(ImageNode node) {
    final index = _activeLayer.children.length;
    _activeLayer.add(node);
    _registerSelectable(node);
    _history?.push(_AddLayerChildOp(node, _activeLayer.id, index));
    _bumpLayerVersion(_activeLayer.id);
    _commitTick.notify();
    return node;
  }

  // ── Shape API (Phase 0.9.0) ───────────────────────────────────────────────

  /// Append [node] to the active layer as a single undoable step. Used
  /// by the commercial `fluera_canvas_gpu` shape-recognition pipeline
  /// to materialize a `ShapeRecognitionResult` into a clean primitive
  /// after the user accepts a snap suggestion. Also useful for paste /
  /// drag-drop of shape clipboard payloads.
  ShapeNode addShapeNode(ShapeNode node) {
    final index = _activeLayer.children.length;
    _activeLayer.add(node);
    _registerSelectable(node);
    _history?.push(_AddLayerChildOp(node, _activeLayer.id, index));
    _bumpLayerVersion(_activeLayer.id);
    _commitTick.notify();
    return node;
  }

  // ── Text API (Phase 0.8.0) ────────────────────────────────────────────────

  /// Append [node] to the active layer as a single undoable step. The
  /// canvas-level seam underneath `FlueraTextEditor.start(...)`; also
  /// useful for paste / clipboard / programmatic-text flows.
  ///
  /// ```dart
  /// final node = TextNode(
  ///   element: DigitalTextElement(text: 'Hello', position: Offset(120, 80)),
  /// );
  /// canvasKey.currentState!.addTextNode(node);
  /// ```
  ///
  /// To open the inline editor for live caret editing instead of
  /// committing static text, use `CanvasTool.text` and let the user
  /// tap — `FlueraTextEditor` calls this method internally.
  TextNode addTextNode(TextNode node) {
    final index = _activeLayer.children.length;
    _activeLayer.add(node);
    _registerSelectable(node);
    _history?.push(_AddLayerChildOp(node, _activeLayer.id, index));
    _bumpLayerVersion(_activeLayer.id);
    _commitTick.notify();
    return node;
  }

  /// Detach a TextNode that was just added by [addTextNode] and
  /// drop the matching `_AddLayerChildOp` from the top of the undo
  /// stack — used by `FlueraTextEditor` when the user dismisses the
  /// editor on a fresh node without typing anything. Surgical:
  /// touches only the matching op, never `state.undo()` (which would
  /// nuke unrelated history).
  void removeFreshTextNode(TextNode node) {
    final layer = node.parent;
    if (layer is! LayerNode) return;
    layer.remove(node);
    _unregisterSelectable(node.id);
    _history?.popMatching(
      (op) => op is _AddLayerChildOp && identical(op.node, node),
    );
    _commitTick.notify();
  }

  /// Replace the [DigitalTextElement] of an existing [TextNode] in
  /// place, pushing a single `_UpdateTextOp` so undo restores the
  /// previous element exactly. Returns `true` when the node was found
  /// and updated, `false` when [id] does not point to a TextNode.
  bool updateTextElement(NodeId id, DigitalTextElement next) {
    final node = _selectableNodes[id];
    if (node is! TextNode) return false;
    final before = node.textElement;
    if (identical(before, next)) return false;
    node.textElement = next;
    // Force layout re-measure on the next paint by clearing the
    // cached size — `DigitalTextPainter` will re-fill it on first
    // paint since the underlying TextPainter inside
    // `DigitalTextElement` is invalidated through `copyWith`.
    node.cachedTextSize = Size.zero;
    _history?.push(_UpdateTextOp(id, before, next));
    // Bump the parent layer's content version so the LayerPictureCache
    // discards its cached `ui.Picture` (which still draws the old
    // text). Without this, the painter keeps replaying the stale
    // cache and the new text only appears the next time some other
    // mutation (stroke push, layer change) bumps the version.
    final parent = node.parent;
    if (parent is LayerNode) {
      _bumpLayerVersion(parent.id);
    }
    _commitTick.notify();
    return true;
  }

  /// Test-only view of the selectable-node index. Mirrors the
  /// internal map; mutating the returned set has no effect on the
  /// canvas. Used by `selectable_nodes_index_test.dart` to assert
  /// invariants after mutations.
  @visibleForTesting
  Set<NodeId> get debugSelectableIds => _selectableNodes.keys.toSet();

  /// Look up a selectable node (stroke, image, text, …) by [id]
  /// without exposing the private index. Returns `null` when the id
  /// is unknown or the node is no longer attached.
  CanvasNode? findNode(NodeId id) => _selectableNodes[id];

  /// Test-only Z-order snapshot. Higher value = front-most. Holes are
  /// allowed (single-insert paths bump the max; rebuilds compact).
  @visibleForTesting
  Map<NodeId, int> get debugZOrderIndex =>
      Map<NodeId, int>.unmodifiable(_zOrderIndex);

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

  final Map<NodeId, FlueraBlendMode> _extendedBlendModes =
      <NodeId, FlueraBlendMode>{};

  /// Per-layer mask images (`ui.Image` in straight-alpha space, R-channel
  /// is read as the canonical alpha by the GPU compositor and as
  /// `BlendMode.dstIn` source by the canvas-core fallback). Keyed by
  /// the owning [LayerNode]'s id; absent entry === no mask.
  ///
  /// The state OWNS the images — calling [setLayerMask] with a fresh
  /// image disposes the previous one; `dispose()` on this state also
  /// frees every entry. Consumers must NOT dispose images they passed
  /// in once they're handed over.
  final Map<NodeId, ui.Image> _layerMasks = <NodeId, ui.Image>{};

  /// Per-layer color tags for the layer panel UI. Optional metadata —
  /// the renderer ignores it. Use [setLayerColorTag] to assign a tag
  /// (typically a small palette color: red / orange / green / blue
  /// / purple / no tag). Wired into the premium layer panel UX.
  final Map<NodeId, Color> _layerColorTags = <NodeId, Color>{};

  /// Lookup the color tag for layer [id], or `null` if none.
  Color? layerColorTagFor(NodeId id) => _layerColorTags[id];

  /// Set or clear the color tag of layer [id]. Pass `null` to clear.
  /// Returns `true` when a layer with [id] existed.
  bool setLayerColorTag(NodeId id, Color? color) {
    if (_findLayer(id) == null) return false;
    if (color == null) {
      _layerColorTags.remove(id);
    } else {
      _layerColorTags[id] = color;
    }
    _commitTick.notify();
    return true;
  }

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
  /// Lookup the mask image for [id], or `null` if the layer has none.
  /// The image lives until [setLayerMask]`(id, null)` is called or the
  /// canvas state is disposed. Do not dispose the returned image — the
  /// state owns its lifetime.
  ui.Image? layerMaskFor(NodeId id) => _layerMasks[id];

  /// Attach (or replace) the alpha mask of layer [id]. Pass `null` to
  /// remove an existing mask. Returns `true` when a layer with [id]
  /// existed (mask attached / cleared), `false` when [id] is unknown.
  ///
  /// The previous mask image is disposed by this method — callers
  /// must hand over ownership of [mask]. To pre-create a mask in
  /// memory, render a layer thumbnail at full layer-rect size with
  /// [renderLayerThumbnail], then transform the resulting image
  /// (e.g. via `Picture.toImageSync`) before passing it here.
  bool setLayerMask(NodeId id, ui.Image? mask) {
    if (_findLayer(id) == null) return false;
    final previous = _layerMasks[id];
    if (mask == null) {
      _layerMasks.remove(id);
    } else {
      _layerMasks[id] = mask;
    }
    if (previous != null && previous != mask) {
      previous.dispose();
    }
    _bumpLayerVersion(id);
    _commitTick.notify();
    return true;
  }

  /// API element `setLayerFlueraBlendMode`.
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
    _bumpLayerVersion(id);
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
    final insertedIndex = _rootLayer.children
        .whereType<LayerNode>()
        .toList()
        .indexOf(layer);
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
    // can re-insert each stroke at its original Z-position. Build a
    // single index map up front so the snapshot loop is O(K) instead
    // of O(K × N).
    final indexByStroke = _flatStrokeIndexMap();
    final snapshots = _snapshotLayerStrokes(target, indexByStroke);
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
    // Drop every selectable node that lived on the removed layer
    // (strokes, images, future text/shape) — `_RemoveLayerOp` will
    // re-register them on undo via `_rebuildSelectableIndex`.
    _rebuildSelectableIndex();
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
      _bumpLayerVersion(id);
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
      _bumpLayerVersion(id);
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
      // Lock state doesn't change pixels but it gates draw / erase
      // behaviour; bumping the version is harmless and keeps the
      // cache invariant trivially correct.
      _bumpLayerVersion(id);
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
      _bumpLayerVersion(id);
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

  /// Merge the layer with [id] into the layer immediately below it
  /// (lower in the children list, i.e. painted earlier). The strokes
  /// of the upper layer are appended to the children of the lower
  /// layer in their existing Z-order; the upper layer is removed.
  ///
  /// Returns `true` on success. `false` when:
  ///   • [id] does not match any layer, or
  ///   • [id] is already at the bottom (no layer below to merge into),
  ///   • the bottom layer is locked (would silently mutate locked
  ///     content — refused so the user can unlock first).
  ///
  /// Trade-off note: a Photoshop-grade extended blend mode on the
  /// upper layer is **not preserved** by the merge — after the merge
  /// every stroke paints with `srcOver` into the destination layer.
  /// Consumers that need to lock in the visual blend should rasterize
  /// the layer first (via [renderLayerThumbnail] at viewport size) and
  /// commit the result as a future ImageNode. This MVP keeps strokes
  /// vector for further editing.
  bool mergeDown(NodeId id) {
    final layers = _rootLayer.children.whereType<LayerNode>().toList();
    if (layers.length <= 1) return false;
    int upperIdx = -1;
    for (int i = 0; i < layers.length; i++) {
      if (layers[i].id == id) {
        upperIdx = i;
        break;
      }
    }
    // The bottom layer (index 0) has nothing under it.
    if (upperIdx <= 0) return false;
    final upper = layers[upperIdx];
    final lower = layers[upperIdx - 1];
    if (lower.isLocked) return false;

    // Snapshot stroke nodes + their flat-list positions BEFORE moving
    // them so undo can rebuild both the upper layer header and the
    // exact Z-order. We move stroke-nodes wholesale (no clone) so
    // pictures stay cached and the ui.Picture instances aren't
    // re-recorded on undo.
    final indexByStroke = _flatStrokeIndexMap();
    final flatSnapshots = _snapshotLayerStrokes(upper, indexByStroke);
    final movedNodes = flatSnapshots.map((s) => s.node).toList(growable: false);

    // Detach from upper, append to lower in the same relative order.
    for (final node in movedNodes) {
      upper.remove(node);
      lower.add(node);
    }
    // Refresh the flat-list ordering: after merge the moved strokes
    // sit at the back of `lower`'s children, which is the correct Z
    // for "painted on top of lower's existing strokes". The flat
    // _strokes list is rebuilt from scratch by walking layers in
    // paint order — keeps the spatial index untouched (entries are
    // already valid; only the iteration order changes).
    _rebuildFlatStrokesFromLayers();

    final activeWasUpper = _activeLayer == upper;
    _rootLayer.remove(upper);
    if (activeWasUpper) {
      _activeLayer = lower;
    }
    // Drop side-table entry — extended blend mode no longer applies
    // (upper is gone; lower keeps its own mode unchanged).
    _extendedBlendModes.remove(upper.id);

    _history?.push(
      _MergeDownOp(upper, upperIdx, flatSnapshots, activeWasUpper),
    );
    _commitTick.notify();
    return true;
  }

  /// Collapse every visible layer into the bottom one. Hidden layers
  /// are dropped (matches Photoshop's `Image > Flatten Image`
  /// behaviour). The bottom layer keeps its name / opacity / blend
  /// mode; every stroke from the layers above is appended to it in
  /// paint order. Returns `true` if anything actually changed.
  bool flatten() {
    final layers = _rootLayer.children.whereType<LayerNode>().toList();
    if (layers.length <= 1) {
      // Even a single layer can have hidden state to drop, but with
      // exactly one layer there is nothing to flatten *into* — the
      // hidden case is handled by [setLayerVisible] elsewhere.
      return false;
    }

    final bottom = layers.first;
    if (bottom.isLocked) return false;

    // Build a per-source-layer snapshot pack so undo can put every
    // stroke back on its original layer at its original Z-order.
    final snapshots = <_FlattenLayerSnapshot>[];
    final flueraOnDrop = <NodeId, FlueraBlendMode>{};

    // Single index map shared across every source layer — all reads
    // happen before any list mutation, so the indices stay valid.
    final indexByStroke = _flatStrokeIndexMap();

    // Iterate top-to-bottom in paint order; for each non-bottom
    // layer collect its strokes + drop the layer.
    for (int i = 1; i < layers.length; i++) {
      final src = layers[i];
      final srcSnaps = _snapshotLayerStrokes(src, indexByStroke);
      // Visible layers contribute strokes to the bottom; hidden
      // layers are tracked for undo but their strokes are also
      // dropped from the live scene during flatten.
      if (src.isVisible) {
        for (final snap in srcSnaps) {
          src.remove(snap.node);
          bottom.add(snap.node);
        }
      } else {
        for (final snap in srcSnaps) {
          src.remove(snap.node);
          _spatialIndex.remove(snap.stroke);
          _strokeToNode.remove(snap.stroke);
        }
      }
      snapshots.add(
        _FlattenLayerSnapshot(layer: src, originalIndex: i, strokes: srcSnaps),
      );
      // Track extended-mode entry so undo can re-register it.
      final extOnSrc = _extendedBlendModes.remove(src.id);
      if (extOnSrc != null) flueraOnDrop[src.id] = extOnSrc;
      _rootLayer.remove(src);
    }

    final activeWasNonBottom = _activeLayer != bottom;
    _activeLayer = bottom;
    _rebuildFlatStrokesFromLayers();
    _history?.push(_FlattenOp(snapshots, flueraOnDrop, activeWasNonBottom));
    _commitTick.notify();
    return true;
  }

  /// Rasterize a single [layer] (or layer ID) into a small `ui.Image`
  /// suitable for a layer-panel thumbnail. The render covers the
  /// bounding box of every stroke on the layer; an empty layer
  /// returns an empty transparent image of the requested [size].
  ///
  /// Synchronous (uses `Picture.toImageSync`) — safe to call from a
  /// `build()` method but avoid running it on every frame; cache the
  /// returned image alongside a `Listenable` (e.g. `layerChanges`).
  ///
  /// Caller owns the returned image — call `.dispose()` when the
  /// thumbnail is replaced.
  ui.Image renderLayerThumbnail(NodeId id, ui.Size size) {
    final layer = _findLayer(id);
    final w = size.width.ceil();
    final h = size.height.ceil();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    );
    if (layer == null || layer.children.isEmpty) {
      return recorder.endRecording().toImageSync(w, h);
    }

    // Compute the bounding box of every stroke so the thumbnail
    // shows the layer's content "fit-to-bounds" rather than a
    // potentially-empty viewport crop.
    Rect? bounds;
    for (final c in layer.children) {
      if (c is CanvasStrokeNode) {
        for (final p in c.stroke.points) {
          if (bounds == null) {
            bounds = Rect.fromLTRB(p.dx, p.dy, p.dx, p.dy);
          } else {
            bounds = Rect.fromLTRB(
              math.min(bounds.left, p.dx),
              math.min(bounds.top, p.dy),
              math.max(bounds.right, p.dx),
              math.max(bounds.bottom, p.dy),
            );
          }
        }
      }
    }
    if (bounds == null || bounds.width == 0 || bounds.height == 0) {
      return recorder.endRecording().toImageSync(w, h);
    }
    // Inflate slightly to leave room for stroke widths.
    bounds = bounds.inflate(8);

    // Fit-uniform: pick the smaller scale so the whole layer fits.
    final scaleX = w / bounds.width;
    final scaleY = h / bounds.height;
    final scale = math.min(scaleX, scaleY);
    final tx = (w - bounds.width * scale) / 2 - bounds.left * scale;
    final ty = (h - bounds.height * scale) / 2 - bounds.top * scale;
    canvas.translate(tx, ty);
    canvas.scale(scale);

    for (final c in layer.children) {
      if (c is CanvasStrokeNode) {
        canvas.drawPicture(c.stroke.picture());
      }
    }
    return recorder.endRecording().toImageSync(w, h);
  }

  /// Internal: rebuild the flat `_strokes` mirror from the current
  /// layer-tree paint order. Used by [mergeDown] / [flatten] which
  /// move stroke-nodes between layers without touching the spatial
  /// index. The spatial index entries stay valid (each stroke still
  /// keys itself); only the linear iteration order is refreshed.
  void _rebuildFlatStrokesFromLayers() {
    _strokes.clear();
    for (final layer in _rootLayer.children.whereType<LayerNode>()) {
      for (final node in layer.children.whereType<CanvasStrokeNode>()) {
        _strokes.add(node.stroke);
      }
    }
  }

  /// O(N) reverse index of every stroke's position in the flat mirror.
  /// Used by the layer-op snapshot loops in [removeLayer] / [mergeDown]
  /// / [flatten] so collecting per-layer snapshots is O(K) per layer
  /// instead of O(K × N) — without this map every `_strokes.indexOf`
  /// call inside the loop was an O(N) scan, making bulk-merge of a
  /// large scene quadratic.
  Map<CanvasStroke, int> _flatStrokeIndexMap() {
    final map = <CanvasStroke, int>{};
    for (int i = 0; i < _strokes.length; i++) {
      map[_strokes[i]] = i;
    }
    return map;
  }

  /// Build a [_LayerStrokeSnapshot] list for every `CanvasStrokeNode`
  /// child of [layer], pulling positions from [indexByStroke]. Strokes
  /// not present in the flat mirror are skipped (defensive — should
  /// never happen for a healthy state, but matches the pre-helper
  /// behaviour of the snapshot loops).
  List<_LayerStrokeSnapshot> _snapshotLayerStrokes(
    LayerNode layer,
    Map<CanvasStroke, int> indexByStroke,
  ) {
    final out = <_LayerStrokeSnapshot>[];
    for (final c in layer.children) {
      if (c is CanvasStrokeNode) {
        final flatIdx = indexByStroke[c.stroke] ?? -1;
        if (flatIdx >= 0) {
          out.add(
            _LayerStrokeSnapshot(stroke: c.stroke, node: c, flatIndex: flatIdx),
          );
        }
      }
    }
    return out;
  }

  LayerNode? _findLayer(NodeId id) {
    for (final l in _rootLayer.children.whereType<LayerNode>()) {
      if (l.id == id) return l;
    }
    return null;
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  /// Serialize the canvas to a compact little-endian byte array. Persist
  /// this with the storage of your choice (files, Hive, SQLite blob,
  /// REST upload, …). Restore later via [loadFromBytes].
  ///
  /// 0.6.1+: writes FCV0 v3 — the full layer hierarchy (id, name,
  /// opacity, blend mode, visibility, lock state) round-trips, plus
  /// the canvas-state side-table for Photoshop-grade extended blend
  /// modes (`FlueraBlendMode` codes 100..108). Camera state, undo
  /// history, the background pattern and the live stroke are runtime
  /// state and are NOT included.
  Uint8List toBytes() => CanvasSerializer.encodeBytesFromLayers(
    _rootLayer,
    extendedCodes: _extendedBlendModes,
  );

  /// Replace the current scene with the layers decoded from [bytes].
  /// The undo history is cleared. Throws [FormatException] on bad input.
  ///
  /// Layer-aware: V2 / V3 files restore the full hierarchy; V1 files
  /// surface as a single synthetic "Layer 1". V3 files also restore
  /// the extended-blend-mode side-table.
  void loadFromBytes(Uint8List bytes) {
    final result = CanvasSerializer.decodeBytesFull(bytes);
    _replaceWithLayers(result.root, result.extendedCodes);
    _hydrateImageBlobs(result.imageBlobs);
  }

  /// Kick off async decode of every image blob carried by a v4+ file.
  /// `ImageNodePainter.decodeAndCache` registers the resulting
  /// `ui.Image` in the process-wide cache; we trigger one repaint per
  /// completed decode so the canvas re-renders with the freshly-bound
  /// asset. Fire-and-forget on purpose — `loadFromBytes` keeps a sync
  /// signature and the visual delay is at most one frame per image.
  void _hydrateImageBlobs(Map<String, Uint8List> blobs) {
    if (blobs.isEmpty) return;
    for (final entry in blobs.entries) {
      ImageNodePainter.decodeAndCache(entry.key, entry.value).then((image) {
        if (image == null) return;
        if (!mounted) return;
        _commitTick.notify();
      });
    }
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

  /// Replace the current scene with [loadedRoot] (full layer hierarchy)
  /// and restore the [codes] side-table. Used by [loadFromBytes] and the
  /// `initialBytes` constructor parameter to honour FCV0 v2 / v3 files
  /// without flattening into a single layer.
  void _replaceWithLayers(
    LayerNode loadedRoot,
    Map<NodeId, FlueraBlendMode> codes,
  ) {
    // Tear down current scene. Dispose old stroke pictures; we drop the
    // old layer tree wholesale and build a fresh one from `loadedRoot`.
    final disposeList = List<CanvasStroke>.from(_strokes);
    _internalClear();
    for (final s in disposeList) {
      s.dispose();
    }
    // Drop side-tables keyed by the layer ids we are about to discard.
    // Mask images are state-owned (see [setLayerMask]) so dispose them
    // here — otherwise each `loadFromBytes` would leak GPU textures
    // for the masks of the layers that are being replaced.
    _extendedBlendModes.clear();
    _disposeAllMasks();
    _layerColorTags.clear();

    // Detach loaded layers from `loadedRoot` (which itself is a freshly
    // synthesized container) and attach them to our own _rootLayer so
    // every existing reference to `_rootLayer` keeps pointing at a live
    // node. The serializer doesn't preserve the root's NodeId — only
    // the per-layer hierarchy below it — so adopting children is safe.
    final loadedLayers = loadedRoot.children.whereType<LayerNode>().toList(
      growable: false,
    );
    // Drop our existing default layer(s) but keep `_rootLayer` itself.
    final existing = _rootLayer.children.whereType<LayerNode>().toList(
      growable: false,
    );
    for (final l in existing) {
      _rootLayer.remove(l);
    }
    // Adopt each loaded layer (detach from synthetic root, attach here).
    for (final l in loadedLayers) {
      // Detach from synthetic loadedRoot first.
      loadedRoot.remove(l);
      // Re-strip any stroke children: we own the flat-mirror invariant
      // and rebuild it via _internalInsertStrokeAt below, so the layer
      // arrives empty and we re-insert each stroke-node onto it.
      final preloadedStrokes = l.children.whereType<CanvasStrokeNode>().toList(
        growable: false,
      );
      for (final n in preloadedStrokes) {
        l.remove(n);
      }
      _rootLayer.add(l);
      // Re-insert the strokes onto this layer via the canonical path so
      // _strokes / _spatialIndex / _strokeToNode stay in sync. We do it
      // here instead of via `_internalInsertStrokeAt` (which targets
      // `_activeLayer`) because we want strokes to land back on their
      // original layer.
      _activeLayer = l;
      for (final n in preloadedStrokes) {
        _strokeToNode[n.stroke] = n;
        _strokes.add(n.stroke);
        _spatialIndex.insert(n.stroke);
        l.add(n);
      }
    }

    // Pick the topmost (last inserted) layer as active — matches user
    // expectation when re-opening a saved file: drawing continues on
    // the layer that was on top.
    final layers = _rootLayer.children.whereType<LayerNode>().toList();
    if (layers.isEmpty) {
      // Pathological: file had no layers. Re-create the default one so
      // subsequent draws have a target.
      final blank = LayerNode(id: NodeId(generateUid()), name: 'Layer 1');
      _rootLayer.add(blank);
      _activeLayer = blank;
    } else {
      _activeLayer = layers.last;
    }

    _extendedBlendModes.addAll(codes);

    // Walk the freshly-adopted tree to (re)populate the selection /
    // Z-order index in one O(N) pass. Patching incrementally inside
    // the layer-adoption loop above would be brittle — a global
    // rebuild after structural mutations is the cleanest invariant.
    _rebuildSelectableIndex();

    _livePoints = null;
    _livePressures = null;
    _commitTick.notify();
    _history?.clear();
  }

  /// Rasterize the canvas to a `ui.Image`, with infinite-canvas-aware
  /// bounds resolution.
  ///
  /// **Bounds modes**:
  /// - [FlueraExportBounds.viewport] (default, legacy) — rasterize
  ///   exactly what the user sees on screen. Output dimensions =
  ///   `width × height` (in logical pixels). `width` / `height` MUST
  ///   be passed; `pixelRatio` and `padding` are ignored.
  /// - [FlueraExportBounds.allContent] — rasterize the union of every
  ///   visible node's `worldBounds`. Output dimensions are auto-computed
  ///   from the content size × `pixelRatio`. Returns a 1×1 sentinel
  ///   image when the canvas is empty.
  /// - [FlueraExportBounds.selection] — rasterize the bounding rect of
  ///   the current selection. Returns a 1×1 sentinel image when the
  ///   selection is empty.
  /// - [FlueraExportBounds.custom] — rasterize the world-space rect
  ///   passed via [region].
  ///
  /// **Common parameters** (apply to non-viewport modes):
  /// - [pixelRatio] (default `1.0`) — output is `worldRect × pixelRatio`
  ///   pixels. Use `2.0` / `3.0` for HiDPI / print export.
  /// - [padding] (default `0`, world-px) — extra margin around the
  ///   resolved world rect before rasterising.
  /// - [transparent] (default `false`) — when `true`, skip the
  ///   solid-colour background fill AND any background pattern
  ///   (grid / dotted / lined). Useful when exporting with a
  ///   transparent PNG alpha channel.
  Future<ui.Image> renderToImage({
    int? width,
    int? height,
    FlueraExportBounds bounds = FlueraExportBounds.viewport,
    Rect? region,
    double pixelRatio = 1.0,
    double padding = 0,
    bool transparent = false,
  }) async {
    // Sanity clamp on pixelRatio. 0.001 would round subwoofer outputs
    // to zero; > 32 with even a moderate viewport would allocate
    // gigabytes (a 1920×1080 viewport at ratio 32 is 1.97 GB just for
    // the bitmap). Hard cap at 32 — that's already 4×-print-DPI for a
    // 1080p source.
    if (pixelRatio < 0.05 || pixelRatio > 32.0) {
      throw ArgumentError(
        'renderToImage: pixelRatio $pixelRatio out of range [0.05, 32.0].',
      );
    }
    // ── Resolve the world rect to rasterise + the output pixel size.
    late Rect worldRect;
    late int outW;
    late int outH;
    switch (bounds) {
      case FlueraExportBounds.viewport:
        if (width == null || height == null) {
          throw ArgumentError(
            'renderToImage(bounds: viewport, …) requires both `width` '
            'and `height`.',
          );
        }
        // Camera-aware: map the screen viewport back into world coords.
        // The legacy code path bakes the camera transform into the
        // canvas — we keep the same behaviour by snapshotting world
        // coordinates that, after the scale/translate below, paint
        // exactly the same pixels the user sees.
        final scale = _controller.scale;
        final off = _controller.offset;
        worldRect = Rect.fromLTWH(
          -off.dx / scale,
          -off.dy / scale,
          width / scale,
          height / scale,
        );
        outW = width;
        outH = height;
        break;
      case FlueraExportBounds.allContent:
        var content = contentBoundsWorld;
        if (content.isEmpty) {
          // Sentinel: canvas is empty. Return a 1×1 transparent / bg
          // image so callers don't have to special-case null.
          return _emptyExportImage(transparent);
        }
        if (padding > 0) content = content.inflate(padding);
        worldRect = content;
        outW = math.max(1, (content.width * pixelRatio).round());
        outH = math.max(1, (content.height * pixelRatio).round());
        break;
      case FlueraExportBounds.selection:
        var sel = selectionBoundsWorld;
        if (sel.isEmpty) {
          return _emptyExportImage(transparent);
        }
        if (padding > 0) sel = sel.inflate(padding);
        worldRect = sel;
        outW = math.max(1, (sel.width * pixelRatio).round());
        outH = math.max(1, (sel.height * pixelRatio).round());
        break;
      case FlueraExportBounds.custom:
        if (region == null || region.isEmpty) {
          throw ArgumentError(
            'renderToImage(bounds: custom, …) requires a non-empty '
            '`region` (world-space Rect).',
          );
        }
        var r = region;
        if (padding > 0) r = r.inflate(padding);
        worldRect = r;
        outW = math.max(1, (r.width * pixelRatio).round());
        outH = math.max(1, (r.height * pixelRatio).round());
        break;
    }

    // Reject pathological output sizes BEFORE allocating the texture
    // (16 384 px is the GPU max on most platforms). A user request for
    // 1 GB+ of bitmap is almost certainly a configuration bug.
    const maxDim = 16384;
    if (outW > maxDim || outH > maxDim) {
      throw ArgumentError(
        'renderToImage: requested output size $outW×$outH exceeds '
        'GPU max ($maxDim per side). Lower pixelRatio or shrink region.',
      );
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Background fill + pattern (skip when caller wants transparency).
    if (!transparent) {
      canvas.drawRect(
        Offset.zero & Size(outW.toDouble(), outH.toDouble()),
        Paint()..color = widget.background.fill,
      );
    }

    // Map world coords directly onto the output bitmap. Order:
    //   1. scale to fit world rect into output pixels,
    //   2. translate so worldRect.topLeft sits at output (0, 0).
    canvas.save();
    canvas.scale(outW / worldRect.width, outH / worldRect.height);
    canvas.translate(-worldRect.left, -worldRect.top);

    if (!transparent) {
      // Background pattern (grid / dotted / lined / paper) honours the
      // exported world rect, not the camera-aligned full screen.
      widget.background.paint(canvas, worldRect, outW / worldRect.width);
    }

    // Polymorphic walk: dispatch every layer's children through the
    // same painters the on-screen committed painter uses, so image,
    // text, shape and grouped nodes are honoured (the legacy
    // implementation iterated `_strokes` only and silently dropped
    // every non-stroke node).
    _paintAllNodesInto(canvas);

    canvas.restore();
    final picture = recorder.endRecording();
    return picture.toImage(outW, outH);
  }

  /// 1×1 sentinel returned by `renderToImage` when the requested
  /// bounds resolve to an empty rect (empty canvas / empty selection).
  /// Lets callers safely await + decode the image without a null check.
  Future<ui.Image> _emptyExportImage(bool transparent) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (!transparent) {
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 1, 1),
        Paint()..color = widget.background.fill,
      );
    }
    final picture = recorder.endRecording();
    return picture.toImage(1, 1);
  }

  /// Walk every visible layer's children and dispatch each node to
  /// its painter. Mirror of `_CommittedStrokesPainter._paintLayerChildren`
  /// without the viewport cull and without the LayerPictureCache —
  /// the export needs every node and a clean record (a stale cached
  /// `ui.Picture` would leak).
  void _paintAllNodesInto(Canvas canvas) {
    for (final layer in _rootLayer.children.whereType<LayerNode>()) {
      if (!layer.isVisible) continue;
      final needsLayer =
          layer.opacity < 1.0 || layer.blendMode != ui.BlendMode.srcOver;
      if (needsLayer) {
        canvas.saveLayer(
          null,
          Paint()
            ..color = Color.fromRGBO(0, 0, 0, layer.opacity)
            ..blendMode = layer.blendMode,
        );
      }
      for (final child in layer.children) {
        if (child is CanvasStrokeNode) {
          _drawStrokeWithTransform(canvas, child.stroke);
        } else if (child is ImageNode) {
          ImageNodePainter.paint(canvas, child);
        } else if (child is TextNode) {
          paintTextNodeInto(canvas, child);
        }
        // Other CanvasNode subtypes (ShapeNode, GroupNode without
        // text/image children) are not painted by the free core
        // painter — they're scene-graph primitives consumed by the
        // commercial canvas_gpu pipeline. Skip silently to keep the
        // export deterministic.
      }
      if (needsLayer) {
        canvas.restore();
      }
    }
  }

  /// Public seam for painting a [TextNode] at its current
  /// `localTransform`. Used by [renderToImage] (via
  /// [_paintAllNodesInto]) and by the on-screen painter
  /// (`_CommittedStrokesPainter._paintTextNode`) — they MUST stay
  /// pixel-identical so the export matches what the user sees.
  void paintTextNodeInto(Canvas canvas, TextNode node) {
    final tp = node.textElement.layoutPainter;
    canvas.save();
    canvas.transform(node.localTransform.storage);
    tp.paint(canvas, node.textElement.position);
    canvas.restore();
    if (node.cachedTextSize != tp.size) {
      node.cachedTextSize = tp.size;
    }
  }

  /// Paint [s] into [canvas], honouring its scene-graph node's
  /// `localTransform` if non-identity. Hot path for the committed
  /// painter — the identity check spares a `save/transform/restore`
  /// triple for the >99% common case where strokes haven't been
  /// transformed yet.
  /// Mutate [node]'s `localTransform`, invalidate its cache, and
  /// keep [_nodesWithTransform] in sync with the identity-state
  /// transition. Single funnel for every transform mutation
  /// (`_applyTransform`, `mirrorSelection`, `_TransformNodesOp` undo /
  /// redo, `_onDrawCancel` rollback) so the painter fast path stays
  /// correct.
  void _writeLocalTransform(CanvasNode node, Matrix4 newMatrix) {
    // The node is leaving its previous worldBounds and arriving at a
    // new one — both regions are dirty (the old slot needs to clear,
    // the new slot needs to draw). Capture BEFORE invalidating so
    // worldBounds reflects the pre-transform state on the first read.
    _markDirty(node.worldBounds);
    final wasIdentity = node.isIdentityTransform;
    node.localTransform = newMatrix;
    node.invalidateTransformCache();
    _markDirty(node.worldBounds);
    final parent = node.parent;
    if (parent is LayerNode) {
      _bumpLayerVersion(parent.id);
    }
    final nowIdentity = node.isIdentityTransform;
    if (wasIdentity && !nowIdentity) {
      _nodesWithTransform++;
      _transformedNodeIds.add(node.id);
    } else if (!wasIdentity && nowIdentity) {
      _nodesWithTransform--;
      _transformedNodeIds.remove(node.id);
    }
  }

  void _drawStrokeWithTransform(Canvas canvas, CanvasStroke s) {
    // Hot path: when zero strokes carry a non-identity transform
    // (the >99% common case on notes-app workloads), skip the
    // `_strokeToNode[s]` map lookup entirely. The counter is
    // maintained by `_applyTransform` / `_endTransform` /
    // `mirrorSelection` / `_TransformNodesOp` / `_onDrawCancel` so
    // the invariant is "0 ⇒ no node has localTransform != identity".
    if (_nodesWithTransform == 0) {
      canvas.drawPicture(s.picture());
      return;
    }
    final node = _strokeToNode[s];
    if (node == null || node.isIdentityTransform) {
      canvas.drawPicture(s.picture());
      return;
    }
    canvas.save();
    canvas.transform(node.localTransform.storage);
    canvas.drawPicture(s.picture());
    canvas.restore();
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

    // Wrap the gesture detector in a LayoutBuilder so we always know
    // the gesture-area size — the edge-pan controller needs it to
    // figure out where the viewport edges are. Cheap (a single
    // build per resize event); the constraints rebuild propagates
    // ONLY into the small builder return, not the whole tree.
    Widget detector = LayoutBuilder(
      builder: (ctx, constraints) {
        _gestureViewportSize = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        return InfiniteCanvasGestureDetector(
          controller: _controller,
          onDrawStart: _onDrawStart,
          onDrawUpdate: _onDrawUpdate,
          onDrawEnd: _onDrawEnd,
          onDrawCancel: _onDrawCancel,
          child: gestureChild,
        );
      },
    );

    // Desktop cursor + eraser-hover preview. On mobile (Android / iOS) we
    // do NOT attach MouseRegion at all — stylus hover fires onHover
    // continuously and any setState would rebuild the tree on every
    // frame, invalidating the gesture arena before pointer-down is
    // claimed → touch events stop reaching the canvas.
    final isDesktopLike =
        kIsWeb ||
        (() {
          return PlatformGuard.isLinux ||
              PlatformGuard.isWindows ||
              PlatformGuard.isMacOS;
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
      onDeleteOrClear: () {
        // Selection-aware Delete: if something is selected, drop the
        // selection (idiomatic Notability / Figma); otherwise fall
        // back to the legacy "Delete clears the canvas" behaviour
        // (preserved for 0.5.x → 0.9.0 backward-compat).
        if (_selectionController.value.isNotEmpty) {
          deleteSelection();
        } else {
          clear();
        }
      },
      onEscape: () => _selectionController.clear(),
      onSelectAll: () {
        // Marquee everything visible by selecting all selectable
        // ids whose worldBounds aren't degenerate.
        final ids = <NodeId>{};
        for (final entry in _selectableNodes.entries) {
          final node = entry.value;
          final parent = node.parent;
          if (parent is LayerNode && (!parent.isVisible || parent.isLocked)) {
            continue;
          }
          ids.add(entry.key);
        }
        if (ids.isNotEmpty) {
          _selectionController.set(_selectionFromIds(ids));
        }
      },
      onDuplicate: () => duplicateSelection(),
      onNudge: (dx, dy) {
        if (_selectionController.value.isEmpty) return;
        final delta = TransformMath.translation(dx, dy);
        final ids = _selectionController.value.ids;
        final before = <NodeId, Matrix4>{};
        final after = <NodeId, Matrix4>{};
        for (final id in ids) {
          final node = _selectableNodes[id];
          if (node == null) continue;
          before[id] = node.localTransform.clone();
          final newM = delta.clone()..multiply(node.localTransform);
          _writeLocalTransform(node, newM);
          after[id] = newM.clone();
        }
        if (before.isNotEmpty) {
          _refreshSelectionBoundsAfterTransform();
          _commitTick.notify();
          _history?.push(_TransformNodesOp(before, after));
        }
      },
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
      case CanvasTool.image:
      case CanvasTool.lasso:
        return SystemMouseCursors.basic;
      case CanvasTool.text:
        return SystemMouseCursors.text;
    }
  }

  // ── Internal history hooks (invoked by _CanvasOp implementations) ────────

  /// Insert [s] at [index] in the flat list AND wrap it in a
  /// `CanvasStrokeNode` appended to [_activeLayer] at the equivalent
  /// position. Keeps the spatial index, the flat mirror and the scene
  /// graph atomically consistent.
  /// Walks `_rootLayer` DFS and rebuilds [_selectableNodes] +
  /// [_zOrderIndex] from scratch. Used after any operation that
  /// mutates the layer tree at a non-trivial scale (clear, load,
  /// remove layer, undo / redo of a multi-node op). For single-node
  /// inserts / removes the helpers below patch the index in place
  /// to avoid the O(N) walk.
  void _rebuildSelectableIndex() {
    _selectableNodes.clear();
    _zOrderIndex.clear();
    _nonStrokeSelectableIds.clear();
    _transformedNodeIds.clear();
    _nodesWithTransform = 0;
    var z = 0;
    void visit(CanvasNode node) {
      // Layers are pure containers — never selectable, always recurse
      // into them. Group nodes ARE selectable (the user selects a
      // group as a single unit, drag the whole thing); their children
      // become inert until ungrouped.
      if (node is LayerNode) {
        for (final c in node.children) {
          visit(c);
        }
        return;
      }
      if (node is GroupNode) {
        // Register the group itself, then DO NOT recurse — children
        // are addressable via the GroupNode.children but not via the
        // selectable index while grouped.
        _selectableNodes[node.id] = node;
        _zOrderIndex[node.id] = z++;
        _nonStrokeSelectableIds.add(node.id);
        if (!node.isIdentityTransform) {
          _transformedNodeIds.add(node.id);
          _nodesWithTransform++;
        }
        return;
      }
      // Leaf selectable node (stroke / image / text / shape …).
      _selectableNodes[node.id] = node;
      _zOrderIndex[node.id] = z++;
      if (node is! CanvasStrokeNode) {
        _nonStrokeSelectableIds.add(node.id);
      }
      if (!node.isIdentityTransform) {
        _transformedNodeIds.add(node.id);
        _nodesWithTransform++;
      }
    }

    visit(_rootLayer);
    _maxZ = z - 1;
  }

  /// Cheap incremental: register [node] as selectable and stamp its
  /// Z-order at the current top of the index. Used by single-insert
  /// paths; for batched ops or undo of multi-node ops, prefer
  /// [_rebuildSelectableIndex] which gets the Z-order globally
  /// consistent.
  void _registerSelectable(CanvasNode node) {
    _selectableNodes[node.id] = node;
    _maxZ += 1;
    _zOrderIndex[node.id] = _maxZ;
    if (node is! CanvasStrokeNode) {
      _nonStrokeSelectableIds.add(node.id);
    }
  }

  void _unregisterSelectable(NodeId id) {
    _selectableNodes.remove(id);
    _zOrderIndex.remove(id);
    _nonStrokeSelectableIds.remove(id);
  }

  void _internalInsertStrokeAt(int index, CanvasStroke s) {
    if (index < 0) index = 0;
    if (index > _strokes.length) index = _strokes.length;
    _strokes.insert(index, s);
    _spatialIndex.insert(s);
    _markDirty(s.bounds);
    _bumpLayerVersion(_activeLayer.id);
    final node =
        _strokeToNode[s] ??
        CanvasStrokeNode(id: NodeId(generateUid()), stroke: s);
    _strokeToNode[s] = node;
    _registerSelectable(node);
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
    _markDirty(s.bounds);
    _strokes.remove(s);
    _spatialIndex.remove(s);
    final node = _strokeToNode.remove(s);
    if (node != null) {
      _unregisterSelectable(node.id);
      if (node.parent is LayerNode) {
        final layer = node.parent! as LayerNode;
        layer.remove(node);
        _bumpLayerVersion(layer.id);
      }
    }
  }

  /// Remove the stroke node with the given [strokeNodeId]. Returns `true`
  /// if a matching stroke was found and removed; the canvas is repainted.
  ///
  /// This is the symmetric counterpart to [pushStroke] keyed by node id —
  /// it's used by `fluera_canvas_gpu` time-travel replay to apply
  /// `strokeRemoved` events without keeping a live `CanvasStroke`
  /// reference. Consumer code should generally rely on the higher-level
  /// erase / undo paths instead.
  bool removeStrokeById(NodeId strokeNodeId) {
    for (final entry in _strokeToNode.entries) {
      if (entry.value.id == strokeNodeId) {
        _internalRemoveStroke(entry.key);
        _commitTick.notify();
        return true;
      }
    }
    return false;
  }

  void _internalClear() {
    for (final s in _strokes) {
      _spatialIndex.remove(s);
    }
    _strokes.clear();
    _strokeToNode.clear();
    // Preserve layer structure (ids + visibility / opacity) — only
    // detach the stroke nodes. Image / text / shape children stay so
    // a partial "clear strokes" is a meaningful 0.7.0 op (the public
    // `clear()` invokes the historical _ClearOp which only snapshots
    // the flat strokes list anyway).
    for (final layer in _rootLayer.children.whereType<LayerNode>()) {
      final children = List<CanvasNode>.from(layer.children);
      for (final c in children) {
        if (c is CanvasStrokeNode) {
          layer.remove(c);
          _unregisterSelectable(c.id);
        }
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
  //   • smooth = false → straight `lineTo` segments. Used for shapes
  //     whose corners must stay sharp (rectangles, polygons).
  //   • smooth = true  → adaptive arc-length resampling (densifies
  //     long segments produced by fast strokes) → two-pass EMA
  //     pre-smoothing → Catmull-Rom → cubic-bezier chain.
  //
  // Why three stages: raw stylus input is a mix of (a) tremor at
  // slow speed (pixel-scale jitter every sample) AND (b) sparse
  // samples at high speed (10-30 px gaps between consecutive
  // points). One-Euro at the ingest stage tames (a). But (b) is the
  // killer — even a perfect spline through 5 widely-spaced points
  // looks like a polyline because there are simply not enough
  // anchors for the curve to bend through. The arc-length
  // resampling stage subdivides any gap larger than `_targetSpacing`
  // by linearly interpolating new anchors, then the EMA + Catmull-
  // Rom passes turn those collinear inserts into a smooth curve.
  if (n == 2 || !smooth) {
    final path = Path()..moveTo(points[0].dx, points[0].dy);
    for (int i = 1; i < n; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    final paint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = strokeWidth;
    canvas.drawPath(path, paint);
    return;
  }

  // ── Stage 1: arc-length subdivision via Catmull-Rom interpolation.
  // For every long gap between consecutive raw samples we insert new
  // anchors that lie ON the Catmull-Rom spline (derived from the
  // four neighbours p[i-1], p[i], p[i+1], p[i+2]), NOT on the
  // straight chord between them. This is the critical difference vs
  // a linear resample: linear inserts are collinear with the
  // existing samples, so the EMA pass below leaves them on the line
  // and the final cubic-bezier degenerates into the very polyline
  // we are trying to avoid. Spline-interpolated inserts already lie
  // on a curve, so the EMA + Catmull-Rom finishing passes refine an
  // already-smooth path. Endpoints preserved exactly. Cap inserts
  // per gap at 12 to bound cost on extreme jumps (pen-up/down).
  const double targetSpacing = 3.0;
  final dense = <Offset>[points[0]];
  for (int i = 0; i < n - 1; i++) {
    final p0 = points[i == 0 ? 0 : i - 1];
    final p1 = points[i];
    final p2 = points[i + 1];
    final p3 = points[i + 2 < n ? i + 2 : n - 1];
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist > targetSpacing * 1.5) {
      var inserts = (dist / targetSpacing).floor() - 1;
      if (inserts > 12) inserts = 12;
      for (int k = 1; k <= inserts; k++) {
        final t = k / (inserts + 1);
        final t2 = t * t;
        final t3 = t2 * t;
        // Standard uniform Catmull-Rom parametric form. At t=0 the
        // formula returns p1; at t=1 it returns p2 — so we only
        // emit the strict interior (k = 1..inserts) here and let
        // the next iteration of the loop append p2 (which is the
        // p1 of that next iteration, written below as `dense.add(p2)`).
        final cx = 0.5 *
            (2 * p1.dx +
                (-p0.dx + p2.dx) * t +
                (2 * p0.dx - 5 * p1.dx + 4 * p2.dx - p3.dx) * t2 +
                (-p0.dx + 3 * p1.dx - 3 * p2.dx + p3.dx) * t3);
        final cy = 0.5 *
            (2 * p1.dy +
                (-p0.dy + p2.dy) * t +
                (2 * p0.dy - 5 * p1.dy + 4 * p2.dy - p3.dy) * t2 +
                (-p0.dy + 3 * p1.dy - 3 * p2.dy + p3.dy) * t3);
        dense.add(Offset(cx, cy));
      }
    }
    dense.add(p2);
  }
  final m = dense.length;

  // ── Stage 2: two-pass EMA pre-smoothing (forward + backward).
  // Endpoints are pinned so the stroke starts and ends exactly where
  // the user lifted/dropped the pointer. The forward pass introduces
  // a directional bias (the smoothed line trails behind the input);
  // the backward pass cancels it.
  const double alpha = 0.3;
  final smoothed = List<Offset>.filled(m, Offset.zero);
  smoothed[0] = dense[0];
  for (int i = 1; i < m; i++) {
    smoothed[i] = Offset(
      smoothed[i - 1].dx * alpha + dense[i].dx * (1.0 - alpha),
      smoothed[i - 1].dy * alpha + dense[i].dy * (1.0 - alpha),
    );
  }
  smoothed[m - 1] = dense[m - 1];
  for (int i = m - 2; i > 0; i--) {
    smoothed[i] = Offset(
      smoothed[i + 1].dx * alpha + smoothed[i].dx * (1.0 - alpha),
      smoothed[i + 1].dy * alpha + smoothed[i].dy * (1.0 - alpha),
    );
  }

  // ── Stage 4: predicted "ghost" anchor for the terminal segment.
  // The Catmull-Rom formula uses `p3` to compute the exit tangent
  // at `p2`. For every interior segment `p3` is a real future
  // sample and the tangent is correct. For the LAST segment we
  // would normally clamp `p3 = smoothed[m-1]`, which makes the
  // final tangent flat (the curve aims at the endpoint along the
  // chord). Extrapolating one step ahead via velocity + half-
  // acceleration gives the spline a natural "pointer-following"
  // tangent that materially reduces the perceived latency on
  // platforms (Linux) where the input pipeline samples slowly.
  // The predicted point is NOT drawn — `cubicTo` still ends
  // exactly at the real `p2` — only the tangent at the last
  // anchor changes.
  Offset? predictedTail;
  if (m >= 3) {
    final pn1 = smoothed[m - 1];
    final pn2 = smoothed[m - 2];
    final pn3 = smoothed[m - 3];
    final vx = pn1.dx - pn2.dx;
    final vy = pn1.dy - pn2.dy;
    final ax = pn1.dx - 2 * pn2.dx + pn3.dx;
    final ay = pn1.dy - 2 * pn2.dy + pn3.dy;
    predictedTail = Offset(pn1.dx + vx + 0.5 * ax, pn1.dy + vy + 0.5 * ay);
  }

  // ── Stage 5: Catmull-Rom → Cubic Bezier with tau = 1/6 (the
  // tension fluera_engine's fountain-pen outline builder uses).
  // C1 = P1 + (P2 - P0) / 6, C2 = P2 - (P3 - P1) / 6 — the spline
  // passes through every smoothed point and is C¹-continuous
  // regardless of input density.
  const tau = 1.0 / 6.0;
  final path = Path()..moveTo(smoothed[0].dx, smoothed[0].dy);
  for (int i = 0; i < m - 1; i++) {
    final p0 = smoothed[i == 0 ? 0 : i - 1];
    final p1 = smoothed[i];
    final p2 = smoothed[i + 1];
    // For every interior segment use the real next-next sample.
    // For the terminal segment substitute the predicted ghost so
    // the closing tangent points along the pointer's trajectory
    // instead of flattening into the chord.
    final p3 =
        i + 2 < m
            ? smoothed[i + 2]
            : (predictedTail ?? smoothed[m - 1]);
    final c1 = Offset(
      p1.dx + (p2.dx - p0.dx) * tau,
      p1.dy + (p2.dy - p0.dy) * tau,
    );
    final c2 = Offset(
      p2.dx - (p3.dx - p1.dx) * tau,
      p2.dy - (p3.dy - p1.dy) * tau,
    );
    path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
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

  /// Walk a layer's children once and dispatch each to the right
  /// per-type painter. When [visibleSet] is `null`, every stroke is
  /// rendered (no viewport cull) — used by the LayerPictureCache
  /// recording path that captures the full layer once. When
  /// [visibleSet] is non-null, only strokes present in the set are
  /// drawn (the legacy fast path used while a transform is active
  /// or no cache is desired).
  void _paintLayerChildren(
    Canvas target,
    LayerNode layer,
    FlueraCanvasState state, {
    required Set<CanvasStroke>? visibleSet,
  }) {
    for (final child in layer.children) {
      if (child is CanvasStrokeNode) {
        if (visibleSet == null || visibleSet.contains(child.stroke)) {
          state._drawStrokeWithTransform(target, child.stroke);
        }
      } else if (child is ImageNode) {
        ImageNodePainter.paint(target, child);
      } else if (child is TextNode) {
        _paintTextNode(target, child);
      }
    }
  }

  /// Paint a [TextNode] honouring its `localTransform` so the live
  /// select / drag / rotate / scale pipeline (which mutates the
  /// matrix only) actually moves the visible glyphs. Without the
  /// `canvas.transform(...)` wrapper the text would always render
  /// at `textElement.position` regardless of selection-driven
  /// transforms.
  void _paintTextNode(Canvas target, TextNode node) {
    final tp = node.textElement.layoutPainter;
    target.save();
    target.transform(node.localTransform.storage);
    tp.paint(target, node.textElement.position);
    target.restore();
    if (node.cachedTextSize != tp.size) {
      node.cachedTextSize = tp.size;
    }
  }

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
    final layers =
        canvasState._rootLayer.children.whereType<LayerNode>().toList();
    final hasNonTrivialLayer =
        layers.length != 1 ||
        !layers.first.isVisible ||
        layers.first.opacity != 1.0 ||
        layers.first.blendMode != ui.BlendMode.srcOver;
    if (!hasNonTrivialLayer) {
      // Single trivial layer fast path. The LayerPictureCache kicks in
      // when no node carries a non-identity transform (the >99% case
      // on notes-app workloads): we replay one cached `ui.Picture`
      // instead of re-walking every child each paint. Pan / zoom
      // doesn't bump the layer version so the cache survives camera
      // moves entirely.
      final layer = layers.first;
      final layerVersion = canvasState._layerVersions[layer.id] ?? 0;
      final canCache = canvasState._nodesWithTransform == 0;

      ui.Picture? cached;
      if (canCache) {
        cached = canvasState._layerPictureCache.get(
          layer.id.value,
          layerVersion,
        );
      }
      if (cached != null) {
        canvas.drawPicture(cached);
      } else if (canCache) {
        // Cache miss — record the WHOLE layer (no viewport cull) into
        // a fresh PictureRecorder, store, then replay. Subsequent
        // paints take the fast path above. Skia clips out off-screen
        // pixels at GPU rasterisation, so recording the full layer
        // is a one-time cost amortised across many frames.
        final recorder = ui.PictureRecorder();
        final recordCanvas = ui.Canvas(recorder);
        _paintLayerChildren(recordCanvas, layer, canvasState, visibleSet: null);
        final picture = recorder.endRecording();
        canvasState._layerPictureCache.put(
          layer.id.value,
          layerVersion,
          picture,
        );
        canvas.drawPicture(picture);
      } else {
        // At least one node has a non-identity transform — caching
        // would snapshot stale world bounds, so fall back to the
        // viewport-culled walk.
        final visibleSet = <CanvasStroke>{};
        for (final s in visibleStrokes) {
          visibleSet.add(s);
        }
        _paintLayerChildren(canvas, layer, canvasState, visibleSet: visibleSet);
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

      // Detect if any visible layer is on an extended (Photoshop-grade)
      // blend mode AND the compositor opted into the backdrop-aware
      // path. Only then do we pay for the parallel "running backdrop"
      // recorder — otherwise stay on the cheap single-canvas path.
      final useBackdropPath =
          compositor != null &&
          compositor.supportsBackdropAwareBlend &&
          _anyExtendedLayer(layers, canvasState);

      // Parallel recorder used to keep a running backdrop image. We
      // mirror every layer paint into this recorder; when an extended
      // layer is reached the compositor consumes a snapshot of it.
      ui.PictureRecorder? bgRecorder;
      ui.Canvas? bgCanvas;
      if (useBackdropPath) {
        bgRecorder = ui.PictureRecorder();
        bgCanvas = ui.Canvas(bgRecorder, layerRect);
        // Match the camera transform of the main canvas so backdrop
        // pixels line up with foreground pixels in the shader.
        bgCanvas.translate(ctrl.offset.dx, ctrl.offset.dy);
        bgCanvas.scale(ctrl.scale);
      }

      // Output pixel size of every backdrop snapshot we hand to the
      // shader: the layerRect under the current camera, scaled by DPR.
      final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;

      for (final layer in layers) {
        if (!layer.isVisible) continue;
        // Walk children in insertion order so chronological Z-order is
        // honoured (a stroke added AFTER an image renders on top of
        // it). Skip layers with no visible content via an emptiness
        // probe over the same iteration.
        bool hasVisibleContent = false;
        for (final child in layer.children) {
          if (child is CanvasStrokeNode && visibleSet[child.stroke] == true) {
            hasVisibleContent = true;
            break;
          }
          if (child is ImageNode || child is TextNode) {
            hasVisibleContent = true;
            break;
          }
        }
        if (!hasVisibleContent) continue;
        // Cache the layer's foreground (children only — opacity /
        // blend / mask happen in the SAVELAYER wrapping this) into
        // a `ui.Picture` keyed on (layerId, layerVersion). Any
        // mutation that would change the foreground bumps the
        // version (insert/remove stroke, image, text, transform).
        // Camera changes never bump → cache survives pan/zoom.
        // Disabled when at least one node is currently transformed
        // (the snapshot would capture stale world bounds).
        final canCacheLayer = canvasState._nodesWithTransform == 0;
        ui.Picture? buildOrFetchCached() {
          if (!canCacheLayer) return null;
          final ver = canvasState._layerVersions[layer.id] ?? 0;
          final cached = canvasState._layerPictureCache.get(
            layer.id.value,
            ver,
          );
          if (cached != null) return cached;
          final recorder = ui.PictureRecorder();
          final recCanvas = ui.Canvas(recorder);
          // Record the FULL layer (no viewport cull) — Skia clips
          // off-screen pixels at GPU rasterisation, so paying the
          // recording cost once is amortised across many paints.
          for (final child in layer.children) {
            if (child is CanvasStrokeNode) {
              canvasState._drawStrokeWithTransform(recCanvas, child.stroke);
            } else if (child is ImageNode) {
              ImageNodePainter.paint(recCanvas, child);
            } else if (child is TextNode) {
              _paintTextNode(recCanvas, child);
            }
          }
          final picture = recorder.endRecording();
          canvasState._layerPictureCache.put(layer.id.value, ver, picture);
          return picture;
        }

        void paintLayer(ui.Canvas c) {
          final cached = buildOrFetchCached();
          if (cached != null) {
            c.drawPicture(cached);
            return;
          }
          // Fallback: a transformed node is in flight, walk children
          // with the legacy viewport-culled dispatch.
          for (final child in layer.children) {
            if (child is CanvasStrokeNode) {
              if (visibleSet[child.stroke] == true) {
                canvasState._drawStrokeWithTransform(c, child.stroke);
              }
            } else if (child is ImageNode) {
              ImageNodePainter.paint(c, child);
            } else if (child is TextNode) {
              _paintTextNode(c, child);
            }
          }
        }

        // Resolve the optional alpha mask. The compositor takes mask
        // in the GPU shader path; for the canvas-core fallback we
        // wrap `paintLayer` in a saveLayer + `BlendMode.dstIn` blit
        // of the mask image so the same visual rule (foreground
        // alpha multiplied by mask alpha) holds without any shader.
        final layerMask = canvasState._layerMasks[layer.id];
        void paintLayerWithMaskFallback(ui.Canvas c) {
          if (layerMask == null) {
            paintLayer(c);
            return;
          }
          c.saveLayer(layerRect, Paint());
          paintLayer(c);
          // dstIn keeps fg pixels only where mask alpha > 0.
          c.drawImageRect(
            layerMask,
            Rect.fromLTWH(
              0,
              0,
              layerMask.width.toDouble(),
              layerMask.height.toDouble(),
            ),
            layerRect,
            Paint()..blendMode = BlendMode.dstIn,
          );
          c.restore();
        }

        // Resolve the FlueraBlendMode from the canvas-state side-table.
        // When the layer is on a standard mode the side-table is empty
        // and we forward `null` for `extendedBlendModeCode`; when it is
        // on an extended mode we pass the stable code so the commercial
        // compositor can dispatch to a custom shader.
        final flueraMode = canvasState.flueraBlendModeFor(layer);
        final extCode = flueraMode.isExtended ? flueraMode.code : null;

        if (useBackdropPath && extCode != null) {
          // Backdrop-aware extended-blend path. Snapshot the running
          // backdrop, hand both backdrop + paintStrokes to the
          // compositor, then update the running backdrop with the
          // composited result so subsequent layers see it as their
          // own backdrop.
          final bgPicture = bgRecorder!.endRecording();
          final pxW = (layerRect.width * ctrl.scale * dpr).ceil();
          final pxH = (layerRect.height * ctrl.scale * dpr).ceil();
          // toImageSync rasterises in-thread, on the GPU surface — no
          // event-loop bounce, so it is safe to call from a paint pass.
          final bgImage = bgPicture.toImageSync(pxW, pxH);
          final fgPxSize = ui.Size(pxW.toDouble(), pxH.toDouble());

          // Prefer `blendExtendedToImage` so the result image can be
          // reused as the running backdrop for any subsequent extended
          // layer — that's what keeps a chain of extended modes
          // pixel-accurate instead of drifting onto the closest-
          // standard substitute at every chain step.
          final resultImage = compositor.blendExtendedToImage(
            opacity: layer.opacity,
            layerRect: layerRect,
            paintStrokes: paintLayer,
            extendedBlendModeCode: extCode,
            backdrop: bgImage,
            foregroundImageSize: fgPxSize,
            devicePixelRatio: dpr,
            mask: layerMask,
          );

          if (resultImage != null) {
            // ── Pixel-accurate chaining path ──────────────────────────
            // 1. Blit the shader output onto the user canvas.
            canvas.save();
            canvas.translate(layerRect.left, layerRect.top);
            canvas.scale(layerRect.width / pxW);
            canvas.drawImage(
              resultImage,
              Offset.zero,
              _alphaPaint(layer.opacity),
            );
            canvas.restore();
            // 2. Replace the running backdrop with the SAME result
            //    image (no closestStandard mirror). Subsequent
            //    extended layers now see the exact pixels the user
            //    sees, so the chain stays pixel-accurate.
            bgRecorder = ui.PictureRecorder();
            bgCanvas = ui.Canvas(bgRecorder, layerRect);
            bgCanvas.translate(ctrl.offset.dx, ctrl.offset.dy);
            bgCanvas.scale(ctrl.scale);
            bgCanvas.save();
            bgCanvas.scale(1.0 / (ctrl.scale * dpr));
            bgCanvas.translate(-ctrl.offset.dx * dpr, -ctrl.offset.dy * dpr);
            bgCanvas.drawImage(resultImage, Offset.zero, Paint());
            bgCanvas.restore();
            resultImage.dispose();
          } else {
            // Fallback path — compositor declined to return an image.
            // Unreachable when `supportsBackdropAwareBlend` is true,
            // but stays here as a safety net so a future compositor
            // can opt out of returning the image without breaking
            // rendering.
            compositor.compositeLayerExtended(
              canvas,
              opacity: layer.opacity,
              layerRect: layerRect,
              paintStrokes: paintLayer,
              extendedBlendModeCode: extCode,
              backdrop: bgImage,
              foregroundImageSize: fgPxSize,
              devicePixelRatio: dpr,
              mask: layerMask,
            );
            bgRecorder = ui.PictureRecorder();
            bgCanvas = ui.Canvas(bgRecorder, layerRect);
            bgCanvas.translate(ctrl.offset.dx, ctrl.offset.dy);
            bgCanvas.scale(ctrl.scale);
            bgCanvas.save();
            bgCanvas.scale(1.0 / (ctrl.scale * dpr));
            bgCanvas.translate(-ctrl.offset.dx * dpr, -ctrl.offset.dy * dpr);
            bgCanvas.drawImage(bgImage, Offset.zero, Paint());
            bgCanvas.restore();
            bgCanvas.saveLayer(
              layerRect,
              _alphaPaint(layer.opacity, flueraMode.closestStandard),
            );
            paintLayer(bgCanvas);
            bgCanvas.restore();
          }
          bgImage.dispose();
        } else if (compositor != null) {
          // Standard path through the compositor. Layer is either on
          // a `ui.BlendMode` (extCode == null) or the compositor did
          // not opt into the backdrop-aware path — in both cases the
          // canvas-core fallback (closestStandard) is acceptable.
          compositor.compositeLayer(
            canvas,
            opacity: layer.opacity,
            blendMode: layer.blendMode,
            layerRect: layerRect,
            paintStrokes: paintLayer,
            extendedBlendModeCode: extCode,
            mask: layerMask,
          );
          if (useBackdropPath) {
            // Mirror the paint into the running backdrop so the next
            // extended layer sees this layer's contribution. The
            // mask (if any) is applied via the dstIn fallback so
            // the running backdrop reflects the masked foreground.
            bgCanvas!.saveLayer(
              layerRect,
              _alphaPaint(layer.opacity, layer.blendMode),
            );
            paintLayerWithMaskFallback(bgCanvas);
            bgCanvas.restore();
          }
        } else {
          canvas.saveLayer(
            layerRect,
            _alphaPaint(layer.opacity, layer.blendMode),
          );
          paintLayerWithMaskFallback(canvas);
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

  /// True iff at least one of [layers] is on an extended (Photoshop-grade)
  /// blend mode in the canvas-state side-table. Short-circuits when the
  /// side-table is empty so the common case (no extended modes) avoids
  /// touching the per-layer blend lookup at all.
  bool _anyExtendedLayer(List<LayerNode> layers, FlueraCanvasState state) {
    if (state._extendedBlendModes.isEmpty) return false;
    for (final l in layers) {
      if (state.flueraBlendModeFor(l).isExtended) return true;
    }
    return false;
  }
}

/// Helper for the painter: build a `Paint` whose only effect is an alpha
/// multiplier. Used as the wrapping paint for `saveLayer` calls and for
/// the post-shader image blit — both forms repeat the same idiom enough
/// times that the inlined `Paint()..color = Color.fromRGBO(0, 0, 0, a)`
/// became noisy. Optional [blendMode] for the saveLayer-with-blend
/// variant.
ui.Paint _alphaPaint(double opacity, [ui.BlendMode? blendMode]) {
  final p = ui.Paint()..color = ui.Color.fromRGBO(0, 0, 0, opacity);
  if (blendMode != null) p.blendMode = blendMode;
  return p;
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
  _LiveStrokePainter({
    required this.strokeNotifier,
    required this.controller,
    required this.activeBlendMode,
    required this.activeOpacity,
    required Listenable layerSettingsTrigger,
  }) : super(
        repaint: Listenable.merge(<Listenable>[
          strokeNotifier,
          controller,
          layerSettingsTrigger,
        ]),
      );

  final _LiveStrokeNotifier strokeNotifier;
  final InfiniteCanvasController controller;

  /// Live ref-cell for the active layer's blend mode. Read at paint
  /// time so toggling `setLayerBlendMode` while a stroke is in flight
  /// updates the in-progress preview immediately.
  final ValueGetter<ui.BlendMode> activeBlendMode;

  /// Live ref-cell for the active layer's opacity (0..1).
  final ValueGetter<double> activeOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final pts = strokeNotifier.points;
    final prs = strokeNotifier.pressures;
    if (pts.length < 2 || prs.length != pts.length) return;

    // Honour the active layer's blend mode + opacity so the live
    // preview matches what the committed stroke will look like once
    // the user lifts the pen. Without this, drawing a `multiply` /
    // `screen` / etc. layer shows pure srcOver in flight and snaps
    // to the correct blend only at pen-up.
    final blend = activeBlendMode();
    final opacity = activeOpacity().clamp(0.0, 1.0);
    final needsLayer = blend != ui.BlendMode.srcOver || opacity < 1.0;
    if (needsLayer) {
      canvas.saveLayer(
        null,
        Paint()
          ..blendMode = blend
          ..color = Color.fromRGBO(0, 0, 0, opacity),
      );
    }

    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(controller.scale);

    // Bake any newly-arrived points into the cache. The closure is
    // invoked once per pending chunk by `maybeChunkAhead`.
    strokeNotifier.maybeChunkAhead((recCanvas, from, toInclusive) {
      final endExclusive = (toInclusive + 1).clamp(0, pts.length);
      final chunkPts = pts.sublist(from, endExclusive);
      final chunkPrs = prs.sublist(from, endExclusive);
      _paintStrokeSegments(
        recCanvas,
        chunkPts,
        chunkPrs,
        strokeNotifier.color,
        strokeNotifier.baseWidth,
        smooth: strokeNotifier.smooth,
      );
    });

    // Replay each cached chunk — one drawPicture per chunkSize range.
    for (final chunk in strokeNotifier.chunks) {
      canvas.drawPicture(chunk);
    }

    // Render the trailing uncached tail (shares its first point with
    // the last chunk so there is no visual seam). When no chunks
    // have been baked yet, this paints the whole stroke.
    final tailStart = strokeNotifier.chunkedThru;
    if (tailStart < pts.length - 1) {
      _paintStrokeSegments(
        canvas,
        pts.sublist(tailStart),
        prs.sublist(tailStart),
        strokeNotifier.color,
        strokeNotifier.baseWidth,
        smooth: strokeNotifier.smooth,
      );
    }
    canvas.restore();
    if (needsLayer) {
      canvas.restore(); // close the saveLayer
    }
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

  /// Append-only cache of the in-progress stroke. Once the stroke
  /// grows past [_chunkSize] new points, the painter calls
  /// [maybeChunkAhead] which records that range into a `ui.Picture`
  /// and appends to [_chunks]. Subsequent paints replay each chunk
  /// via `drawPicture` and only re-tessellate the trailing
  /// (uncached) tail. For long handwriting strokes this drops
  /// per-frame work from O(N) segments to O(K) where K = chunkSize.
  final List<ui.Picture> _chunks = <ui.Picture>[];
  int _chunkedThru = 0;
  static const int _chunkSize = 256;

  /// Read-only handle on the recorded chunks. The painter consumes
  /// them in order, then renders the trailing uncached points.
  List<ui.Picture> get chunks => _chunks;

  /// Index up to which the points list has been baked into
  /// [_chunks]. The tail (`points[chunkedThru..end]`) is rendered
  /// dynamically each paint. The shared boundary point keeps the
  /// stroke visually seamless across the cache split.
  int get chunkedThru => _chunkedThru;

  void beginStroke({
    required Color color,
    required double baseWidth,
    bool smooth = true,
  }) {
    this.color = color;
    this.baseWidth = baseWidth;
    this.smooth = smooth;
    _flushChunks();
  }

  void setStroke(List<Offset> pts, List<double> prs) {
    _flushChunks();
    points = pts;
    pressures = prs;
    notifyListeners();
  }

  /// Explicit notify after in-place add() on [points] / [pressures].
  void forceRepaint() => notifyListeners();

  void clear() {
    _flushChunks();
    points = const <Offset>[];
    pressures = const <double>[];
    notifyListeners();
  }

  void _flushChunks() {
    for (final p in _chunks) {
      p.dispose();
    }
    _chunks.clear();
    _chunkedThru = 0;
  }

  /// Drive the chunking. Called by the painter on every paint —
  /// when the points list has grown past [_chunkSize] beyond
  /// [_chunkedThru], record the next chunk via [recordRange] and
  /// advance the cursor. Loops until fewer than [_chunkSize] new
  /// points remain (multiple chunks can flush in one tick if the
  /// painter was idle for a while).
  void maybeChunkAhead(
    void Function(ui.Canvas canvas, int fromInclusive, int toInclusive)
    recordRange,
  ) {
    while (points.length - _chunkedThru > _chunkSize) {
      final from = _chunkedThru;
      // Cache `chunkSize` segments by capturing
      // `points[from..from+chunkSize]` (inclusive of both ends).
      // Sharing the boundary point with the next chunk / tail keeps
      // smoothing splines + variable-width polygons continuous.
      final toInclusive = from + _chunkSize;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      recordRange(canvas, from, toInclusive);
      _chunks.add(recorder.endRecording());
      _chunkedThru = toInclusive;
    }
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

class _KeyboardShortcuts extends StatelessWidget {
  const _KeyboardShortcuts({
    required this.focusNode,
    required this.onUndo,
    required this.onRedo,
    required this.onDeleteOrClear,
    required this.onEscape,
    required this.onSelectAll,
    required this.onDuplicate,
    required this.onNudge,
    required this.child,
  });

  final FocusNode focusNode;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onDeleteOrClear;
  final VoidCallback onEscape;
  final VoidCallback onSelectAll;
  final VoidCallback onDuplicate;
  final void Function(double dx, double dy) onNudge;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isMac = PlatformGuard.isMacOS || PlatformGuard.isIOS;
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
        const SingleActivator(LogicalKeyboardKey.delete):
            const _DeleteOrClearIntent(),
        const SingleActivator(LogicalKeyboardKey.backspace):
            const _DeleteOrClearIntent(),
        const SingleActivator(LogicalKeyboardKey.escape): const _EscapeIntent(),
        SingleActivator(LogicalKeyboardKey.keyA, control: !isMac, meta: isMac):
            const _SelectAllIntent(),
        SingleActivator(LogicalKeyboardKey.keyD, control: !isMac, meta: isMac):
            const _DuplicateIntent(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): const _NudgeIntent(
          -1,
          0,
        ),
        const SingleActivator(
          LogicalKeyboardKey.arrowRight,
        ): const _NudgeIntent(1, 0),
        const SingleActivator(LogicalKeyboardKey.arrowUp): const _NudgeIntent(
          0,
          -1,
        ),
        const SingleActivator(LogicalKeyboardKey.arrowDown): const _NudgeIntent(
          0,
          1,
        ),
        const SingleActivator(
          LogicalKeyboardKey.arrowLeft,
          shift: true,
        ): const _NudgeIntent(-10, 0),
        const SingleActivator(
          LogicalKeyboardKey.arrowRight,
          shift: true,
        ): const _NudgeIntent(10, 0),
        const SingleActivator(
          LogicalKeyboardKey.arrowUp,
          shift: true,
        ): const _NudgeIntent(0, -10),
        const SingleActivator(
          LogicalKeyboardKey.arrowDown,
          shift: true,
        ): const _NudgeIntent(0, 10),
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
          // Gate every action that would otherwise hijack a keystroke
          // the user is sending to the inline text editor. Backspace
          // / Delete must edit the buffer, not delete the canvas;
          // arrows must move the caret, not nudge a selection;
          // Ctrl+A must select-all-in-text, not all-on-canvas.
          _DeleteOrClearIntent: CallbackAction<_DeleteOrClearIntent>(
            onInvoke: (_) {
              if (FlueraTextEditor.isEditing) return null;
              onDeleteOrClear();
              return null;
            },
          ),
          _EscapeIntent: CallbackAction<_EscapeIntent>(
            onInvoke: (_) {
              onEscape();
              return null;
            },
          ),
          _SelectAllIntent: CallbackAction<_SelectAllIntent>(
            onInvoke: (_) {
              if (FlueraTextEditor.isEditing) return null;
              onSelectAll();
              return null;
            },
          ),
          _DuplicateIntent: CallbackAction<_DuplicateIntent>(
            onInvoke: (_) {
              if (FlueraTextEditor.isEditing) return null;
              onDuplicate();
              return null;
            },
          ),
          _NudgeIntent: CallbackAction<_NudgeIntent>(
            onInvoke: (intent) {
              if (FlueraTextEditor.isEditing) return null;
              onNudge(intent.dx, intent.dy);
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

class _DeleteOrClearIntent extends Intent {
  const _DeleteOrClearIntent();
}

class _EscapeIntent extends Intent {
  const _EscapeIntent();
}

class _SelectAllIntent extends Intent {
  const _SelectAllIntent();
}

class _DuplicateIntent extends Intent {
  const _DuplicateIntent();
}

class _NudgeIntent extends Intent {
  const _NudgeIntent(this.dx, this.dy);
  final double dx;
  final double dy;
}

// ─────────────────────────────────────────────────────────────────────────────
// Snap-to-grid + smart guides (0.9.x) — design-tool primitives that gate
// translate-mode delta correction during a body-drag move. Both opt-in via
// `FlueraCanvas.snapToGrid` / `FlueraCanvas.smartGuidesEnabled`.
// ─────────────────────────────────────────────────────────────────────────────

/// One alignment line emitted by the smart-guide engine. Drawn by
/// the selection painter as a dashed colored guide while the user
/// is dragging a selection to align it with another visible node.
///
/// `axis` is the line's orientation: `Axis.vertical` lines extend
/// up/down (constant `position` on the X axis); `Axis.horizontal`
/// lines extend left/right (constant `position` on the Y axis).
/// `[rangeStart, rangeEnd]` is the world-space extent on the
/// non-axis dimension.
class SmartGuideLine {
  /// API element `SmartGuideLine`.
  const SmartGuideLine({
    required this.axis,
    required this.position,
    required this.rangeStart,
    required this.rangeEnd,
  });
  /// Field `axis`.
  final Axis axis;
  /// Field `position`.
  final double position;
  /// Field `rangeStart`.
  final double rangeStart;
  /// Field `rangeEnd`.
  final double rangeEnd;
}

// ─────────────────────────────────────────────────────────────────────────────
// History (undo / redo) — lightweight command pattern.
// ─────────────────────────────────────────────────────────────────────────────

abstract class _CanvasOp {
  void undo(FlueraCanvasState s);
  void redo(FlueraCanvasState s);

  /// Called by [_CanvasHistory] when this op falls off the ring buffer
  /// (history capacity exceeded). The op no longer reachable via undo
  /// owns whatever GPU resources its snapshot retains — `ui.Picture`
  /// caches on stroke nodes that won't be redrawn, decoded `ui.Image`
  /// handles on image nodes that aren't referenced elsewhere — and is
  /// the right place to release them. Default no-op so existing ops
  /// don't have to opt in.
  void onEvicted(FlueraCanvasState s) {}
}

class _AddOp extends _CanvasOp {
  _AddOp(this.stroke, this.index);
  final CanvasStroke stroke;
  final int index;

  @override
  void undo(FlueraCanvasState s) => s._internalRemoveStroke(stroke);

  @override
  void redo(FlueraCanvasState s) => s._internalInsertStrokeAt(index, stroke);
}

/// Captures `TextNode.textElement` mutation across an editing session
/// so undo can restore the previous element exactly. The node identity
/// is the [NodeId]; both [before] and [after] are immutable snapshots
/// (DigitalTextElement uses copyWith semantics, so they don't share
/// mutable state with the live node).
class _UpdateTextOp extends _CanvasOp {
  _UpdateTextOp(this.id, this.before, this.after);
  final NodeId id;
  final DigitalTextElement before;
  final DigitalTextElement after;

  void _apply(FlueraCanvasState s, DigitalTextElement element) {
    final node = s._selectableNodes[id];
    if (node is! TextNode) return;
    node.textElement = element;
    node.cachedTextSize = ui.Size.zero;
    s._commitTick.notify();
  }

  @override
  void undo(FlueraCanvasState s) => _apply(s, before);

  @override
  void redo(FlueraCanvasState s) => _apply(s, after);
}

/// Pen-up commit when the user's stroke crossed image boundaries.
/// Stores per-segment routing — some pieces become free children of
/// the active layer (`target == null`), others ride a specific
/// [ImageNode]'s `annotations` list and follow every move/rotate/scale
/// applied to the host image. Single op for the whole gesture so undo
/// reverts the user's pen-up holistically (no half-erased segments).
class _SplitStrokeOp extends _CanvasOp {
  _SplitStrokeOp(this.segments);

  final List<_SplitSegment> segments;

  @override
  void undo(FlueraCanvasState s) {
    for (final seg in segments) {
      if (seg.target == null) {
        s._internalRemoveStroke(seg.stroke);
      } else {
        seg.target!.annotations.remove(seg.node);
        s._commitTick.notify();
      }
    }
  }

  @override
  void redo(FlueraCanvasState s) {
    for (final seg in segments) {
      if (seg.target == null) {
        s._internalInsertStrokeAt(seg.layerIndex!, seg.stroke);
      } else {
        seg.target!.annotations.add(seg.node);
      }
    }
    s._commitTick.notify();
  }
}

/// Cached "is this world point inside this image?" probe, with the
/// image's inverse-rendering matrix pre-computed so per-point
/// classification across N stroke samples doesn't pay the matrix
/// inversion N times. Built once per candidate image at split time.
class _ImageHitFrame {
  _ImageHitFrame._({
    required this.node,
    required this.z,
    required this.worldToLocal,
    required this.localRect,
  });

  factory _ImageHitFrame.forNode(ImageNode node, int z) {
    final el = node.imageElement;
    final w = node.imageSize.width > 0 ? node.imageSize.width : 200.0;
    final h = node.imageSize.height > 0 ? node.imageSize.height : 200.0;
    // Forward (image-local → world) — mirrors the order in
    // `ImageNodePainter.paint`.
    final m =
        Matrix4.identity()
          ..multiply(node.localTransform)
          ..translateByDouble(el.position.dx, el.position.dy, 0, 1);
    if (el.rotation != 0.0) {
      m
        ..translateByDouble(w * el.scale * 0.5, h * el.scale * 0.5, 0, 1)
        ..rotateZ(el.rotation)
        ..translateByDouble(-w * el.scale * 0.5, -h * el.scale * 0.5, 0, 1);
    }
    if (el.scale != 1.0) {
      m.scaleByDouble(el.scale, el.scale, 1, 1);
    }
    final inverse = Matrix4.inverted(m);
    return _ImageHitFrame._(
      node: node,
      z: z,
      worldToLocal: inverse,
      localRect: Rect.fromLTWH(0, 0, w, h),
    );
  }

  final ImageNode node;
  final int z;
  final Matrix4 worldToLocal;
  final Rect localRect;

  bool contains(Offset world) {
    final lp = MatrixUtils.transformPoint(worldToLocal, world);
    return localRect.contains(lp);
  }
}

class _SplitSegment {
  _SplitSegment({
    required this.stroke,
    required this.node,
    required this.target,
    required this.layerIndex,
  });

  /// The stroke geometry — in *world* coords for free segments,
  /// in image-local coords for image-parented segments.
  final CanvasStroke stroke;

  /// Node wrapping [stroke]. For image-parented segments this lives
  /// in `target.annotations`; for free segments it's the same node
  /// `_internalInsertStrokeAt` would have produced and the index
  /// inside `_strokes` is captured in [layerIndex] so redo replays.
  final CanvasStrokeNode node;

  /// Host image when the segment was routed to image-local coords;
  /// `null` when the segment is a free layer child.
  final ImageNode? target;

  /// Index in `_strokes` for free segments, captured at first apply
  /// so redo can re-insert at the same Z slot.
  final int? layerIndex;
}

class _AddBatchOp extends _CanvasOp {
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

class _EraseOp extends _CanvasOp {
  _EraseOp(
    this.strokes,
    Map<CanvasStroke, int> indexes, {
    List<_AnnotationEraseRecord>? annotations,
  }) : indexes = Map.of(indexes),
       annotations =
           annotations == null
               ? const <_AnnotationEraseRecord>[]
               : List<_AnnotationEraseRecord>.from(annotations);
  final List<CanvasStroke> strokes;
  final Map<CanvasStroke, int> indexes;
  final List<_AnnotationEraseRecord> annotations;

  @override
  void undo(FlueraCanvasState s) {
    // Re-insert in ascending original-index order so the Z-order is
    // reconstructed faithfully.
    final sorted = List<CanvasStroke>.from(strokes)
      ..sort((a, b) => (indexes[a] ?? 0).compareTo(indexes[b] ?? 0));
    for (final stroke in sorted) {
      s._internalInsertStrokeAt(indexes[stroke] ?? 0, stroke);
    }
    // Re-attach annotation strokes to their host images at the
    // original index — sorted ascending so adjacent indices land in
    // order even when multiple anns from the same image were erased.
    final sortedAnn = List<_AnnotationEraseRecord>.from(annotations)
      ..sort((a, b) => a.index.compareTo(b.index));
    for (final r in sortedAnn) {
      final idx = r.index.clamp(0, r.node.annotations.length);
      r.node.annotations.insert(idx, r.ann);
    }
    if (annotations.isNotEmpty) s._commitTick.notify();
  }

  @override
  void redo(FlueraCanvasState s) {
    for (final stroke in strokes) {
      s._internalRemoveStroke(stroke);
    }
    for (final r in annotations) {
      r.node.annotations.remove(r.ann);
    }
    if (annotations.isNotEmpty) s._commitTick.notify();
  }
}

/// Bookkeeping for a single annotation stroke removed by the live
/// eraser. Used by [_EraseOp.undo] to re-parent the stroke onto its
/// host image at the original index.
class _AnnotationEraseRecord {
  _AnnotationEraseRecord({
    required this.node,
    required this.ann,
    required this.index,
  });
  final ImageNode node;
  final CanvasStrokeNode ann;
  final int index;
}

class _ClearOp extends _CanvasOp {
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

class _PixelEraseOp extends _CanvasOp {
  _PixelEraseOp(
    List<_PixelEraseRecord> records,
    List<CanvasStroke> survivors, {
    List<_PixelAnnotationEraseRecord>? annotationRecords,
  }) : _records = List<_PixelEraseRecord>.from(records),
       _survivors = List<CanvasStroke>.from(survivors),
       _annotationRecords =
           annotationRecords == null
               ? const <_PixelAnnotationEraseRecord>[]
               : List<_PixelAnnotationEraseRecord>.from(annotationRecords);
  final List<_PixelEraseRecord> _records;
  final List<CanvasStroke> _survivors;
  final List<_PixelAnnotationEraseRecord> _annotationRecords;

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
    // Annotation pass: pull every survivor off its host image, then
    // re-attach the original at the captured slot. Iterating in
    // ascending order keeps adjacent annotations stable.
    final sortedAnn = List<_PixelAnnotationEraseRecord>.from(_annotationRecords)
      ..sort((a, b) => a.index.compareTo(b.index));
    for (final r in _annotationRecords) {
      for (final survivor in r.survivors) {
        r.node.annotations.remove(survivor);
      }
    }
    for (final r in sortedAnn) {
      final idx = r.index.clamp(0, r.node.annotations.length);
      r.node.annotations.insert(idx, r.original);
    }
    if (_annotationRecords.isNotEmpty) s._commitTick.notify();
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
    for (final r in _annotationRecords) {
      r.node.annotations.remove(r.original);
      for (final survivor in r.survivors) {
        r.node.annotations.add(survivor);
      }
    }
    if (_annotationRecords.isNotEmpty) s._commitTick.notify();
  }
}

/// Bookkeeping entry for a single annotation stroke split by the
/// pixel-mode eraser. Captures the host image, the original
/// `CanvasStrokeNode`, the original index inside `image.annotations`,
/// and the survivors that replaced it.
class _PixelAnnotationEraseRecord {
  _PixelAnnotationEraseRecord({
    required this.node,
    required this.original,
    required this.index,
    required this.survivors,
  });
  final ImageNode node;
  final CanvasStrokeNode original;
  final int index;
  final List<CanvasStrokeNode> survivors;
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

class _AddLayerOp extends _CanvasOp {
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
    s._rebuildSelectableIndex();
  }

  @override
  void redo(FlueraCanvasState s) {
    s._rootLayer.insertAt(index, layer);
    s._rebuildSelectableIndex();
  }
}

class _RemoveLayerOp extends _CanvasOp {
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
    s._rebuildSelectableIndex();
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
    s._rebuildSelectableIndex();
  }
}

class _MergeDownOp extends _CanvasOp {
  _MergeDownOp(
    this.upper,
    this.upperIndex,
    this.snapshots,
    this.activeWasUpper,
  );

  /// The layer that was merged DOWN — at the time of `mergeDown` we
  /// detached its stroke-nodes and removed the empty header. Undo
  /// re-inserts the layer header and re-parents every stroke-node
  /// onto it.
  final LayerNode upper;
  final int upperIndex;
  final List<_LayerStrokeSnapshot> snapshots;
  final bool activeWasUpper;

  @override
  void undo(FlueraCanvasState s) {
    // Re-insert the upper layer at its original Z-order.
    s._rootLayer.insertAt(upperIndex, upper);
    // Move each stroke-node back from the lower layer to the upper.
    // Walk in reverse so the same Z-order is restored.
    final sorted = List<_LayerStrokeSnapshot>.from(snapshots);
    for (final snap in sorted) {
      final lower = snap.node.parent as LayerNode?;
      lower?.remove(snap.node);
      upper.add(snap.node);
    }
    s._rebuildFlatStrokesFromLayers();
    if (activeWasUpper) s._activeLayer = upper;
  }

  @override
  void redo(FlueraCanvasState s) {
    final layers = s._rootLayer.children.whereType<LayerNode>().toList();
    if (upperIndex <= 0 || upperIndex >= layers.length) return;
    final lower = layers[upperIndex - 1];
    final movedNodes = upper.children.whereType<CanvasStrokeNode>().toList(
      growable: false,
    );
    for (final node in movedNodes) {
      upper.remove(node);
      lower.add(node);
    }
    s._rootLayer.remove(upper);
    s._rebuildFlatStrokesFromLayers();
    if (activeWasUpper) s._activeLayer = lower;
  }
}

class _FlattenLayerSnapshot {
  _FlattenLayerSnapshot({
    required this.layer,
    required this.originalIndex,
    required this.strokes,
  });

  /// The layer header that was dropped during flatten.
  final LayerNode layer;

  /// Z-position the layer occupied in `_rootLayer.children` before
  /// flatten — undo re-inserts the layer at the same index.
  final int originalIndex;

  /// Per-stroke flat-list snapshots at the moment of flatten. Visible
  /// layers had their strokes appended to `bottom`; hidden layers had
  /// their strokes removed from the spatial index entirely. Undo
  /// reverses both branches by re-attaching the stroke-nodes to
  /// [layer] and re-inserting them into the spatial index.
  final List<_LayerStrokeSnapshot> strokes;
}

class _FlattenOp extends _CanvasOp {
  _FlattenOp(this.snapshots, this.extendedOnDrop, this.activeWasNonBottom);
  final List<_FlattenLayerSnapshot> snapshots;
  final Map<NodeId, FlueraBlendMode> extendedOnDrop;
  final bool activeWasNonBottom;

  @override
  void undo(FlueraCanvasState s) {
    // Re-attach every dropped layer at its original Z-order, then
    // move each snapshotted stroke-node back onto its layer. After
    // all moves the bottom layer regains its original (pre-flatten)
    // child set. The flat-list mirror is rebuilt from the tree.
    final layersInOrder = List<_FlattenLayerSnapshot>.from(snapshots)
      ..sort((a, b) => a.originalIndex.compareTo(b.originalIndex));
    for (final pack in layersInOrder) {
      // Re-insert at original index — children are positions among
      // LayerNode siblings; insertAt operates on raw children, but
      // since LayerNodes are the only children of `_rootLayer` the
      // index is equivalent.
      s._rootLayer.insertAt(pack.originalIndex, pack.layer);
      for (final snap in pack.strokes) {
        // If the node was previously moved onto the bottom layer
        // (visible-flatten branch), detach it from there before
        // re-attaching.
        final currentParent = snap.node.parent;
        if (currentParent is LayerNode && currentParent != pack.layer) {
          currentParent.remove(snap.node);
        }
        if (snap.node.parent != pack.layer) {
          pack.layer.add(snap.node);
        }
        // Re-insert into spatial index for layers that were hidden
        // (their strokes were removed during flatten).
        if (!s._strokeToNode.containsKey(snap.stroke)) {
          s._spatialIndex.insert(snap.stroke);
          s._strokeToNode[snap.stroke] = snap.node;
        }
      }
    }
    s._extendedBlendModes.addAll(extendedOnDrop);
    s._rebuildFlatStrokesFromLayers();
    if (activeWasNonBottom) {
      // Best-effort: restore active to the topmost re-attached layer.
      final layers = s._rootLayer.children.whereType<LayerNode>().toList();
      if (layers.isNotEmpty) s._activeLayer = layers.last;
    }
  }

  @override
  void redo(FlueraCanvasState s) {
    final layers = s._rootLayer.children.whereType<LayerNode>().toList();
    if (layers.length <= 1) return;
    final bottom = layers.first;
    // Re-apply: drop every non-bottom layer, transferring visible
    // strokes to the bottom and removing hidden ones from the
    // spatial index.
    for (int i = 1; i < layers.length; i++) {
      final src = layers[i];
      final movedNodes = src.children.whereType<CanvasStrokeNode>().toList(
        growable: false,
      );
      if (src.isVisible) {
        for (final node in movedNodes) {
          src.remove(node);
          bottom.add(node);
        }
      } else {
        for (final node in movedNodes) {
          src.remove(node);
          s._spatialIndex.remove(node.stroke);
          s._strokeToNode.remove(node.stroke);
        }
      }
      s._extendedBlendModes.remove(src.id);
      s._rootLayer.remove(src);
    }
    s._activeLayer = bottom;
    s._rebuildFlatStrokesFromLayers();
  }
}

class _ReorderLayerOp extends _CanvasOp {
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

class _LayerVisibleOp extends _CanvasOp {
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

class _LayerLockedOp extends _CanvasOp {
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

class _LayerOpacityOp extends _CanvasOp {
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

class _LayerBlendModeOp extends _CanvasOp {
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

class _LayerNameOp extends _CanvasOp {
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
class _TransformNodesOp extends _CanvasOp {
  _TransformNodesOp(Map<NodeId, Matrix4> before, Map<NodeId, Matrix4> after)
    : _before = Map<NodeId, Matrix4>.from(before),
      _after = Map<NodeId, Matrix4>.from(after);

  final Map<NodeId, Matrix4> _before;
  final Map<NodeId, Matrix4> _after;

  void _apply(FlueraCanvasState s, Map<NodeId, Matrix4> snapshots) {
    // Walk the snapshot keys — direct O(K) lookup against the
    // unified selectable index. Works for stroke + image + any
    // future CanvasNode-derived type.
    snapshots.forEach((id, m) {
      final node = s._selectableNodes[id];
      if (node == null) return;
      s._writeLocalTransform(node, m.clone());
    });
    s._refreshSelectionBoundsAfterTransform();
  }

  @override
  void undo(FlueraCanvasState s) => _apply(s, _before);

  @override
  void redo(FlueraCanvasState s) => _apply(s, _after);
}

/// Generic add/remove op for a non-stroke node (image, future text /
/// shape) inside a specific layer. Skips the flat `_strokes` mirror
/// because non-stroke nodes don't ride that hot path. The cached
/// `ui.Image` for an [ImageNode] is NOT evicted on undo — it stays
/// in [ImageNodePainter] so a redo is instant; the cache is dropped
/// only when the op falls off the history capacity ring buffer.
/// One snapshot row for [groupSelection]: which node, which layer
/// it lived on, and at what index inside that layer's children list.
/// Used by [_GroupOp.undo] to scatter children back to their
/// original positions when the user un-groups via undo.
class _GroupMember {
  _GroupMember({required this.node, required this.parent, required this.index});
  final CanvasNode node;
  final LayerNode parent;
  final int index;
}

/// Captures a `groupSelection()` call: the freshly-minted GroupNode,
/// the layer it lives on, where it was inserted, and where each of
/// its children originally lived. Undo dissolves the group and puts
/// every child back at its original index; redo re-groups them.
class _GroupOp extends _CanvasOp {
  _GroupOp({
    required this.group,
    required this.layer,
    required this.members,
    required this.insertedAt,
  });
  final GroupNode group;
  final LayerNode layer;
  final List<_GroupMember> members;
  final int insertedAt;

  @override
  void undo(FlueraCanvasState s) {
    // Detach every child from the group, scatter them back to the
    // layer at their original index. Members were sorted desc at
    // group time; iterate ascending for re-insert so adjacent
    // indices land in the right slots.
    final sorted = List<_GroupMember>.from(members)
      ..sort((a, b) => a.index.compareTo(b.index));
    for (final m in sorted) {
      group.remove(m.node);
    }
    layer.remove(group);
    for (final m in sorted) {
      final idx = m.index.clamp(0, layer.children.length);
      if (idx >= layer.children.length) {
        layer.add(m.node);
      } else {
        layer.insertAt(idx, m.node);
      }
    }
    s._bumpLayerVersion(layer.id);
    s._rebuildSelectableIndex();
    s._selectionController.set(
      s._selectionFromIds(members.map((m) => m.node.id).toSet()),
    );
    s._commitTick.notify();
  }

  @override
  void redo(FlueraCanvasState s) {
    // Pull every original member off its current parent slot,
    // re-attach to the group, re-insert the group at `insertedAt`.
    final sortedDesc = List<_GroupMember>.from(members)
      ..sort((a, b) => b.index.compareTo(a.index));
    for (final m in sortedDesc) {
      if (m.node.parent is LayerNode) {
        (m.node.parent! as LayerNode).remove(m.node);
      }
    }
    for (final m in sortedDesc.reversed) {
      group.add(m.node);
    }
    final idx = insertedAt.clamp(0, layer.children.length);
    if (idx >= layer.children.length) {
      layer.add(group);
    } else {
      layer.insertAt(idx, group);
    }
    s._bumpLayerVersion(layer.id);
    s._rebuildSelectableIndex();
    s._selectionController.set(s._selectionFromIds({group.id}));
    s._commitTick.notify();
  }
}

/// One ungroup snapshot: the group that was dissolved, the layer it
/// lived on, the index it occupied inside that layer's children,
/// and the ordered ids of the children at dissolve time. The
/// child-id list is the canonical source of truth for undo because
/// `group.children` is empty after `ungroupSelection()` (we
/// explicitly detach to keep the group's `_childIdIndex` clean).
class _UngroupOp {
  _UngroupOp({
    required this.group,
    required this.layer,
    required this.groupIndex,
    required this.formerChildIds,
  });
  final GroupNode group;
  final LayerNode layer;
  final int groupIndex;
  final List<String> formerChildIds;
}

/// Single history step covering every group dissolved by one
/// `ungroupSelection()` call. Undo re-wraps each set of children
/// into the original group; redo re-flattens them.
class _UngroupBatchOp extends _CanvasOp {
  _UngroupBatchOp(this.ops);
  final List<_UngroupOp> ops;

  @override
  void undo(FlueraCanvasState s) {
    for (final op in ops) {
      // Pull each former child off the layer using the captured id
      // list. We can't trust `op.group.children` (empty after the
      // detach) nor positional indexing (other ops may have
      // shuffled siblings since dissolve time). The id-keyed lookup
      // is canonical.
      final freed = <CanvasNode>[];
      for (final id in op.formerChildIds) {
        for (int i = 0; i < op.layer.children.length; i++) {
          if (op.layer.children[i].id == id) {
            freed.add(op.layer.children[i]);
            op.layer.remove(op.layer.children[i]);
            break;
          }
        }
      }
      for (final c in freed) {
        op.group.add(c);
      }
      final idx = op.groupIndex.clamp(0, op.layer.children.length);
      if (idx >= op.layer.children.length) {
        op.layer.add(op.group);
      } else {
        op.layer.insertAt(idx, op.group);
      }
      s._bumpLayerVersion(op.layer.id);
    }
    s._rebuildSelectableIndex();
    s._selectionController.set(
      s._selectionFromIds(ops.map((o) => o.group.id).toSet()),
    );
    s._commitTick.notify();
  }

  @override
  void redo(FlueraCanvasState s) {
    final freedIds = <NodeId>{};
    for (final op in ops) {
      // Snapshot from the group's *current* children — populated by
      // the previous undo. Detach properly so the group's id index
      // is clean if the user undoes/redoes again.
      final snapshot = List<CanvasNode>.from(op.group.children);
      for (final c in snapshot) {
        op.group.remove(c);
      }
      op.layer.remove(op.group);
      for (int i = 0; i < snapshot.length; i++) {
        op.layer.insertAt(op.groupIndex + i, snapshot[i]);
        freedIds.add(snapshot[i].id);
      }
      s._bumpLayerVersion(op.layer.id);
    }
    s._rebuildSelectableIndex();
    s._selectionController.set(s._selectionFromIds(freedIds));
    s._commitTick.notify();
  }
}

/// Z-order reorder of a single child within its parent layer.
/// Captured at the moment of the move so undo restores the
/// original index even after intermediate ops shuffled siblings.
class _ReorderChildOp extends _CanvasOp {
  _ReorderChildOp(this.nodeId, this.layerId, this.previousIndex, this.toFront);
  final NodeId nodeId;
  final NodeId layerId;
  final int previousIndex;
  final bool toFront;

  @override
  void undo(FlueraCanvasState s) {
    final layer = s._findLayer(layerId);
    if (layer == null) return;
    final node = s._selectableNodes[nodeId];
    if (node == null) return;
    layer.remove(node);
    final idx = previousIndex.clamp(0, layer.children.length);
    if (idx >= layer.children.length) {
      layer.add(node);
    } else {
      layer.insertAt(idx, node);
    }
    s._bumpLayerVersion(layer.id);
    s._rebuildSelectableIndex();
    s._commitTick.notify();
  }

  @override
  void redo(FlueraCanvasState s) {
    s._reorderChildToEdge(nodeId, toFront: toFront);
  }
}

class _AddLayerChildOp extends _CanvasOp {
  _AddLayerChildOp(this.node, this.layerId, this.index);
  final CanvasNode node;
  final NodeId layerId;
  final int index;

  @override
  void undo(FlueraCanvasState s) {
    final layer = s._findLayer(layerId);
    if (layer == null) return;
    layer.remove(node);
    s._unregisterSelectable(node.id);
    s._commitTick.notify();
  }

  @override
  void redo(FlueraCanvasState s) {
    final layer = s._findLayer(layerId);
    if (layer == null) return;
    if (index >= layer.children.length) {
      layer.add(node);
    } else {
      layer.insertAt(index, node);
    }
    s._registerSelectable(node);
    s._commitTick.notify();
  }

  @override
  void onEvicted(FlueraCanvasState s) {
    // The op held the only reachable handle to `node` while it sat
    // on the redo stack (post-undo, awaiting a possible redo). Now
    // that the op's been dropped, the node will never be redrawn.
    // Release its GPU resources.
    final n = node;
    if (n is CanvasStrokeNode) {
      n.stroke.dispose();
    } else if (n is ImageNode) {
      // Annotation strokes attached to this orphaned image are
      // unreachable too — release their picture caches alongside the
      // image's GPU handle.
      for (final ann in n.annotations) {
        ann.stroke.dispose();
      }
      // Only evict the image-cache entry if no LIVE ImageNode
      // references the same path. Iterate the non-stroke subset only.
      final path = n.imageElement.imagePath;
      var stillReferenced = false;
      for (final id in s._nonStrokeSelectableIds) {
        final live = s._selectableNodes[id];
        if (live is ImageNode && live.imageElement.imagePath == path) {
          stillReferenced = true;
          break;
        }
      }
      if (!stillReferenced) ImageNodePainter.evict(path);
    }
  }
}

/// Snapshot of one node deleted by [FlueraCanvasState.deleteSelection].
/// Stores everything needed to rehydrate the node on undo without
/// touching `_selectableNodes` from the op itself (the op routes
/// through state helpers).
class _DeletedNodeSnapshot {
  _DeletedNodeSnapshot({
    required this.node,
    required this.layerId,
    required this.childIndex,
    required this.flatStrokeIndex,
  });

  /// The node that was removed. For stroke nodes the underlying
  /// `CanvasStroke` is reachable via `(node as CanvasStrokeNode).stroke`.
  final CanvasNode node;
  final NodeId layerId;

  /// Index inside the parent layer's `children` list at remove time.
  /// Used to restore Z-order on undo.
  final int childIndex;

  /// For stroke nodes only — index inside the flat `_strokes` mirror.
  /// `null` for image / future text-shape nodes.
  final int? flatStrokeIndex;

  bool get isStroke => node is CanvasStrokeNode;
}

/// Generic multi-node deletion op (Phase 5). Replaces the
/// stroke-only `_EraseOp` for the public `deleteSelection()` path.
/// `_EraseOp` lives on for the pen-eraser flow.
class _DeleteNodesOp extends _CanvasOp {
  _DeleteNodesOp(this.snapshots);
  final List<_DeletedNodeSnapshot> snapshots;

  @override
  void undo(FlueraCanvasState s) {
    // Restore in ascending child-index order so each `insertAt` lands
    // at the position it occupied at remove time.
    final sorted = List<_DeletedNodeSnapshot>.from(snapshots)
      ..sort((a, b) => a.childIndex.compareTo(b.childIndex));
    for (final snap in sorted) {
      final layer = s._findLayer(snap.layerId);
      if (layer == null) continue;
      if (snap.isStroke) {
        // Reattach the SAME CanvasStrokeNode (preserves its id, its
        // localTransform, and the flat-mirror invariant). We can't
        // route through `_internalInsertStrokeAt` because that helper
        // mints a fresh node when `_strokeToNode[stroke]` is empty,
        // which it always is post-removal — patching the maps + flat
        // list directly is the only way to round-trip the original id.
        final node = snap.node as CanvasStrokeNode;
        final stroke = node.stroke;
        final flatIdx = (snap.flatStrokeIndex ?? s._strokes.length).clamp(
          0,
          s._strokes.length,
        );
        s._strokes.insert(flatIdx, stroke);
        s._spatialIndex.insert(stroke);
        s._strokeToNode[stroke] = node;
        if (snap.childIndex >= layer.children.length) {
          layer.add(node);
        } else {
          layer.insertAt(snap.childIndex, node);
        }
        s._registerSelectable(node);
      } else {
        if (snap.childIndex >= layer.children.length) {
          layer.add(snap.node);
        } else {
          layer.insertAt(snap.childIndex, snap.node);
        }
        s._registerSelectable(snap.node);
      }
    }
    s._commitTick.notify();
  }

  @override
  void redo(FlueraCanvasState s) {
    for (final snap in snapshots) {
      if (snap.isStroke) {
        final stroke = (snap.node as CanvasStrokeNode).stroke;
        s._internalRemoveStroke(stroke);
      } else {
        final layer = s._findLayer(snap.layerId);
        layer?.remove(snap.node);
        s._unregisterSelectable(snap.node.id);
      }
    }
    s._selectionController.clear();
    s._commitTick.notify();
  }

  /// History evictor reached this op — undo / redo can no longer
  /// resurrect the snapshot, so any GPU resources the snapshot
  /// retained are dead weight. Strokes carry a cached `ui.Picture`
  /// (released via `CanvasStroke.dispose`); images carry a decoded
  /// `ui.Image` in [ImageNodePainter]'s process-wide cache, but ONLY
  /// if no other live ImageNode references the same `imagePath`.
  /// We check the live `_selectableNodes` to make that call.
  @override
  void onEvicted(FlueraCanvasState s) {
    // Collect every imagePath still referenced by a live ImageNode
    // somewhere in the canvas. Iterate only the non-stroke subset —
    // strokes never carry a path, so walking them is wasted work on
    // canvases with thousands of strokes.
    final livePaths = <String>{};
    for (final id in s._nonStrokeSelectableIds) {
      final node = s._selectableNodes[id];
      if (node is ImageNode) {
        livePaths.add(node.imageElement.imagePath);
      }
    }
    for (final snap in snapshots) {
      if (snap.isStroke) {
        // Release the cached `ui.Picture` — `picture()` rebuilds
        // lazily, so this is safe even if some other code path
        // surfaces the stroke later (unlikely after eviction).
        (snap.node as CanvasStrokeNode).stroke.dispose();
      } else if (snap.node is ImageNode) {
        final imageNode = snap.node as ImageNode;
        // Dispose every annotation stroke's `ui.Picture` cache — the
        // image is forever lost from history, the annotations along
        // with it. Their handles would otherwise leak for the lifetime
        // of the process.
        for (final ann in imageNode.annotations) {
          ann.stroke.dispose();
        }
        final path = imageNode.imageElement.imagePath;
        if (!livePaths.contains(path)) {
          ImageNodePainter.evict(path);
        }
      }
    }
  }
}

class _CanvasHistory {
  _CanvasHistory({required this.capacity, this.state});
  int capacity;

  /// Owning state. When non-null, [push] calls `op.onEvicted(state)`
  /// on every op that falls off the ring buffer (capacity exceeded)
  /// — that's where ops with disposable GPU resources (decoded
  /// `ui.Image` handles in `_DeleteNodesOp`, picture caches in
  /// `_PixelEraseOp`) get to release them. `null` keeps the field
  /// optional so the legacy 2-arg `_CanvasHistory(capacity: ...)`
  /// constructor still works in tests / one-off use.
  FlueraCanvasState? state;

  final List<_CanvasOp> _undo = <_CanvasOp>[];
  final List<_CanvasOp> _redo = <_CanvasOp>[];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  int get undoLength => _undo.length;

  void push(_CanvasOp op) {
    _undo.add(op);
    // The redo stack is becoming unreachable — release whatever
    // resources the abandoned ops held. Doing it before clearing the
    // list lets the ops see live `_selectableNodes` while deciding
    // what to evict.
    final s = state;
    if (s != null) {
      for (final dropped in _redo) {
        dropped.onEvicted(s);
      }
    }
    _redo.clear();
    while (_undo.length > capacity) {
      final dropped = _undo.removeAt(0);
      if (s != null) dropped.onEvicted(s);
    }
  }

  _CanvasOp? popUndo() {
    if (_undo.isEmpty) return null;
    final op = _undo.removeLast();
    _redo.add(op);
    return op;
  }

  /// Surgical removal of the most recent op that satisfies [test].
  /// Used by `removeFreshTextNode` to drop the matching
  /// `_AddLayerChildOp` for an editor session that ended on empty
  /// text — without touching unrelated entries the way a plain
  /// [popUndo] would. The op is dropped from the undo stack and its
  /// `onEvicted` is invoked so any GPU resources it owned are
  /// released. Returns `true` when an op was removed.
  bool popMatching(bool Function(_CanvasOp op) test) {
    for (int i = _undo.length - 1; i >= 0; i--) {
      if (test(_undo[i])) {
        final op = _undo.removeAt(i);
        final s = state;
        if (s != null) op.onEvicted(s);
        return true;
      }
    }
    return false;
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
