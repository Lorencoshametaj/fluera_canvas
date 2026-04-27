import 'dart:ui' show Color, Offset;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget pump(GlobalKey<FlueraCanvasState> key) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 600,
        height: 400,
        child: FlueraCanvas(
          key: key,
          tool: CanvasTool.text,
          strokeColor: const Color(0xFF1A1A1A),
          strokeWidth: 2.0,
        ),
      ),
    ),
  );

  group('FlueraTextEditor', () {
    testWidgets(
      'start on a fresh world position commits a new TextNode after typing',
      (tester) async {
        final key = GlobalKey<FlueraCanvasState>();
        await tester.pumpWidget(pump(key));
        final state = key.currentState!;
        expect(FlueraTextEditor.isEditing, isFalse);

        FlueraTextEditor.start(state, worldPosition: const Offset(40, 60));
        await tester.pumpAndSettle();
        expect(FlueraTextEditor.isEditing, isTrue);
        // The fresh empty TextNode is on the layer immediately so the
        // overlay can position itself; the editor session is what
        // tracks the rollback.
        final textNodes =
            state.activeLayer.children.whereType<TextNode>().toList();
        expect(textNodes, hasLength(1));

        // Type into the live overlay.
        await tester.enterText(find.byType(TextField), 'Hello');
        await tester.pumpAndSettle();

        FlueraTextEditor.commit(state);
        await tester.pumpAndSettle();
        expect(FlueraTextEditor.isEditing, isFalse);
        final after = state.activeLayer.children.whereType<TextNode>().toList();
        expect(after, hasLength(1));
        expect(after.single.textElement.text, 'Hello');
      },
    );

    testWidgets(
      'cancel on a fresh empty node drops it without touching history',
      (tester) async {
        final key = GlobalKey<FlueraCanvasState>();
        await tester.pumpWidget(pump(key));
        final state = key.currentState!;
        // Leave a sentinel op on the undo stack — we want to verify
        // cancel doesn't clobber it.
        state.pushStroke(
          CanvasStroke(
            points: List<Offset>.unmodifiable([
              const Offset(0, 0),
              const Offset(10, 10),
            ]),
            pressures: const [0.5, 0.7],
            color: const Color(0xFF000000),
            baseWidth: 2.0,
          ),
        );
        expect(state.canUndo, isTrue);

        FlueraTextEditor.start(state, worldPosition: const Offset(40, 60));
        await tester.pumpAndSettle();
        // No typing.
        FlueraTextEditor.cancel(state);
        await tester.pumpAndSettle();

        // Sentinel stroke must still be reachable via undo.
        expect(
          state.activeLayer.children.whereType<TextNode>(),
          isEmpty,
          reason: 'fresh empty node should be removed on cancel',
        );
        expect(state.strokes, hasLength(1));
        expect(
          state.canUndo,
          isTrue,
          reason: 'cancel must not pop the sentinel stroke off the stack',
        );
      },
    );

    testWidgets('start on an existing TextNode opens the editor on it', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      final node = TextNode(
        id: const NodeId('hello-node'),
        textElement: DigitalTextElement(
          id: 'hello-node',
          text: 'before',
          position: const Offset(20, 20),
          color: const Color(0xFF000000),
          createdAt: DateTime(2026, 4, 26),
        ),
      );
      state.addTextNode(node);

      FlueraTextEditor.start(state, existing: const NodeId('hello-node'));
      await tester.pumpAndSettle();
      expect(FlueraTextEditor.isEditing, isTrue);

      await tester.enterText(find.byType(TextField), 'after');
      FlueraTextEditor.commit(state);
      await tester.pumpAndSettle();

      final reloaded = state.findNode(const NodeId('hello-node'))! as TextNode;
      expect(reloaded.textElement.text, 'after');
    });
  });
}
