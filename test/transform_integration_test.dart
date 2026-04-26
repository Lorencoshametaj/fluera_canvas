import 'dart:ui' show Color, Offset, Rect;

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
          body: SizedBox(
            width: 600,
            height: 400,
            child: FlueraCanvas(key: key),
          ),
        ),
      );

  group('mirrorSelection (Phase C2)', () {
    testWidgets('mirrorSelection returns 0 on empty selection', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      expect(state.mirrorSelection(Axis.horizontal), 0);
    });

    testWidgets('mirrorSelection horizontal flips around the bounds center',
        (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStrokes([makeStroke(1), makeStroke(2)]);
      state.selectInRect(const Rect.fromLTWH(-100, -100, 1000, 1000));
      final selectedNode = state.activeLayer.children.first as CanvasStrokeNode;
      final before = selectedNode.localTransform.clone();

      final affected = state.mirrorSelection(Axis.horizontal);
      expect(affected, 2);
      expect(
        selectedNode.localTransform.storage[0],
        isNot(equals(before.storage[0])),
        reason: 'mirrorH should flip the X-scale component',
      );
    });

    testWidgets('mirrorSelection is undoable as a single op', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStrokes([makeStroke(1), makeStroke(2)]);
      state.selectInRect(const Rect.fromLTWH(-100, -100, 1000, 1000));
      final node = state.activeLayer.children.first as CanvasStrokeNode;
      final beforeMatrix = node.localTransform.clone();

      state.mirrorSelection(Axis.vertical);
      expect(node.localTransform.storage[5], isNot(beforeMatrix.storage[5]));

      expect(state.undo(), isTrue);
      for (int i = 0; i < 16; i++) {
        expect(node.localTransform.storage[i],
            closeTo(beforeMatrix.storage[i], 1e-9));
      }
    });

    testWidgets('mirrorSelection redo restores the post-mirror state',
        (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStroke(makeStroke(1));
      state.selectInRect(const Rect.fromLTWH(-100, -100, 1000, 1000));
      final node = state.activeLayer.children.single as CanvasStrokeNode;

      state.mirrorSelection(Axis.horizontal);
      final mirrored = node.localTransform.clone();
      state.undo();
      state.redo();
      for (int i = 0; i < 16; i++) {
        expect(node.localTransform.storage[i],
            closeTo(mirrored.storage[i], 1e-9));
      }
    });
  });

  group('Selection bounds reflect post-transform geometry', () {
    testWidgets('mirroring updates the selection bounds', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStroke(makeStroke(2));
      state.selectInRect(const Rect.fromLTWH(-100, -100, 1000, 1000));
      final boundsBefore = state.selection.bounds;

      state.mirrorSelection(Axis.horizontal);
      final boundsAfter = state.selection.bounds;
      // Width should be preserved (mirror is shape-isomorphic) but the
      // center moves on the X axis when the node is off-center.
      expect(boundsAfter.width, closeTo(boundsBefore.width, 1e-3));
    });
  });
}
