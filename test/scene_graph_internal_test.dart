import 'dart:ui' show Color, Offset;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CanvasStroke makeStroke(int seed) => CanvasStroke(
    points: List.unmodifiable([
      Offset(seed.toDouble(), 0),
      Offset(seed.toDouble() + 10, 0),
      Offset(seed.toDouble() + 10, 20),
    ]),
    pressures: List.unmodifiable(const [0.5, 0.7, 0.9]),
    color: Color(0xFF000000 + seed),
    baseWidth: 2.0,
  );

  Widget pump(GlobalKey<FlueraCanvasState> key) => MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 400, height: 400, child: FlueraCanvas(key: key)),
    ),
  );

  group('FlueraCanvas scene-graph mirror', () {
    testWidgets('initial state exposes one default layer', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;

      expect(state.layers, hasLength(1));
      expect(state.activeLayer, same(state.layers.single));
      expect(state.activeLayer.elementCount, 0);
      expect(state.rootLayer.children, hasLength(1));
    });

    testWidgets('pushStroke mirrors into the active layer', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      final s = makeStroke(1);

      state.pushStroke(s);

      expect(state.strokeCount, 1);
      expect(state.activeLayer.children, hasLength(1));
      expect(state.activeLayer.children.single, isA<CanvasStrokeNode>());
      expect(
        (state.activeLayer.children.single as CanvasStrokeNode).stroke,
        same(s),
      );
    });

    testWidgets('clear empties both flat list and active layer', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStrokes([makeStroke(1), makeStroke(2), makeStroke(3)]);

      state.clear();

      expect(state.strokeCount, 0);
      expect(state.activeLayer.children, isEmpty);
      expect(
        state.layers,
        hasLength(1),
        reason: 'clear must preserve the layer itself',
      );
    });

    testWidgets('undo restores both flat list and scene-graph children', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStrokes([makeStroke(1), makeStroke(2), makeStroke(3)]);
      state.clear();
      expect(state.strokeCount, 0);

      final ok = state.undo();
      expect(ok, isTrue);
      expect(state.strokeCount, 3);
      expect(state.activeLayer.children, hasLength(3));
      // Z-order preserved: indexes 0/1/2 match insertion order.
      for (int i = 0; i < 3; i++) {
        final node = state.activeLayer.children[i] as CanvasStrokeNode;
        expect(node.stroke, same(state.strokes[i]));
      }
    });

    testWidgets('Z-order after pushStrokes matches insertion order', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      final strokes = List.generate(5, makeStroke);
      state.pushStrokes(strokes);

      for (int i = 0; i < 5; i++) {
        final node = state.activeLayer.children[i] as CanvasStrokeNode;
        expect(node.stroke, same(strokes[i]));
      }
    });

    testWidgets('loadFromBytes round-trips through FCV0 + repopulates graph', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStrokes([makeStroke(1), makeStroke(2)]);
      final bytes = state.toBytes();

      // Wipe.
      state.clear();
      expect(state.strokeCount, 0);

      state.loadFromBytes(bytes);
      expect(state.strokeCount, 2);
      expect(state.activeLayer.children, hasLength(2));
      expect(state.activeLayer.children.first, isA<CanvasStrokeNode>());
    });
  });
}
