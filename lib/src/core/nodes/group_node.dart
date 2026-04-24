import 'package:flutter/material.dart';
import '../scene_graph/canvas_node.dart';
import '../scene_graph/node_visitor.dart';

/// A node that contains an ordered list of child [CanvasNode]s.
///
/// Children are rendered in list order (index 0 = bottom, last = top).
/// The group's [localBounds] is the union of all children's world bounds
/// transformed back into local space.
class GroupNode extends CanvasNode {
  final List<CanvasNode> _children = [];

  /// 🚀 O(1) child lookup by ID (maintained on add/remove).
  final Map<String, int> _childIdIndex = {};

  /// 🚀 Defer index rebuilds during batch operations.
  bool _deferIndexRebuild = false;
  bool _indexRebuildNeeded = false;
  bool _typedCacheInvalidNeeded = false;

  /// Cached bounds — invalidated when children change.
  Rect? _cachedLocalBounds;
  bool _boundsDirty = true;

  GroupNode({
    required super.id,
    super.name,
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
  });

  // ---------------------------------------------------------------------------
  // Children access
  // ---------------------------------------------------------------------------

  /// Read-only view of children.
  List<CanvasNode> get children => List.unmodifiable(_children);

  /// Number of children.
  int get childCount => _children.length;

  /// Whether this group has no children.
  bool get isEmpty => _children.isEmpty;

  // ---------------------------------------------------------------------------
  // Modification
  // ---------------------------------------------------------------------------

  /// Add a child at the end (top of z-order).
  ///
  /// Throws [StateError] if adding [child] would create a cycle.
  void add(CanvasNode child) {
    _assertNoCycle(child);
    assert(
      !_childIdIndex.containsKey(child.id),
      'Duplicate child ID "${child.id}" in ${this.id}',
    );
    child.parent = this;
    _childIdIndex[child.id] = _children.length;
    _children.add(child);
    invalidateTypedCaches();
    _expandBoundsIncremental(child);
  }

  /// Expand the cached bounds to include [child]'s world bounds
  /// without recomputing the entire subtree.
  void _expandBoundsIncremental(CanvasNode child) {
    if (_boundsDirty) return; // already dirty, nothing to expand
    final childBounds = child.worldBounds;
    if (childBounds.isEmpty) return;

    final inverse = Matrix4.tryInvert(worldTransform);
    final localChildBounds =
        inverse != null
            ? MatrixUtils.transformRect(inverse, childBounds)
            : childBounds;

    final current = _cachedLocalBounds ?? Rect.zero;
    _cachedLocalBounds =
        current.isEmpty
            ? localChildBounds
            : current.expandToInclude(localChildBounds);
    // Propagate upward — parent group's bounds depend on ours.
    if (parent is GroupNode) {
      (parent as GroupNode).invalidateBoundsCache();
    }
  }

  /// Insert a child at a specific z-index.
  ///
  /// Throws [StateError] if adding [child] would create a cycle.
  void insertAt(int index, CanvasNode child) {
    _assertNoCycle(child);
    assert(
      !_childIdIndex.containsKey(child.id),
      'Duplicate child ID "${child.id}" in ${this.id}',
    );
    child.parent = this;
    _children.insert(index, child);
    _rebuildIdIndex();
    invalidateTypedCaches();
    invalidateBoundsCache();
  }

  /// Remove a child by reference.
  bool remove(CanvasNode child) {
    final removed = _children.remove(child);
    if (removed) {
      child.parent = null;
      _rebuildIdIndex();
      invalidateTypedCaches();
      invalidateBoundsCache();
    }
    return removed;
  }

  /// Remove a child by ID. O(1) lookup via HashMap index,
  /// or O(N) linear scan when index rebuild is deferred (batch mode).
  CanvasNode? removeById(String nodeId) {
    int? index;
    if (_deferIndexRebuild) {
      // 🚀 During batch operations, _childIdIndex is stale after the
      // first removal. Fall back to linear scan to find the correct
      // position. O(N) but safe — batch operations are already O(N).
      for (int i = 0; i < _children.length; i++) {
        if (_children[i].id == nodeId) {
          index = i;
          break;
        }
      }
    } else {
      index = _childIdIndex[nodeId];
    }
    if (index == null) return null;
    final child = _children.removeAt(index);
    child.parent = null;
    _rebuildIdIndex();
    // 🚀 During batch mode, defer cache invalidation — the caller
    // has already snapshot the strokes list. Rebuilding caches on
    // every removal causes O(N²) allocations (30 eraseAt × 181 strokes).
    if (_deferIndexRebuild) {
      _typedCacheInvalidNeeded = true;
    } else {
      invalidateTypedCaches();
      invalidateBoundsCache();
    }
    return child;
  }

