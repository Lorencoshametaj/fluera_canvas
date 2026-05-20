// Widget tests for the 0.11.0 FlueraCanvasToolbar Material 3 restyle.
//
// Covers the new interactive surfaces (pill tool buttons, restyled
// circular swatches, opacity slider). The pre-restyle tests in
// `toolbar_phase_e_test.dart` exercise the show* flag matrix and
// continue to apply — what we add here is behaviour specific to the
// new widgets (selected pill state, opacity-driven alpha, alpha-preserving
// swatch picking).

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget pump({
    required GlobalKey<FlueraCanvasState> canvasKey,
    required ValueChanged<CanvasTool> onTool,
    required ValueChanged<Color> onColor,
    required CanvasTool tool,
    required Color color,
    bool showOpacitySlider = true,
  }) {
    return MaterialApp(
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: Scaffold(
        body: Column(
          children: [
            SizedBox(
              height: 200,
              child: FlueraCanvas(
                key: canvasKey,
                tool: tool,
                strokeColor: color,
                strokeWidth: 2.5,
              ),
            ),
            FlueraCanvasToolbar(
              canvasKey: canvasKey,
              tool: tool,
              onToolChanged: onTool,
              color: color,
              onColorChanged: onColor,
              strokeWidth: 2.5,
              onStrokeWidthChanged: (_) {},
              showOpacitySlider: showOpacitySlider,
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('tapping a tool pill calls onToolChanged', (tester) async {
    final key = GlobalKey<FlueraCanvasState>();
    CanvasTool tool = CanvasTool.draw;
    Color color = const Color(0xFF1A1A1A);
    await tester.pumpWidget(
      pump(
        canvasKey: key,
        tool: tool,
        color: color,
        onTool: (t) => tool = t,
        onColor: (c) => color = c,
      ),
    );
    await tester.tap(find.byTooltip('Erase'));
    await tester.pump();
    expect(tool, CanvasTool.erase);
  });

  testWidgets('tapping a swatch preserves the alpha set by opacity slider', (
    tester,
  ) async {
    final key = GlobalKey<FlueraCanvasState>();
    CanvasTool tool = CanvasTool.draw;
    // Start with a half-transparent black — swatch tap should preserve
    // the 0.5 alpha when picking red.
    Color color = const Color(0x801A1A1A);
    await tester.pumpWidget(
      pump(
        canvasKey: key,
        tool: tool,
        color: color,
        onTool: (t) => tool = t,
        onColor: (c) => color = c,
      ),
    );
    // Default palette: index 1 is red (0xFFE53935). Tap it.
    await tester.tap(find.byTooltip('#E53935'));
    await tester.pump();
    // RGB switched to red, alpha preserved at ~0x80 (0.5).
    expect(color.r, closeTo(0xE5 / 255, 0.01));
    expect(color.g, closeTo(0x39 / 255, 0.01));
    expect(color.b, closeTo(0x35 / 255, 0.01));
    expect(color.a, closeTo(0.5, 0.01));
  });

  testWidgets('opacity slider is hidden while eraser tool is active', (
    tester,
  ) async {
    final key = GlobalKey<FlueraCanvasState>();
    CanvasTool tool = CanvasTool.erase;
    Color color = const Color(0xFF1A1A1A);
    await tester.pumpWidget(
      pump(
        canvasKey: key,
        tool: tool,
        color: color,
        onTool: (t) => tool = t,
        onColor: (c) => color = c,
      ),
    );
    // The opacity slider's tooltip identifies it uniquely.
    expect(find.byTooltip('Opacity 100%'), findsNothing);
  });

  testWidgets('opacity slider tooltip reflects current alpha', (tester) async {
    final key = GlobalKey<FlueraCanvasState>();
    CanvasTool tool = CanvasTool.draw;
    Color color = const Color(0x801A1A1A); // 50%
    await tester.pumpWidget(
      pump(
        canvasKey: key,
        tool: tool,
        color: color,
        onTool: (t) => tool = t,
        onColor: (c) => color = c,
      ),
    );
    expect(find.byTooltip('Opacity 50%'), findsOneWidget);
  });

  testWidgets('showOpacitySlider: false hides the slider entirely', (
    tester,
  ) async {
    final key = GlobalKey<FlueraCanvasState>();
    CanvasTool tool = CanvasTool.draw;
    Color color = const Color(0xFF1A1A1A);
    await tester.pumpWidget(
      pump(
        canvasKey: key,
        tool: tool,
        color: color,
        onTool: (t) => tool = t,
        onColor: (c) => color = c,
        showOpacitySlider: false,
      ),
    );
    expect(find.byTooltip('Opacity 100%'), findsNothing);
  });
}
