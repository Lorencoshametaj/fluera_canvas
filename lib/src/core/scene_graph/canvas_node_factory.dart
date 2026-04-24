import './canvas_node.dart';
import './node_id.dart';
import '../nodes/group_node.dart';
import '../nodes/layer_node.dart';
import '../nodes/stroke_node.dart';
import '../nodes/shape_node.dart';
import '../nodes/text_node.dart';
import '../nodes/image_node.dart';
import '../nodes/path_node.dart';

/// Factory for deserializing [CanvasNode] subclasses from JSON.
///
/// Canvas-core ships built-in cases for the base node types (stroke, shape,
/// text, image, group, layer, path). Consumer packages (fluera_engine and
/// friends) register their own node types by setting
/// [CanvasNodeFactory.externalFactory] — typically at app init, wiring it
/// up to their module registry. When the hardcoded switch does not match
/// the [nodeType], the factory calls out to [externalFactory]; if that
/// returns null, an [ArgumentError] is thrown.
class CanvasNodeFactory {
  /// Optional external hook that fluera_engine (or any add-on) can install
  /// to deserialize nodeTypes unknown to canvas core. It receives the raw
  /// JSON map and returns either a [CanvasNode] or null (meaning "not mine").
  static CanvasNode? Function(Map<String, dynamic> json)? externalFactory;

  /// Create a [CanvasNode] from its JSON representation.
  ///
  /// Throws [ArgumentError] if the `nodeType` is unknown AND no external
  /// factory handled it.
  static CanvasNode fromJson(Map<String, dynamic> json) {
    final nodeType = json['nodeType'] as String?;

    // ── Tier 1: external registry (engine module registry, add-ons). ──
    final ext = externalFactory?.call(json);
    if (ext != null) return ext;

    // ── Tier 2: canvas built-in node types ──
    switch (nodeType) {
      case 'stroke':
        return StrokeNode.fromJson(json);

      case 'shape':
        return ShapeNode.fromJson(json);

      case 'text':
        return TextNode.fromJson(json);

      case 'image':
        return ImageNode.fromJson(json);

      case 'group':
        final group = GroupNode(id: NodeId(json['id'] as String));
        CanvasNode.applyBaseFromJson(group, json);
        if (json['children'] != null) {
          group.loadChildrenFromJson(
            json['children'] as List<dynamic>,
            fromJson,
          );
        }
        return group;

      case 'layer':
        return layerFromJson(json);

      case 'path':
        return PathNode.fromJson(json);

      default:
        throw ArgumentError('Unknown nodeType: $nodeType');
    }
  }

  /// Create a [LayerNode] from JSON.
  static LayerNode layerFromJson(Map<String, dynamic> json) {
    final layer = LayerNode(id: NodeId(json['id'] as String));
    CanvasNode.applyBaseFromJson(layer, json);
    if (json['children'] != null) {
      layer.loadChildrenFromJson(json['children'] as List<dynamic>, fromJson);
    }
    return layer;
  }

  /// 🚀 LAZY DECODE: Create a [LayerNode] from JSON, skipping stroke children.
  static LayerNode layerFromJsonMetadataOnly(Map<String, dynamic> json) {
    final layer = LayerNode(id: NodeId(json['id'] as String));
    CanvasNode.applyBaseFromJson(layer, json);
    if (json['children'] != null) {
      final nonStrokeChildren =
          (json['children'] as List<dynamic>)
              .where((c) => c is Map && c['nodeType'] != 'stroke')
              .toList();
      if (nonStrokeChildren.isNotEmpty) {
        layer.loadChildrenFromJson(nonStrokeChildren, fromJson);
      }
    }
    return layer;
  }
}
