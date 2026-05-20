// Tests for the 0.13.0 InfiniteCanvasController constructor params:
// configurable minScale / maxScale (was hard-coded 0.1 / 5.0) and a new
// optional panBoundary that clamps setOffset.

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InfiniteCanvasController constructor params', () {
    test('default constructor reproduces 0.12.0 limits', () {
      final c = InfiniteCanvasController();
      expect(c.minScale, 0.1);
      expect(c.maxScale, 5.0);
      expect(c.panBoundary, isNull);
    });

    test('custom min/max scale honoured by setScale clamp', () {
      final c = InfiniteCanvasController(minScale: 0.5, maxScale: 2.0);
      c.setScale(0.1); // below min
      expect(c.scale, 0.5);
      c.setScale(10.0); // above max
      expect(c.scale, 2.0);
      c.setScale(1.5); // in range
      expect(c.scale, 1.5);
    });

    test('asserts when minScale invalid', () {
      expect(() => InfiniteCanvasController(minScale: 0), throwsAssertionError);
      expect(
        () => InfiniteCanvasController(minScale: 2, maxScale: 1),
        throwsAssertionError,
      );
    });

    test('panBoundary clamps setOffset to the rectangle', () {
      final c = InfiniteCanvasController(
        panBoundary: const Rect.fromLTWH(0, 0, 100, 100),
      );
      c.setOffset(const Offset(-50, -50));
      expect(c.offset.dx, 0);
      expect(c.offset.dy, 0);
      c.setOffset(const Offset(500, 500));
      expect(c.offset.dx, 100);
      expect(c.offset.dy, 100);
      c.setOffset(const Offset(40, 60));
      expect(c.offset, const Offset(40, 60));
    });

    test('null panBoundary leaves setOffset unclamped (default behaviour)', () {
      final c = InfiniteCanvasController();
      c.setOffset(const Offset(-9999, 9999));
      expect(c.offset, const Offset(-9999, 9999));
    });
  });
}
