/// Coverage for the zero-config drop-in widgets introduced in 0.10.0:
/// `FlueraSketch`, `FlueraSketchScaffold`, `FlueraSketchApp` and the
/// shared `FlueraSketchPreset` enum.
library;

import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlueraSketch', () {
    testWidgets('builds a FlueraCanvas + FlueraCanvasToolbar (default '
        'whiteboard preset)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SizedBox(width: 800, height: 600,
              child: FlueraSketch())),
        ),
      );
      expect(find.byType(FlueraCanvas), findsOneWidget);
      expect(find.byType(FlueraCanvasToolbar), findsOneWidget);
    });

    testWidgets('whiteboard preset enables text + sticker + layers + '
        'shape segments', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SizedBox(width: 800, height: 600,
              child: FlueraSketch(preset: FlueraSketchPreset.whiteboard))),
        ),
      );
      final tb = tester.widget<FlueraCanvasToolbar>(
        find.byType(FlueraCanvasToolbar),
      );
      expect(tb.showShapeTools, isTrue);
      expect(tb.showLassoTool, isTrue);
      expect(tb.showTextTool, isTrue);
      expect(tb.showStickerPanel, isTrue);
      expect(tb.showLayers, isTrue);
      expect(tb.showImageTool, isTrue);
    });

    testWidgets('notes preset hides shape / lasso / sticker / layers', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SizedBox(width: 800, height: 600,
              child: FlueraSketch(preset: FlueraSketchPreset.notes))),
        ),
      );
      final tb = tester.widget<FlueraCanvasToolbar>(
        find.byType(FlueraCanvasToolbar),
      );
      expect(tb.showShapeTools, isFalse);
      expect(tb.showLassoTool, isFalse);
      expect(tb.showStickerPanel, isFalse);
      expect(tb.showLayers, isFalse);
      // Text + pixel-eraser + color picker still on for notes apps.
      expect(tb.showTextTool, isTrue);
      expect(tb.showPixelEraser, isTrue);
      expect(tb.showColorPickerButton, isTrue);
    });

    testWidgets('signature preset is the most minimal', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SizedBox(width: 800, height: 600,
              child: FlueraSketch(preset: FlueraSketchPreset.signature))),
        ),
      );
      final tb = tester.widget<FlueraCanvasToolbar>(
        find.byType(FlueraCanvasToolbar),
      );
      expect(tb.showShapeTools, isFalse);
      expect(tb.showLassoTool, isFalse);
      expect(tb.showTextTool, isFalse);
      expect(tb.showStickerPanel, isFalse);
      expect(tb.showLayers, isFalse);
      expect(tb.showImageTool, isFalse);
      expect(tb.showPixelEraser, isFalse);
    });

    testWidgets('caller-supplied canvasKey is honoured', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SizedBox(width: 800, height: 600,
              child: FlueraSketch(canvasKey: key))),
        ),
      );
      expect(key.currentState, isNotNull);
      key.currentState!.pushStroke(
        CanvasStroke(
          points: const [Offset(0, 0), Offset(10, 10)],
          pressures: const [1.0, 1.0],
          color: const Color(0xFF000000),
          baseWidth: 2,
        ),
      );
      expect(key.currentState!.strokes, hasLength(1));
    });
  });

  group('FlueraSketchScaffold', () {
    testWidgets('shows AppBar with undo / redo / clear / export', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: FlueraSketchScaffold()),
      );
      // After the bootstrap future resolves the spinner disappears.
      await tester.pumpAndSettle();
      // The toolbar lower in the tree may also expose undo / redo /
      // clear glyphs, so we just assert the AppBar set is *present*.
      expect(find.byIcon(Icons.undo_rounded), findsAtLeastNWidgets(1));
      expect(find.byIcon(Icons.redo_rounded), findsAtLeastNWidgets(1));
      expect(find.byIcon(Icons.clear_all_rounded), findsAtLeastNWidgets(1));
      expect(find.byIcon(Icons.save_alt_rounded), findsOneWidget);
    });

    testWidgets('onAutoLoad is invoked at startup and bytes feed the canvas',
        (tester) async {
      var loadCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: FlueraSketchScaffold(
            onAutoLoad: () async {
              loadCalls += 1;
              return null; // empty restore
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(loadCalls, 1);
      expect(find.byType(FlueraCanvas), findsOneWidget);
    });

    testWidgets('onAutoSave fires after a mutation past autoSaveDebounce',
        (tester) async {
      Uint8List? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: FlueraSketchScaffold(
            autoSaveDebounce: const Duration(milliseconds: 50),
            onAutoSave: (bytes) async {
              saved = bytes;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      // Mutate via the public state hidden inside the scaffold.
      final state =
          tester.state(find.byType(FlueraCanvas)) as FlueraCanvasState;
      state.pushStroke(
        CanvasStroke(
          points: const [Offset(0, 0), Offset(20, 20)],
          pressures: const [1.0, 1.0],
          color: const Color(0xFFFF0000),
          baseWidth: 3,
        ),
      );
      // Wait for the debounce to elapse.
      await tester.pump(const Duration(milliseconds: 80));
      // Microtask flush.
      await tester.pump();
      expect(saved, isNotNull);
      expect(saved!.lengthInBytes, greaterThan(0));
    });
  });

  group('FlueraSketchApp', () {
    testWidgets('mounts a MaterialApp wrapping a FlueraSketchScaffold', (
      tester,
    ) async {
      await tester.pumpWidget(const FlueraSketchApp());
      await tester.pumpAndSettle();
      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.byType(FlueraSketchScaffold), findsOneWidget);
      expect(find.byType(FlueraCanvas), findsOneWidget);
    });
  });
}
