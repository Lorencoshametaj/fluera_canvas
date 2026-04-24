import 'dart:ui';
import '../scene_graph/canvas_node.dart';
import 'package:fluera_canvas/fluera_canvas.dart';
import '../scene_graph/node_visitor.dart';
import '../models/digital_text_element.dart';

/// Scene graph node that wraps a [DigitalTextElement].
///
/// The text's position is stored in [localTransform] (translation component).
/// The original [DigitalTextElement.position] is used to initialize the
/// transform; subsequent moves update only the matrix.
class TextNode extends CanvasNode {
  /// The actual text element data.
  DigitalTextElement textElement;

  /// Cached text bounds (width × height from TextPainter).
  /// Updated externally when the text is laid out.
  Size _cachedTextSize = Size.zero;

  TextNode({
    required super.id,
    required this.textElement,
    super.name = '',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
  });

  /// Set the measured text size (called after layout).
  set cachedTextSize(Size size) => _cachedTextSize = size;
  Size get cachedTextSize => _cachedTextSize;

  // ---------------------------------------------------------------------------
  // Bounds
  // ---------------------------------------------------------------------------

  @override
  Rect get localBounds {
    final effectiveScale = textElement.scale;
    final w =
        _cachedTextSize.width > 0
            ? _cachedTextSize.width * effectiveScale
            : textElement.fontSize *
                textElement.text.length *
                0.6 *
                effectiveScale;
    final h =
        _cachedTextSize.height > 0
            ? _cachedTextSize.height * effectiveScale
            : textElement.fontSize * 1.4 * effectiveScale;

    return Rect.fromLTWH(
      textElement.position.dx,
      textElement.position.dy,
      w,
      h,
    );
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'text';
    json['text'] = textElement.toJson();
    return json;
  }

  factory TextNode.fromJson(Map<String, dynamic> json) {
    final node = TextNode(
      id: NodeId(json['id'] as String),
      textElement: DigitalTextElement.fromJson(
        json['text'] as Map<String, dynamic>,
      ),
    );
    CanvasNode.applyBaseFromJson(node, json);
    return node;
  }

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitText(this);

  @override
  String toString() =>
      'TextNode(id: $id, text: "${textElement.text.length > 20 ? textElement.text.substring(0, 20) : textElement.text}")';
}
