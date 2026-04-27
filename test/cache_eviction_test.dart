import 'dart:ui' as ui;
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
    imageSize: const Size(100, 80),
  );

  /// Push a fake `ui.Image`-shaped sentinel into the painter cache so
  /// we can assert eviction by checking `isCached`. We can't easily
  /// instantiate a real `ui.Image` here without a codec; the cache
  /// API is keyed on the path string, so this works as a smoke test
  /// of the eviction wiring.
  Future<void> primeCacheForId(String id) async {
    // The painter cache wants a `ui.Image`. Build a 1×1 transparent
    // image via PictureRecorder so the test stays runtime-only.
    final recorder = ui.PictureRecorder();
    Canvas(recorder);
    final picture = recorder.endRecording();
    final image = await picture.toImage(1, 1);
    ImageNodePainter.cache('fluera-canvas://memory/$id', image);
  }

  Widget pump(GlobalKey<FlueraCanvasState> key, {int historyCapacity = 100}) =>
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: FlueraCanvas(key: key, historyCapacity: historyCapacity),
          ),
        ),
      );

  setUp(() {
    ImageNodePainter.clearCache();
  });

  group('History capacity → onEvicted', () {
    testWidgets('image cache is evicted when delete op falls off ring buffer', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      // Tiny ring buffer so the eviction path is reachable in 2 ops.
      await tester.pumpWidget(pump(key, historyCapacity: 1));
      final state = key.currentState!;
      await tester.runAsync(() => primeCacheForId('img-evict-me'));
      expect(
        ImageNodePainter.isCached('fluera-canvas://memory/img-evict-me'),
        isTrue,
      );

      // Add the image, select it, delete it. _DeleteNodesOp now sits
      // at the top of the undo stack.
      state.addImageNode(makeImage('img-evict-me'));
      state.selectInRect(const Rect.fromLTRB(-100, -100, 1000, 1000));
      state.deleteSelection();

      // Push one more op (a stroke commit) — capacity = 1, so the
      // _DeleteNodesOp gets pushed off the back of the ring buffer.
      // Its onEvicted should drop the image's cached ui.Image.
      state.pushStroke(makeStroke(1));

      expect(
        ImageNodePainter.isCached('fluera-canvas://memory/img-evict-me'),
        isFalse,
        reason: 'image cache must be released when its delete op evicts',
      );
    });

    testWidgets(
      'image cache stays alive if a live ImageNode still references its path',
      (tester) async {
        final key = GlobalKey<FlueraCanvasState>();
        await tester.pumpWidget(pump(key, historyCapacity: 1));
        final state = key.currentState!;
        await tester.runAsync(() => primeCacheForId('shared-asset'));

        // Add TWO image nodes that share the same imagePath. Delete
        // one, push another op to evict the delete op. The cache key
        // should survive because the sibling still references it.
        final img1 = ImageNode(
          id: const NodeId('a'),
          imageElement: ImageElement(
            id: 'a',
            imagePath: 'fluera-canvas://memory/shared-asset',
            position: Offset.zero,
            createdAt: DateTime.now(),
            pageIndex: 0,
          ),
          imageSize: const Size(100, 100),
        );
        final img2 = ImageNode(
          id: const NodeId('b'),
          imageElement: ImageElement(
            id: 'b',
            imagePath: 'fluera-canvas://memory/shared-asset',
            position: const Offset(150, 0),
            createdAt: DateTime.now(),
            pageIndex: 0,
          ),
          imageSize: const Size(100, 100),
        );
        state.addImageNode(img1);
        state.addImageNode(img2);
        state.select(img1.id);
        state.deleteSelection();

        // Force the delete op out of the ring buffer.
        state.pushStroke(makeStroke(1));

        expect(
          ImageNodePainter.isCached('fluera-canvas://memory/shared-asset'),
          isTrue,
          reason: 'live sibling reference must keep the cache entry alive',
        );
      },
    );

    testWidgets(
      'redo-stack clear of an addImage op evicts the orphaned image',
      (tester) async {
        // Flow that exercises `_AddLayerChildOp.onEvicted`:
        //  - addImage  → pushes AddLayerChildOp on the undo stack
        //  - undo      → the op moves to the redo stack; image is
        //                detached from the scene (no longer in
        //                _selectableNodes); the cache key is now
        //                only reachable via redo.
        //  - pushStroke → fresh op clears the redo stack; the
        //                 AddLayerChildOp's `onEvicted` runs, sees
        //                 no live ImageNode referencing the path,
        //                 calls `ImageNodePainter.evict`.
        final key = GlobalKey<FlueraCanvasState>();
        await tester.pumpWidget(pump(key, historyCapacity: 100));
        final state = key.currentState!;
        await tester.runAsync(() => primeCacheForId('redo-evict'));

        state.addImageNode(makeImage('redo-evict'));
        // Undo to push the AddLayerChildOp into the redo stack and
        // detach the image from the scene.
        expect(state.undo(), isTrue);
        // New op invalidates the redo stack — the orphaned op gets
        // its `onEvicted` call so the cache is released.
        state.pushStroke(makeStroke(1));

        expect(
          ImageNodePainter.isCached('fluera-canvas://memory/redo-evict'),
          isFalse,
          reason:
              'pushing a fresh op clears the redo stack and must evict its ops',
        );
      },
    );
  });
}
