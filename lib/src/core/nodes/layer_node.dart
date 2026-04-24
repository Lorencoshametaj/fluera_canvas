import './group_node.dart';
import 'package:fluera_canvas/fluera_canvas.dart';
import '../scene_graph/node_visitor.dart';
import './stroke_node.dart';
import './shape_node.dart';
import './text_node.dart';
import './image_node.dart';
import '../models/digital_text_element.dart';
import '../models/image_element.dart';

/// A [GroupNode] that represents a canvas layer.
///
/// Layers are the top-level grouping mechanism in the scene graph.
/// Each layer is a direct child of the root node. A [LayerNode] provides
/// typed convenience getters to query its children by element type,
/// preserving the familiar API while storing everything in a unified
/// children list with proper z-ordering.
class LayerNode extends GroupNode {
  LayerNode({
    required super.id,
    super.name = 'Layer',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
  });

  // ---------------------------------------------------------------------------
  // 🚀 Cached typed getters (invalidated on child add/remove/reorder)
  // ---------------------------------------------------------------------------

  List<StrokeNode>? _cachedStrokeNodes;
  List<ShapeNode>? _cachedShapeNodes;
  List<ProStroke>? _cachedStrokes;
  List<GeometricShape>? _cachedShapes;

  @override
  void invalidateTypedCaches() {
    super.invalidateTypedCaches();
    _cachedStrokeNodes = null;
    _cachedShapeNodes = null;
    _cachedStrokes = null;
    _cachedShapes = null;
  }

  /// 🛡️ Invalidate only stroke caches (used by save pipeline after
  /// restoring paged-out stubs on StrokeNode.stroke).
  void invalidateStrokeCache() {
    _cachedStrokeNodes = null;
    _cachedStrokes = null;
  }

  // ---------------------------------------------------------------------------
  // Typed convenience getters (cached)
  // ---------------------------------------------------------------------------

  /// All stroke nodes in this layer.
  List<StrokeNode> get strokeNodes =>
      _cachedStrokeNodes ??= childrenOfType<StrokeNode>();

  /// All shape nodes in this layer.
  List<ShapeNode> get shapeNodes =>
      _cachedShapeNodes ??= childrenOfType<ShapeNode>();

  /// All text nodes in this layer.
  List<TextNode> get textNodes => childrenOfType<TextNode>();

  /// All image nodes in this layer.
  List<ImageNode> get imageNodes => childrenOfType<ImageNode>();

  // Engine-only node convenience getters (AdjustmentLayerNode,
  // FunctionGraphNode) live in fluera_engine via extension methods.

  /// All ProStroke objects in this layer (convenience for rendering).
  List<ProStroke> get strokes =>
      _cachedStrokes ??= strokeNodes.map((n) => n.stroke).toList();

  /// All GeometricShape objects in this layer.
  List<GeometricShape> get shapes =>
      _cachedShapes ??= shapeNodes.map((n) => n.shape).toList();

  /// All DigitalTextElement objects in this layer.
  List<DigitalTextElement> get texts =>
      textNodes.map((n) => n.textElement).toList();

  /// All ImageElement objects in this layer.
  List<ImageElement> get images =>
      imageNodes.map((n) => n.imageElement).toList();

  // ---------------------------------------------------------------------------
  // Typed add helpers
  // ---------------------------------------------------------------------------

  /// Add a stroke to this layer. Returns the created StrokeNode.
  StrokeNode addStroke(ProStroke stroke) {
    final node = StrokeNode(id: NodeId(stroke.id), stroke: stroke);
    add(node);
    return node;
  }

  /// Add a shape to this layer. Returns the created ShapeNode.
  ShapeNode addShape(GeometricShape shape) {
    final node = ShapeNode(id: NodeId(shape.id), shape: shape);
    add(node);
    return node;
  }

  /// Add a text element to this layer. Returns the created TextNode.
  TextNode addText(DigitalTextElement text) {
    final node = TextNode(id: NodeId(text.id), textElement: text);
    add(node);
    return node;
  }

  /// Add an image element to this layer. Returns the created ImageNode.
  ImageNode addImage(ImageElement image) {
    final node = ImageNode(id: NodeId(image.id), imageElement: image);
    add(node);
    return node;
  }

  // Engine-only node type add helpers (AdjustmentLayerNode, FunctionGraphNode)
  // live in fluera_engine via extension methods.

  // ---------------------------------------------------------------------------
  // Typed remove helpers
  // ---------------------------------------------------------------------------

  /// Remove a stroke by its ID. Returns true if found and removed.
  bool removeStrokeById(String strokeId) {
    return removeById(strokeId) != null;
  }

  /// Remove a shape by its ID.
  bool removeShapeById(String shapeId) {
    return removeById(shapeId) != null;
  }

  /// Remove a text element by its ID.
  bool removeTextById(String textId) {
    return removeById(textId) != null;
  }

  /// Remove an image element by its ID.
  bool removeImageById(String imageId) {
    return removeById(imageId) != null;
  }

  /// Remove an adjustment layer by its ID.
  bool removeAdjustmentLayerById(String adjustmentId) {
    return removeById(adjustmentId) != null;
  }

  /// Remove a function graph by its ID.
  bool removeGraphById(String graphId) {
    return removeById(graphId) != null;
  }

  // ---------------------------------------------------------------------------
  // Typed find helpers
  // ---------------------------------------------------------------------------

  /// Find a stroke node by its stroke ID.
  StrokeNode? findStrokeNode(String strokeId) {
    final node = findChild(strokeId);
    return node is StrokeNode ? node : null;
  }

  /// Find a shape node by its shape ID.
  ShapeNode? findShapeNode(String shapeId) {
    final node = findChild(shapeId);
    return node is ShapeNode ? node : null;
  }

  /// Find a text node by its text element ID.
  TextNode? findTextNode(String textId) {
    final node = findChild(textId);
    return node is TextNode ? node : null;
  }

  /// Find an image node by its image element ID.
  ImageNode? findImageNode(String imageId) {
    final node = findChild(imageId);
    return node is ImageNode ? node : null;
  }

  // findGraphNode lives in fluera_engine (it returns the engine-only
  // FunctionGraphNode type).

  // ---------------------------------------------------------------------------
  // Update helpers
  // ---------------------------------------------------------------------------

  /// Update a text element in-place.
  bool updateText(DigitalTextElement updatedText) {
    final node = findTextNode(updatedText.id);
    if (node == null) return false;
    node.textElement = updatedText;
    return true;
  }

  /// Update an image element in-place.
  bool updateImage(ImageElement updatedImage) {
    final node = findImageNode(updatedImage.id);
    if (node == null) return false;
    node.imageElement = updatedImage;
    return true;
  }

  // ---------------------------------------------------------------------------
  // Counts
  // ---------------------------------------------------------------------------

  /// Total element count (all types).
  int get elementCount => childCount;

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'layer';
    json['children'] = children.map((c) => c.toJson()).toList();
    return json;
  }

  /// 🚀 PERF: Serialize layer metadata WITHOUT stroke data.
  ///
  /// Used by the sharded cloud save path where strokes are saved to a
  /// subcollection. Skips `StrokeNode.toJson()` for all stroke children,
  /// avoiding ~1MB of temporary allocation (300+ strokes × ~3KB each).
  Map<String, dynamic> toJsonMetadataOnly() {
    final json = baseToJson();
    json['nodeType'] = 'layer';
    json['children'] =
        children.where((c) => c is! StrokeNode).map((c) => c.toJson()).toList();
    return json;
  }

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitLayer(this);
}
