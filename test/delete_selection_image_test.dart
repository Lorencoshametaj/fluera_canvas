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

  Widget pump(
    GlobalKey<FlueraCanvasState> key, {
    void Function(List<CanvasNode>)? onNodesDeleted,
    void Function(List<CanvasStroke>)? onStrokesErased,
  }) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 600,
        height: 400,
        child: FlueraCanvas(
          key: key,
          onNodesDeleted: onNodesDeleted,
          onStrokesErased: onStrokesErased,
        ),
      ),
    ),
  );

  group('deleteSelection on stroke + image mix', () {
    testWidgets('removes both kinds of nodes from the canvas', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStroke(makeStroke(1));
      state.addImageNode(makeImage('i1'));
      state.selectInRect(const Rect.fromLTRB(-100, -100, 1000, 1000));
      expect(state.selection.length, 2);

      final removed = state.deleteSelection();
      expect(removed, 2);
      expect(state.strokeCount, 0);
      expect(state.activeLayer.children.whereType<ImageNode>().length, 0);
      expect(state.debugSelectableIds, isEmpty);
      expect(state.selection.isEmpty, isTrue);
    });

    testWidgets('undo restores both stroke and image at original Z-order', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStroke(makeStroke(1));
      state.pushStroke(makeStroke(2));
      state.addImageNode(makeImage('i1'));
      // Capture pre-delete state.
      final preIds = state.debugSelectableIds;
      expect(preIds.length, 3);

      state.selectInRect(const Rect.fromLTRB(-100, -100, 1000, 1000));
      state.deleteSelection();
      expect(state.debugSelectableIds, isEmpty);

      expect(state.undo(), isTrue);
      expect(state.debugSelectableIds.length, 3);
      // Same id set restored.
      expect(state.debugSelectableIds, preIds);
    });

    testWidgets('redo re-applies the deletion', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStroke(makeStroke(1));
      state.addImageNode(makeImage('i1'));
      state.selectInRect(const Rect.fromLTRB(-100, -100, 1000, 1000));
      state.deleteSelection();
      state.undo();
      expect(state.debugSelectableIds.length, 2);
      state.redo();
      expect(state.debugSelectableIds, isEmpty);
    });

    testWidgets('onNodesDeleted callback fires with every removed node', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      List<CanvasNode>? lastCb;
      await tester.pumpWidget(
        pump(key, onNodesDeleted: (nodes) => lastCb = nodes),
      );
      final state = key.currentState!;
      state.pushStroke(makeStroke(1));
      state.addImageNode(makeImage('i1'));
      state.selectInRect(const Rect.fromLTRB(-100, -100, 1000, 1000));
      state.deleteSelection();
      expect(lastCb, isNotNull);
      expect(lastCb!, hasLength(2));
    });

    testWidgets(
      'onStrokesErased still fires (backward-compat) with stroke subset',
      (tester) async {
        final key = GlobalKey<FlueraCanvasState>();
        List<CanvasStroke>? lastCb;
        await tester.pumpWidget(
          pump(key, onStrokesErased: (strokes) => lastCb = strokes),
        );
        final state = key.currentState!;
        state.pushStroke(makeStroke(1));
        state.addImageNode(makeImage('i1'));
        state.selectInRect(const Rect.fromLTRB(-100, -100, 1000, 1000));
        state.deleteSelection();
        expect(lastCb, isNotNull);
        expect(
          lastCb!,
          hasLength(1),
          reason: 'onStrokesErased gets the stroke-only subset',
        );
      },
    );

    testWidgets('image-only deleteSelection skips onStrokesErased', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      List<CanvasStroke>? lastCb;
      await tester.pumpWidget(
        pump(key, onStrokesErased: (strokes) => lastCb = strokes),
      );
      final state = key.currentState!;
      state.addImageNode(makeImage('i1'));
      state.selectInRect(const Rect.fromLTRB(-100, -100, 1000, 1000));
      state.deleteSelection();
      expect(
        lastCb,
        isNull,
        reason: 'no strokes were erased — callback must not fire',
      );
    });
  });
}
