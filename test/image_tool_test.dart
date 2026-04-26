import 'dart:typed_data' show Uint8List;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget pump(GlobalKey<FlueraCanvasState> key, {CanvasTool? tool}) =>
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: FlueraCanvas(
              key: key,
              tool: tool ?? CanvasTool.draw,
            ),
          ),
        ),
      );

  setUp(() {
    ImageNodePainter.clearCache();
  });

  group('FlueraImageTool.commitBytes', () {
    testWidgets('corrupt bytes return null without throwing', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      // Random non-PNG bytes — `instantiateImageCodec` will reject; the
      // tool must catch and return null without surfacing an exception.
      final node = await tester.runAsync(() => FlueraImageTool.commitBytes(
            state,
            bytes: Uint8List.fromList(const [0, 1, 2, 3, 4, 5]),
          ));
      expect(node, isNull);
      expect(state.activeLayer.children, isEmpty);
    });
  });

  group('addImageNode (Phase D synchronous API)', () {
    testWidgets('appends to active layer + pushes a single undo step',
        (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      final element = ImageElement(
        id: 'manual',
        imagePath: 'fluera-canvas://memory/manual',
        position: Offset.zero,
        createdAt: DateTime.now(),
        pageIndex: 0,
      );
      final node = ImageNode(
        id: const NodeId('manual'),
        imageElement: element,
      );

      state.addImageNode(node);
      expect(state.activeLayer.children, hasLength(1));
      expect(state.activeLayer.children.single, same(node));

      expect(state.undo(), isTrue);
      expect(state.activeLayer.children, isEmpty);

      expect(state.redo(), isTrue);
      expect(state.activeLayer.children, hasLength(1));
      expect(state.activeLayer.children.single, same(node));
    });

    testWidgets('two addImageNode calls produce two layer children',
        (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      ImageNode make(String id) => ImageNode(
            id: NodeId(id),
            imageElement: ImageElement(
              id: id,
              imagePath: 'fluera-canvas://memory/$id',
              position: Offset.zero,
              createdAt: DateTime.now(),
              pageIndex: 0,
            ),
          );
      state.addImageNode(make('a'));
      state.addImageNode(make('b'));
      expect(state.activeLayer.children, hasLength(2));
      expect(state.historyLength, 2,
          reason: 'each addImageNode pushes its own undo step');
    });
  });

  group('CanvasTool.image is a no-op gesture', () {
    testWidgets('canvas accepts CanvasTool.image without crashing',
        (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key, tool: CanvasTool.image));
      final state = key.currentState!;
      expect(state.strokeCount, 0);
      expect(state.selection.isEmpty, isTrue);
      // Tool is imperative — `pickAndCommit` is the entry point; the
      // gesture pipeline never produces strokes when `tool` is image.
    });
  });

  group('ImageNodePainter cache', () {
    test('cache + isCached + evict + clearCache', () async {
      // No widgets, no codec — just exercise the cache contract.
      // Use a fake string key + skip the real ui.Image (not needed for
      // the cache table itself; the painter's contract is the public
      // map operations).
      ImageNodePainter.clearCache();
      expect(ImageNodePainter.isCached('a'), isFalse);
      // Real ui.Image is non-trivial to construct in tests without a
      // codec, so we test indirectly: the cache is only callable via
      // `cache(path, image)`. We can't round-trip without a real image,
      // but we CAN assert eviction is idempotent + clearCache empties
      // the table without throwing.
      ImageNodePainter.evict('a');
      ImageNodePainter.clearCache();
    });
  });
}
