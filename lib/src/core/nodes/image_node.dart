import 'dart:ui';
import '../scene_graph/canvas_node.dart';
import 'package:fluera_canvas/fluera_canvas.dart';
import '../scene_graph/node_visitor.dart';
import '../models/image_element.dart';

/// Scene graph node that wraps an [ImageElement].
///
/// The image's position, scale, and rotation from [ImageElement] are
/// kept in the element for backward compatibility. The [localTransform]
/// is identity by default — the rendering pipeline uses [imageElement]'s
/// own position/scale/rotation directly for now.
class ImageNode extends CanvasNode {
  /// The actual image element data.
  ImageElement imageElement;

  /// Cached image dimensions (set after decoding).
  Size _imageSize;

  ImageNode({
    required super.id,
    required this.imageElement,
    Size imageSize = Size.zero,
    super.name = '',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
  }) : _imageSize = imageSize;

  /// Set the decoded image dimensions.
  set imageSize(Size size) => _imageSize = size;
  Size get imageSize => _imageSize;

  // ---------------------------------------------------------------------------
  // Bounds
  // ---------------------------------------------------------------------------

  @override
  Rect get localBounds {
    final pos = imageElement.position;
    final scale = imageElement.scale;

    // Use actual image dimensions if available, otherwise estimate
    final w = _imageSize.width > 0 ? _imageSize.width * scale : 200.0 * scale;
    final h = _imageSize.height > 0 ? _imageSize.height * scale : 200.0 * scale;

    return Rect.fromLTWH(pos.dx, pos.dy, w, h);
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'image';
    json['image'] = imageElement.toJson();
    return json;
  }

  factory ImageNode.fromJson(Map<String, dynamic> json) {
    final node = ImageNode(
      id: NodeId(json['id'] as String),
      imageElement: ImageElement.fromJson(
        json['image'] as Map<String, dynamic>,
      ),
    );
    CanvasNode.applyBaseFromJson(node, json);
    return node;
  }

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitImage(this);

  @override
  String toString() => 'ImageNode(id: $id, path: ${imageElement.imagePath})';
}
