import 'dart:ui' show Color, Offset;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CanvasStroke makeStroke(int seed) => CanvasStroke(
    points: List<Offset>.unmodifiable([
      Offset(seed.toDouble() * 50, 0),
      Offset(seed.toDouble() * 50 + 30, 0),
      Offset(seed.toDouble() * 50 + 30, 30),
    ]),
    pressures: const [0.5, 0.7, 0.9],
    color: Color(0xFF000000 + seed),
    baseWidth: 2.0,
  );

  Widget pump(GlobalKey<FlueraCanvasState> key) => MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 400, height: 400, child: FlueraCanvas(key: key)),
    ),
  );

  group('CanvasSelection model', () {
    test('empty constants and equality', () {
      expect(CanvasSelection.empty.isEmpty, isTrue);
      expect(CanvasSelection.empty.length, 0);
      final a = CanvasSelection(ids: <NodeId>{}, bounds: Rect.zero);
      expect(a, CanvasSelection.empty);
    });

    test('controller fires only on real changes', () {
      final c = CanvasSelectionController();
      var fired = 0;
      c.addListener(() => fired++);
      c.set(CanvasSelection.empty);
      expect(fired, 0, reason: 'no-op write should not notify');
      c.set(
        CanvasSelection(
          ids: <NodeId>{const NodeId('a')},
          bounds: const Rect.fromLTWH(0, 0, 10, 10),
        ),
      );
      expect(fired, 1);
      c.clear();
      expect(fired, 2);
    });
  });

  group('FlueraCanvasState selection API', () {
    testWidgets('selection defaults to empty + updates fire listeners', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;

      expect(state.selection.isEmpty, isTrue);

      var fired = 0;
      state.selectionListenable.addListener(() => fired++);

      state.pushStrokes([makeStroke(1), makeStroke(2)]);
      expect(state.strokeCount, 2);

      // selectInRect catches the stroke whose bbox falls inside the rect.
      final hits = state.selectInRect(const Rect.fromLTWH(0, -5, 80, 50));
      expect(hits, greaterThan(0));
      expect(state.selection.isNotEmpty, isTrue);
      expect(fired, greaterThan(0));
    });

    testWidgets('clearSelection resets to empty', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStrokes([makeStroke(1), makeStroke(2)]);
      state.selectInRect(const Rect.fromLTWH(-100, -100, 1000, 1000));
      expect(state.selection.isNotEmpty, isTrue);

      state.clearSelection();
      expect(state.selection.isEmpty, isTrue);
    });

    testWidgets(
      'select(NodeId) targets a known stroke node, returns false otherwise',
      (tester) async {
        final key = GlobalKey<FlueraCanvasState>();
        await tester.pumpWidget(pump(key));
        final state = key.currentState!;
        state.pushStroke(makeStroke(1));
        final activeChild =
            state.activeLayer.children.single as CanvasStrokeNode;

        expect(state.select(activeChild.id), isTrue);
        expect(state.selection.ids, {activeChild.id});

        expect(state.select(const NodeId('does-not-exist')), isFalse);
      },
    );

    testWidgets('deleteSelection removes the strokes + is undoable', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStrokes([makeStroke(1), makeStroke(2), makeStroke(3)]);
      expect(state.strokeCount, 3);

      state.selectInRect(const Rect.fromLTWH(-100, -100, 1000, 1000));
      expect(state.selection.length, 3);

      final removed = state.deleteSelection();
      expect(removed, 3);
      expect(state.strokeCount, 0);
      expect(state.selection.isEmpty, isTrue);

      expect(state.undo(), isTrue);
      expect(
        state.strokeCount,
        3,
        reason: 'undo of deleteSelection must restore every stroke',
      );
    });

    testWidgets('selection skips locked + hidden layers', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      // Add two layers, push 1 stroke into each.
      state.pushStroke(makeStroke(1));
      final l2 = state.addLayer(name: 'Top');
      state.setActiveLayer(l2.id);
      state.pushStroke(makeStroke(2));
      expect(state.strokeCount, 2);

      // Lock the bottom layer and verify selection ignores its strokes.
      state.setLayerLocked(state.layers.first.id, true);
      final hits = state.selectInRect(
        const Rect.fromLTWH(-100, -100, 1000, 1000),
      );
      expect(hits, 1, reason: 'locked layer should be filtered out');

      // Unlock + hide instead — same expectation.
      state.setLayerLocked(state.layers.first.id, false);
      state.setLayerVisible(state.layers.first.id, false);
      final hits2 = state.selectInRect(
        const Rect.fromLTWH(-100, -100, 1000, 1000),
      );
      expect(hits2, 1, reason: 'hidden layer should be filtered out');
    });
  });
}
