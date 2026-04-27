import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

void main() {
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

  TextNode makeText(String id, String body, {Offset position = Offset.zero}) =>
      TextNode(
        id: NodeId(id),
        textElement: DigitalTextElement(
          id: id,
          text: body,
          position: position,
          color: const Color(0xFF1A1A1A),
          fontSize: 18.0,
          createdAt: DateTime(2026, 4, 26),
        ),
      );

  group('FCV0 v6 — text persistence round-trip', () {
    testWidgets('addTextNode + toBytes + loadFromBytes preserves a TextNode', (
      tester,
    ) async {
      final keyA = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(keyA));
      final stateA = keyA.currentState!;
      stateA.addTextNode(
        makeText('hello', 'Hello canvas', position: const Offset(40, 60)),
      );

      final encoded = stateA.toBytes();

      final keyB = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(keyB, initial: encoded));
      await tester.pumpAndSettle();
      final stateB = keyB.currentState!;
      expect(stateB.debugSelectableIds, contains(const NodeId('hello')));
      final reloaded = stateB.findNode(const NodeId('hello')) as TextNode;
      expect(reloaded.textElement.text, 'Hello canvas');
      expect(reloaded.textElement.position.dx, closeTo(40, 1e-5));
      expect(reloaded.textElement.fontSize, closeTo(18.0, 1e-5));
    });

    testWidgets('round-trip preserves localTransform bit-for-bit', (
      tester,
    ) async {
      final keyA = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(keyA));
      final stateA = keyA.currentState!;
      final node = makeText('rotated', 'Tilted');
      node.localTransform = Matrix4.identity()..rotateZ(0.42);
      node.invalidateTransformCache();
      stateA.addTextNode(node);
      final original = node.localTransform.storage.toList();

      final encoded = stateA.toBytes();

      final keyB = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(keyB, initial: encoded));
      await tester.pumpAndSettle();
      final reloaded =
          keyB.currentState!.findNode(const NodeId('rotated')) as TextNode;
      for (int i = 0; i < 16; i++) {
        expect(
          reloaded.localTransform.storage[i],
          closeTo(original[i], 1e-5),
          reason: 'storage[$i] must round-trip within float32 precision',
        );
      }
    });

    testWidgets('updateTextElement is undoable + redoable', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.addTextNode(makeText('edit-me', 'before'));
      final next = (state.findNode(const NodeId('edit-me'))! as TextNode)
          .textElement
          .copyWith(text: 'after');
      state.updateTextElement(const NodeId('edit-me'), next);
      expect(
        (state.findNode(const NodeId('edit-me'))! as TextNode).textElement.text,
        'after',
      );
      expect(state.undo(), isTrue);
      expect(
        (state.findNode(const NodeId('edit-me'))! as TextNode).textElement.text,
        'before',
      );
      expect(state.redo(), isTrue);
      expect(
        (state.findNode(const NodeId('edit-me'))! as TextNode).textElement.text,
        'after',
      );
    });
  });
}
