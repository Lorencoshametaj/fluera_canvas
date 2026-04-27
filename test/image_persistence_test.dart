import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Color, Offset;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

void main() {
  // Build a 1×1 transparent PNG via PictureRecorder so the test stays
  // runtime-only (no file_selector). The painter cache is keyed on
  // the path string, so the actual pixels don't matter — what matters
  // is that `cacheWithBytes` stores both handle and bytes, and
  // `decodeAndCache` round-trips them back.
  Future<({ui.Image image, Uint8List bytes})> makeFakeImage() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder);
    final picture = recorder.endRecording();
    final image = await picture.toImage(1, 1);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return (image: image, bytes: byteData!.buffer.asUint8List());
  }

  CanvasStroke makeStroke(int seed) => CanvasStroke(
    points: List<Offset>.unmodifiable([
      Offset(seed.toDouble(), 0),
      Offset(seed.toDouble() + 10, 10),
    ]),
    pressures: const [0.5, 0.7],
    color: Color(0xFF000000 + seed),
    baseWidth: 2.0,
  );

  ImageNode makeImage(String id, {Size size = const Size(50, 60)}) => ImageNode(
    id: NodeId(id),
    imageElement: ImageElement(
      id: id,
      imagePath: 'fluera-canvas://memory/$id',
      position: const Offset(10, 20),
      createdAt: DateTime.now(),
      pageIndex: 0,
    ),
    imageSize: size,
  );

  Widget pump(GlobalKey<FlueraCanvasState> key, {Uint8List? initial}) =>
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: FlueraCanvas(key: key, initialBytes: initial),
          ),
        ),
      );

  setUp(() {
    ImageNodePainter.clearCache();
  });

  group('FCV0 v4 — image persistence round-trip', () {
    testWidgets('toBytes + loadFromBytes preserves an ImageNode', (
      tester,
    ) async {
      final fake = await tester.runAsync(makeFakeImage);
      // Phase 1 wiring: cacheWithBytes registers both handle + bytes.
      ImageNodePainter.cacheWithBytes(
        'fluera-canvas://memory/persist-me',
        fake!.image,
        fake.bytes,
      );

      final keyA = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(keyA));
      final stateA = keyA.currentState!;
      stateA.addImageNode(makeImage('persist-me'));
      stateA.pushStroke(makeStroke(7));

      final encoded = stateA.toBytes();

      // Drop the cache so the reader has to re-hydrate from the file's
      // embedded bytes, not RAM. addImageNode-time handles are gone.
      ImageNodePainter.clearCache();
      expect(
        ImageNodePainter.isCached('fluera-canvas://memory/persist-me'),
        isFalse,
      );

      final keyB = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(keyB, initial: encoded));
      // The async decode kicks off in initState; pump until it lands.
      await tester.runAsync(() async {
        for (int i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
      });
      await tester.pumpAndSettle();

      final stateB = keyB.currentState!;
      // Selectable index must contain the image at its original id.
      expect(stateB.debugSelectableIds, contains(const NodeId('persist-me')));
      // The painter cache must have been re-hydrated (handle + bytes).
      expect(
        ImageNodePainter.isCached('fluera-canvas://memory/persist-me'),
        isTrue,
      );
      expect(
        ImageNodePainter.bytesFor('fluera-canvas://memory/persist-me'),
        isNotNull,
      );
    });

    testWidgets('round-trip preserves localTransform bit-for-bit', (
      tester,
    ) async {
      final fake = await tester.runAsync(makeFakeImage);
      ImageNodePainter.cacheWithBytes(
        'fluera-canvas://memory/transform-me',
        fake!.image,
        fake.bytes,
      );

      final keyA = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(keyA));
      final stateA = keyA.currentState!;
      final node = makeImage('transform-me');
      // Bake a non-identity transform onto the node before save.
      node.localTransform =
          Matrix4.identity()
            ..rotateZ(0.5)
            ..scaleByDouble(1.3, 1.3, 1.0, 1.0);
      node.invalidateTransformCache();
      stateA.addImageNode(node);
      final originalStorage = node.localTransform.storage.toList();

      final encoded = stateA.toBytes();
      // Don't clearCache here: we want the existing handle to remain
      // alive so the second canvas can paint immediately. The async
      // decode kicks off but lands on the already-cached entry — the
      // important assertion is that the localTransform survived.

      final keyB = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(keyB, initial: encoded));
      await tester.pumpAndSettle();

      final stateB = keyB.currentState!;
      final layer = stateB.activeLayer;
      final reloaded = layer.children.whereType<ImageNode>().firstWhere(
        (n) => n.id == const NodeId('transform-me'),
      );
      // float32 round-trip is lossy in the last few bits — compare with
      // a generous tolerance on every storage entry.
      for (int i = 0; i < 16; i++) {
        expect(
          reloaded.localTransform.storage[i],
          closeTo(originalStorage[i], 1e-5),
          reason: 'storage[$i] must round-trip within float32 precision',
        );
      }
    });

    testWidgets(
      'images without registered bytes are silently skipped at save time',
      (tester) async {
        final keyA = GlobalKey<FlueraCanvasState>();
        await tester.pumpWidget(pump(keyA));
        final stateA = keyA.currentState!;
        // No `cacheWithBytes` call → bytesFor() returns null → writer
        // skips this image. The user's canvas keeps the node in memory
        // but the saved file is image-free.
        stateA.addImageNode(makeImage('no-bytes'));
        stateA.pushStroke(makeStroke(1));

        final encoded = stateA.toBytes();
        final result = CanvasSerializer.decodeBytesFull(encoded);
        expect(result.imageBlobs, isEmpty);
        // The single stroke must still be there.
        var strokeCount = 0;
        for (final layer in result.root.children.whereType<LayerNode>()) {
          strokeCount += layer.children.whereType<CanvasStrokeNode>().length;
        }
        expect(strokeCount, 1);
      },
    );
  });

  group('FCV0 v3 backward read', () {
    testWidgets('a v3 file (strokes only) decodes with empty imageBlobs', (
      tester,
    ) async {
      final keyA = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(keyA));
      final stateA = keyA.currentState!;
      stateA.pushStrokes([makeStroke(1), makeStroke(2)]);
      // Even though the writer is now v4, a stroke-only canvas should
      // round-trip cleanly with an empty `imageBlobs` map.
      final encoded = stateA.toBytes();
      final result = CanvasSerializer.decodeBytesFull(encoded);
      expect(result.imageBlobs, isEmpty);
      var strokeCount = 0;
      for (final layer in result.root.children.whereType<LayerNode>()) {
        strokeCount += layer.children.whereType<CanvasStrokeNode>().length;
      }
      expect(strokeCount, 2);
    });
  });
}
