import 'dart:collection';
import 'dart:ui';

/// Pool of `Path` objects to reduce allocations during rendering.
///
/// Usage:
/// ```dart
/// final pool = PathPool.instance;
/// final path = pool.acquire();
/// // Use path...
/// pool.release(path); // Return to pool when done
/// ```
class PathPool {
  /// Process-wide singleton accessor.
  static PathPool get instance => _instance;
  static final PathPool _instance = PathPool._();

  /// Creates a new instance. Engine integrators that want their own scoped
  /// pool (e.g. one per canvas controller) can construct directly via
  /// [PathPool.create].
  PathPool.create();

  PathPool._();

  static const int _maxPoolSize = 100;
  static const int _initialPoolSize = 20;

  final Queue<Path> _availablePaths = Queue<Path>();
  int _allocatedCount = 0;
  int _reusedCount = 0;

  /// Initialize pool with pre-allocated paths.
  void initialize() {
    if (_availablePaths.isEmpty) {
      for (int i = 0; i < _initialPoolSize; i++) {
        _availablePaths.add(Path());
      }
    }
  }

  /// Acquire a path from the pool or create new if pool is empty.
  Path acquire() {
    if (_availablePaths.isNotEmpty) {
      _reusedCount++;
      final path = _availablePaths.removeFirst();
      path.reset(); // Clear any previous data
      return path;
    }

    _allocatedCount++;
    return Path();
  }

  /// Release path back to pool for reuse.
  void release(Path path) {
    if (_availablePaths.length < _maxPoolSize) {
      path.reset(); // Clear before returning to pool
      _availablePaths.add(path);
    }
  }

  /// Release multiple paths at once.
  void releaseAll(List<Path> paths) {
    for (final path in paths) {
      release(path);
    }
  }

  /// Clear all pooled paths.
  void clear() {
    _availablePaths.clear();
    _allocatedCount = 0;
    _reusedCount = 0;
  }

  /// Get pool statistics.
  PathPoolStatistics get statistics => PathPoolStatistics(
    poolSize: _availablePaths.length,
    totalAllocated: _allocatedCount,
    totalReused: _reusedCount,
    reuseRate:
        _allocatedCount > 0
            ? (_reusedCount / (_allocatedCount + _reusedCount)) * 100
            : 0,
  );
}

/// Statistics about path pool usage.
class PathPoolStatistics {
  final int poolSize;
  final int totalAllocated;
  final int totalReused;
  final double reuseRate;

  const PathPoolStatistics({
    required this.poolSize,
    required this.totalAllocated,
    required this.totalReused,
    required this.reuseRate,
  });

  @override
  String toString() {
    return 'PathPoolStatistics(pool: $poolSize, allocated: $totalAllocated, '
        'reused: $totalReused, reuse rate: ${reuseRate.toStringAsFixed(1)}%)';
  }
}
