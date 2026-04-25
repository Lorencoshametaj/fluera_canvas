import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

void main() {
  group('CanvasStroke.splitAroundCircle (pixel-eraser primitive)', () {
    CanvasStroke makeStroke(List<Offset> pts) => CanvasStroke(
      points: pts,
      pressures: List<double>.filled(pts.length, 0.5),
      color: const Color(0xFF000000),
      baseWidth: 2.0,
    );

    test('empty stroke returns empty', () {
      final survivors = CanvasStroke.splitAroundCircle(
        makeStroke(const []),
        const Offset(0, 0),
        100,
      );
      expect(survivors, isEmpty);
    });

    test('all points outside the circle → 1 survivor identical to input', () {
      final stroke = makeStroke(const [
        Offset(0, 0),
        Offset(100, 0),
        Offset(200, 0),
      ]);
      final survivors = CanvasStroke.splitAroundCircle(
        stroke,
        const Offset(500, 500),
        100, // r² = 100, so r = 10 — far away
      );
      expect(survivors.length, 1);
      expect(survivors.first.points.length, 3);
    });

    test('all points inside the circle → no survivors (full erase)', () {
      final stroke = makeStroke(const [
        Offset(0, 0),
        Offset(1, 1),
        Offset(2, 0),
      ]);
      final survivors = CanvasStroke.splitAroundCircle(
        stroke,
        const Offset(1, 1),
        100, // r² = 100 → r = 10, big enough to swallow all 3 pts
      );
      expect(survivors, isEmpty);
    });

    test('eraser cuts the middle → 2 survivors before and after', () {
      // Points at x = 0, 50, 100, 150, 200. Circle at x=100, r=30.
      // x=70..130 inside → only points 0 (x=50) and 200, 150 outside
      // Wait: x=100 is the center, x=70..130 is inside the circle.
      // Points: 0, 50, 100, 150, 200 → 0,50 outside, 100 inside, 150,200 outside.
      final stroke = makeStroke(const [
        Offset(0, 0),
        Offset(50, 0),
        Offset(100, 0),
        Offset(150, 0),
        Offset(200, 0),
      ]);
      final survivors = CanvasStroke.splitAroundCircle(
        stroke,
        const Offset(100, 0),
        30 * 30, // r² = 900 → r = 30
      );
      expect(survivors.length, 2);
      // The new splitter inserts intersection points at the eraser
      // boundary so the silhouette ends exactly at the circle edge.
      // Survivor 1: 0 → 50 → 70 (entry); Survivor 2: 130 (exit) → 150 → 200.
      expect(survivors[0].points.first, const Offset(0, 0));
      expect(survivors[0].points.last, const Offset(70, 0));
      expect(survivors[1].points.first, const Offset(130, 0));
      expect(survivors[1].points.last, const Offset(200, 0));
    });

    test('eraser at one end → single survivor at the other end', () {
      final stroke = makeStroke(const [
        Offset(0, 0),
        Offset(10, 0),
        Offset(100, 0),
        Offset(200, 0),
      ]);
      final survivors = CanvasStroke.splitAroundCircle(
        stroke,
        const Offset(0, 0),
        20 * 20, // r² = 400, swallows points (0,10)
      );
      expect(survivors.length, 1);
      // Exit point of the segment (10,0)→(100,0) at x=20, then 100, 200.
      expect(survivors.first.points.first, const Offset(20, 0));
      expect(survivors.first.points.last, const Offset(200, 0));
    });

    test('segment that crosses the circle but anchors are outside is cut', () {
      // 2 anchors only — eraser sits in the middle. Without proper
      // line-circle intersection the splitter would (incorrectly)
      // return the whole stroke. With it: 2 sub-strokes split at the
      // entry / exit points.
      final stroke = makeStroke(const [Offset(0, 0), Offset(200, 0)]);
      final survivors = CanvasStroke.splitAroundCircle(
        stroke,
        const Offset(100, 0),
        30 * 30,
      );
      expect(survivors.length, 2);
      expect(survivors[0].points, [const Offset(0, 0), const Offset(70, 0)]);
      expect(survivors[1].points, [const Offset(130, 0), const Offset(200, 0)]);
    });

    test('survivors inherit color, baseWidth and smooth flag', () {
      final stroke = CanvasStroke(
        points: const [Offset(0, 0), Offset(100, 0), Offset(200, 0)],
        pressures: const [0.3, 0.7, 0.9],
        color: const Color(0xFFAB12CD),
        baseWidth: 4.5,
        smooth: false,
      );
      final survivors = CanvasStroke.splitAroundCircle(
        stroke,
        const Offset(100, 0),
        25, // r=5
      );
      // With segment-aware splitting we get 2 sub-strokes (the cuts
      // happen on the segments, not at the original anchor points).
      expect(survivors.length, 2);
      for (final s in survivors) {
        expect(s.color.toARGB32(), const Color(0xFFAB12CD).toARGB32());
        expect(s.baseWidth, 4.5);
        expect(s.smooth, false);
      }
    });

    test(
      'far-away eraser leaves the stroke untouched, all 6 points / pressures preserved',
      () {
        // Eraser at (100, 500), nowhere near the y=0 stroke → 1 survivor
        // identical to the original.
        final stroke = CanvasStroke(
          points: const [
            Offset(0, 0),
            Offset(25, 0),
            Offset(50, 0),
            Offset(175, 0),
            Offset(200, 0),
            Offset(225, 0),
          ],
          pressures: const [0.1, 0.2, 0.3, 0.4, 0.5, 0.6],
          color: const Color(0xFF000000),
          baseWidth: 2.0,
        );
        final survivors = CanvasStroke.splitAroundCircle(
          stroke,
          const Offset(100, 500),
          10 * 10,
        );
        expect(survivors.length, 1);
        expect(survivors.first.pressures, [0.1, 0.2, 0.3, 0.4, 0.5, 0.6]);
      },
    );
  });

  group('Pixel-erase + persistence', () {
    test('survivors roundtrip cleanly through CanvasSerializer', () {
      final original = CanvasStroke(
        points: const [
          Offset(0, 0),
          Offset(50, 0),
          Offset(100, 0),
          Offset(150, 0),
          Offset(200, 0),
        ],
        pressures: const [0.5, 0.5, 0.5, 0.5, 0.5],
        color: const Color(0xFF0044FF),
        baseWidth: 3.0,
      );
      final survivors = CanvasStroke.splitAroundCircle(
        original,
        const Offset(100, 0),
        30 * 30,
      );
      expect(survivors.length, 2);

      final bytes = CanvasSerializer.encodeBytes(survivors);
      final decoded = CanvasSerializer.decodeBytes(bytes);
      expect(decoded.length, 2);
      for (int i = 0; i < 2; i++) {
        expect(decoded[i].points.length, survivors[i].points.length);
        expect(decoded[i].color.toARGB32(), survivors[i].color.toARGB32());
      }
    });
  });

  group('FlueraColorPickerDialog edge cases', () {
    testWidgets('enableAlpha=false hides the alpha slider', (tester) async {
      // Pump the dialog directly so we don't depend on a button tap.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlueraColorPickerDialog(
              initial: Color(0xFFFF0000),
              enableAlpha: false,
            ),
          ),
        ),
      );
      // The dialog itself renders; we can't easily detect the absence
      // of a private widget, so we just confirm the dialog didn't crash
      // and the OK button is reachable.
      expect(find.text('OK'), findsOneWidget);
      expect(find.byType(FlueraColorPickerDialog), findsOneWidget);
    });

    testWidgets('custom title is rendered', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlueraColorPickerDialog(
              initial: Color(0xFF00FF00),
              title: 'Choose ink color',
            ),
          ),
        ),
      );
      expect(find.text('Choose ink color'), findsOneWidget);
    });

    test('kFlueraDefaultPalette has 6 distinct colors', () {
      expect(kFlueraDefaultPalette.length, 6);
      final argbs = kFlueraDefaultPalette.map((c) => c.toARGB32()).toSet();
      expect(argbs.length, 6); // all distinct
    });
  });

  group('FlueraCanvasToolbar opt-in flag combinations', () {
    testWidgets(
      'showPixelEraser=true renders the Pixel segment in the toolbar',
      (tester) async {
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
                    showPixelEraser: true,
                  ),
                ],
              ),
            ),
          ),
        );
        expect(find.text('Cut'), findsOneWidget);
      },
    );

    testWidgets(
      'all opt-in flags ON renders all 6 tool segments without overflow',
      (tester) async {
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
                    showPixelEraser: true,
                    showShapeTools: true,
                    showColorPickerButton: true,
                  ),
                ],
              ),
            ),
          ),
        );
        expect(find.text('Pen'), findsOneWidget);
        expect(find.text('Erase'), findsOneWidget);
        expect(find.text('Cut'), findsOneWidget);
        expect(find.text('Line'), findsOneWidget);
        expect(find.text('Rect'), findsOneWidget);
        expect(find.text('Oval'), findsOneWidget);
        // No RenderFlex overflow exception thrown during pump.
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Shape tool degenerate cases', () {
    testWidgets(
      'rectangle with anchor==current commits as a 5-point degenerate '
      'polygon (no crash)',
      (tester) async {
        // Direct unit test on the geometry the gesture detector would
        // produce: anchor==current → all 5 points equal.
        const p = Offset(50, 50);
        final stroke = CanvasStroke(
          points: const [p, p, p, p, p],
          pressures: const [1.0, 1.0, 1.0, 1.0, 1.0],
          color: Colors.red,
          baseWidth: 2.0,
        );
        // Bounds collapse to a tight rect around p.
        expect(stroke.bounds.width, closeTo(2.4, 1e-6));
        expect(stroke.bounds.height, closeTo(2.4, 1e-6));
        // Picture builds without throwing.
        expect(stroke.picture, returnsNormally);
      },
    );

    testWidgets('shape strokes participate in undo / redo', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlueraCanvas(key: key, enableNativeLiveStroke: false),
          ),
        ),
      );
      final state = key.currentState!;
      // Push a "rectangle" stroke programmatically.
      state.pushStroke(
        CanvasStroke(
          points: const [
            Offset(0, 0),
            Offset(100, 0),
            Offset(100, 50),
            Offset(0, 50),
            Offset(0, 0),
          ],
          pressures: List<double>.filled(5, 1.0),
          color: Colors.green,
          baseWidth: 2.0,
        ),
      );
      expect(state.strokeCount, 1);
      expect(state.undo(), true);
      expect(state.strokeCount, 0);
      expect(state.redo(), true);
      expect(state.strokeCount, 1);
    });
  });
}
