// Tests for layer-mask side-table API on FlueraCanvasState.
//
// Keep these focused on the data-model surface — the rendering path
// (canvas-core dstIn fallback + GPU shader path) is verified visually
// in the canvas_gpu example demo.

import 'dart:ui' as ui;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ui.Image> tinyImage(int w, int h) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    );
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    return recorder.endRecording().toImage(w, h);
  }

  Widget pump(GlobalKey<FlueraCanvasState> key) => MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 400, height: 400, child: FlueraCanvas(key: key)),
    ),
  );

  group('FlueraCanvasState layer mask side-table', () {
    testWidgets(
      'setLayerMask returns true on a known layer + reflects in lookup',
      (tester) async {
        final key = GlobalKey<FlueraCanvasState>();
        await tester.pumpWidget(pump(key));
        final state = key.currentState!;
        final layer = state.layers.first;
        final img = await tinyImage(8, 8);

        final ok = state.setLayerMask(layer.id, img);
        expect(ok, isTrue);
        expect(state.layerMaskFor(layer.id), same(img));
      },
    );

    testWidgets('setLayerMask(null) clears a previously attached mask', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      final layer = state.layers.first;
      final img = await tinyImage(8, 8);
      state.setLayerMask(layer.id, img);
      expect(state.layerMaskFor(layer.id), isNotNull);

      final ok = state.setLayerMask(layer.id, null);
      expect(ok, isTrue);
      expect(state.layerMaskFor(layer.id), isNull);
    });

    testWidgets('setLayerMask returns false for unknown layer id', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      final img = await tinyImage(4, 4);
      final ok = state.setLayerMask(NodeId('does-not-exist'), img);
      expect(ok, isFalse);
      img.dispose();
    });
  });

  group('FlueraCanvasState layer color tag side-table', () {
    testWidgets('setLayerColorTag round-trips through layerColorTagFor', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      final layer = state.layers.first;

      expect(state.layerColorTagFor(layer.id), isNull);
      final ok = state.setLayerColorTag(layer.id, const Color(0xFFE53935));
      expect(ok, isTrue);
      expect(state.layerColorTagFor(layer.id), const Color(0xFFE53935));

      // Clear via null.
      state.setLayerColorTag(layer.id, null);
      expect(state.layerColorTagFor(layer.id), isNull);
    });

    testWidgets('setLayerColorTag returns false for unknown layer id', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      expect(
        state.setLayerColorTag(NodeId('not-here'), const Color(0xFF000000)),
        isFalse,
      );
    });
  });
}
