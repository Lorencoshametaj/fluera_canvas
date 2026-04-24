import 'dart:ui';
import 'dart:math' as math;
import 'package:fluera_canvas/fluera_canvas.dart';

// ============================================================================
// Generic R-tree — Industry-standard spatial index
// ============================================================================

/// 🚀 Generic R-tree for O(log n) spatial queries.
///
/// PERFORMANCE with 10k+ items:
/// - Without R-tree: O(n) per frame → LAG
/// - With R-tree: O(log n) → SMOOTH ✨
///
/// ADVANTAGES over QuadTree:
/// - Items live in exactly ONE node (no duplication for overlapping bounds)
/// - Better worst-case for objects with large or overlapping bounds
/// - Bulk loading support: O(n log n) build time
/// - Industry standard (Figma, PostGIS, SQLite R*-tree)
///
/// OPTIMIZATIONS (v2):
/// - Lazy deletion: O(1) remove via tombstone set
/// - Short-circuit query: flat collect for fully-contained nodes
/// - Auto-compaction: periodic STR bulk rebuild after mutation threshold
/// - Wider fan-out (maxEntries=16): fewer tree levels at scale
///
/// Usage:
/// ```dart
/// final tree = RTree<MyItem>((item) => item.bounds);
/// tree.insert(item);
/// final visible = tree.queryVisible(viewport);
/// ```
class RTree<T> {
  /// Function to extract the bounding rect from an item.
  final Rect Function(T) _boundsOf;

  /// Maximum entries per node before split.
  final int _maxEntries;

  /// Minimum entries per node (typically maxEntries / 2).
  final int _minEntries;

  /// Root node of the tree.
  _RTreeNode<T>? _root;

  /// Total number of live items in the tree (excludes tombstones).
  int _count = 0;

  /// Tracks active query depth to prevent concurrent modification.
  /// Mutations during a query would corrupt internal node lists.
  int _queryDepth = 0;

  // ─── Lazy Deletion ──────────────────────────────────────────────
  // O(1) remove: mark items as dead, skip them during queries.
  // Periodic compaction rebuilds the tree without dead entries.

  /// Identity-based set of logically deleted items.
  final Set<T> _tombstones = Set<T>.identity();

  /// Identity-based set of live items (for O(1) membership check).
  final Set<T> _liveItems = Set<T>.identity();

  /// Number of tombstoned entries still physically in the tree.
  int _tombstoneCount = 0;

  /// Mutations (insert + remove) since last STR rebuild.
  int _mutationsSinceRebuild = 0;

  /// Threshold: auto-compact when tombstones exceed this fraction of live count.
  static const double _tombstoneCompactThreshold = 0.25;

  /// Threshold: auto-rebuild when total mutations exceed this fraction of count.
  static const double _mutationRebuildThreshold = 0.30;

  RTree(this._boundsOf, {int maxEntries = 16})
    : _maxEntries = maxEntries,
      _minEntries = (maxEntries / 2).ceil();

  /// Number of live items in the tree.
  int get count => _count;

  /// Whether the tree has no live items.
  bool get isEmpty => _count == 0;

  /// Number of tombstoned (logically deleted) items.
  int get tombstoneCount => _tombstoneCount;

  /// Guard against mutation during an active query.
  void _guardMutation(String operation) {
    if (_queryDepth > 0) {
      throw StateError(
        'RTree.$operation() called during an active query. '
        'Mutations during iteration would corrupt the tree. '
        'Buffer mutations and apply them after the query completes.',
      );
    }
  }

  // ─── Insert ──────────────────────────────────────────────────────

  /// ➕ Insert an item into the R-tree.
  void insert(T item) {
    _guardMutation('insert');
    final bounds = _boundsOf(item);
    if (bounds.isEmpty || !bounds.isFinite) return;

    // 🚀 If re-inserting a tombstoned item (undo/redo cycle),
    // just resurrect it — the entry is still physically in the tree.
    if (_tombstones.remove(item)) {
      _tombstoneCount--;
      _count++;
      _liveItems.add(item);
      _mutationsSinceRebuild++;
      return;
    }

    final entry = _Entry<T>(item: item, bounds: bounds);

    if (_root == null) {
      _root = _RTreeNode<T>(isLeaf: true);
    }

    final splitNode = _insertEntry(_root!, entry);

    // If root was split, create a new root.
    if (splitNode != null) {
      final newRoot = _RTreeNode<T>(isLeaf: false);
      newRoot.children.add(_root!);
      newRoot.children.add(splitNode);
      newRoot.recalculateBounds();
      _root = newRoot;
    }

    _count++;
    _liveItems.add(item);
    _mutationsSinceRebuild++;
  }

