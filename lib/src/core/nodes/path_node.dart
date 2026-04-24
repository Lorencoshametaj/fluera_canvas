import 'dart:ui' as ui;
import '../scene_graph/canvas_node.dart';
import 'package:fluera_canvas/fluera_canvas.dart';
import '../scene_graph/node_visitor.dart';
import '../scene_graph/paint_stack_mixin.dart';
import '../vector/vector_path.dart';

/// Scene graph node that wraps a [VectorPath] for rendering.
///
/// Supports stacked fills and strokes via [PaintStackMixin].
/// Legacy single fill/stroke fields are preserved for backward
/// compatibility and auto-migrated into the stack on deserialization.
///
/// ```
/// PathNode (star)
///   path: VectorPath (5-point star Bézier)
///   fills: [FillLayer.solid(color: Colors.gold)]
///   strokes: [StrokeLayer(color: Colors.black, width: 2.0)]
/// ```
class PathNode extends CanvasNode with PaintStackMixin {
  VectorPath path;

  /// Fill color — **deprecated**, use [fills] instead.
  @Deprecated('Use fills list from PaintStackMixin instead')
  ui.Color? fillColor;

  /// Fill gradient — **deprecated**, use [fills] instead.
  @Deprecated('Use fills list from PaintStackMixin instead')
  GradientFill? fillGradient;

  /// Stroke color — **deprecated**, use [strokes] instead.
  @Deprecated('Use strokes list from PaintStackMixin instead')
  ui.Color? strokeColor;

  /// Stroke gradient — **deprecated**, use [strokes] instead.
  @Deprecated('Use strokes list from PaintStackMixin instead')
  GradientFill? strokeGradient;

  /// Stroke width — **deprecated**, use [strokes] instead.
  @Deprecated('Use strokes list from PaintStackMixin instead')
  double strokeWidth;

  /// Stroke cap — **deprecated**, use [strokes] instead.
  @Deprecated('Use strokes list from PaintStackMixin instead')
  ui.StrokeCap strokeCap;

  /// Stroke join — **deprecated**, use [strokes] instead.
  @Deprecated('Use strokes list from PaintStackMixin instead')
  ui.StrokeJoin strokeJoin;

  PathNode({
    required super.id,
    required this.path,
    super.name = '',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
    this.fillColor,
    this.fillGradient,
    this.strokeColor,
    this.strokeGradient,
    this.strokeWidth = 2.0,
    this.strokeCap = ui.StrokeCap.round,
    this.strokeJoin = ui.StrokeJoin.round,
    List<FillLayer>? fills,
    List<StrokeLayer>? strokes,
  }) {
    if (fills != null) this.fills = fills;
    if (strokes != null) this.strokes = strokes;
  }

  @override
  ui.Rect get localBounds {
    final pathBounds = path.computeBounds();
    if (pathBounds.isEmpty) return ui.Rect.zero;
    // Use the maximum inflation from the stroke stack, or fall back
    // to the legacy strokeWidth for backward compat.
    final inflation =
        // ignore: deprecated_member_use_from_same_package
        strokes.isNotEmpty ? maxStrokeBoundsInflation : strokeWidth / 2;
    return pathBounds.inflate(inflation);
  }

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'path';
    json['path'] = path.toJson();

    // Serialize paint stack (new format).
    json.addAll(paintStackToJson());

    // Legacy fields — only serialize if stack is empty (backward compat).
    if (fills.isEmpty) {
      // ignore: deprecated_member_use_from_same_package
      json['strokeWidth'] = strokeWidth;
      // ignore: deprecated_member_use_from_same_package
      json['strokeCap'] = strokeCap.index;
      // ignore: deprecated_member_use_from_same_package
      json['strokeJoin'] = strokeJoin.index;
      // ignore: deprecated_member_use_from_same_package
      if (fillColor != null) json['fillColor'] = fillColor!.toARGB32();
      // ignore: deprecated_member_use_from_same_package
      if (fillGradient != null) json['fillGradient'] = fillGradient!.toJson();
      // ignore: deprecated_member_use_from_same_package
      if (strokeColor != null) json['strokeColor'] = strokeColor!.toARGB32();
      // ignore: deprecated_member_use_from_same_package
      if (strokeGradient != null) {
        // ignore: deprecated_member_use_from_same_package
        json['strokeGradient'] = strokeGradient!.toJson();
      }
    }

    return json;
  }

  factory PathNode.fromJson(Map<String, dynamic> json) {
    final node = PathNode(
      id: NodeId(json['id'] as String),
      path: VectorPath.fromJson(json['path'] as Map<String, dynamic>),
      strokeWidth: (json['strokeWidth'] as num?)?.toDouble() ?? 2.0,
      strokeCap:
          json['strokeCap'] != null
              ? ui.StrokeCap.values[json['strokeCap'] as int]
              : ui.StrokeCap.round,
      strokeJoin:
          json['strokeJoin'] != null
              ? ui.StrokeJoin.values[json['strokeJoin'] as int]
              : ui.StrokeJoin.round,
      fillColor:
          json['fillColor'] != null
              ? ui.Color((json['fillColor'] as int).toUnsigned(32))
              : null,
      fillGradient:
          json['fillGradient'] != null
              ? GradientFill.fromJson(
                json['fillGradient'] as Map<String, dynamic>,
              )
              : null,
      strokeColor:
          json['strokeColor'] != null
              ? ui.Color((json['strokeColor'] as int).toUnsigned(32))
              : null,
      strokeGradient:
          json['strokeGradient'] != null
              ? GradientFill.fromJson(
                json['strokeGradient'] as Map<String, dynamic>,
              )
              : null,
    );
    CanvasNode.applyBaseFromJson(node, json);

    // Paint stack deserialization — new format has priority.
    if (json.containsKey('fills') || json.containsKey('strokes')) {
      PaintStackMixin.applyPaintStackFromJson(node, json);
    } else {
      // Auto-migrate legacy single fill/stroke into the stack.
      _migrateLegacyPaintStack(node, json);
    }

    return node;
  }

  /// Migrate legacy single fill/stroke fields into the paint stack.
  static void _migrateLegacyPaintStack(
    PathNode node,
    Map<String, dynamic> json,
  ) {
    // Migrate fill.
    // ignore: deprecated_member_use_from_same_package
    if (node.fillGradient != null) {
      // ignore: deprecated_member_use_from_same_package
      node.fills.add(FillLayer.fromGradient(gradient: node.fillGradient!));
      // ignore: deprecated_member_use_from_same_package
    } else if (node.fillColor != null) {
      // ignore: deprecated_member_use_from_same_package
      node.fills.add(FillLayer.solid(color: node.fillColor!));
    }
    // Migrate stroke.
    // ignore: deprecated_member_use_from_same_package
    if (node.strokeColor != null || node.strokeGradient != null) {
      node.strokes.add(
        StrokeLayer(
          // ignore: deprecated_member_use_from_same_package
          color: node.strokeColor,
          // ignore: deprecated_member_use_from_same_package
          gradient: node.strokeGradient,
          // ignore: deprecated_member_use_from_same_package
          width: node.strokeWidth,
          // ignore: deprecated_member_use_from_same_package
          cap: node.strokeCap,
          // ignore: deprecated_member_use_from_same_package
          join: node.strokeJoin,
        ),
      );
    }
  }

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitPath(this);
}
