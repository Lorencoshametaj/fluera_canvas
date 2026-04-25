import 'package:flutter/material.dart' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

class _Box {
  _Box(this.id, this.bounds);
  final int id;
  final Rect bounds;
  @override
  String toString() => 'Box($id)';
}

void main() {
  group('RTree', () {
    test('queryVisible returns items intersecting the viewport', () {
      final tree = RTree<_Box>((b) => b.bounds);
      final inside = _Box(1, const Rect.fromLTWH(10, 10, 5, 5));
      final outside = _Box(2, const Rect.fromLTWH(1000, 1000, 5, 5));
      final overlap = _Box(3, const Rect.fromLTWH(95, 95, 20, 20));
      tree.insert(inside);
      tree.insert(outside);
      tree.insert(overlap);

      final visible = tree.queryVisible(
        const Rect.fromLTWH(0, 0, 100, 100),
        margin: 0,
      );
      expect(visible.map((b) => b.id).toSet(), {1, 3});
    });

    test('count tracks live items, remove decreases it', () {
      final tree = RTree<_Box>((b) => b.bounds);
      final a = _Box(1, const Rect.fromLTWH(0, 0, 10, 10));
      final b = _Box(2, const Rect.fromLTWH(20, 20, 10, 10));
      tree.insert(a);
      tree.insert(b);
      expect(tree.count, 2);
      tree.remove(a);
      expect(tree.count, 1);
      final remaining = tree.queryVisible(
        const Rect.fromLTWH(-1000, -1000, 5000, 5000),
        margin: 0,
      );
      expect(remaining.map((x) => x.id), [2]);
    });

    test('re-inserting a removed item resurrects it', () {
      final tree = RTree<_Box>((b) => b.bounds);
      final a = _Box(1, const Rect.fromLTWH(0, 0, 10, 10));
      tree.insert(a);
      tree.remove(a);
      tree.insert(a);
      expect(tree.count, 1);
      final visible = tree.queryVisible(
        const Rect.fromLTWH(-100, -100, 200, 200),
        margin: 0,
      );
      expect(visible.length, 1);
    });

    test('viewport margin expands the query box', () {
      final tree = RTree<_Box>((b) => b.bounds);
      final justOutside = _Box(1, const Rect.fromLTWH(105, 105, 5, 5));
      tree.insert(justOutside);

      // Without margin: should NOT include the item.
      var hits = tree.queryVisible(
        const Rect.fromLTWH(0, 0, 100, 100),
        margin: 0,
      );
      expect(hits, isEmpty);

      // With margin 50: viewport expands to (-50,-50,200,200), now overlaps.
      hits = tree.queryVisible(const Rect.fromLTWH(0, 0, 100, 100), margin: 50);
      expect(hits.length, 1);
    });
  });
}