  // ─── Remove ──────────────────────────────────────────────────────

  /// ➖ Remove an item from the R-tree.
  ///
  /// O(1): marks the item as a tombstone. The entry remains physically
  /// in the tree but is excluded from all query results.
  /// Periodic compaction removes dead entries and rebuilds optimally.
  bool remove(T item) {
    _guardMutation('remove');
    if (_root == null || _count <= 0) return false;

    // Already tombstoned — idempotent
    if (_tombstones.contains(item)) return false;

    // Only tombstone items that are actually in the tree.
    if (!_liveItems.remove(item)) return false;

    _tombstones.add(item);
    _tombstoneCount++;
    _count--;
    _mutationsSinceRebuild++;
    return true;
  }

  /// 🗑️ Compact the tree: remove all tombstoned entries and rebuild
  /// via STR bulk-load for optimal node structure.
  ///
  /// Call this explicitly, or let it trigger automatically via
  /// [_maybeAutoCompact].
  void compact() {
    _guardMutation('compact');
    if (_root == null) {
      _tombstones.clear();
      _tombstoneCount = 0;
      _mutationsSinceRebuild = 0;
      return;
    }

    // Collect all live entries.
    final live = <_Entry<T>>[];
    _collectEntries(_root!, live);
    if (_tombstones.isNotEmpty) {
      live.removeWhere((e) => _tombstones.contains(e.item));
    }

    _tombstones.clear();
    _tombstoneCount = 0;
    _mutationsSinceRebuild = 0;

    // Rebuild _liveItems from surviving entries.
    _liveItems.clear();

    if (live.isEmpty) {
      _root = null;
      _count = 0;
      return;
    }

    for (final e in live) {
      _liveItems.add(e.item);
    }

    _root = _bulkLoad(live);
    _count = live.length;
  }

  // ─── Bulk Load ───────────────────────────────────────────────────

  /// 🏗️ Factory: build an R-tree from a list of items using Sort-Tile-Recursive
  /// (STR) bulk loading for optimal tree structure.
  factory RTree.fromItems(
    List<T> items,
    Rect Function(T) boundsOf, {
    int maxEntries = 16,
  }) {
    final tree = RTree<T>(boundsOf, maxEntries: maxEntries);
    if (items.isEmpty) return tree;

    // For small lists, just insert one by one.
    if (items.length <= maxEntries) {
      for (final item in items) {
        tree.insert(item);
      }
      return tree;
    }

    // STR bulk load: sort by center X, partition into slices,
    // within each slice sort by center Y, then build leaf nodes.
    final entries =
        items
            .map((item) => _Entry<T>(item: item, bounds: boundsOf(item)))
            .where((e) => e.bounds.isFinite && !e.bounds.isEmpty)
            .toList();

    tree._root = tree._bulkLoad(entries);
    tree._count = entries.length;
    for (final e in entries) {
      tree._liveItems.add(e.item);
    }
    return tree;
  }