  /// Remove a child at a specific index.
  CanvasNode removeAt(int index) {
    final child = _children.removeAt(index);
    child.parent = null;
    _rebuildIdIndex();
    invalidateTypedCaches();
    invalidateBoundsCache();
    return child;
  }

  /// Move a child from [oldIndex] to [newIndex].
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final child = _children.removeAt(oldIndex);
    // Adjust index after removal
    final adjustedIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    _children.insert(adjustedIndex, child);
    _rebuildIdIndex();
    invalidateTypedCaches();
    invalidateBoundsCache();
  }

  /// Remove all children.
  void clear() {
    for (final child in _children) {
      child.parent = null;
    }
    _children.clear();
    _childIdIndex.clear();
    invalidateTypedCaches();
    invalidateBoundsCache();
  }

  // ---------------------------------------------------------------------------
  // Query
  // ---------------------------------------------------------------------------

  /// Find a child by ID (non-recursive). O(1) via HashMap.
  CanvasNode? findChild(String nodeId) {
    final index = _childIdIndex[nodeId];
    if (index == null) return null;
    return _children[index];
  }

  /// Recursively find a node by ID in this subtree.
  CanvasNode? findDescendant(String nodeId) {
    // O(1) check direct children first
    final direct = findChild(nodeId);
    if (direct != null) return direct;
    // Then recurse
    for (final child in _children) {
      if (child is GroupNode) {
        final found = child.findDescendant(nodeId);
        if (found != null) return found;
      }
    }
    return null;
  }

  /// Index of a child, or -1 if not found.
  int indexOf(CanvasNode child) => _children.indexOf(child);

  /// Index of a child by ID, or -1 if not found. O(1) via HashMap.
  int indexOfById(String nodeId) => _childIdIndex[nodeId] ?? -1;

  // ---------------------------------------------------------------------------
  // Typed convenience getters
  // ---------------------------------------------------------------------------

  /// All children of type [T].
  List<T> childrenOfType<T extends CanvasNode>() =>
      _children.whereType<T>().toList();

  // ---------------------------------------------------------------------------
  // Internal index maintenance
  // ---------------------------------------------------------------------------

  /// Rebuild the id→index map after mutations that shift indices.
  void _rebuildIdIndex() {
    if (_deferIndexRebuild) {
      _indexRebuildNeeded = true;
      return;
    }
    _childIdIndex.clear();
    for (int i = 0; i < _children.length; i++) {
      _childIdIndex[_children[i].id] = i;
    }
  }

  /// Begin deferring index rebuilds (for batch operations).
  void beginDeferIndexRebuild() {
    _deferIndexRebuild = true;
  }

  /// Flush deferred index rebuild and cache invalidation.
  void endDeferIndexRebuild() {
    _deferIndexRebuild = false;
    if (_indexRebuildNeeded) {
      _indexRebuildNeeded = false;
      _rebuildIdIndex();
    }
    if (_typedCacheInvalidNeeded) {
      _typedCacheInvalidNeeded = false;
      invalidateTypedCaches();
      invalidateBoundsCache();
    }
  }

  /// Hook for subclasses (LayerNode) to invalidate typed caches.
  @mustCallSuper
  void invalidateTypedCaches() {}

  // ---------------------------------------------------------------------------
  // Bounds
  // ---------------------------------------------------------------------------

  @override
  Rect get localBounds {
    if (!_boundsDirty && _cachedLocalBounds != null) {
      return _cachedLocalBounds!;
    }

    if (_children.isEmpty) {
      _cachedLocalBounds = Rect.zero;
      _boundsDirty = false;
      return Rect.zero;
    }

    // Compute the inverse ONCE — it doesn't change across children.
    final inverse = Matrix4.tryInvert(worldTransform);

    Rect? result;
    for (final child in _children) {
      if (!child.isVisible) continue;
      final childBounds = child.worldBounds;
      if (childBounds.isEmpty) continue;

      // Transform child world bounds back to our local space
      final localChildBounds =
          inverse != null
              ? MatrixUtils.transformRect(inverse, childBounds)
              : childBounds;

      result =
          result == null
              ? localChildBounds
              : result.expandToInclude(localChildBounds);
    }

    _cachedLocalBounds = result ?? Rect.zero;
    _boundsDirty = false;
    return _cachedLocalBounds!;
  }

  /// Invalidate the cached bounds for this group and propagate upward.
  ///
  /// Called when children are added, removed, reordered, or when
  /// a child's transform changes.
  void invalidateBoundsCache() {
    _boundsDirty = true;
    _cachedLocalBounds = null;
    // Propagate upward — parent group's bounds depend on ours.
    if (parent is GroupNode) {
      (parent as GroupNode).invalidateBoundsCache();
    }
  }

  // ---------------------------------------------------------------------------
  // Hit testing
  // ---------------------------------------------------------------------------

  /// Hit test children in reverse z-order (top to bottom).
  /// Returns the topmost hit child, or null.
  CanvasNode? hitTestChildren(Offset worldPoint) {
    for (int i = _children.length - 1; i >= 0; i--) {
      final child = _children[i];
      if (!child.isVisible) continue;

      if (child is GroupNode) {
        final hit = child.hitTestChildren(worldPoint);
        if (hit != null) return hit;
      }

      if (child.hitTest(worldPoint)) return child;
    }
    return null;
  }

  @override
  bool hitTest(Offset worldPoint) {
    if (!isVisible) return false;
    return hitTestChildren(worldPoint) != null;
  }

  // ---------------------------------------------------------------------------
  // Iteration
  // ---------------------------------------------------------------------------

  /// Iterate over all descendant nodes (depth-first).
  Iterable<CanvasNode> get allDescendants sync* {
    for (final child in _children) {
      yield child;
      if (child is GroupNode) {
        yield* child.allDescendants;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'group';
    json['children'] = _children.map((c) => c.toJson()).toList();
    return json;
  }

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitGroup(this);

  /// Restore children from JSON. Call after constructing the GroupNode.
  void loadChildrenFromJson(
    List<dynamic> childrenJson,
    CanvasNode Function(Map<String, dynamic>) nodeFactory,
  ) {
    _children.clear();
    _childIdIndex.clear();
    for (final childJson in childrenJson) {
      final child = nodeFactory(childJson as Map<String, dynamic>);
      child.parent = this;
      _childIdIndex[child.id] = _children.length;
      _children.add(child);
    }
    invalidateTypedCaches();
    invalidateBoundsCache();
  }

  // ---------------------------------------------------------------------------
  // Transform cache
  // ---------------------------------------------------------------------------

  /// Invalidate cached world transform for this node and all descendants.
  ///
  /// When a parent moves, every child's world transform is stale.
  /// Uses lazy top-down marking (GAP 6): the `invalidateTransformCache()`
  /// on each child only sets dirty flags — the actual O(depth) matrix
  /// multiplication happens lazily when `worldTransform` is first accessed.
  ///
  /// The `propagatingTransform_` flag ensures that children don't
  /// individually fire `onNodeTransformInvalidated` on the SceneGraph
  /// bridge, avoiding O(n²) cascade storms.
  @override
  void invalidateTransformCache() {
    super.invalidateTransformCache();
    invalidateBoundsCache();
    for (final child in _children) {
      child.propagatingTransform_ = true;
      child.invalidateTransformCache();
      child.propagatingTransform_ = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  /// Verify that [child] is not an ancestor of this node (cycle prevention).
  void _assertNoCycle(CanvasNode child) {
    CanvasNode? current = this;
    while (current != null) {
      if (identical(current, child)) {
        throw StateError(
          'Cannot add node "${child.id}" as its own descendant — '
          'this would create a cycle in the scene graph.',
        );
      }
      current = current.parent;
    }
  }
}
