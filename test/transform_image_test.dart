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

  ImageNode makeImage(String id, {Offset position = Offset.zero}) => ImageNode(
        id: NodeId(id),
        imageElement: ImageElement(
          id: id,
          imagePath: 'fluera-canvas://memory/$id',
          position: position,
          createdAt: DateTime.now(),
          pageIndex: 0,
        ),
        imageSize: const Size(100, 80),
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

  group('mirrorSelection over CanvasNode mix', () {
    testWidgets('image-only selection: mirrorH flips localTransform[0]',
        (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      final image = makeImage('i1');
      state.addImageNode(image);
      state.select(image.id);

      final affected = state.mirrorSelection(Axis.horizontal);
      expect(affected, 1);
      expect(image.localTransform.storage[0], lessThan(0),
          reason: 'mirrorH must flip the X-scale component');
    });

    testWidgets('image-only selection: mirrorV flips localTransform[5]',
        (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      final image = makeImage('i2');
      state.addImageNode(image);
      state.select(image.id);

      final affected = state.mirrorSelection(Axis.vertical);
      expect(affected, 1);
      expect(image.localTransform.storage[5], lessThan(0));
    });

    testWidgets('mixed stroke + image: both nodes mirrored, single op pushed',
        (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStroke(makeStroke(1));
      final image = makeImage('mixed');
      state.addImageNode(image);
      state.selectInRect(const Rect.fromLTRB(-100, -100, 1000, 1000));
      expect(state.selection.length, 2);
      final undoBefore = state.historyLength;

      final affected = state.mirrorSelection(Axis.horizontal);
      expect(affected, 2);
      // Single coalesced TransformNodesOp.
      expect(state.historyLength, undoBefore + 1);

      // Image localTransform was mutated.
      expect(image.localTransform.storage[0], lessThan(0));

      // Undo restores both — image's localTransform back to identity.
      expect(state.undo(), isTrue);
      expect(image.localTransform.storage[0], 1.0);
    });

    testWidgets('redo of mirrorSelection re-applies to image',
        (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      final image = makeImage('redo');
      state.addImageNode(image);
      state.select(image.id);

      state.mirrorSelection(Axis.horizontal);
      final mirrored = image.localTransform.clone();
      state.undo();
      expect(image.localTransform.storage[0], 1.0);
      state.redo();
      for (int i = 0; i < 16; i++) {
        expect(image.localTransform.storage[i],
            closeTo(mirrored.storage[i], 1e-9));
      }
    });
  });
}
