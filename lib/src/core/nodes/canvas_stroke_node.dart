import 'dart:ui' show Rect;

import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_id.dart';
import '../scene_graph/node_visitor.dart';
import '../../canvas/fluera_canvas_widget.dart' show CanvasStroke;
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

  /// API element `CanvasStrokeNode`.
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

  /// API element `fromJson`.
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

Map<String, dynamic> _strokeToJson(CanvasStroke s) => s.toJson();

CanvasStroke _strokeFromJson(Map<String, dynamic> map) =>
    CanvasStroke.fromJson(map);
