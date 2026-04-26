import 'dart:typed_data' show Uint8List;
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
      );

  Widget pump(GlobalKey<FlueraCanvasState> key, {Uint8List? bytes}) =>
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: FlueraCanvas(key: key, initialBytes: bytes),
          ),
        ),
      );

  group('FlueraCanvasState selectable-nodes index', () {
    testWidgets('initial state contains zero selectable nodes',
        (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      expect(state.debugSelectableIds, isEmpty);
      expect(state.debugZOrderIndex, isEmpty);
    });

    testWidgets('pushStroke + addImageNode register both in the index',
        (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;

      state.pushStroke(makeStroke(1));
      final img = makeImage('img-1');
      state.addImageNode(img);

      expect(state.debugSelectableIds, hasLength(2));
      expect(state.debugSelectableIds, contains(img.id));
      // Stroke node id is auto-generated; we just check that exactly
      // one non-image entry exists.
      final nonImageIds = state.debugSelectableIds.toSet()..remove(img.id);
      expect(nonImageIds, hasLength(1));
    });

    testWidgets('Z-order: image inserted after stroke wins front-most',
        (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;

      state.pushStroke(makeStroke(1));
      final strokeId = state.debugSelectableIds.single;
      final img = makeImage('img-late');
      state.addImageNode(img);

      final z = state.debugZOrderIndex;
      expect(z[img.id]! > z[strokeId]!, isTrue,
          reason: 'image inserted later must have higher Z than stroke');
    });

    testWidgets('clear() unregisters all stroke nodes', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;

      state.pushStrokes([makeStroke(1), makeStroke(2), makeStroke(3)]);
      expect(state.debugSelectableIds, hasLength(3));
      state.clear();
      expect(state.debugSelectableIds, isEmpty,
          reason: 'clear() drops every stroke from the selectable index');
    });

    testWidgets(
        'undo of stroke commit removes the node from the selectable index',
        (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;

      state.pushStroke(makeStroke(1));
      expect(state.debugSelectableIds, hasLength(1));

      expect(state.undo(), isTrue);
      expect(state.debugSelectableIds, isEmpty);

      expect(state.redo(), isTrue);
      expect(state.debugSelectableIds, hasLength(1));
    });

    testWidgets('addImageNode + undo removes image from index',
        (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      final img = makeImage('img-undo');
      state.addImageNode(img);
      expect(state.debugSelectableIds, contains(img.id));

      expect(state.undo(), isTrue);
      expect(state.debugSelectableIds, isNot(contains(img.id)));

      expect(state.redo(), isTrue);
      expect(state.debugSelectableIds, contains(img.id));
    });

    testWidgets('removeLayer also drops every contained node',
        (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      // Default Layer 1 is active. Add a stroke + image to it.
      state.pushStroke(makeStroke(1));
      final img = makeImage('img-on-default');
      state.addImageNode(img);
      // Add a second layer so removeLayer is allowed (last layer is
      // preserved by `removeLayer`'s contract).
      final l2 = state.addLayer(name: 'Top');
      state.setActiveLayer(l2.id);
      state.pushStroke(makeStroke(2));
      // Now drop the original (default) layer entirely.
      final defaultLayerId = state.layers.first.id;
      expect(state.removeLayer(defaultLayerId), isTrue);

      expect(state.debugSelectableIds, isNot(contains(img.id)),
          reason: 'image on the dropped layer must be unregistered');
      // Only the lone stroke on l2 remains.
      expect(state.debugSelectableIds, hasLength(1));
    });

    testWidgets('loadFromBytes (FCV0) rebuilds the index', (tester) async {
      // Save a 2-stroke canvas, then reload it in a fresh canvas and
      // assert the index reflects the loaded state.
      final saveKey = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(saveKey));
      final saveState = saveKey.currentState!;
      saveState.pushStrokes([makeStroke(1), makeStroke(2)]);
      final bytes = saveState.toBytes();

      final loadKey = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(loadKey, bytes: bytes));
      final loadState = loadKey.currentState!;
      expect(loadState.debugSelectableIds, hasLength(2),
          reason: 'serializer round-trip must repopulate the index');
    });
  });
}
