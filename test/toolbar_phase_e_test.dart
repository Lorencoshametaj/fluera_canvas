import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget pump({
    required GlobalKey<FlueraCanvasState> canvasKey,
    bool showSelectionTool = false,
    bool showImageTool = false,
    bool showTransformActions = false,
    CanvasTool tool = CanvasTool.draw,
  }) {
    Color color = const Color(0xFF000000);
    double width = 2.5;
    var currentTool = tool;
    return MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              children: [
                SizedBox(
                  height: 300,
                  child: FlueraCanvas(
                    key: canvasKey,
                    tool: currentTool,
                    strokeColor: color,
                    strokeWidth: width,
                  ),
                ),
                FlueraCanvasToolbar(
                  canvasKey: canvasKey,
                  tool: currentTool,
                  onToolChanged: (t) => setState(() => currentTool = t),
                  color: color,
                  onColorChanged: (c) => setState(() => color = c),
                  strokeWidth: width,
                  onStrokeWidthChanged: (w) => setState(() => width = w),
                  showSelectionTool: showSelectionTool,
                  showImageTool: showImageTool,
                  showTransformActions: showTransformActions,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  group('FlueraCanvasToolbar showSelectionTool flag', () {
    testWidgets('default (false) hides the Select segment', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(canvasKey: key));
      expect(find.text('Select'), findsNothing);
    });

    testWidgets('true renders the Select segment in the segmented control',
        (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(canvasKey: key, showSelectionTool: true));
      expect(find.text('Select'), findsOneWidget);
    });
  });

  group('FlueraCanvasToolbar showImageTool flag', () {
    testWidgets('default (false) hides the image IconButton', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(canvasKey: key));
      expect(find.byIcon(Icons.image_rounded), findsNothing);
    });

    testWidgets('true renders the image trailing IconButton', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(canvasKey: key, showImageTool: true));
      expect(find.byIcon(Icons.image_rounded), findsOneWidget);
    });
  });

  group('FlueraCanvasToolbar showTransformActions flag', () {
    // We finder-by-tooltip rather than by-icon: Material's icon font has
    // some codepoint collisions in the test runtime (the row is hidden
    // but other widgets may legitimately surface the same glyph),
    // tooltips on the IconButtons we render are unique strings.

    testWidgets('hidden when selection is empty even with flag = true',
        (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(canvasKey: key, showTransformActions: true));
      expect(find.byTooltip('Mirror horizontally'), findsNothing);
      expect(find.byTooltip('Mirror vertically'), findsNothing);
      expect(find.byTooltip('Delete selection'), findsNothing);
      expect(find.byTooltip('Clear selection'), findsNothing);
    });

    testWidgets('appears when selection is non-empty', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(canvasKey: key, showTransformActions: true));
      final state = key.currentState!;
      state.pushStroke(CanvasStroke(
        points: List.unmodifiable(const [Offset(0, 0), Offset(10, 10)]),
        pressures: const [0.5, 0.7],
        color: const Color(0xFF000000),
        baseWidth: 2.0,
      ));
      state.selectInRect(const Rect.fromLTWH(-100, -100, 1000, 1000));
      await tester.pump();
      expect(find.byTooltip('Mirror horizontally'), findsOneWidget);
      expect(find.byTooltip('Mirror vertically'), findsOneWidget);
      expect(find.byTooltip('Delete selection'), findsOneWidget);
      expect(find.byTooltip('Clear selection'), findsOneWidget);
    });

    testWidgets('mirror-H tap mirrors selection + history grows by 1',
        (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(canvasKey: key, showTransformActions: true));
      final state = key.currentState!;
      state.pushStroke(CanvasStroke(
        points: List.unmodifiable(const [Offset(0, 0), Offset(10, 10)]),
        pressures: const [0.5, 0.7],
        color: const Color(0xFF000000),
        baseWidth: 2.0,
      ));
      state.selectInRect(const Rect.fromLTWH(-100, -100, 1000, 1000));
      await tester.pump();
      final beforeHistory = state.historyLength;
      await tester.tap(find.byTooltip('Mirror horizontally'));
      await tester.pump();
      expect(state.historyLength, beforeHistory + 1);
    });

    testWidgets('clear-selection tap empties the selection', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(canvasKey: key, showTransformActions: true));
      final state = key.currentState!;
      state.pushStroke(CanvasStroke(
        points: List.unmodifiable(const [Offset(0, 0), Offset(10, 10)]),
        pressures: const [0.5, 0.7],
        color: const Color(0xFF000000),
        baseWidth: 2.0,
      ));
      state.selectInRect(const Rect.fromLTWH(-100, -100, 1000, 1000));
      await tester.pump();
      expect(state.selection.isNotEmpty, isTrue);
      await tester.tap(find.byTooltip('Clear selection'));
      await tester.pump();
      expect(state.selection.isEmpty, isTrue);
    });
  });
}
