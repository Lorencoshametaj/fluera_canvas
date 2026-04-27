import 'dart:ui';
import '../scene_graph/canvas_node.dart';
import 'package:fluera_canvas/fluera_canvas.dart';
import '../scene_graph/node_visitor.dart';
import '../scene_graph/paint_stack_mixin.dart';
import '../effects/mesh_gradient.dart';

/// Scene graph node that wraps a [GeometricShape].
///
/// Supports stacked fills and strokes via [PaintStackMixin].
/// The shape's geometry (startPoint/endPoint) is stored in local coordinates.
/// The [localTransform] positions/rotates/scales the shape in parent space.
class ShapeNode extends CanvasNode with PaintStackMixin {
  /// The actual shape data.
  GeometricShape shape;

  /// Optional mesh gradient fill (rendered instead of solid fill).
  MeshGradient? meshGradient;

  /// API element `ShapeNode`.
  ShapeNode({
    required super.id,
    required this.shape,
    this.meshGradient,
    super.name = '',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
    List<FillLayer>? fills,
    List<StrokeLayer>? strokes,
  }) {
    if (fills != null) this.fills = fills;
    if (strokes != null) this.strokes = strokes;
  }

  // ---------------------------------------------------------------------------
  // Bounds
  // ---------------------------------------------------------------------------

  @override
  Rect get localBounds {
    final left =
        shape.startPoint.dx < shape.endPoint.dx
            ? shape.startPoint.dx
            : shape.endPoint.dx;
    final top =
        shape.startPoint.dy < shape.endPoint.dy
            ? shape.startPoint.dy
            : shape.endPoint.dy;
    final right =
        shape.startPoint.dx > shape.endPoint.dx
            ? shape.startPoint.dx
            : shape.endPoint.dx;
    final bottom =
        shape.startPoint.dy > shape.endPoint.dy
            ? shape.startPoint.dy
            : shape.endPoint.dy;

    // Use stroke stack inflation or legacy strokeWidth.
    final padding =
        strokes.isNotEmpty ? maxStrokeBoundsInflation : shape.strokeWidth;
    return Rect.fromLTRB(
      left - padding,
      top - padding,
      right + padding,
      bottom + padding,
    );
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'shape';
    json['shape'] = shape.toJson();
    if (meshGradient != null) {
      json['meshGradient'] = meshGradient!.toJson();
    }
    // Paint stack (new format).
    json.addAll(paintStackToJson());
    return json;
  }

  /// API element `fromJson`.
  factory ShapeNode.fromJson(Map<String, dynamic> json) {
    final shape = GeometricShape.fromJson(
      json['shape'] as Map<String, dynamic>,
    );
    final node = ShapeNode(
      id: NodeId(json['id'] as String),
      shape: shape,
      meshGradient:
          json['meshGradient'] != null
              ? MeshGradient.fromJson(
                json['meshGradient'] as Map<String, dynamic>,
              )
              : null,
    );
    CanvasNode.applyBaseFromJson(node, json);

    // Paint stack — new format has priority.
    if (json.containsKey('fills') || json.containsKey('strokes')) {
      PaintStackMixin.applyPaintStackFromJson(node, json);
    } else {
      // Auto-migrate from GeometricShape's legacy fields.
      _migrateLegacyPaintStack(node);
    }

    return node;
  }

  /// Migrate legacy GeometricShape fill/stroke into the paint stack.
  static void _migrateLegacyPaintStack(ShapeNode node) {
    final shape = node.shape;
    if (shape.fillGradient != null) {
      node.fills.add(FillLayer.fromGradient(gradient: shape.fillGradient!));
    } else if (shape.filled) {
      node.fills.add(FillLayer.solid(color: shape.color));
    }
    if (shape.strokeGradient != null) {
      node.strokes.add(
        StrokeLayer(gradient: shape.strokeGradient, width: shape.strokeWidth),
      );
    } else {
      node.strokes.add(
        StrokeLayer(color: shape.color, width: shape.strokeWidth),
      );
    }
  }

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitShape(this);

  @override
  String toString() => 'ShapeNode(id: $id, type: ${shape.type})';
}
