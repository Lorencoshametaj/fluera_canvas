// Tests for Step E layer ops (mergeDown / flatten / renderLayerThumbnail).

import 'dart:ui' show Color, Offset, Size;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CanvasStroke makeStroke(int seed, {double y = 0}) => CanvasStroke(
    points: List<Offset>.unmodifiable([
      Offset(seed.toDouble(), y),
      Offset(seed.toDouble() + 10, y),
    ]),
    pressures: const [0.5, 0.7],
    color: Color(0xFF000000 + seed),
    baseWidth: 2.0,
  );

  Widget pump(GlobalKey<FlueraCanvasState> key) => MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 400, height: 400, child: FlueraCanvas(key: key)),
    ),
  );

  group('FlueraCanvasState.mergeDown', () {
    testWidgets('merges upper layer strokes into lower in Z-order', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      final lower = state.layers.first;
      state.pushStrokes([makeStroke(1), makeStroke(2)]); // on lower

      final upper = state.addLayer(name: 'Upper');
      state.setActiveLayer(upper.id);
      state.pushStrokes([makeStroke(3), makeStroke(4)]); // on upper

      expect(state.layers, hasLength(2));
      expect(state.strokeCount, 4);

      final ok = state.mergeDown(upper.id);
      expect(ok, isTrue);
      expect(
        state.layers,
        hasLength(1),
        reason: 'upper layer should be removed',
      );
      expect(
        state.layers.first.id,
        lower.id,
        reason: 'lower layer survives the merge',
      );
      expect(state.strokeCount, 4, reason: 'all 4 strokes survive the merge');
    });

    testWidgets('refuses to merge when target is the bottom layer', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      final bottom = state.layers.first;
      state.addLayer(name: 'Top');
      expect(
        state.mergeDown(bottom.id),
        isFalse,
        reason: 'no layer below bottom — refuse',
      );
    });

    testWidgets('refuses to merge when destination layer is locked', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      final lower = state.layers.first;
      state.setLayerLocked(lower.id, true);
      final upper = state.addLayer(name: 'Upper');
      expect(state.mergeDown(upper.id), isFalse);
      expect(state.layers, hasLength(2));
    });

    testWidgets('mergeDown is undoable + redoable', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStrokes([makeStroke(1)]);
      final upper = state.addLayer(name: 'Upper');
      state.setActiveLayer(upper.id);
      state.pushStrokes([makeStroke(2)]);

      expect(state.mergeDown(upper.id), isTrue);
      expect(state.layers, hasLength(1));

      expect(state.undo(), isTrue);
      expect(
        state.layers,
        hasLength(2),
        reason: 'undo restores the upper layer',
      );
      expect(state.strokeCount, 2);

      expect(state.redo(), isTrue);
      expect(state.layers, hasLength(1), reason: 'redo re-applies the merge');
      expect(state.strokeCount, 2);
    });
  });

  group('FlueraCanvasState.flatten', () {
    testWidgets('collapses every layer into the bottom one', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      final bottom = state.layers.first;
      state.pushStrokes([makeStroke(1)]); // on bottom
      final mid = state.addLayer(name: 'Mid');
      state.setActiveLayer(mid.id);
      state.pushStrokes([makeStroke(2)]);
      final top = state.addLayer(name: 'Top');
      state.setActiveLayer(top.id);
      state.pushStrokes([makeStroke(3)]);

      expect(state.layers, hasLength(3));
      expect(state.strokeCount, 3);

      expect(state.flatten(), isTrue);
      expect(state.layers, hasLength(1));
      expect(
        state.layers.first.id,
        bottom.id,
        reason: 'bottom layer survives flatten',
      );
      expect(
        state.strokeCount,
        3,
        reason: 'visible-layer strokes are preserved',
      );
    });

    testWidgets('flatten drops hidden-layer strokes', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStrokes([makeStroke(1)]);
      final mid = state.addLayer(name: 'Mid');
      state.setActiveLayer(mid.id);
      state.pushStrokes([makeStroke(2)]);
      state.setLayerVisible(mid.id, false);

      expect(state.flatten(), isTrue);
      // Hidden layer's stroke is gone; bottom's stroke survives.
      expect(state.strokeCount, 1);
    });

    testWidgets('flatten is undoable + restores hidden-layer strokes', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStrokes([makeStroke(1)]);
      final mid = state.addLayer(name: 'Mid');
      state.setActiveLayer(mid.id);
      state.pushStrokes([makeStroke(2)]);
      state.setLayerVisible(mid.id, false);

      state.flatten();
      expect(state.strokeCount, 1);

      expect(state.undo(), isTrue);
      expect(
        state.layers,
        hasLength(2),
        reason: 'undo re-attaches the hidden layer',
      );
      expect(
        state.strokeCount,
        2,
        reason: 'undo re-inserts the hidden stroke into the index',
      );
    });
  });

  group('FlueraCanvasState.renderLayerThumbnail', () {
    testWidgets('returns a non-empty image at the requested size', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStrokes([makeStroke(10), makeStroke(20, y: 30)]);

      final img = state.renderLayerThumbnail(
        state.layers.first.id,
        const Size(64, 64),
      );
      expect(img.width, 64);
      expect(img.height, 64);
      img.dispose();
    });

    testWidgets('empty layer returns transparent image at the size', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      // Create a fresh layer that has no strokes.
      final empty = state.addLayer(name: 'Empty');
      final img = state.renderLayerThumbnail(empty.id, const Size(48, 48));
      expect(img.width, 48);
      expect(img.height, 48);
      img.dispose();
    });
  });
}
