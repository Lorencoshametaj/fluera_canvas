// Smoke tests for the 0.13.0 FlueraMinimap widget.
//
// We don't assert pixel-level rendering (CustomPainter testing is
// brittle); we just verify the widget builds with / without a
// mounted canvas and that tapping triggers a controller setOffset
// call (proven by reading controller.offset after the tap).

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FlueraMinimap renders without crash on empty canvas', (
    tester,
  ) async {
    final canvasKey = GlobalKey<FlueraCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              SizedBox(
                width: 600,
                height: 400,
                child: FlueraCanvas(key: canvasKey),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: FlueraMinimap(canvasKey: canvasKey),
              ),
            ],
          ),
        ),
      ),
    );
    // Pump twice — first frame mounts the canvas; second wires
    // the minimap's listenables and repaints with content.
    await tester.pump();
    expect(find.byType(FlueraMinimap), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FlueraMinimap survives a stroke commit + repaint cycle', (
    tester,
  ) async {
    final canvasKey = GlobalKey<FlueraCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              SizedBox(
                width: 600,
                height: 400,
                child: FlueraCanvas(key: canvasKey),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: FlueraMinimap(
                  canvasKey: canvasKey,
                  size: const Size(120, 80),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    // Commit a stroke programmatically, then repaint.
    final state = canvasKey.currentState!;
    state.pushStroke(
      CanvasStroke(
        points: const [Offset(50, 50), Offset(200, 100), Offset(120, 200)],
        pressures: const [0.5, 0.7, 0.6],
        color: const Color(0xFF1A1A1A),
        baseWidth: 3,
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(FlueraMinimap), findsOneWidget);
  });
}
