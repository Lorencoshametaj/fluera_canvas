import 'dart:typed_data';
import 'dart:ui';
import './canvas_node.dart';
import 'package:fluera_canvas/fluera_canvas.dart';
import '../nodes/group_node.dart';

/// Immutable read-only projection of a [CanvasNode].
///
/// Unlike [CanvasNode], which is inherently mutable (e.g. [localTransform]),
/// [FrozenNodeView] exposes only getters and unmodifiable data structures.
/// This guarantees that consumers (like plugins or background threads)
/// cannot accidentally or maliciously mutate the scene graph.
class FrozenNodeView {
  /// Field `id`.
  final NodeId id;
  /// Field `name`.
  final String name;
  /// Field `typeName`.
  final String typeName;
  /// Field `worldBounds`.
  final Rect worldBounds;
  /// Field `localBounds`.
  final Rect localBounds;
  /// Field `opacity`.
  final double opacity;
  /// Field `blendMode`.
  final BlendMode blendMode;
  /// Field `isVisible`.
  final bool isVisible;
  /// Field `isLocked`.
  final bool isLocked;
  /// Field `transformStorage`.
  final Float64List transformStorage;
  /// Field `children`.
  final List<FrozenNodeView> children;

  FrozenNodeView._({
    required this.id,
    required this.name,
    required this.typeName,
    required this.worldBounds,
    required this.localBounds,
    required this.opacity,
    required this.blendMode,
    required this.isVisible,
    required this.isLocked,
    required this.transformStorage,
    required this.children,
  });

  /// Create a frozen, deeply-immutable snapshot of the given [node].
  factory FrozenNodeView.from(CanvasNode node) {
    // recursively freeze children if it's a group
    final children = <FrozenNodeView>[];
    if (node is GroupNode) {
      for (final child in node.children) {
        children.add(FrozenNodeView.from(child));
      }
    }

    return FrozenNodeView._(
      id: node.id,
      name: node.name,
      typeName: node.runtimeType.toString(),
      worldBounds: node.worldBounds,
      localBounds: node.localBounds,
      opacity: node.opacity,
      blendMode: node.blendMode,
      isVisible: node.isVisible,
      isLocked: node.isLocked,
      transformStorage: Float64List.fromList(node.worldTransform.storage),
      children: List.unmodifiable(children),
    );
  }
}