  _RTreeNode<T> _bulkLoad(List<_Entry<T>> entries) {
    if (entries.length <= _maxEntries) {
      final node = _RTreeNode<T>(isLeaf: true);
      node.entries.addAll(entries);
      node.recalculateBounds();
      return node;
    }

    // Sort by center X.
    entries.sort((a, b) => a.bounds.center.dx.compareTo(b.bounds.center.dx));

    // Number of leaf nodes needed.
    final leafCount = (entries.length / _maxEntries).ceil();
    // Number of slices = sqrt(leafCount).
    final sliceCount = math.sqrt(leafCount.toDouble()).ceil();
    final sliceSize = (entries.length / sliceCount).ceil();

    final childNodes = <_RTreeNode<T>>[];

    for (int i = 0; i < entries.length; i += sliceSize) {
      final sliceEnd =
          (i + sliceSize) < entries.length ? (i + sliceSize) : entries.length;
      final slice = entries.sublist(i, sliceEnd);

      // Sort slice by center Y.
      slice.sort((a, b) => a.bounds.center.dy.compareTo(b.bounds.center.dy));

      // Create leaf nodes from the slice.
      for (int j = 0; j < slice.length; j += _maxEntries) {
        final nodeEnd =
            (j + _maxEntries) < slice.length ? (j + _maxEntries) : slice.length;
        final node = _RTreeNode<T>(isLeaf: true);
        node.entries.addAll(slice.sublist(j, nodeEnd));
        node.recalculateBounds();
        childNodes.add(node);
      }
    }

    // Recursively build internal nodes.
    return _buildInternalNodes(childNodes);
  }

  _RTreeNode<T> _buildInternalNodes(List<_RTreeNode<T>> nodes) {
    if (nodes.length <= _maxEntries) {
      final parent = _RTreeNode<T>(isLeaf: false);
      parent.children.addAll(nodes);
      parent.recalculateBounds();
      return parent;
    }

    // Group into chunks of _maxEntries.
    final parents = <_RTreeNode<T>>[];
    for (int i = 0; i < nodes.length; i += _maxEntries) {
      final end =
          (i + _maxEntries) < nodes.length ? (i + _maxEntries) : nodes.length;
      final parent = _RTreeNode<T>(isLeaf: false);
      parent.children.addAll(nodes.sublist(i, end));
      parent.recalculateBounds();
      parents.add(parent);
    }

    return _buildInternalNodes(parents);
  }

  // ─── Queries ─────────────────────────────────────────────────────

  /// 🔍 Query: returns items whose bounds intersect the viewport.
  ///
  /// PERFORMANCE: O(log n) instead of O(n).
  List<T> queryVisible(Rect viewport, {double margin = 1000.0}) {
    if (_root == null) return const [];

    final expandedViewport = viewport.inflate(margin);
    final results = <T>[];
    _queryDepth++;
    try {
      _queryRange(_root!, expandedViewport, results);
    } finally {
      _queryDepth--;
    }
    return results;
  }

  /// Whether compaction is needed based on tombstone/mutation thresholds.
  bool needsCompaction() {
    if (_count < 50) return false;
    if (_tombstoneCount > _count * _tombstoneCompactThreshold) return true;
    if (_mutationsSinceRebuild > _count * _mutationRebuildThreshold)
      return true;
    return false;
  }

  /// 📊 Statistics for debugging.
  Map<String, int> get stats {
    if (_root == null) {
      return {
        'totalItems': 0,
        'liveItems': 0,
        'tombstones': _tombstoneCount,
        'totalNodes': 0,
        'leafNodes': 0,
        'height': 0,
      };
    }
    final s = _collectStats(_root!);
    s['tombstones'] = _tombstoneCount;
    s['liveItems'] = _count;
    return s;
  }

  /// 🧹 Clear and reset the tree.
  void clear() {
    _guardMutation('clear');
    _root = null;
    _count = 0;
    _tombstones.clear();
    _liveItems.clear();
    _tombstoneCount = 0;
    _mutationsSinceRebuild = 0;
  }

  // ─── Internal: Insert ────────────────────────────────────────────

  /// Insert an entry, returning a split node if the node overflows.
  _RTreeNode<T>? _insertEntry(_RTreeNode<T> node, _Entry<T> entry) {
    if (node.isLeaf) {
      node.entries.add(entry);
      node.expandBounds(entry.bounds);

      if (node.entries.length > _maxEntries) {
        return _splitLeaf(node);
      }
      return null;
    }

    // Choose the child that needs least area enlargement.
    final bestChild = _chooseBestChild(node, entry.bounds);
    final splitChild = _insertEntry(bestChild, entry);

    node.recalculateBounds();

    if (splitChild != null) {
      node.children.add(splitChild);
      if (node.children.length > _maxEntries) {
        return _splitInternal(node);
      }
    }

    return null;
  }

