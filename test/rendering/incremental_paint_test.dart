import 'package:flutter_test/flutter_test.dart';

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';

// =============================================================================
// Test painter classes
// =============================================================================

/// A testable painter that uses IncrementalPaintMixin.
class _TestIncrementalPainter extends CustomPainter with IncrementalPaintMixin {
  final DirtyRegionTracker? _tracker;
  int paintContentCallCount = 0;
  bool wasClipped = false;

  _TestIncrementalPainter({DirtyRegionTracker? tracker}) : _tracker = tracker;

  @override
  DirtyRegionTracker? get dirtyTracker => _tracker;

  @override
  void paintContent(Canvas canvas, Size size) {
    paintContentCallCount++;
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

void main() {
  group('IncrementalPaintMixin', () {
    test('calls paintContent without tracker', () {
      final painter = _TestIncrementalPainter();
      expect(painter.dirtyTracker, isNull);
    });

    test('calls paintContent when no dirty regions', () {
      final tracker = DirtyRegionTracker();
      final painter = _TestIncrementalPainter(tracker: tracker);
      expect(tracker.hasDirtyRegions, isFalse);
    });

    test('tracker has dirty regions after markDirty', () {
      final tracker = DirtyRegionTracker();
      tracker.markDirty(const Rect.fromLTWH(10, 10, 50, 50));
      expect(tracker.hasDirtyRegions, isTrue);
      expect(tracker.dirtyBounds, isNotNull);
    });

    test('dirty bounds is null when no dirty regions', () {
      final tracker = DirtyRegionTracker();
      expect(tracker.dirtyBounds, isNull);
    });

    test('clearDirty resets all dirty regions', () {
      final tracker = DirtyRegionTracker();
      tracker.markDirty(const Rect.fromLTWH(10, 10, 50, 50));
      tracker.markDirty(const Rect.fromLTWH(200, 200, 50, 50));
      expect(tracker.hasDirtyRegions, isTrue);

      tracker.clearDirty();
      expect(tracker.hasDirtyRegions, isFalse);
    });

    testWidgets('paint calls paintContent', (tester) async {
      final painter = _TestIncrementalPainter();

      await tester.pumpWidget(CustomPaint(painter: painter));

      expect(painter.paintContentCallCount, 1);
    });

    testWidgets('paint with tracker and no dirty regions calls paintContent', (
      tester,
    ) async {
      final tracker = DirtyRegionTracker();
      final painter = _TestIncrementalPainter(tracker: tracker);

      await tester.pumpWidget(CustomPaint(painter: painter));

      expect(painter.paintContentCallCount, 1);
    });

    testWidgets('paint with dirty regions calls paintContent and clears', (
      tester,
    ) async {
      final tracker = DirtyRegionTracker();
      tracker.markDirty(const Rect.fromLTWH(10, 10, 50, 50));

      final painter = _TestIncrementalPainter(tracker: tracker);

      await tester.pumpWidget(CustomPaint(painter: painter));

      expect(painter.paintContentCallCount, 1);
      // Dirty should be cleared after paint.
      expect(tracker.hasDirtyRegions, isFalse);
    });

    test('useIncrementalPaint defaults to true', () {
      final painter = _TestIncrementalPainter();
      expect(painter.useIncrementalPaint, isTrue);
    });
  });
}
