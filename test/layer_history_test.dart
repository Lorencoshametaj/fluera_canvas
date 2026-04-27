import 'dart:ui' show Color, Offset;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CanvasStroke makeStroke(int seed) => CanvasStroke(
    points: List<Offset>.unmodifiable([
      Offset(seed.toDouble(), 0),
      Offset(seed.toDouble() + 10, 0),
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

  group('Layer history ops (undo/redo)', () {
    testWidgets('addLayer is undoable + redoable', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      expect(state.layers, hasLength(1));

      final created = state.addLayer(name: 'Sketch');
      expect(state.layers, hasLength(2));

      expect(state.undo(), isTrue);
      expect(
        state.layers,
        hasLength(1),
        reason: 'addLayer undo should drop the layer',
      );

      expect(state.redo(), isTrue);
      expect(state.layers, hasLength(2));
      expect(state.layers.last.id, created.id);
    });

    testWidgets('removeLayer restores the layer + its strokes on undo', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      // Build: 2 layers, each with 2 strokes.
      final l2 = state.addLayer(name: 'Top');
      // Push strokes into the active (default) layer.
      state.pushStrokes([makeStroke(1), makeStroke(2)]);
      // Switch active to l2 so subsequent strokes land there.
      state.setActiveLayer(l2.id);
      state.pushStrokes([makeStroke(3), makeStroke(4)]);
      expect(state.strokeCount, 4);

      final removed = state.removeLayer(state.layers.first.id);
      expect(removed, isTrue);
      expect(state.layers, hasLength(1));
      expect(
        state.strokeCount,
        2,
        reason: 'removed layer\'s strokes should be dropped',
      );

      expect(state.undo(), isTrue);
      expect(state.layers, hasLength(2));
      expect(
        state.strokeCount,
        4,
        reason: 'undo should reattach all dropped strokes',
      );

      expect(state.redo(), isTrue);
      expect(state.layers, hasLength(1));
      expect(state.strokeCount, 2);
    });

    testWidgets('setLayerVisible / setLayerLocked are undoable', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      final layer = state.activeLayer;

      state.setLayerVisible(layer.id, false);
      expect(state.activeLayer.isVisible, isFalse);
      state.undo();
      expect(state.activeLayer.isVisible, isTrue);

      state.setLayerLocked(layer.id, true);
      expect(state.activeLayer.isLocked, isTrue);
      state.undo();
      expect(state.activeLayer.isLocked, isFalse);
    });

    testWidgets('setLayerOpacity is undoable + tolerant to no-op writes', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      final layer = state.activeLayer;
      final undoBefore = state.historyLength;

      state.setLayerOpacity(layer.id, 1.0);
      expect(
        state.historyLength,
        undoBefore,
        reason: 'opacity 1.0 -> 1.0 should not push to history',
      );

      state.setLayerOpacity(layer.id, 0.4);
      expect(layer.opacity, closeTo(0.4, 1e-6));
      state.undo();
      expect(layer.opacity, closeTo(1.0, 1e-6));
    });

    testWidgets('reorderLayer is undoable, restores original Z-order', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      final l1 = state.activeLayer;
      final l2 = state.addLayer(name: 'Second');
      final l3 = state.addLayer(name: 'Third');
      expect(state.layers.map((l) => l.id), [l1.id, l2.id, l3.id]);

      state.reorderLayer(l3.id, 0);
      expect(state.layers.map((l) => l.id), [l3.id, l1.id, l2.id]);

      state.undo();
      expect(state.layers.map((l) => l.id), [l1.id, l2.id, l3.id]);

      state.redo();
      expect(state.layers.map((l) => l.id), [l3.id, l1.id, l2.id]);
    });

    testWidgets('setLayerName + setLayerBlendMode are undoable', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      final layer = state.activeLayer;
      final originalName = layer.name;

      state.setLayerName(layer.id, 'Renamed');
      expect(layer.name, 'Renamed');
      state.undo();
      expect(layer.name, originalName);

      state.setLayerBlendMode(layer.id, BlendMode.multiply);
      expect(layer.blendMode, BlendMode.multiply);
      state.undo();
      expect(layer.blendMode, BlendMode.srcOver);
    });
  });
}