  /// Choose the child node that requires the least area enlargement.
  _RTreeNode<T> _chooseBestChild(_RTreeNode<T> node, Rect entryBounds) {
    _RTreeNode<T>? best;
    double bestEnlargement = double.infinity;
    double bestArea = double.infinity;

    for (final child in node.children) {
      final merged = child.bounds.expandToInclude(entryBounds);
      final enlargement =
          (merged.width * merged.height) -
          (child.bounds.width * child.bounds.height);
      final area = child.bounds.width * child.bounds.height;

      // Prefer least enlargement; tie-break by smallest area.
      if (enlargement < bestEnlargement ||
          (enlargement == bestEnlargement && area < bestArea)) {
        bestEnlargement = enlargement;
        bestArea = area;
        best = child;
      }
    }

    return best!;
  }

  // ─── Internal: Split ─────────────────────────────────────────────

  /// Compute the axis with the largest variance (extent) among a list of bounds.
  /// Returns 0 for X-axis, 1 for Y-axis.
  int _chooseSplitAxis(Iterable<Rect> boundsList) {
    if (boundsList.isEmpty) return 0;
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final b in boundsList) {
      final cx = b.center.dx;
      final cy = b.center.dy;
      if (cx < minX) minX = cx;
      if (cx > maxX) maxX = cx;
      if (cy < minY) minY = cy;
      if (cy > maxY) maxY = cy;
    }
    return (maxX - minX) > (maxY - minY) ? 0 : 1;
  }

  /// Split a leaf node by sorting entries by the axis with the largest variance.
  _RTreeNode<T> _splitLeaf(_RTreeNode<T> node) {
    final entries = node.entries.toList();
    final axis = _chooseSplitAxis(entries.map((e) => e.bounds));

    if (axis == 0) {
      entries.sort((a, b) => a.bounds.center.dx.compareTo(b.bounds.center.dx));
    } else {
      entries.sort((a, b) => a.bounds.center.dy.compareTo(b.bounds.center.dy));
    }

    final mid = entries.length ~/ 2;
    node.entries.clear();
    node.entries.addAll(entries.sublist(0, mid));

    final sibling = _RTreeNode<T>(isLeaf: true);
    sibling.entries.addAll(entries.sublist(mid));

    node.recalculateBounds();
    sibling.recalculateBounds();
    return sibling;
  }

  /// Split an internal node by sorting children by the axis with the largest variance.
  _RTreeNode<T> _splitInternal(_RTreeNode<T> node) {
    final children = node.children.toList();
    final axis = _chooseSplitAxis(children.map((c) => c.bounds));

    if (axis == 0) {
      children.sort((a, b) => a.bounds.center.dx.compareTo(b.bounds.center.dx));
    } else {
      children.sort((a, b) => a.bounds.center.dy.compareTo(b.bounds.center.dy));
    }

    final mid = children.length ~/ 2;
    node.children.clear();
    node.children.addAll(children.sublist(0, mid));

    final sibling = _RTreeNode<T>(isLeaf: false);
    sibling.children.addAll(children.sublist(mid));

    node.recalculateBounds();
    sibling.recalculateBounds();
    return sibling;
  }

  // ─── Internal: Remove (kept for direct removal if needed) ───────

  bool _removeEntry(
    _RTreeNode<T> node,
    T item,
    Rect bounds,
    List<_Entry<T>> orphans,
  ) {
    if (!node.bounds.overlaps(bounds)) return false;

    if (node.isLeaf) {
      final idx = node.entries.indexWhere((e) => identical(e.item, item));
      if (idx < 0) return false;
      node.entries.removeAt(idx);
      node.recalculateBounds();
      return true;
    }

    for (int i = node.children.length - 1; i >= 0; i--) {
      final child = node.children[i];
      if (_removeEntry(child, item, bounds, orphans)) {
        // Check for underflow.
        if (child.isLeaf && child.entries.length < _minEntries) {
          // Collect orphan entries and remove this child.
          orphans.addAll(child.entries);
          node.children.removeAt(i);
        } else if (!child.isLeaf && child.children.length < _minEntries) {
          // Collect all leaf entries from this subtree.
          _collectEntries(child, orphans);
          node.children.removeAt(i);
        }
        node.recalculateBounds();
        return true;
      }
    }
    return false;
  }

  void _collectEntries(_RTreeNode<T> node, List<_Entry<T>> result) {
    if (node.isLeaf) {
      result.addAll(node.entries);
    } else {
      for (final child in node.children) {
        _collectEntries(child, result);
      }
    }
  }

  // ─── Internal: Query ─────────────────────────────────────────────

  void _queryRange(_RTreeNode<T> node, Rect range, List<T> results) {
    if (!node.bounds.overlaps(range)) return;

    // 🚀 SHORT-CIRCUIT: if the node is fully contained within the range,
    // ALL descendants are visible → flat collect without overlap checks.
    // This is a massive win at zoom-out (most strokes visible).
    if (_rectContains(range, node.bounds)) {
      _collectAllItems(node, results);
      return;
    }

    if (node.isLeaf) {
      for (final entry in node.entries) {
        // 🚀 Skip tombstoned items — O(1) identity hash lookup
        if (_tombstones.isNotEmpty && _tombstones.contains(entry.item)) {
          continue;
        }
        if (entry.bounds.overlaps(range)) {
          results.add(entry.item);
        }
      }
    } else {
      for (final child in node.children) {
        _queryRange(child, range, results);
      }
    }
  }

  /// 🚀 Fast flat collection of ALL items under a node.
  /// Used when the node is fully contained in the query range.
  /// Skips tombstoned items.
  void _collectAllItems(_RTreeNode<T> node, List<T> results) {
    if (node.isLeaf) {
      if (_tombstones.isEmpty) {
        // Hot path: no tombstones → zero overhead
        for (final entry in node.entries) {
          results.add(entry.item);
        }
      } else {
        for (final entry in node.entries) {
          if (!_tombstones.contains(entry.item)) {
            results.add(entry.item);
          }
        }
      }
    } else {
      for (final child in node.children) {
        _collectAllItems(child, results);
      }
    }
  }

  /// Check if [outer] fully contains [inner].
  static bool _rectContains(Rect outer, Rect inner) {
    return outer.left <= inner.left &&
        outer.top <= inner.top &&
        outer.right >= inner.right &&
        outer.bottom >= inner.bottom;
  }

  // ─── Internal: Stats ─────────────────────────────────────────────

  Map<String, int> _collectStats(_RTreeNode<T> node) {
    if (node.isLeaf) {
      return {
        'totalItems': node.entries.length,
        'totalNodes': 1,
        'leafNodes': 1,
        'height': 1,
      };
    }

    int totalItems = 0;
    int totalNodes = 1;
    int leafNodes = 0;
    int maxHeight = 0;

    for (final child in node.children) {
      final s = _collectStats(child);
      totalItems += s['totalItems']!;
      totalNodes += s['totalNodes']!;
      leafNodes += s['leafNodes']!;
      final h = s['height']!;
      if (h > maxHeight) maxHeight = h;
    }

    return {
      'totalItems': totalItems,
      'totalNodes': totalNodes,
      'leafNodes': leafNodes,
      'height': maxHeight + 1,
    };
  }
}

