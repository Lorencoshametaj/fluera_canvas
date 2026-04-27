import 'dart:ui' show Offset;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ImageNode makeImage(String id) => ImageNode(
    id: NodeId(id),
    imageElement: ImageElement(
      id: id,
      imagePath: 'fluera-canvas://memory/$id',
      position: Offset.zero,
      createdAt: DateTime.now(),
      pageIndex: 0,
    ),
    imageSize: const Size(100, 80),
  );

  Widget pump(GlobalKey<FlueraCanvasState> key, {CanvasTool? tool}) =>
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: FlueraCanvas(key: key, tool: tool ?? CanvasTool.draw),
          ),
        ),
      );

  group('Auto-clear selection on draw start', () {
    testWidgets(
      'tap+drag in tool=draw clears active image selection on first stroke',
      (tester) async {
        final key = GlobalKey<FlueraCanvasState>();
        // Mount in select mode first so we can populate a selection.
        await tester.pumpWidget(pump(key, tool: CanvasTool.draw));
        final state = key.currentState!;

        // Programmatically place an image and select it (simulating
        // the user having tapped Select then the image).
        final image = makeImage('i1');
        state.addImageNode(image);
        state.select(image.id);
        expect(state.selection.isNotEmpty, isTrue);

        // Simulate a drag gesture on the canvas in tool=draw — first
        // pen-down should clear the selection.
        await tester.drag(find.byType(FlueraCanvas), const Offset(40, 40));
        await tester.pump();
        expect(
          state.selection.isEmpty,
          isTrue,
          reason: 'tool=draw must auto-clear selection on first stroke',
        );
      },
    );

    testWidgets(
      'eraser tool does NOT auto-clear selection (eraser is non-modal)',
      (tester) async {
        final key = GlobalKey<FlueraCanvasState>();
        await tester.pumpWidget(pump(key, tool: CanvasTool.erase));
        final state = key.currentState!;
        final image = makeImage('i1');
        state.addImageNode(image);
        state.select(image.id);
        expect(state.selection.isNotEmpty, isTrue);

        await tester.drag(find.byType(FlueraCanvas), const Offset(40, 40));
        await tester.pump();
        expect(
          state.selection.isNotEmpty,
          isTrue,
          reason: 'erase / erasePixel must keep the selection visible',
        );
      },
    );
  });
}
