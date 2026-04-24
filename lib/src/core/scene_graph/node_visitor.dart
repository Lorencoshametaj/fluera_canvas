// Imports from concrete node types for visitor dispatch.
import '../nodes/group_node.dart';
import '../nodes/layer_node.dart';
import '../nodes/shape_node.dart';
import '../nodes/stroke_node.dart';
import '../nodes/text_node.dart';
import '../nodes/image_node.dart';
import '../nodes/path_node.dart';
import './canvas_node.dart';

/// Double-dispatch visitor for type-safe scene graph traversal.
///
/// Canvas-core defines visit methods for the **base** node types that ship
/// with the SDK. Consumer packages (e.g. fluera_engine) contribute their
/// own node classes (LaTeX, Tabular, PDF, VectorNetwork, ...) whose
/// [CanvasNode.accept] forwards to [visitOther]. Those packages typically
/// extend [DefaultNodeVisitor] and override [visitOther] to downcast and
/// dispatch to their own visit methods.
abstract class NodeVisitor<R> {
  R visitGroup(GroupNode node);
  R visitLayer(LayerNode node);
  R visitShape(ShapeNode node);
  R visitStroke(StrokeNode node);
  R visitText(TextNode node);
  R visitImage(ImageNode node);
  R visitPath(PathNode node);

  /// Fallback for nodes whose concrete type lives outside canvas-core.
  /// Engine-only nodes (LaTeX, Tabular, PDF, ...) dispatch here.
  R visitOther(CanvasNode node);
}

/// Default implementation that returns a fallback value for every node type.
///
/// Extend this instead of [NodeVisitor] when you only care about a few
/// node types and want no-ops for the rest.
class DefaultNodeVisitor<R> implements NodeVisitor<R> {
  /// Value returned for unhandled node types.
  final R defaultValue;

  DefaultNodeVisitor(this.defaultValue);

  @override
  R visitGroup(GroupNode node) => defaultValue;
  @override
  R visitLayer(LayerNode node) => defaultValue;
  @override
  R visitShape(ShapeNode node) => defaultValue;
  @override
  R visitStroke(StrokeNode node) => defaultValue;
  @override
  R visitText(TextNode node) => defaultValue;
  @override
  R visitImage(ImageNode node) => defaultValue;
  @override
  R visitPath(PathNode node) => defaultValue;
  @override
  R visitOther(CanvasNode node) => defaultValue;
}