// ============================================================================
// Internal R-tree data structures
// ============================================================================

class _RTreeNode<T> {
  final bool isLeaf;
  Rect bounds;

  /// Child nodes (for internal nodes).
  final List<_RTreeNode<T>> children = [];

  /// Leaf entries (for leaf nodes).
  final List<_Entry<T>> entries = [];

  _RTreeNode({required this.isLeaf}) : bounds = Rect.zero;

  void expandBounds(Rect rect) {
    if (bounds == Rect.zero) {
      bounds = rect;
    } else {
      bounds = bounds.expandToInclude(rect);
    }
  }

  void recalculateBounds() {
    if (isLeaf) {
      if (entries.isEmpty) {
        bounds = Rect.zero;
        return;
      }
      bounds = entries.first.bounds;
      for (int i = 1; i < entries.length; i++) {
        bounds = bounds.expandToInclude(entries[i].bounds);
      }
    } else {
      if (children.isEmpty) {
        bounds = Rect.zero;
        return;
      }
      bounds = children.first.bounds;
      for (int i = 1; i < children.length; i++) {
        bounds = bounds.expandToInclude(children[i].bounds);
      }
    }
  }
}

class _Entry<T> {
  final T item;
  final Rect bounds;

  _Entry({required this.item, required this.bounds});
}

