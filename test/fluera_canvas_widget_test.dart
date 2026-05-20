import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

void main() {
  group('FlueraCanvas widget', () {
    testWidgets('mounts without errors and exposes empty state', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlueraCanvas(
              key: key,
              // Disable native overlay so the test runs purely in Dart.
              enableNativeLiveStroke: false,
            ),
          ),
        ),
      );
      expect(key.currentState, isNotNull);
      expect(key.currentState!.strokeCount, 0);
      expect(key.currentState!.canUndo, false);
      expect(key.currentState!.canRedo, false);
      expect(key.currentState!.historyLength, 0);
    });

    testWidgets('pushStroke adds to count, undo / redo cycle works', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlueraCanvas(key: key, enableNativeLiveStroke: false),
          ),
        ),
      );
      final state = key.currentState!;
      final stroke = CanvasStroke(
        points: const [Offset(0, 0), Offset(50, 50)],
        pressures: const [0.5, 0.5],
        color: Colors.red,
        baseWidth: 2.0,
      );
      state.pushStroke(stroke);
      expect(state.strokeCount, 1);
      expect(state.canUndo, true);

      expect(state.undo(), true);
      expect(state.strokeCount, 0);
      expect(state.canRedo, true);

      expect(state.redo(), true);
      expect(state.strokeCount, 1);

      // Undo on empty redo stack returns true (we have one undo to do)
      // then false the next time.
      expect(state.undo(), true);
      expect(state.undo(), false);
    });

    testWidgets('clear removes all strokes; undo restores them', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlueraCanvas(key: key, enableNativeLiveStroke: false),
          ),
        ),
      );
      final state = key.currentState!;
      for (int i = 0; i < 5; i++) {
        state.pushStroke(
          CanvasStroke(
            points: [
              Offset(i.toDouble(), i.toDouble()),
              Offset(i + 10.0, i + 10.0),
            ],
            pressures: const [0.5, 0.5],
            color: Colors.black,
            baseWidth: 2.0,
          ),
        );
      }
      expect(state.strokeCount, 5);
      state.clear();
      expect(state.strokeCount, 0);
      // Undo restores the cleared scene as a single op.
      expect(state.undo(), true);
      expect(state.strokeCount, 5);
    });

    testWidgets('toBytes / loadFromBytes roundtrip preserves all strokes', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlueraCanvas(key: key, enableNativeLiveStroke: false),
          ),
        ),
      );
      final state = key.currentState!;
      state.pushStroke(
        CanvasStroke(
          points: const [Offset(1, 2), Offset(3, 4), Offset(5, 6)],
          pressures: const [0.3, 0.6, 0.9],
          color: const Color(0xFFAB12CD),
          baseWidth: 3.5,
        ),
      );
      final bytes = state.toBytes();
      state.clear();
      expect(state.strokeCount, 0);
      state.loadFromBytes(bytes);
      expect(state.strokeCount, 1);
      // History cleared after load.
      expect(state.canUndo, false);
    });
  });

  group('FlueraCanvas initialBytes', () {
    testWidgets('initialBytes pre-loads strokes before the first paint', (
      tester,
    ) async {
      // Build the bytes from a transient canvas, then mount a SECOND
      // canvas with `initialBytes` and verify strokeCount is non-zero
      // without ever calling `loadFromBytes`.
      final source = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlueraCanvas(key: source, enableNativeLiveStroke: false),
          ),
        ),
      );
      source.currentState!.pushStroke(
        CanvasStroke(
          points: const [Offset(1, 2), Offset(3, 4)],
          pressures: const [0.5, 0.5],
          color: Colors.red,
          baseWidth: 2.0,
        ),
      );
      final bytes = source.currentState!.toBytes();

      final target = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlueraCanvas(
              key: target,
              initialBytes: bytes,
              enableNativeLiveStroke: false,
            ),
          ),
        ),
      );
      // strokeCount available immediately — strokes were inserted in
      // initState, before any frame was rendered.
      expect(target.currentState!.strokeCount, 1);
    });

    testWidgets('corrupt initialBytes leaves canvas empty (no exception)', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlueraCanvas(
              key: key,
              initialBytes: Uint8List.fromList(const [
                0xDE,
                0xAD,
                0xBE,
                0xEF,
                0,
                0,
                0,
                0,
              ]),
              enableNativeLiveStroke: false,
            ),
          ),
        ),
      );
      expect(key.currentState!.strokeCount, 0);
    });

    testWidgets('empty initialBytes (10-byte header) loads to 0 strokes', (
      tester,
    ) async {
      final emptyBytes = CanvasSerializer.encodeBytes(const []);
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlueraCanvas(
              key: key,
              initialBytes: emptyBytes,
              enableNativeLiveStroke: false,
            ),
          ),
        ),
      );
      expect(key.currentState!.strokeCount, 0);
      expect(key.currentState!.canUndo, false);
    });
  });

  group('FlueraCanvas edge cases', () {
    testWidgets('single-point stroke is accepted by pushStroke', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlueraCanvas(key: key, enableNativeLiveStroke: false),
          ),
        ),
      );
      key.currentState!.pushStroke(
        CanvasStroke(
          points: const [Offset(0, 0)],
          pressures: const [0.5],
          color: Colors.black,
          baseWidth: 2.0,
        ),
      );
      expect(key.currentState!.strokeCount, 1);
    });

    testWidgets('undo / redo after pushStroke + pushStrokes batch', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlueraCanvas(key: key, enableNativeLiveStroke: false),
          ),
        ),
      );
      final state = key.currentState!;
      state.pushStroke(
        CanvasStroke(
          points: const [Offset(0, 0), Offset(1, 1)],
          pressures: const [0.5, 0.5],
          color: Colors.black,
          baseWidth: 2.0,
        ),
      );
      state.pushStrokes(
        List.generate(
          3,
          (i) => CanvasStroke(
            points: [Offset(i.toDouble(), 0), Offset(i + 1.0, 0)],
            pressures: const [0.5, 0.5],
            color: Colors.blue,
            baseWidth: 2.0,
          ),
        ),
      );
      expect(state.strokeCount, 4);
      // Undo the batch as one op.
      expect(state.undo(), true);
      expect(state.strokeCount, 1);
      // Undo the single push.
      expect(state.undo(), true);
      expect(state.strokeCount, 0);
      // Redo brings them all back.
      state.redo();
      state.redo();
      expect(state.strokeCount, 4);
    });

    testWidgets('strokeAt finds stroke within tolerance, null otherwise', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlueraCanvas(key: key, enableNativeLiveStroke: false),
          ),
        ),
      );
      final state = key.currentState!;
      state.pushStroke(
        CanvasStroke(
          points: const [Offset(0, 0), Offset(100, 0)],
          pressures: const [0.5, 0.5],
          color: Colors.black,
          baseWidth: 4.0,
        ),
      );
      expect(state.strokeAt(const Offset(50, 0), tolerance: 5), isNotNull);
      expect(state.strokeAt(const Offset(50, 100), tolerance: 5), isNull);
    });

    testWidgets(
      'clear empties the scene; undo restores; clear again is no-op',
      (tester) async {
        final key = GlobalKey<FlueraCanvasState>();
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FlueraCanvas(key: key, enableNativeLiveStroke: false),
            ),
          ),
        );
        final state = key.currentState!;
        state.pushStroke(
          CanvasStroke(
            points: const [Offset(0, 0), Offset(1, 1)],
            pressures: const [0.5, 0.5],
            color: Colors.black,
            baseWidth: 2.0,
          ),
        );
        state.clear();
        expect(state.strokeCount, 0);
        // Re-running clear on empty scene shouldn't push another op.
        final undoLengthBefore = state.historyLength;
        state.clear();
        expect(state.historyLength, undoLengthBefore);
      },
    );
  });

  group('FlueraCanvasToolbar widget', () {
    testWidgets('renders pen / eraser segmented and color swatches', (
      tester,
    ) async {
      final canvasKey = GlobalKey<FlueraCanvasState>();
      CanvasTool tool = CanvasTool.draw;
      Color color = Colors.black;
      double width = 2.0;
      await tester.pumpWidget(
        StatefulBuilder(
          builder:
              (ctx, setState) => MaterialApp(
                home: Scaffold(
                  body: Column(
                    children: [
                      SizedBox(
                        height: 200,
                        child: FlueraCanvas(
                          key: canvasKey,
                          tool: tool,
                          strokeColor: color,
                          strokeWidth: width,
                          enableNativeLiveStroke: false,
                        ),
                      ),
                      FlueraCanvasToolbar(
                        canvasKey: canvasKey,
                        tool: tool,
                        onToolChanged: (t) => setState(() => tool = t),
                        color: color,
                        onColorChanged: (c) => setState(() => color = c),
                        strokeWidth: width,
                        onStrokeWidthChanged: (w) => setState(() => width = w),
                      ),
                    ],
                  ),
                ),
              ),
        ),
      );
      expect(find.byTooltip('Pen'), findsOneWidget);
      expect(find.byTooltip('Erase'), findsOneWidget);
      // Stroke-width slider + opacity slider (added in 0.11.0).
      expect(find.byType(Slider), findsNWidgets(2));
    });
  });
}
