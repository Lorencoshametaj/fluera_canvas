import 'dart:collection';

/// Dirty flag categories for incremental invalidation.
///
/// Each flag represents a category of property that may become stale
/// when a node (or one of its dependents) is mutated.
///
/// ```dart
/// graph.markDirty('node-1', DirtyFlag.transform);
/// ```
enum DirtyFlag {
  /// The node's world transform needs recomputation.
  transform,

  /// The node's visual paint properties changed (fill, stroke, opacity, effects).
  paint,

  /// The node's bounding box needs recomputation.
  bounds,

  /// The node's layout (auto-layout / constraints) needs re-solving.
  layout,

  /// The node's effects (blur, shadow, glow) changed.
  effects,
}

// ---------------------------------------------------------------------------
// Dependency edge
// ---------------------------------------------------------------------------

/// A directed dependency edge in the invalidation graph.
///
/// When the source node is dirtied with [flag], the [targetNodeId] is
/// also marked dirty with the same flag.
class _DependencyEdge {
  final String targetNodeId;
  final DirtyFlag flag;

  const _DependencyEdge(this.targetNodeId, this.flag);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _DependencyEdge &&
          targetNodeId == other.targetNodeId &&
          flag == other.flag;

  @override
  int get hashCode => Object.hash(targetNodeId, flag);
}

// ---------------------------------------------------------------------------
// InvalidationGraph
// ---------------------------------------------------------------------------

/// Reactive invalidation graph for incremental scene graph updates.
///
/// Tracks which nodes are "dirty" and propagates dirty flags through
/// registered dependency edges. This enables the renderer to skip
/// unchanged nodes and only re-compute what actually changed.
///
/// ## Usage
///
/// ```dart
/// final graph = InvalidationGraph();
///
/// // When a node's transform changes:
/// graph.markDirty('star', DirtyFlag.transform);
///
/// // Register a dependency: if 'star' moves, 'label' must re-layout:
/// graph.addDependency('star', 'label', DirtyFlag.layout);
///
/// // Before rendering, collect dirty nodes:
/// final dirtyTransforms = graph.collectDirty(DirtyFlag.transform);
/// final dirtyLayouts   = graph.collectDirty(DirtyFlag.layout);
///
/// // After rendering:
/// graph.clearAll();
/// ```
///
/// ## Design
///
/// - The graph is **sparse**: only nodes that have been dirtied or have
///   dependencies are tracked. Overhead for clean nodes is zero.
/// - Propagation is **breadth-first** to avoid redundant re-marking.
/// - The graph is **frame-scoped**: [clearAll] resets all dirty flags
///   at the end of each render frame.
class InvalidationGraph {
  /// Per-node dirty flags. Absent = fully clean.
  final Map<String, Set<DirtyFlag>> _dirty = {};

  /// Forward dependency edges: source → list of (target, flag).
  final Map<String, Set<_DependencyEdge>> _edges = {};

  /// Cross-flag cascade rules.
  ///
  /// When a node is marked dirty with a key flag, it is also automatically
  /// marked dirty with each value flag. This centralizes implicit
  /// dependencies (e.g. `transform → bounds`) instead of scattering them
  /// across call sites.
  static final Map<DirtyFlag, List<DirtyFlag>> _cascadeRules = {
    DirtyFlag.transform: [DirtyFlag.bounds],
  };

  /// Register an additional cascade rule.
  ///
  /// Example: `addCascadeRule(DirtyFlag.layout, DirtyFlag.bounds);`
  static void addCascadeRule(DirtyFlag from, DirtyFlag to) {
    _cascadeRules.putIfAbsent(from, () => []).add(to);
  }

  // -------------------------------------------------------------------------
  // Mark dirty
  // -------------------------------------------------------------------------

  /// Pooled BFS queue — reused across markDirty calls to avoid per-call
  /// Queue allocations (reduces GC pressure in frames with many dirty marks).
  final Queue<_MarkEntry> _bfsQueue = Queue<_MarkEntry>();

