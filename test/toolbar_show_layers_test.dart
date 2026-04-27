import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget pump({
    required GlobalKey<FlueraCanvasState> canvasKey,
    required bool showLayers,
    String? title,
  }) {
    CanvasTool tool = CanvasTool.draw;
    Color color = const Color(0xFF000000);
    double width = 2.5;
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
                    tool: tool,
                    strokeColor: color,
                    strokeWidth: width,
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
                  showLayers: showLayers,
                  layersBottomSheetTitle: title,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  group('FlueraCanvasToolbar showLayers flag', () {
    testWidgets('default (false) hides the layers IconButton', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(canvasKey: key, showLayers: false));
      expect(find.byIcon(Icons.layers_rounded), findsNothing);
    });

    testWidgets('true renders the trailing layers IconButton', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(canvasKey: key, showLayers: true));
      expect(find.byIcon(Icons.layers_rounded), findsOneWidget);
    });

    testWidgets('tap opens FlueraLayerPanel in a bottom sheet with default '
        '"Layers" title', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(canvasKey: key, showLayers: true));
      await tester.tap(find.byIcon(Icons.layers_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(FlueraLayerPanel), findsOneWidget);
      expect(find.text('Layers'), findsWidgets);
    });

    testWidgets('layersBottomSheetTitle override is honoured', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(
        pump(canvasKey: key, showLayers: true, title: 'My layers'),
      );
      await tester.tap(find.byIcon(Icons.layers_rounded));
      await tester.pumpAndSettle();
      expect(find.text('My layers'), findsWidgets);
    });
  });
}
