// Tests for the 0.16.1 FlueraCanvasCupertinoToolbar.
// Mirrors the Material toolbar tests' structure but asserts Cupertino
// widget tree presence + same callback contract.

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget _wrap({
    required GlobalKey<FlueraCanvasState> canvasKey,
    required ValueChanged<CanvasTool> onTool,
    required ValueChanged<Color> onColor,
    required CanvasTool tool,
    required Color color,
    double? viewportWidth,
  }) {
    final toolbar = FlueraCanvasCupertinoToolbar(
      canvasKey: canvasKey,
      tool: tool,
      onToolChanged: onTool,
      color: color,
      onColorChanged: onColor,
      strokeWidth: 2.5,
      onStrokeWidthChanged: (_) {},
    );
    // Mounted under a CupertinoApp — that's the consumer's typical
    // wrapper when targeting iOS / macOS-only.
    return CupertinoApp(
      home: CupertinoPageScaffold(
        child: SafeArea(
          child: Column(
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
              if (viewportWidth != null)
                SizedBox(width: viewportWidth, child: toolbar)
              else
                toolbar,
            ],
          ),
        ),
      ),
    );
  }

  testWidgets('renders without crash with default props', (tester) async {
    final key = GlobalKey<FlueraCanvasState>();
    CanvasTool tool = CanvasTool.draw;
    Color color = const Color(0xFF1A1A1A);
    await tester.pumpWidget(
      _wrap(
        canvasKey: key,
        tool: tool,
        color: color,
        onTool: (t) => tool = t,
        onColor: (c) => color = c,
      ),
    );
    expect(find.byType(FlueraCanvasCupertinoToolbar), findsOneWidget);
    expect(find.byType(CupertinoSlider), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap on a Cupertino tool pill calls onToolChanged', (tester) async {
    final key = GlobalKey<FlueraCanvasState>();
    CanvasTool tool = CanvasTool.draw;
    Color color = const Color(0xFF1A1A1A);
    await tester.pumpWidget(
      _wrap(
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

  testWidgets('compact layout under 600px swaps slider widths', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final key = GlobalKey<FlueraCanvasState>();
    CanvasTool tool = CanvasTool.draw;
    Color color = const Color(0xFF1A1A1A);
    await tester.pumpWidget(
      _wrap(
        canvasKey: key,
        tool: tool,
        color: color,
        onTool: (t) => tool = t,
        onColor: (c) => color = c,
        viewportWidth: 500,
      ),
    );
    final boxes = tester.widgetList<SizedBox>(find.byType(SizedBox))
        .where((b) => b.width == 140.0);
    expect(boxes, isNotEmpty,
        reason: 'compact layout should swap slider width to 140');
  });
}
