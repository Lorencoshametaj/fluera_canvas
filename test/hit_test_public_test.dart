// Tests for the 0.15.0 public hit-test API on FlueraCanvasState.

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<FlueraCanvasState> _pumpCanvas(WidgetTester tester) async {
    final canvasKey = GlobalKey<FlueraCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: FlueraCanvas(key: canvasKey),
          ),
        ),
      ),
    );
    await tester.pump();
    return canvasKey.currentState!;
  }

  testWidgets('hitTest returns NodeId on a stroke point', (tester) async {
    final state = await _pumpCanvas(tester);
    state.pushStroke(
      CanvasStroke(
        points: const [Offset(50, 50), Offset(150, 150)],
        pressures: const [0.5, 0.5],
        color: const Color(0xFF1A1A1A),
        baseWidth: 3,
      ),
    );
    await tester.pump();
    final hit = state.hitTest(const Offset(100, 100));
    expect(hit, isNotNull,
        reason: 'tap on the midpoint of a 50,50→150,150 stroke should hit');
  });

  testWidgets('hitTest returns null far from any stroke', (tester) async {
    final state = await _pumpCanvas(tester);
    state.pushStroke(
      CanvasStroke(
        points: const [Offset(0, 0), Offset(20, 20)],
        pressures: const [0.5, 0.5],
        color: const Color(0xFF1A1A1A),
        baseWidth: 3,
      ),
    );
    await tester.pump();
    // 500 units away — well past any tolerance.
    final hit = state.hitTest(const Offset(500, 500));
    expect(hit, isNull);
  });

  testWidgets('hitTestInRect returns multiple node IDs in a big rect', (
    tester,
  ) async {
    final state = await _pumpCanvas(tester);
    for (int i = 0; i < 5; i++) {
      state.pushStroke(
        CanvasStroke(
          points: [Offset(i * 30.0, 0), Offset(i * 30.0, 30)],
          pressures: const [0.5, 0.5],
          color: const Color(0xFF1A1A1A),
          baseWidth: 2,
        ),
      );
    }
    await tester.pump();
    final hits = state.hitTestInRect(const Rect.fromLTWH(-10, -10, 200, 200));
    expect(hits.length, 5);
  });

  // Regression: 0.16.2 — hitTestInRect normalises degenerate rects
  // (zero / negative size from inverted marquee drags, non-finite
  // coordinates) to an empty result instead of probing the spatial
  // index with garbage.
  testWidgets('hitTestInRect returns empty set for degenerate rects', (
    tester,
  ) async {
    final state = await _pumpCanvas(tester);
    state.pushStroke(
      CanvasStroke(
        points: const [Offset(0, 0), Offset(20, 20)],
        pressures: const [0.5, 0.5],
        color: const Color(0xFF1A1A1A),
        baseWidth: 3,
      ),
    );
    await tester.pump();
    expect(state.hitTestInRect(Rect.zero), isEmpty);
    // Inverted rect far from any stroke — after normalisation this is
    // a 5×5 box at (95,95)→(100,100), not overlapping the stroke at
    // (0,0)→(20,20).
    expect(
      state.hitTestInRect(const Rect.fromLTWH(100, 100, -5, -5)),
      isEmpty,
    );
    // Inverted rect that DOES overlap, after normalisation, must
    // still hit — that's the marquee-drag-up-left case.
    expect(
      state.hitTestInRect(const Rect.fromLTWH(50, 50, -100, -100)),
      isNotEmpty,
    );
    expect(
      state.hitTestInRect(const Rect.fromLTWH(0, 0, double.nan, 10)),
      isEmpty,
    );
  });

  testWidgets('hitTestInRect returns unmodifiable set', (tester) async {
    final state = await _pumpCanvas(tester);
    state.pushStroke(
      CanvasStroke(
        points: const [Offset(0, 0), Offset(20, 20)],
        pressures: const [0.5, 0.5],
        color: const Color(0xFF1A1A1A),
        baseWidth: 3,
      ),
    );
    await tester.pump();
    final hits = state.hitTestInRect(const Rect.fromLTWH(-10, -10, 100, 100));
    expect(
      () => hits.add(const NodeId('mutation')),
      throwsUnsupportedError,
    );
  });
}