// ============================================================================
// Type aliases for backward compatibility
// ============================================================================

/// R-tree specialized for strokes (replaces StrokeQuadTree).
typedef StrokeQuadTree = RTree<ProStroke>;

/// R-tree specialized for geometric shapes (replaces ShapeQuadTree).
typedef ShapeQuadTree = RTree<GeometricShape>;

// ============================================================================
// Spatial Index Manager
// ============================================================================

/// 🎯 Manages R-trees for per-layer viewport culling.
///
/// Maintains one R-tree per element type (strokes, shapes),
/// updated incrementally as elements are added/removed.
class SpatialIndexManager {
  /// R-tree for strokes.
  RTree<ProStroke>? _strokeTree;

  /// R-tree for shapes.
  RTree<GeometricShape>? _shapeTree;

  /// R-tree for text elements.
  RTree<DigitalTextElement>? _textTree;

  void build({
    required List<ProStroke> strokes,
    required List<GeometricShape> shapes,
    List<DigitalTextElement> texts = const [],
    Rect canvasBounds = const Rect.fromLTWH(0, 0, 100000, 100000),
  }) {
    _strokeTree = RTree<ProStroke>.fromItems(strokes, (s) => s.bounds);
    _shapeTree = RTree<GeometricShape>.fromItems(shapes, _getShapeBounds);
    _textTree = RTree<DigitalTextElement>.fromItems(
      texts,
      (t) => t.getBounds(),
    );
  }

  /// ➕ Add a stroke to the index.
  void addStroke(ProStroke stroke) {
    _strokeTree?.insert(stroke);
  }

  /// ➖ Remove a stroke from the index.
  void removeStroke(ProStroke stroke) {
    _strokeTree?.remove(stroke);
  }

  /// ➕ Add a shape to the index.
  void addShape(GeometricShape shape) {
    _shapeTree?.insert(shape);
  }

  /// ➖ Remove a shape from the index.
  void removeShape(GeometricShape shape) {
    _shapeTree?.remove(shape);
  }

  /// ➕ Add a text element to the index.
  void addText(DigitalTextElement text) {
    _textTree?.insert(text);
  }

  /// ➖ Remove a text element from the index.
  void removeText(DigitalTextElement text) {
    _textTree?.remove(text);
  }

  /// 🔍 Query visible strokes in the viewport.
  List<ProStroke> queryVisibleStrokes(Rect viewport, {double margin = 1000.0}) {
    return _strokeTree?.queryVisible(viewport, margin: margin) ?? const [];
  }

  /// 🔍 Query visible shapes in the viewport.
  List<GeometricShape> queryVisibleShapes(
    Rect viewport, {
    double margin = 1000.0,
  }) {
    return _shapeTree?.queryVisible(viewport, margin: margin) ?? const [];
  }

  /// 🔍 Query visible text elements in the viewport.
  List<DigitalTextElement> queryVisibleTexts(
    Rect viewport, {
    double margin = 1000.0,
  }) {
    return _textTree?.queryVisible(viewport, margin: margin) ?? const [];
  }

  /// 📊 Statistics for debugging.
  Map<String, dynamic> get stats => {
    'strokes': _strokeTree?.stats ?? {},
    'shapes': _shapeTree != null ? 'active' : 'inactive',
  };

  /// 🧹 Clear the index.
  void clear() {
    _strokeTree?.clear();
    _shapeTree?.clear();
    _textTree?.clear();
    _strokeTree = null;
    _shapeTree = null;
    _textTree = null;
  }

  /// Whether the index has been built.
  bool get isBuilt => _strokeTree != null;

  /// Compute bounds for a geometric shape.
  static Rect _getShapeBounds(GeometricShape shape) {
    final padding = shape.strokeWidth * 2;
    return Rect.fromPoints(shape.startPoint, shape.endPoint).inflate(padding);
  }
}