  /// Mark [nodeId] as dirty for [flag] and propagate to dependents.
  ///
  /// Propagation is breadth-first: if A → B → C, marking A will
  /// dirty B and C in one call.
  void markDirty(String nodeId, DirtyFlag flag) {
    _bfsQueue.clear();
    _bfsQueue.add(_MarkEntry(nodeId, flag));

    // Also enqueue cascade targets (e.g. transform → bounds).
    final cascades = _cascadeRules[flag];
    if (cascades != null) {
      for (final cascadeFlag in cascades) {
        _bfsQueue.add(_MarkEntry(nodeId, cascadeFlag));
      }
    }

    while (_bfsQueue.isNotEmpty) {
      final entry = _bfsQueue.removeFirst();
      final flags = _dirty.putIfAbsent(entry.nodeId, () => {});
      if (flags.contains(entry.flag)) continue; // already dirty
      flags.add(entry.flag);

      // Propagate to dependents.
      final edges = _edges[entry.nodeId];
      if (edges != null) {
        for (final edge in edges) {
          if (edge.flag == entry.flag) {
            _bfsQueue.add(_MarkEntry(edge.targetNodeId, edge.flag));
          }
        }
      }
    }
  }

  /// Mark [nodeId] dirty for multiple flags at once.
  void markDirtyAll(String nodeId, Iterable<DirtyFlag> flags) {
    for (final flag in flags) {
      markDirty(nodeId, flag);
    }
  }

  // -------------------------------------------------------------------------
  // Dependency edges
  // -------------------------------------------------------------------------

  /// Register a dependency: when [sourceNodeId] is dirtied with [flag],
  /// [targetNodeId] will also be marked dirty with the same flag.
  void addDependency(String sourceNodeId, String targetNodeId, DirtyFlag flag) {
    _edges
        .putIfAbsent(sourceNodeId, () => {})
        .add(_DependencyEdge(targetNodeId, flag));
  }

  /// Remove a specific dependency edge.
  void removeDependency(
    String sourceNodeId,
    String targetNodeId,
    DirtyFlag flag,
  ) {
    _edges[sourceNodeId]?.remove(_DependencyEdge(targetNodeId, flag));
    if (_edges[sourceNodeId]?.isEmpty ?? false) {
      _edges.remove(sourceNodeId);
    }
  }

  /// Remove all dependency edges from [sourceNodeId].
  void removeAllDependencies(String sourceNodeId) {
    _edges.remove(sourceNodeId);
  }

  /// Remove all dependency edges pointing to [targetNodeId].
  void removeAllDependents(String targetNodeId) {
    for (final edges in _edges.values) {
      edges.removeWhere((e) => e.targetNodeId == targetNodeId);
    }
    // Prune empty entries.
    _edges.removeWhere((_, edges) => edges.isEmpty);
  }

  /// Remove a node entirely (both as source and target).
  void removeNode(String nodeId) {
    _dirty.remove(nodeId);
    removeAllDependencies(nodeId);
    removeAllDependents(nodeId);
  }

  // -------------------------------------------------------------------------
  // Query
  // -------------------------------------------------------------------------

  /// Whether [nodeId] is dirty for [flag].
  bool isDirty(String nodeId, DirtyFlag flag) {
    return _dirty[nodeId]?.contains(flag) ?? false;
  }

  /// Whether [nodeId] is dirty for any flag.
  bool isAnyDirty(String nodeId) {
    return _dirty[nodeId]?.isNotEmpty ?? false;
  }

  /// Collect all node IDs that are dirty for [flag].
  Set<String> collectDirty(DirtyFlag flag) {
    final result = <String>{};
    for (final entry in _dirty.entries) {
      if (entry.value.contains(flag)) {
        result.add(entry.key);
      }
    }
    return result;
  }

  /// Collect all node IDs that are dirty for any flag.
  Set<String> collectAllDirty() {
    return _dirty.keys.toSet();
  }

  /// Number of dirty nodes (across all flags).
  int get dirtyCount => _dirty.length;

  /// Whether any node is dirty.
  bool get hasDirty => _dirty.isNotEmpty;

  // -------------------------------------------------------------------------
  // Frame lifecycle
  // -------------------------------------------------------------------------

  /// Clear all dirty flags. Call at the end of each render frame.
  void clearAll() {
    _dirty.clear();
  }

  /// Clear dirty flags for a single node.
  void clearNode(String nodeId) {
    _dirty.remove(nodeId);
  }

  // -------------------------------------------------------------------------
  // Debug
  // -------------------------------------------------------------------------

  /// Number of registered dependency edges.
  int get edgeCount {
    int count = 0;
    for (final edges in _edges.values) {
      count += edges.length;
    }
    return count;
  }

  /// Dispose — release all data.
  void dispose() {
    _dirty.clear();
    _edges.clear();
  }

  @override
  String toString() =>
      'InvalidationGraph(dirty: $dirtyCount, edges: $edgeCount)';
}

/// Internal helper for BFS propagation.
class _MarkEntry {
  final String nodeId;
  final DirtyFlag flag;
  const _MarkEntry(this.nodeId, this.flag);
}
