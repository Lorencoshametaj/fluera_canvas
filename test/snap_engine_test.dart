// Geometric tests for the 0.15.0 SnapEngine — pure pure-Dart pass
// over candidate AABBs, no canvas / widget dependency.

import 'dart:ui';

import 'package:fluera_canvas/src/canvas/snap/snap_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SnapEngine.snap — basic edge alignment', () {
    test('left-edge snap pulls dragged onto candidate left edge', () {
      // Candidate at x=100..200; dragged at x=104..160 (4 px right
      // of candidate left edge — within 6 px tolerance).
      const candidate = Rect.fromLTWH(100, 0, 100, 50);
      const dragged = Rect.fromLTWH(104, 200, 56, 50);
      const engine = SnapEngine();
      final result = engine.snap(
        draggedBounds: dragged,
        candidates: const [candidate],
      );
      expect(result.didSnap, isTrue);
      expect(result.bounds.left, 100); // snapped from 104 → 100
      // Width preserved (move, not scale).
      expect(result.bounds.width, dragged.width);
      // Guide for left-edge present.
      expect(result.guides.any((g) => g.kind == 'edge-left'), isTrue);
    });

    test('center-x snap aligns horizontal centers', () {
      // Candidate centered at x=150; dragged centered at x=148 (2 px
      // left, well within tolerance).
      const candidate = Rect.fromLTWH(100, 0, 100, 50);
      const dragged = Rect.fromLTWH(118, 200, 60, 50); // center.dx = 148
      const engine = SnapEngine();
      final result = engine.snap(
        draggedBounds: dragged,
        candidates: const [candidate],
      );
      expect(result.didSnap, isTrue);
      expect(result.bounds.center.dx, closeTo(150, 0.001));
      expect(result.guides.any((g) => g.kind == 'center-x'), isTrue);
    });
  });

  group('SnapEngine.snap — tolerance + axes', () {
    test('candidate beyond tolerance does NOT snap', () {
      // Every X anchor pairing is well past the 6 px default
      // tolerance: candidate centred at x=150, dragged at x=228
      // (gap 78); same for edges. Y anchors also far apart so we
      // know neither axis triggers.
      const candidate = Rect.fromLTWH(100, 0, 100, 50);
      const dragged = Rect.fromLTWH(200, 200, 56, 50);
      const engine = SnapEngine();
      final result = engine.snap(
        draggedBounds: dragged,
        candidates: const [candidate],
      );
      expect(result.didSnap, isFalse);
      expect(result.bounds, dragged); // unchanged
      expect(result.guides, isEmpty);
    });

    test('axes=x ignores Y-axis pairings even if they match', () {
      // Y-edges line up perfectly (both top=200) — would snap with
      // axes.both, but axes.x must skip Y entirely.
      const candidate = Rect.fromLTWH(0, 200, 50, 50);
      const dragged = Rect.fromLTWH(102, 200, 50, 50);
      const engine = SnapEngine();
      final result = engine.snap(
        draggedBounds: dragged,
        candidates: const [candidate],
        axes: SnapAxes.x,
      );
      // No X anchors close enough → no snap, no guide.
      expect(result.didSnap, isFalse);
      expect(result.guides.where((g) => g.kind.startsWith('edge-top')), isEmpty);
    });

    test('axes=none returns input unchanged', () {
      const candidate = Rect.fromLTWH(100, 100, 50, 50);
      const dragged = Rect.fromLTWH(101, 100, 50, 50);
      const engine = SnapEngine();
      final result = engine.snap(
        draggedBounds: dragged,
        candidates: const [candidate],
        axes: SnapAxes.none,
      );
      expect(result.didSnap, isFalse);
      expect(result.bounds, dragged);
    });
  });
}
