import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

void main() {
  group('CanvasTool enum (0.4.0 additions)', () {
    test(
        'contains the documented tool variants in order '
        '(incl. 0.6.0 select + image)', () {
      expect(CanvasTool.values, [
        CanvasTool.draw,
        CanvasTool.erase,
        CanvasTool.erasePixel,
        CanvasTool.line,
        CanvasTool.rectangle,
        CanvasTool.ellipse,
        CanvasTool.select,
        CanvasTool.image,
      ]);
    });
  });

  group('Shape stroke geometry', () {
    // The shape builder is private; we verify behaviour by committing
    // a stroke programmatically with the same point sets the
    // _buildShapePoints helper would produce for each tool, then
    // asserting bounds + closure / segment counts.

    testWidgets('line shape: 2 points, bounds = aabb of endpoints', (
      tester,
    ) async {
      final stroke = CanvasStroke(
        points: const [Offset(10, 20), Offset(110, 70)],
        pressures: const [1.0, 1.0],
        color: Colors.blue,
        baseWidth: 2.0,
      );
      expect(stroke.points.length, 2);
      // Bounds padded by baseWidth * 0.6 = 1.2.
      expect(stroke.bounds.left, closeTo(10 - 1.2, 1e-9));
      expect(stroke.bounds.right, closeTo(110 + 1.2, 1e-9));
    });

    testWidgets('rectangle shape: 5-point closed polygon', (tester) async {
      final pts = const [
        Offset(0, 0),
        Offset(100, 0),
        Offset(100, 50),
        Offset(0, 50),
        Offset(0, 0),
      ];
      final stroke = CanvasStroke(
        points: pts,
        pressures: List<double>.filled(pts.length, 1.0),
        color: Colors.red,
        baseWidth: 2.0,
      );
      expect(stroke.points.first, stroke.points.last);
      expect(stroke.points.length, 5);
    });

    testWidgets('ellipse shape: 33 points (32 segments + closing point)', (
      tester,
    ) async {
      const cx = 50.0;
      const cy = 50.0;
      const rx = 40.0;
      const ry = 25.0;
      const segments = 32;
      final pts = <Offset>[];
      for (int i = 0; i <= segments; i++) {
        final t = i / segments * 2 * math.pi;
        pts.add(Offset(cx + rx * math.cos(t), cy + ry * math.sin(t)));
      }
      final stroke = CanvasStroke(
        points: pts,
        pressures: List<double>.filled(pts.length, 1.0),
        color: Colors.green,
        baseWidth: 2.0,
      );
      expect(stroke.points.length, 33);
      // First and last close the loop.
      expect(
        (stroke.points.first - stroke.points.last).distance,
        closeTo(0.0, 1e-6),
      );
    });
  });

  group('Pixel-mode eraser tool wiring', () {
    testWidgets('FlueraCanvas accepts erasePixel as widget.tool', (
      tester,
    ) async {
      // Smoke test: the canvas builds without throwing when given
      // erasePixel. The actual subdivision is exercised via gesture
      // flow which is harder to drive in widget tests.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlueraCanvas(
              tool: CanvasTool.erasePixel,
              enableNativeLiveStroke: false,
            ),
          ),
        ),
      );
      expect(find.byType(FlueraCanvas), findsOneWidget);
    });
  });

  group('FlueraColorPickerDialog', () {
    testWidgets('opens, reflects initial color, returns picked color', (
      tester,
    ) async {
      Color? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                return ElevatedButton(
                  onPressed: () async {
                    picked = await showFlueraColorPicker(
                      context: ctx,
                      initial: Colors.red,
                    );
                  },
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(FlueraColorPickerDialog), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);

      // Tap OK without changing → returns the initial color.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(picked!.toARGB32(), Colors.red.toARGB32());
    });

    testWidgets('Cancel returns null', (tester) async {
      Color? picked = Colors.black; // sentinel
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                return ElevatedButton(
                  onPressed: () async {
                    picked = await showFlueraColorPicker(
                      context: ctx,
                      initial: Colors.blue,
                    );
                  },
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(picked, isNull);
    });
  });

  group('FlueraCanvasToolbar opt-in flags', () {
    testWidgets('showShapeTools=true renders Line / Rect / Oval segments', (
      tester,
    ) async {
      final canvasKey = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  height: 200,
                  child: FlueraCanvas(
                    key: canvasKey,
                    enableNativeLiveStroke: false,
                  ),
                ),
                FlueraCanvasToolbar(
                  canvasKey: canvasKey,
                  tool: CanvasTool.draw,
                  onToolChanged: (_) {},
                  color: Colors.black,
                  onColorChanged: (_) {},
                  strokeWidth: 2.0,
                  onStrokeWidthChanged: (_) {},
                  showShapeTools: true,
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Line'), findsOneWidget);
      expect(find.text('Rect'), findsOneWidget);
      expect(find.text('Oval'), findsOneWidget);
    });

    testWidgets('showShapeTools=false (default) hides shape buttons', (
      tester,
    ) async {
      final canvasKey = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(
                  height: 200,
                  child: FlueraCanvas(
                    key: canvasKey,
                    enableNativeLiveStroke: false,
                  ),
                ),
                FlueraCanvasToolbar(
                  canvasKey: canvasKey,
                  tool: CanvasTool.draw,
                  onToolChanged: (_) {},
                  color: Colors.black,
                  onColorChanged: (_) {},
                  strokeWidth: 2.0,
                  onStrokeWidthChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Line'), findsNothing);
      expect(find.text('Rect'), findsNothing);
      expect(find.text('Oval'), findsNothing);
    });
  });
}
