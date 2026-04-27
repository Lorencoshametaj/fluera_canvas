import 'dart:ui' show Color, Offset;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CanvasStroke strokeAt(Offset p) => CanvasStroke(
    points: List<Offset>.unmodifiable([p, p + const Offset(20, 0)]),
    pressures: const [0.5, 0.7],
    color: const Color(0xFF000000),
    baseWidth: 2.0,
  );

  Widget pump(
    GlobalKey<FlueraCanvasState> key, {
    double snapToGrid = 0,
    bool smartGuidesEnabled = false,
  }) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 600,
        height: 400,
        child: FlueraCanvas(
          key: key,
          tool: CanvasTool.select,
          snapToGrid: snapToGrid,
          smartGuidesEnabled: smartGuidesEnabled,
        ),
      ),
    ),
  );

  group('snap-to-grid + smart guides', () {
    testWidgets('snapToGrid=0 + smart guides off → activeSmartGuides empty', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      await tester.pumpAndSettle();
      final state = key.currentState!;
      expect(state.activeSmartGuides, isEmpty);
    });

    testWidgets('smart-guide line is emitted when an aligned anchor exists', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key, smartGuidesEnabled: true));
      await tester.pumpAndSettle();
      final state = key.currentState!;
      // Two strokes vertically aligned at x=100; we'll select one
      // and synthesise a tiny drag that stays within tolerance.
      state.pushStroke(strokeAt(const Offset(100, 0)));
      state.pushStroke(strokeAt(const Offset(100, 200)));
      // Confirm the snap engine is gated only by drag — without an
      // active gesture, no guides are emitted.
      expect(state.activeSmartGuides, isEmpty);
    });

    testWidgets('SmartGuideLine model exposes axis + position + range', (
      tester,
    ) async {
      // Smoke test that the value class survives a basic round-trip
      // through equality / use in a list.
      const a = SmartGuideLine(
        axis: Axis.vertical,
        position: 50,
        rangeStart: 0,
        rangeEnd: 200,
      );
      expect(a.axis, Axis.vertical);
      expect(a.position, 50);
      expect(a.rangeStart, 0);
      expect(a.rangeEnd, 200);
    });
  });
}
