import 'dart:ui' show Color, Offset, Rect;

import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_id.dart';
import '../scene_graph/node_visitor.dart';
import '../../canvas/fluera_canvas_widget.dart' show CanvasStroke;
import '../../drawing/brush_config.dart'
    show PencilConfig, FountainPenConfig;
import '../../utils/uid.dart' show generateUid;

/// Scene-graph node that wraps a [CanvasStroke] (the flat free-tier
/// stroke model used by `FlueraCanvas`).
///
/// This is the canvas-core counterpart to the engine-resident
/// [StrokeNode], which wraps a richer `ProStroke`. The two coexist:
/// `StrokeNode` is consumed by `fluera_engine`, `CanvasStrokeNode` is
/// the type the free `FlueraCanvas` widget stores in its scene graph.
/// Conversion between the two is intentionally not auto-magic —
/// converting `CanvasStroke <-> ProStroke` would lose the lazy
/// `ui.Picture` cache that the canvas painter relies on for the
/// 5k–10k strokes-at-60-FPS path.
class CanvasStrokeNode extends CanvasNode {
  /// The wrapped flat stroke (points, pressures, color, width, brush).
  CanvasStroke stroke;

  CanvasStrokeNode({
    required super.id,
    required this.stroke,
    super.name = '',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
  });

  @override
  Rect get localBounds => stroke.bounds;

  @override
  void dispose() {
    stroke.dispose();
    super.dispose();
  }

  /// Lightweight clone — share the same `CanvasStroke` ref (immutable
  /// content, including the GPU `ui.Picture` cache). Useful for split /
  /// merge ops in the pixel eraser.
  @override
  CanvasNode cloneInternal() {
    final copy = CanvasStrokeNode(
      id: NodeId(generateUid()),
      stroke: stroke,
      name: name,
      localTransform: localTransform.clone(),
      opacity: opacity,
      blendMode: blendMode,
      isVisible: isVisible,
      isLocked: isLocked,
    );
    return copy;
  }

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitOther(this);

  // ───────────────────────────────────────────────────────────────────
  // JSON
  // ───────────────────────────────────────────────────────────────────

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'canvas_stroke';
    json['stroke'] = _strokeToJson(stroke);
    return json;
  }

  factory CanvasStrokeNode.fromJson(Map<String, dynamic> json) {
    final node = CanvasStrokeNode(
      id: NodeId(json['id'] as String),
      stroke: _strokeFromJson(json['stroke'] as Map<String, dynamic>),
    );
    CanvasNode.applyBaseFromJson(node, json);
    return node;
  }

  @override
  String toString() =>
      'CanvasStrokeNode(id: $id, points: ${stroke.points.length}, '
      'brush: ${stroke.brushType})';
}

// ─── Stroke <-> JSON (full-fidelity, scene-graph-internal) ───────────
//
// `CanvasSerializer.encodeJson` uses a lossy stroke shape (`x/y/p/c/w`)
// kept for FCV0 v1 backward-compat. Scene-graph serialization needs
// the full fidelity (smooth, brushType, pencilConfig, fountainConfig)
// so that round-tripping a `CanvasStrokeNode` is exact.

Map<String, dynamic> _strokeToJson(CanvasStroke s) {
  final n = s.points.length;
  final xs = List<double>.filled(n, 0);
  final ys = List<double>.filled(n, 0);
  for (int i = 0; i < n; i++) {
    xs[i] = s.points[i].dx;
    ys[i] = s.points[i].dy;
  }
  final out = <String, dynamic>{
    'x': xs,
    'y': ys,
    'p': s.pressures,
    'c': s.color.toARGB32(),
    'w': s.baseWidth,
  };
  // Compact: only emit deviations from defaults.
  if (!s.smooth) out['s'] = false;
  if (s.brushType != 0) out['bt'] = s.brushType;
  if (s.pencilConfig != PencilConfig.defaults) {
    out['pc'] = _pencilToJson(s.pencilConfig);
  }
  if (s.fountainConfig != FountainPenConfig.defaults) {
    out['fc'] = _fountainToJson(s.fountainConfig);
  }
  return out;
}

CanvasStroke _strokeFromJson(Map<String, dynamic> map) {
  final xs = (map['x'] as List).cast<num>();
  final ys = (map['y'] as List).cast<num>();
  final ps = (map['p'] as List).cast<num>();
  if (xs.length != ys.length || xs.length != ps.length) {
    throw const FormatException('Stroke arrays length mismatch.');
  }
  final points = <Offset>[
    for (int i = 0; i < xs.length; i++)
      Offset(xs[i].toDouble(), ys[i].toDouble()),
  ];
  return CanvasStroke(
    points: List<Offset>.unmodifiable(points),
    pressures: List<double>.unmodifiable(ps.map((e) => e.toDouble())),
    color: Color((map['c'] as num).toInt()),
    baseWidth: (map['w'] as num).toDouble(),
    smooth: (map['s'] as bool?) ?? true,
    brushType: (map['bt'] as int?) ?? 0,
    pencilConfig: map['pc'] is Map<String, dynamic>
        ? _pencilFromJson(map['pc'] as Map<String, dynamic>)
        : PencilConfig.defaults,
    fountainConfig: map['fc'] is Map<String, dynamic>
        ? _fountainFromJson(map['fc'] as Map<String, dynamic>)
        : FountainPenConfig.defaults,
  );
}

Map<String, dynamic> _pencilToJson(PencilConfig c) => {
      'bo': c.baseOpacity,
      'mo': c.maxOpacity,
      'mn': c.minPressure,
      'mx': c.maxPressure,
    };

PencilConfig _pencilFromJson(Map<String, dynamic> m) => PencilConfig(
      baseOpacity: (m['bo'] as num).toDouble(),
      maxOpacity: (m['mo'] as num).toDouble(),
      minPressure: (m['mn'] as num).toDouble(),
      maxPressure: (m['mx'] as num).toDouble(),
    );

Map<String, dynamic> _fountainToJson(FountainPenConfig c) => {
      'th': c.thinning,
      'na': c.nibAngleDeg,
      'ns': c.nibStrength,
      'pr': c.pressureRate,
      'te': c.taperEntry,
    };

FountainPenConfig _fountainFromJson(Map<String, dynamic> m) =>
    FountainPenConfig(
      thinning: (m['th'] as num).toDouble(),
      nibAngleDeg: (m['na'] as num).toDouble(),
      nibStrength: (m['ns'] as num).toDouble(),
      pressureRate: (m['pr'] as num).toDouble(),
      taperEntry: (m['te'] as num).toInt(),
    );
