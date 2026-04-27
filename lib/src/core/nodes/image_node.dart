import 'dart:ui';
import '../scene_graph/canvas_node.dart';
import 'package:fluera_canvas/fluera_canvas.dart';
import '../scene_graph/node_visitor.dart';
import '../models/image_element.dart';
import 'canvas_stroke_node.dart';

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

  /// API element `ImageNode`.
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
  /// Getter `imageSize`.
  Size get imageSize => _imageSize;

  /// Strokes drawn ON this image. Stored in the image's *local* coords
  /// (i.e. as if the image were axis-aligned at its native position):
  /// the painter walks them under `canvas.transform(localTransform)` so
  /// they ride every move / rotate / scale applied to the image as a
  /// single rigid block. Populated by `_onDrawEnd` whenever a stroke
  /// (or stroke segment) lies inside this image's local bounds.
  /// Live strokes that cross the image boundary get split: the inside
  /// run lands here, the outside run stays a free child of the active
  /// layer.
  final List<CanvasStrokeNode> annotations = <CanvasStrokeNode>[];

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

  /// API element `fromJson`.
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
