import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<({ui.Image image, Uint8List bytes})> makeFake() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder);
    final picture = recorder.endRecording();
    final image = await picture.toImage(1, 1);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return (image: image, bytes: byteData!.buffer.asUint8List());
  }

  setUp(() {
    ImageNodePainter.clearCache();
  });

  group('FlueraStickerPanel', () {
    testWidgets('renders the empty-state placeholder when stickers is empty', (
      tester,
    ) async {
      final canvasKey = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(height: 100, child: FlueraCanvas(key: canvasKey)),
                // Pass an explicit empty list to opt out of the
                // default Material-icon catalogue (introduced in
                // 0.9.x post-spike). The default is non-empty so a
                // bare `FlueraStickerPanel(canvasKey: ...)` now
                // shows 8 icons; this test isolates the "no
                // stickers wired" UX.
                Expanded(
                  child: FlueraStickerPanel(
                    canvasKey: canvasKey,
                    stickers: const [],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.textContaining('No stickers configured'), findsOneWidget);
    });

    testWidgets(
      'default catalogue (kFlueraDefaultStickers) renders the bundled icons',
      (tester) async {
        final canvasKey = GlobalKey<FlueraCanvasState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  SizedBox(height: 100, child: FlueraCanvas(key: canvasKey)),
                  Expanded(child: FlueraStickerPanel(canvasKey: canvasKey)),
                ],
              ),
            ),
          ),
        );
        // The default catalogue ships 8 icon stickers; we verify a
        // few of the labels render in the grid.
        expect(find.text('Star'), findsOneWidget);
        expect(find.text('Heart'), findsOneWidget);
        expect(find.text('Idea'), findsOneWidget);
      },
    );

    testWidgets('tap on a thumbnail commits an ImageNode + fires onSelected', (
      tester,
    ) async {
      final fake = await tester.runAsync(makeFake);
      // Pre-warm the cache so the panel's commit path takes the fast
      // re-decode-skip branch (E optimisation).
      const stickerId = 'cat';
      final imagePath = 'fluera-canvas://sticker/$stickerId';
      ImageNodePainter.cacheWithBytes(imagePath, fake!.image, fake.bytes);

      final canvasKey = GlobalKey<FlueraCanvasState>();
      FlueraSticker? captured;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: 200,
                  height: 100,
                  child: FlueraCanvas(key: canvasKey),
                ),
                Expanded(
                  child: FlueraStickerPanel(
                    canvasKey: canvasKey,
                    stickers: [
                      FlueraSticker(
                        id: stickerId,
                        label: 'Cat',
                        // MemoryImage so the thumbnail renders without
                        // touching an AssetBundle in the test env.
                        provider: MemoryImage(fake.bytes),
                      ),
                    ],
                    onSelected: (sticker, _) => captured = sticker,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cat'));
      await tester.pumpAndSettle();

      final state = canvasKey.currentState!;
      final images = state.activeLayer.children.whereType<ImageNode>().toList();
      expect(images, hasLength(1));
      expect(images.single.imageElement.imagePath, imagePath);
      expect(captured?.id, stickerId);
    });

    testWidgets('two taps reuse the same cache entry', (tester) async {
      final fake = await tester.runAsync(makeFake);
      const stickerId = 'star';
      final imagePath = 'fluera-canvas://sticker/$stickerId';
      ImageNodePainter.cacheWithBytes(imagePath, fake!.image, fake.bytes);

      final canvasKey = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  width: 200,
                  height: 100,
                  child: FlueraCanvas(key: canvasKey),
                ),
                Expanded(
                  child: FlueraStickerPanel(
                    canvasKey: canvasKey,
                    stickers: [
                      FlueraSticker(
                        id: stickerId,
                        label: 'Star',
                        provider: MemoryImage(fake.bytes),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The first ui.Image identity captured at cache time.
      final firstImage = ImageNodePainter.get(imagePath);
      expect(firstImage, isNotNull);

      // Drop the same sticker twice.
      await tester.tap(find.text('Star'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Star'));
      await tester.pumpAndSettle();

      // Same cached handle survived both drops — the optimisation
      // means we never re-decoded.
      expect(
        identical(ImageNodePainter.get(imagePath), firstImage),
        isTrue,
        reason: 'sticker cache must reuse the original ui.Image handle',
      );
      final state = canvasKey.currentState!;
      expect(
        state.activeLayer.children.whereType<ImageNode>(),
        hasLength(2),
        reason: 'each tap is its own ImageNode pointing at the shared cache',
      );
    });
  });
}
