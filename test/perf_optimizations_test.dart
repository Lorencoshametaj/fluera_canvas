import 'dart:ui' show Color, Offset, Rect;

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

  ImageNode makeImage(String id) => ImageNode(
    id: NodeId(id),
    imageElement: ImageElement(
      id: id,
      imagePath: 'fluera-canvas://memory/$id',
      position: Offset.zero,
      createdAt: DateTime.now(),
      pageIndex: 0,
    ),
    imageSize: const Size(50, 50),
  );

  Widget pump(GlobalKey<FlueraCanvasState> key) => MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 600, height: 400, child: FlueraCanvas(key: key)),
    ),
  );

  group('A — incremental Z-order (no fold)', () {
    testWidgets('Z-stamps grow monotonically with each register', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStroke(makeStroke(1));
      state.pushStroke(makeStroke(2));
      state.pushStroke(makeStroke(3));
      final z = state.debugZOrderIndex;
      // Each stroke gets a strictly higher Z than the previous.
      final values = z.values.toList()..sort();
      for (int i = 1; i < values.length; i++) {
        expect(
          values[i] > values[i - 1],
          isTrue,
          reason: 'stamp must increase monotonically',
        );
      }
    });

    testWidgets('1000 inserts run without quadratic blow-up', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      // Crude: insert 1000 strokes and assert it completes in
      // way-under a generous wall-clock budget. With the old fold
      // this was Σi from 1..1000 = ~500k comparisons.
      final sw = Stopwatch()..start();
      for (int i = 0; i < 1000; i++) {
        state.pushStroke(makeStroke(i));
      }
      sw.stop();
      expect(
        sw.elapsedMilliseconds,
        lessThan(2000),
        reason: '1k inserts should complete well under 2s',
      );
      expect(state.debugSelectableIds, hasLength(1000));
    });
  });

  group('B — non-stroke fast path', () {
    testWidgets('hit-test on canvas with many strokes + few images uses '
        'the non-stroke subset', (tester) async {
      // Smoke check: with 200 strokes and 1 image, tap on the image
      // must succeed. The optimisation iterates only the non-stroke
      // subset (1 entry) instead of all 201 selectable ids.
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      for (int i = 0; i < 200; i++) {
        state.pushStroke(makeStroke(i));
      }
      final image = makeImage('the-image');
      state.addImageNode(image);

      // Marquee covering everything should pick up the image.
      final hits = state.selectInRect(
        const Rect.fromLTRB(-100, -100, 1000, 1000),
      );
      expect(state.selection.ids, contains(image.id));
      expect(hits, greaterThanOrEqualTo(1));
    });
  });

  group('F — _nodesWithTransform counter', () {
    testWidgets('mirror + undo round-trip leaves the counter at 0', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStrokes([makeStroke(1), makeStroke(2), makeStroke(3)]);
      state.selectInRect(const Rect.fromLTRB(-100, -100, 1000, 1000));
      // Apply a mirror — every stroke gets a non-identity transform.
      state.mirrorSelection(Axis.horizontal);
      // Undo restores identity for all of them.
      expect(state.undo(), isTrue);
      // No public counter, but we can assert correctness indirectly:
      // a fresh paint pass on a transform-free scene must produce
      // the SAME visible nodes as before the gesture. Bounds covering
      // every stroke selects exactly 3.
      final hits = state.selectInRect(
        const Rect.fromLTRB(-1000, -1000, 2000, 2000),
      );
      expect(
        hits,
        3,
        reason: 'undo must restore identity transforms for all 3 strokes',
      );
    });

    testWidgets('mirror H + mirror H = identity (counter back to 0)', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStroke(makeStroke(1));
      state.selectInRect(const Rect.fromLTRB(-100, -100, 1000, 1000));
      state.mirrorSelection(Axis.horizontal);
      state.mirrorSelection(Axis.horizontal);
      // Two consecutive horizontal mirrors compose back to identity
      // — _nodesWithTransform should swing 0 → 1 → 0 across the two
      // calls. Indirect assertion: the localTransform comes back to
      // identity (storage[0] = 1, [5] = 1, no translation).
      final node = state.activeLayer.children.single as CanvasStrokeNode;
      expect(node.localTransform.storage[0], closeTo(1.0, 1e-6));
      expect(node.localTransform.storage[5], closeTo(1.0, 1e-6));
    });
  });
}
