import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/widgets.dart';

import '../../core/models/image_element.dart';
import '../../core/nodes/image_node.dart';
import '../../core/scene_graph/node_id.dart';
import '../../rendering/canvas/image_node_painter.dart';
import '../../utils/uid.dart' show generateUid;
import '../fluera_canvas_widget.dart' show FlueraCanvasState;

/// Imperative entry-point for the 0.6.0 image tool.
///
/// Opens the platform-native file picker (Android / iOS / macOS / Linux /
/// Windows / Web all covered by `file_selector`'s federated plugin
/// implementations), decodes the chosen image into a `ui.Image`,
/// registers it with [ImageNodePainter]'s cache, then commits a fresh
/// [ImageNode] on the canvas's active layer as a single undoable step.
///
/// Returns the committed node, or `null` when the user cancelled the
/// picker. Callers don't need to wire `CanvasTool.image` — the tool is
/// imperative on purpose, the enum value exists only so the toolbar
/// segmented control has a slot for it.
class FlueraImageTool {
  FlueraImageTool._();

  /// File extensions accepted by the picker. Image-only by default.
  static const List<String> kDefaultExtensions = <String>[
    'png',
    'jpg',
    'jpeg',
    'webp',
    'gif',
    'bmp',
  ];

  /// Open the picker, decode the chosen image, commit it on
  /// `state.activeLayer`. The image is positioned at the centre of
  /// the current viewport (or `worldPosition` when explicitly given)
  /// and inserted at its native pixel dimensions.
  static Future<ImageNode?> pickAndCommit(
    BuildContext context,
    FlueraCanvasState state, {
    List<String> extensions = kDefaultExtensions,
    Offset? worldPosition,
  }) async {
    final XTypeGroup typeGroup = XTypeGroup(
      label: 'images',
      extensions: extensions,
    );
    final XFile? file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[typeGroup],
    );
    if (file == null) return null;
    final Uint8List bytes = await file.readAsBytes();
    return commitBytes(
      state,
      bytes: bytes,
      label: file.name,
      worldPosition: worldPosition,
    );
  }

  /// Decode [bytes] and commit them on `state.activeLayer`. Useful
  /// when the consumer already has the bytes (clipboard paste, network
  /// fetch, drag-and-drop) and wants to skip the file picker. Returns
  /// the new node, or `null` if decoding failed (e.g. corrupt bytes).
  static Future<ImageNode?> commitBytes(
    FlueraCanvasState state, {
    required Uint8List bytes,
    String? label,
    Offset? worldPosition,
  }) async {
    final ui.Image image;
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      image = frame.image;
    } catch (_) {
      return null;
    }
    final id = generateUid();
    // Mint a unique cache key for this image instance. We DON'T reuse
    // the file path even when one is available — picking the same file
    // twice should produce two independent canvas nodes (the user may
    // expect to drop the second one elsewhere or transform it
    // separately).
    final imagePath =
        'fluera-canvas://memory/$id${label != null ? '/$label' : ''}';
    // Register both the decoded `ui.Image` and the original encoded
    // bytes so the canvas serializer (FCV0 v4+) can persist the asset.
    ImageNodePainter.cacheWithBytes(imagePath, image, bytes);
    final element = ImageElement(
      id: id,
      imagePath: imagePath,
      position: worldPosition ?? Offset.zero,
      createdAt: DateTime.now(),
      pageIndex: 0,
    );
    final node = ImageNode(
      id: NodeId(id),
      imageElement: element,
      imageSize: Size(image.width.toDouble(), image.height.toDouble()),
    );
    state.addImageNode(node);
    return node;
  }
}
