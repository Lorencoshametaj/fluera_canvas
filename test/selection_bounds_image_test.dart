import 'dart:ui' show Color, Offset, Rect;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CanvasStroke makeStroke(Offset start, Offset end) => CanvasStroke(
    points: List<Offset>.unmodifiable([start, end]),
    pressures: const [0.5, 0.7],
    color: const Color(0xFF000000),
    baseWidth: 2.0,
  );

  ImageNode makeImage(
    String id, {
    required Offset position,
    required Size size,
  }) {
    return ImageNode(
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
  }

  Widget pump(GlobalKey<FlueraCanvasState> key) => MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 600, height: 400, child: FlueraCanvas(key: key)),
    ),
  );

  group('selection.bounds includes image worldBounds', () {
    testWidgets('image-only selection bounds = image worldBounds', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      final image = makeImage(
        'i1',
        position: const Offset(50, 60),
        size: const Size(100, 80),
      );
      state.addImageNode(image);
      state.select(image.id);
      final b = state.selection.bounds;
      // localBounds = (50, 60, 100, 80) at scale=1, no localTransform.
      expect(b.left, closeTo(50, 1e-6));
      expect(b.top, closeTo(60, 1e-6));
      expect(b.width, closeTo(100, 1e-6));
      expect(b.height, closeTo(80, 1e-6));
    });

    testWidgets('mixed stroke + image selection: bounds expands across both', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      // Stroke at top-left.
      state.pushStroke(makeStroke(const Offset(0, 0), const Offset(20, 20)));
      // Image far to the bottom-right.
      final image = makeImage(
        'i1',
        position: const Offset(300, 200),
        size: const Size(40, 40),
      );
      state.addImageNode(image);
      // Wide marquee picks both.
      state.selectInRect(const Rect.fromLTRB(-5, -5, 500, 500));
      expect(state.selection.length, 2);
      final b = state.selection.bounds;
      // Bounding rect must cover stroke top-left (~ 0,0) AND
      // image bottom-right (340, 240).
      expect(b.left, lessThanOrEqualTo(0));
      expect(b.top, lessThanOrEqualTo(0));
      expect(b.right, greaterThanOrEqualTo(340));
      expect(b.bottom, greaterThanOrEqualTo(240));
    });

    // mirrorSelection over an ImageNode lands in Phase 4 (transform
    // pipeline generalisation). The current implementation iterates
    // `_strokeToNode` which doesn't see images yet — covered there.
  });
}
