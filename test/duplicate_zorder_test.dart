import 'dart:ui' show Color, Offset;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CanvasStroke makeStroke(int seed) => CanvasStroke(
    points: List<Offset>.unmodifiable([
      Offset(seed.toDouble(), 0),
      Offset(seed.toDouble() + 10, 10),
    ]),
    pressures: const [0.5, 0.7],
    color: Color(0xFF000000 + seed),
    baseWidth: 2.0,
  );

  Widget pump(GlobalKey<FlueraCanvasState> key) => MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 600, height: 400, child: FlueraCanvas(key: key)),
    ),
  );

  group('duplicateSelection', () {
    testWidgets('clones strokes + replaces selection with new ids', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStroke(makeStroke(1));
      state.selectInRect(const Rect.fromLTRB(-100, -100, 1000, 1000));
      final originalIds = state.selection.ids.toSet();
      expect(originalIds, hasLength(1));

      final n = state.duplicateSelection();
      expect(n, 1);
      expect(state.strokes, hasLength(2));
      // The selection now points at the clone, not the original.
      expect(state.selection.ids, hasLength(1));
      expect(
        originalIds.intersection(state.selection.ids),
        isEmpty,
        reason: 'selection should swap to the freshly-cloned id',
      );
    });

    testWidgets('undo restores pre-duplicate state', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStroke(makeStroke(1));
      state.selectInRect(const Rect.fromLTRB(-100, -100, 1000, 1000));
      state.duplicateSelection();
      expect(state.strokes, hasLength(2));
      expect(state.undo(), isTrue);
      expect(state.strokes, hasLength(1));
    });
  });

  group('bringToFront / sendToBack', () {
    testWidgets('moves the node to the end / start of children list', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStrokes([makeStroke(1), makeStroke(2), makeStroke(3)]);
      // Original order: indices 0, 1, 2 → strokes 1, 2, 3.
      final ids =
          state.activeLayer.children
              .whereType<CanvasStrokeNode>()
              .map((n) => n.id)
              .toList();
      expect(ids, hasLength(3));

      // Bring middle to front.
      expect(state.bringToFront(ids[1]), isTrue);
      var afterBring =
          state.activeLayer.children
              .whereType<CanvasStrokeNode>()
              .map((n) => n.id)
              .toList();
      expect(afterBring.last, ids[1]);

      // Send first to back (already at back, no-op).
      expect(state.sendToBack(ids[0]), isFalse);

      // Send last (originally middle) to back.
      expect(state.sendToBack(ids[1]), isTrue);
      final afterSend =
          state.activeLayer.children
              .whereType<CanvasStrokeNode>()
              .map((n) => n.id)
              .toList();
      expect(afterSend.first, ids[1]);
    });

    testWidgets('undo restores Z-order', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStrokes([makeStroke(1), makeStroke(2), makeStroke(3)]);
      final ids =
          state.activeLayer.children
              .whereType<CanvasStrokeNode>()
              .map((n) => n.id)
              .toList();
      state.bringToFront(ids[0]);
      expect(state.undo(), isTrue);
      final reverted =
          state.activeLayer.children
              .whereType<CanvasStrokeNode>()
              .map((n) => n.id)
              .toList();
      expect(reverted, ids);
    });
  });
}
