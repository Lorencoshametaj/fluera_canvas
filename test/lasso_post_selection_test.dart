/// Coverage for the lasso UX parity work in 0.10.x:
/// - tap-on-selection inside the bbox enters transform mode (drag /
///   handle) instead of starting a fresh lasso,
/// - tap-on-selection outside the bbox clears the old selection and
///   starts a fresh lasso,
/// - the hit-test no longer over-selects via the
///   `lassoBounds.overlaps(nodeBounds)` catch-all.
library;

import 'dart:ui' show Offset;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CanvasStroke makeStroke(double x, double y, {double size = 30}) =>
      CanvasStroke(
        points: List<Offset>.unmodifiable([
          Offset(x, y),
          Offset(x + size, y + size),
        ]),
        pressures: const [1.0, 1.0],
        color: const Color(0xFF1A1A1A),
        baseWidth: 2,
      );

  Widget pump(GlobalKey<FlueraCanvasState> key, CanvasTool tool) =>
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: FlueraCanvas(key: key, tool: tool),
          ),
        ),
      );

  /// Simulate a lasso polyline by routing pointer events along
  /// `path` (in widget-local coords).
  Future<void> sweepLasso(WidgetTester tester, List<Offset> path) async {
    expect(path.length, greaterThanOrEqualTo(3));
    final canvas = find.byType(FlueraCanvas);
    final origin = tester.getTopLeft(canvas);
    final gesture =
        await tester.startGesture(origin + path.first);
    for (var i = 1; i < path.length; i++) {
      await gesture.moveTo(origin + path[i]);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('lasso seleziona stroke racchiusi dal path', (tester) async {
    final key = GlobalKey<FlueraCanvasState>();
    await tester.pumpWidget(pump(key, CanvasTool.lasso));
    final state = key.currentState!;
    // Place a small stroke at canvas-local (100, 100)-(130, 130).
    state.pushStroke(makeStroke(100, 100, size: 30));
    await tester.pumpAndSettle();

    // Lasso a generous rectangle around the stroke's bbox. (Canvas
    // tool is already lasso; the InfiniteCanvasController defaults to
    // identity transform so widget-local == world coords for the
    // first frame.)
    await sweepLasso(tester, const [
      Offset(80, 80),
      Offset(160, 80),
      Offset(160, 160),
      Offset(80, 160),
      Offset(80, 80),
    ]);
    expect(state.selection.ids, isNotEmpty,
        reason: 'lasso enclosing the stroke should select it');
  });

  testWidgets(
      'precision: lasso stretto intorno a un punto NON seleziona uno '
      'stroke vicino ma fuori dal path', (tester) async {
    final key = GlobalKey<FlueraCanvasState>();
    await tester.pumpWidget(pump(key, CanvasTool.lasso));
    final state = key.currentState!;
    // Stroke A at (50, 50)-(80, 80) — we will lasso AROUND it.
    // Stroke B at (200, 200)-(230, 230) — far away, should never be
    //   touched. Pre-0.10.x its bbox could fall inside the lasso's
    //   AABB if the lasso swept that area without enclosing B.
    state.pushStroke(makeStroke(50, 50));
    state.pushStroke(makeStroke(200, 200));
    await tester.pumpAndSettle();

    // Sweep a tight loop around stroke A only.
    await sweepLasso(tester, const [
      Offset(40, 40),
      Offset(90, 40),
      Offset(90, 90),
      Offset(40, 90),
      Offset(40, 40),
    ]);
    // Stroke B's bbox is OUTSIDE the lasso's bbox → must not be hit.
    expect(state.selection.ids.length, lessThanOrEqualTo(1));
  });

  testWidgets(
      'pen-down dentro il bbox della selezione lasso → muove i nodi '
      '(non azzera la selezione)', (tester) async {
    final key = GlobalKey<FlueraCanvasState>();
    await tester.pumpWidget(pump(key, CanvasTool.lasso));
    final state = key.currentState!;
    state.pushStroke(makeStroke(100, 100, size: 30));
    await tester.pumpAndSettle();

    await sweepLasso(tester, const [
      Offset(80, 80),
      Offset(160, 80),
      Offset(160, 160),
      Offset(80, 160),
      Offset(80, 80),
    ]);
    expect(state.selection.ids, isNotEmpty);
    final selectedIds = state.selection.ids.toList();

    // Now drag from inside the selection bbox to a new spot. Pre-fix,
    // this would have wiped the selection and started a new lasso.
    final canvas = find.byType(FlueraCanvas);
    final origin = tester.getTopLeft(canvas);
    final gesture =
        await tester.startGesture(origin + const Offset(115, 115));
    await gesture.moveBy(const Offset(40, 40));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();

    // Selection survived the drag.
    expect(state.selection.ids, equals(selectedIds.toSet()));
  });

  testWidgets(
      'pen-down fuori dal bbox della selezione lasso → svuota la '
      'selezione precedente e inizia un nuovo lasso', (tester) async {
    final key = GlobalKey<FlueraCanvasState>();
    await tester.pumpWidget(pump(key, CanvasTool.lasso));
    final state = key.currentState!;
    state.pushStroke(makeStroke(100, 100, size: 30));
    await tester.pumpAndSettle();

    // First lasso → select.
    await sweepLasso(tester, const [
      Offset(80, 80),
      Offset(160, 80),
      Offset(160, 160),
      Offset(80, 160),
      Offset(80, 80),
    ]);
    expect(state.selection.ids, isNotEmpty);

    // Tap-and-drag in a far-away empty region: must clear the old
    // selection and start a fresh lasso.
    await sweepLasso(tester, const [
      Offset(300, 300),
      Offset(360, 300),
      Offset(360, 360),
      Offset(300, 360),
      Offset(300, 300),
    ]);
    // No nodes inside the new lasso → empty selection.
    expect(state.selection.ids, isEmpty);
  });
}
