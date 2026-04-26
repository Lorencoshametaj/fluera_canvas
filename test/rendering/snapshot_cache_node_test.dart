import 'package:flutter_test/flutter_test.dart';

import 'package:fluera_canvas/fluera_canvas.dart';

void main() {
  group('SnapshotCacheManager node-based API (GAP 8)', () {
    test('starts with empty node cache', () {
      final cache = SnapshotCacheManager();
      expect(cache.nodeCacheSize, 0);
    });

    test('getNodeSnapshot returns null for missing entry', () {
      final cache = SnapshotCacheManager();
      expect(cache.getNodeSnapshot('node-1', 1), isNull);
    });

    test('invalidateNode is safe on missing entry', () {
      final cache = SnapshotCacheManager();
      cache.invalidateNode('missing');
      expect(cache.nodeCacheSize, 0);
    });

    test('onDirtyNodes processes set of IDs', () {
      final cache = SnapshotCacheManager();
      cache.onDirtyNodes({'a', 'b', 'c'});
      expect(cache.nodeCacheSize, 0);
    });

    test('dispose clears node cache', () {
      final cache = SnapshotCacheManager();
      cache.dispose();
      expect(cache.nodeCacheSize, 0);
    });

    test('rect-based cache still works (backward compatibility)', () {
      final cache = SnapshotCacheManager();
      // Rect-based API should still be accessible.
      expect(cache.stats['entries'], 0);
    });
  });
}
