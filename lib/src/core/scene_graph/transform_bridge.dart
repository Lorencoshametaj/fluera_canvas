import 'canvas_node.dart';

/// Bridge interface for notifying the [SceneGraph] when a node's
/// transform changes.
///
/// This breaks the circular import between `canvas_node.dart` and
/// `scene_graph.dart` while keeping full type safety (no `dynamic`).
abstract class TransformBridge {
  /// Called by [CanvasNode.invalidateTransformCache] when a node's
  /// world transform becomes stale.
  void onNodeTransformInvalidated(CanvasNode node);
}
