import 'dart:ui';
import '../scene_graph/canvas_node.dart';
import 'package:fluera_canvas/fluera_canvas.dart';
import '../scene_graph/node_visitor.dart';

/// Scene graph node that wraps a [ProStroke].
///
/// The stroke's points are stored in **local coordinates**.
/// The [localTransform] positions the stroke in the parent's space.
/// By default, the transform is identity (stroke points are in world coords),
/// which is backward-compatible with the existing system.
class StrokeNode extends CanvasNode {
  /// The actual stroke data (points, color, width, pen type, etc.).
  ProStroke stroke;

  StrokeNode({
    required super.id,
    required this.stroke,
    super.name = '',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
  });

  // ---------------------------------------------------------------------------
  // Bounds
  // ---------------------------------------------------------------------------

  @override
  Rect get localBounds => stroke.bounds;

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'stroke';
    json['stroke'] = stroke.toJson();
    return json;
  }

  factory StrokeNode.fromJson(Map<String, dynamic> json) {
    final node = StrokeNode(
      id: NodeId(json['id'] as String),
      stroke: ProStroke.fromJson(json['stroke'] as Map<String, dynamic>),
    );
    CanvasNode.applyBaseFromJson(node, json);
    return node;
  }

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitStroke(this);

  @override
  String toString() =>
      'StrokeNode(id: $id, points: ${stroke.points.length}, pen: ${stroke.penType})';
}
