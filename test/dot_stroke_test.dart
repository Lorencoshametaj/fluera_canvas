/// Single-point stroke (pen-down + pen-up without moving) regression
/// test. Pre-0.9.3 the canvas silently dropped the gesture; from
/// 0.9.3 it commits a 2-point "dot" stroke that renders as a round
/// cap at the tap location.
library;

import 'dart:ui' show Offset;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pen-down + pen-up sul posto commits a dot stroke', (
    tester,
  ) async {
    final key = GlobalKey<FlueraCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: FlueraCanvas(key: key, tool: CanvasTool.draw),
          ),
        ),
      ),
    );
    expect(key.currentState!.strokes, isEmpty);

    final centre = tester.getCenter(find.byType(FlueraCanvas));
    // Single tap → exactly one pointer-down + pointer-up cycle on
    // the same screen pixel.
    final gesture = await tester.startGesture(centre);
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(
      key.currentState!.strokes,
      hasLength(1),
      reason: 'Single-tap should commit a 1-stroke "dot" via the '
          'synthesised 2-point fallback.',
    );
    final dot = key.currentState!.strokes.first;
    expect(dot.points.length, greaterThanOrEqualTo(2));
    // The synthesised second point sits 0.01 px from the first.
    expect(
      (dot.points[1] - dot.points[0]).distance,
      lessThan(0.1),
    );
  });

  testWidgets(
    'programmatic single-point pushStroke is unaffected by the dot fix',
    (tester) async {
      // The dot fallback runs ONLY in `_onDrawEnd`, not in
      // `pushStroke`. Programmatic clients can still push strokes
      // with arbitrary point counts (including 1) — verified here so
      // the ad-hoc fallback does not leak into the public API.
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: FlueraCanvas(key: key),
            ),
          ),
        ),
      );
      key.currentState!.pushStroke(
        CanvasStroke(
          points: const [Offset(10, 10)],
          pressures: const [1.0],
          color: const Color(0xFF000000),
          baseWidth: 2,
        ),
      );
      expect(
        key.currentState!.strokes.first.points,
        hasLength(1),
        reason: 'pushStroke must respect the caller-provided point list.',
      );
    },
  );
}
