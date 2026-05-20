// Tests for the 0.15.0 programmatic drawing helpers on FlueraCanvasState.

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

  testWidgets('drawLine commits a 2-point stroke with overrides honoured', (
    tester,
  ) async {
    final state = await _pumpCanvas(tester);
    final stroke = state.drawLine(
      const Offset(10, 10),
      const Offset(60, 60),
      color: const Color(0xFFE53935),
      width: 5,
      metadata: const {'tutorial-step': 'arrow-1'},
    );
    expect(state.strokes, hasLength(1));
    expect(stroke.points, [const Offset(10, 10), const Offset(60, 60)]);
    expect(stroke.color.toARGB32(), 0xFFE53935);
    expect(stroke.baseWidth, 5);
    expect(stroke.metadata?['tutorial-step'], 'arrow-1');
  });

  testWidgets('drawCircle commits a closed N-segment polyline', (tester) async {
    final state = await _pumpCanvas(tester);
    final stroke = state.drawCircle(
      const Offset(100, 100),
      40,
      segments: 16,
    );
    // 16 segments → 17 points (last point repeats first to close).
    expect(stroke.points.length, 17);
    // First and last points coincide → closed ring.
    expect(stroke.points.first.dx, closeTo(stroke.points.last.dx, 1e-5));
    expect(stroke.points.first.dy, closeTo(stroke.points.last.dy, 1e-5));
    // All points equidistant from centre.
    for (final p in stroke.points) {
      final d = (p - const Offset(100, 100)).distance;
      expect(d, closeTo(40, 1e-3));
    }
  });

  testWidgets('drawPolygon honours closed flag', (tester) async {
    final state = await _pumpCanvas(tester);
    final open = state.drawPolygon(
      const [Offset(0, 0), Offset(10, 0), Offset(10, 10)],
    );
    final closed = state.drawPolygon(
      const [Offset(20, 0), Offset(30, 0), Offset(30, 10)],
      closed: true,
    );
    expect(open.points.length, 3);
    expect(closed.points.length, 4);
    expect(closed.points.last, closed.points.first);
  });

  // Regression: 0.16.2 — degenerate input must throw ArgumentError
  // in release builds (the pre-fix asserts only fired in debug, so
  // production callers silently committed malformed strokes).
  testWidgets('drawCircle rejects radius <= 0 and segments < 3', (
    tester,
  ) async {
    final state = await _pumpCanvas(tester);
    expect(() => state.drawCircle(Offset.zero, 0), throwsArgumentError);
    expect(() => state.drawCircle(Offset.zero, -1), throwsArgumentError);
    expect(
      () => state.drawCircle(Offset.zero, double.nan),
      throwsArgumentError,
    );
    expect(
      () => state.drawCircle(Offset.zero, 10, segments: 2),
      throwsArgumentError,
    );
  });

  testWidgets('drawPolygon rejects fewer than 2 points', (tester) async {
    final state = await _pumpCanvas(tester);
    expect(() => state.drawPolygon(const []), throwsArgumentError);
    expect(
      () => state.drawPolygon(const [Offset(0, 0)]),
      throwsArgumentError,
    );
  });

  testWidgets('helpers fall back to widget defaults when overrides null', (
    tester,
  ) async {
    final canvasKey = GlobalKey<FlueraCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: FlueraCanvas(
              key: canvasKey,
              strokeColor: const Color(0xFF00CC88),
              strokeWidth: 7,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final stroke = canvasKey.currentState!.drawLine(
      const Offset(0, 0),
      const Offset(50, 50),
    );
    expect(stroke.color.toARGB32(), 0xFF00CC88);
    expect(stroke.baseWidth, 7);
  });
}
