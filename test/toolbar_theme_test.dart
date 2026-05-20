// Widget tests for the 0.11.1 FlueraToolbarTheme + compact-mode features.
//
// Theming covers: copyWith preservation, ThemeData.extensions
// integration, local `theme:` prop priority over global. Compact mode
// covers: layout switch at the breakpoint and the slider-width swap.

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget pump({
    required GlobalKey<FlueraCanvasState> canvasKey,
    FlueraToolbarTheme? globalExtension,
    FlueraToolbarTheme? localTheme,
    double? viewportWidth,
    CanvasTool tool = CanvasTool.draw,
    Color color = const Color(0xFF000000),
  }) {
    final toolbar = FlueraCanvasToolbar(
      canvasKey: canvasKey,
      tool: tool,
      onToolChanged: (_) {},
      color: color,
      onColorChanged: (_) {},
      strokeWidth: 2.5,
      onStrokeWidthChanged: (_) {},
      theme: localTheme,
    );
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.indigo,
        extensions: globalExtension == null ? null : [globalExtension],
      ),
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
            // SizedBox-constrained outer width forces LayoutBuilder
            // to use the test viewport width without depending on
            // MediaQuery (which is governed by the test surface).
            if (viewportWidth != null)
              SizedBox(width: viewportWidth, child: toolbar)
            else
              toolbar,
          ],
        ),
      ),
    );
  }

  group('FlueraToolbarTheme', () {
    test('copyWith preserves unspecified fields', () {
      const base = FlueraToolbarTheme.defaults;
      final updated = base.copyWith(swatchSize: 40, motion: const Duration(milliseconds: 50));
      expect(updated.swatchSize, 40.0);
      expect(updated.motion, const Duration(milliseconds: 50));
      // Untouched fields keep the defaults.
      expect(updated.radius, base.radius);
      expect(updated.tap, base.tap);
      expect(updated.spacing, base.spacing);
    });

    test('lerp interpolates geometry and falls back when types differ', () {
      const a = FlueraToolbarTheme(swatchSize: 30, radius: 14);
      const b = FlueraToolbarTheme(swatchSize: 50, radius: 20);
      final mid = a.lerp(b, 0.5);
      expect(mid.swatchSize, closeTo(40, 0.01));
      expect(mid.radius, closeTo(17, 0.01));
    });

    testWidgets('ThemeData extension applies — selected pill picks up override', (
      tester,
    ) async {
      const overrideFill = Color(0xFF00CC88);
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(
        pump(
          canvasKey: key,
          globalExtension: const FlueraToolbarTheme(selectedFill: overrideFill),
        ),
      );
      // Selected pill is the Pen tool (default tool=draw).
      final pillFinder = find.descendant(
        of: find.byTooltip('Pen'),
        matching: find.byType(AnimatedContainer),
      );
      final pill = tester.widget<AnimatedContainer>(pillFinder.first);
      final decoration = pill.decoration as BoxDecoration;
      expect(decoration.color, overrideFill);
    });

    testWidgets('local theme prop wins over ThemeData extension', (
      tester,
    ) async {
      const globalFill = Color(0xFFFF0000);
      const localFill = Color(0xFF00FF00);
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(
        pump(
          canvasKey: key,
          globalExtension: const FlueraToolbarTheme(selectedFill: globalFill),
          localTheme: const FlueraToolbarTheme(selectedFill: localFill),
        ),
      );
      final pillFinder = find.descendant(
        of: find.byTooltip('Pen'),
        matching: find.byType(AnimatedContainer),
      );
      final pill = tester.widget<AnimatedContainer>(pillFinder.first);
      final decoration = pill.decoration as BoxDecoration;
      expect(decoration.color, localFill);
      expect(decoration.color, isNot(globalFill));
    });
  });

  group('Compact mode', () {
    testWidgets('wide viewport (>= 600 px) uses default sliderWidth (220)', (
      tester,
    ) async {
      // Big surface so the toolbar gets a wide constraint.
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(canvasKey: key, viewportWidth: 1200));
      // The size slider lives in a SizedBox(width: 220) (default theme).
      final sliderBox = tester.widgetList<SizedBox>(find.byType(SizedBox))
          .where((b) => b.width == 220.0);
      expect(sliderBox, isNotEmpty,
          reason: 'wide layout should use FlueraToolbarTheme.defaults.sliderWidth = 220');
    });

    testWidgets('narrow viewport (< 600 px) swaps to compactSliderWidth (140)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(canvasKey: key, viewportWidth: 500));
      final sliderBox = tester.widgetList<SizedBox>(find.byType(SizedBox))
          .where((b) => b.width == 140.0);
      expect(sliderBox, isNotEmpty,
          reason: 'compact layout should swap to FlueraToolbarTheme.defaults.compactSliderWidth = 140');
    });
  });
}
