import 'dart:collection';
import 'dart:ui';

/// Pool of `Offset` objects for stroke points to reduce allocations and GC pressure.
///
/// Usage:
/// ```dart
/// final pool = StrokePointPool.instance;
/// final point = pool.acquire(x, y);
/// // Use point...
/// pool.release(point); // Return to pool when done
/// ```
class StrokePointPool {
  /// Process-wide singleton accessor.
  static StrokePointPool get instance => _instance;
  static final StrokePointPool _instance = StrokePointPool._();

  /// Creates a new instance (used by integrators wanting a scoped pool).
  StrokePointPool.create();

  StrokePointPool._();

  static const int _maxPoolSize = 10000;
  static const int _initialPoolSize = 1000;

  final Queue<Offset> _availablePoints = Queue<Offset>();
  int _allocatedCount = 0;
  int _reusedCount = 0;

  /// Initialize pool with pre-allocated points.
  void initialize() {
    if (_availablePoints.isEmpty) {
      for (int i = 0; i < _initialPoolSize; i++) {
        _availablePoints.add(Offset.zero);
      }
    }
  }

  /// Acquire a point from the pool or create new if pool is empty.
  Offset acquire(double x, double y) {
    if (_availablePoints.isNotEmpty) {
      _reusedCount++;
      _availablePoints.removeFirst();
      // Note: Offset is immutable, so we create new with desired values.
      return Offset(x, y);
    }

    _allocatedCount++;
    return Offset(x, y);
  }

  /// Release point back to pool for reuse.
  void release(Offset point) {
    if (_availablePoints.length < _maxPoolSize) {
      _availablePoints.add(point);
    }
  }

  /// Release multiple points at once.
  void releaseAll(List<Offset> points) {
    for (final point in points) {
      release(point);
    }
  }

  /// Clear all pooled points.
  void clear() {
    _availablePoints.clear();
    _allocatedCount = 0;
    _reusedCount = 0;
  }

  /// Get pool statistics.
  PoolStatistics get statistics => PoolStatistics(
    poolSize: _availablePoints.length,
    totalAllocated: _allocatedCount,
    totalReused: _reusedCount,
    reuseRate:
        _allocatedCount > 0
            ? (_reusedCount / (_allocatedCount + _reusedCount)) * 100
            : 0,
  );
}

/// Statistics about pool usage.
class PoolStatistics {
  /// Field `poolSize`.
  final int poolSize;
  /// Field `totalAllocated`.
  final int totalAllocated;
  /// Field `totalReused`.
  final int totalReused;
  /// Field `reuseRate`.
  final double reuseRate;

  /// API element `PoolStatistics`.
  const PoolStatistics({
    required this.poolSize,
    required this.totalAllocated,
    required this.totalReused,
    required this.reuseRate,
  });

  @override
  String toString() {
    return 'PoolStatistics(pool: $poolSize, allocated: $totalAllocated, '
        'reused: $totalReused, reuse rate: ${reuseRate.toStringAsFixed(1)}%)';
  }
}
