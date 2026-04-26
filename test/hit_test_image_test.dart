import 'dart:ui' show Color, Offset, Rect;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CanvasStroke makeStroke({
    required double x,
    required double y,
    double size = 30,
  }) =>
      CanvasStroke(
        points: List<Offset>.unmodifiable([
          Offset(x, y),
          Offset(x + size, y),
          Offset(x + size, y + size),
        ]),
        pressures: const [0.5, 0.7, 0.9],
        color: const Color(0xFF000000),
        baseWidth: 2.0,
      );

  ImageNode makeImage(
    String id, {
    required Offset position,
    Size size = const Size(100, 100),
  }) {
    final node = ImageNode(
      id: NodeId(id),
      imageElement: ImageElement(
        id: id,
        imagePath: 'fluera-canvas://memory/$id',
        position: position,
        createdAt: DateTime.now(),
        pageIndex: 0,
      ),
      imageSize: size,
    );
    return node;
  }

  Widget pump(GlobalKey<FlueraCanvasState> key) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: FlueraCanvas(key: key),
          ),
        ),
      );

  group('selectInRect (marquee) on stroke + image mix', () {
    testWidgets('marquee covering an image picks it up', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;

      final image = makeImage('img-1', position: const Offset(100, 100));
      state.addImageNode(image);

      // Wide-net marquee covering the image's full bounds.
      final hits = state.selectInRect(const Rect.fromLTRB(0, 0, 500, 500));
      expect(hits, greaterThanOrEqualTo(1));
      expect(state.selection.ids, contains(image.id));
    });

    testWidgets('marquee NOT covering the image leaves it unselected',
        (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;

      final image = makeImage('img-far', position: const Offset(400, 400));
      state.addImageNode(image);

      final hits = state.selectInRect(const Rect.fromLTRB(0, 0, 50, 50));
      expect(hits, 0);
      expect(state.selection.isEmpty, isTrue);
    });

    testWidgets('marquee covering both stroke and image picks both',
        (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStroke(makeStroke(x: 50, y: 50));
      final image = makeImage('img-1', position: const Offset(200, 200));
      state.addImageNode(image);

      final hits = state.selectInRect(const Rect.fromLTRB(0, 0, 500, 500));
      expect(hits, 2);
      expect(state.selection.ids, contains(image.id));
    });

    testWidgets('hidden layer is filtered out of marquee selection',
        (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      final image = makeImage('img-hidden', position: const Offset(100, 100));
      state.addImageNode(image);
      state.setLayerVisible(state.activeLayer.id, false);

      final hits = state.selectInRect(const Rect.fromLTRB(0, 0, 500, 500));
      expect(hits, 0);
    });
  });

  group('select(NodeId?) accepts image ids', () {
    testWidgets('select on a known image id succeeds', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      final image = makeImage('img-explicit', position: Offset.zero);
      state.addImageNode(image);

      expect(state.select(image.id), isTrue);
      expect(state.selection.ids, {image.id});
    });

    testWidgets('select on an unknown id returns false', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      expect(state.select(const NodeId('does-not-exist')), isFalse);
    });
  });
}
