import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

void main() {
  // =========================================================================
  // PathPool
  // =========================================================================

  group('PathPool', () {
    late PathPool pool;

    setUp(() {
      pool = PathPool.create();
    });

    tearDown(() {
      pool.clear();
    });

    // ── Initial State ──────────────────────────────────────────────────

    group('initial state', () {
      test('starts with zero statistics', () {
        final stats = pool.statistics;
        expect(stats.poolSize, 0);
        expect(stats.totalAllocated, 0);
        expect(stats.totalReused, 0);
        expect(stats.reuseRate, 0);
      });
    });

    // ── Initialize ─────────────────────────────────────────────────────

    group('initialize', () {
      test('pre-allocates paths', () {
        pool.initialize();
        expect(pool.statistics.poolSize, 20); // _initialPoolSize = 20
      });

      test('initialize is idempotent when pool not empty', () {
        pool.initialize();
        pool.initialize(); // second call should be a no-op
        expect(pool.statistics.poolSize, 20);
      });
    });

    // ── Acquire / Release ──────────────────────────────────────────────

    group('acquire', () {
      test('returns a Path object', () {
        final path = pool.acquire();
        expect(path, isA<Path>());
      });

      test('allocates new path when pool is empty', () {
        final path = pool.acquire();
        expect(path, isNotNull);
        expect(pool.statistics.totalAllocated, 1);
      });

      test('reuses pool path when available', () {
        pool.initialize();
        pool.acquire();
        expect(pool.statistics.totalReused, 1);
        expect(pool.statistics.poolSize, 19); // one removed
      });
    });

    group('release', () {
      test('returns path to pool', () {
        final path = pool.acquire();
        pool.release(path);
        expect(pool.statistics.poolSize, 1);
      });

      test('respects max pool size', () {
        // Fill pool to max size (100)
        for (int i = 0; i < 110; i++) {
          pool.release(Path());
        }
        expect(pool.statistics.poolSize, 100); // _maxPoolSize = 100
      });
    });

    group('releaseAll', () {
      test('releases multiple paths at once', () {
        final paths = [Path(), Path(), Path()];
        pool.releaseAll(paths);
        expect(pool.statistics.poolSize, 3);
      });
    });

    // ── Clear ──────────────────────────────────────────────────────────

    group('clear', () {
      test('removes all paths and resets counters', () {
        pool.initialize();
        pool.acquire();
        pool.acquire();
        pool.clear();

        final stats = pool.statistics;
        expect(stats.poolSize, 0);
        expect(stats.totalAllocated, 0);
        expect(stats.totalReused, 0);
      });
    });

    // ── Statistics ─────────────────────────────────────────────────────

    group('statistics', () {
      test('tracks reuse rate correctly', () {
        pool.initialize();
        // Acquire 10 (reused from pool)
        for (int i = 0; i < 10; i++) {
          pool.acquire();
        }
        // Pool had 20, 10 reused, 0 allocated
        expect(pool.statistics.totalReused, 10);
        expect(pool.statistics.totalAllocated, 0);
      });

      test('tracks allocation correctly', () {
        // No initialization — acquires are fresh allocations
        for (int i = 0; i < 5; i++) {
          pool.acquire();
        }
        expect(pool.statistics.totalAllocated, 5);
        expect(pool.statistics.totalReused, 0);
      });

      test('toString formats correctly', () {
        final str = pool.statistics.toString();
        expect(str, contains('PathPoolStatistics'));
        expect(str, contains('pool:'));
      });
    });
  });

  // =========================================================================
  // StrokePointPool
  // =========================================================================

  group('StrokePointPool', () {
    late StrokePointPool pool;

    setUp(() {
      pool = StrokePointPool.create();
    });

    tearDown(() {
      pool.clear();
    });

    // ── Initial State ──────────────────────────────────────────────────

    group('initial state', () {
      test('starts with zero statistics', () {
        final stats = pool.statistics;
        expect(stats.poolSize, 0);
        expect(stats.totalAllocated, 0);
        expect(stats.totalReused, 0);
      });
    });

    // ── Initialize ─────────────────────────────────────────────────────

    group('initialize', () {
      test('pre-allocates 1000 points', () {
        pool.initialize();
        expect(pool.statistics.poolSize, 1000); // _initialPoolSize = 1000
      });
    });

    // ── Acquire / Release ──────────────────────────────────────────────

    group('acquire', () {
      test('returns Offset with correct coordinates', () {
        final point = pool.acquire(10.0, 20.0);
        expect(point.dx, 10.0);
        expect(point.dy, 20.0);
      });

      test('tracks allocation when pool empty', () {
        pool.acquire(1.0, 2.0);
        expect(pool.statistics.totalAllocated, 1);
      });

      test('tracks reuse from initialized pool', () {
        pool.initialize();
        pool.acquire(5.0, 5.0);
        expect(pool.statistics.totalReused, 1);
        expect(pool.statistics.poolSize, 999);
      });
    });

    group('release', () {
      test('returns point to pool', () {
        final point = pool.acquire(1.0, 1.0);
        pool.release(point);
        expect(pool.statistics.poolSize, 1);
      });

      test('respects max pool size (10000)', () {
        for (int i = 0; i < 10100; i++) {
          pool.release(Offset.zero);
        }
        expect(pool.statistics.poolSize, 10000);
      });
    });

    group('releaseAll', () {
      test('releases all points', () {
        final points = [
          const Offset(1, 2),
          const Offset(3, 4),
          const Offset(5, 6),
        ];
        pool.releaseAll(points);
        expect(pool.statistics.poolSize, 3);
      });
    });

    // ── Clear ──────────────────────────────────────────────────────────

    group('clear', () {
      test('resets all state', () {
        pool.initialize();
        pool.acquire(0, 0);
        pool.clear();

        final stats = pool.statistics;
        expect(stats.poolSize, 0);
        expect(stats.totalAllocated, 0);
        expect(stats.totalReused, 0);
      });
    });

    // ── Statistics ─────────────────────────────────────────────────────

    group('statistics', () {
      test('toString formats correctly', () {
        final str = pool.statistics.toString();
        expect(str, contains('PoolStatistics'));
        expect(str, contains('pool:'));
      });
    });
  });
}
