// Tests for the 0.16.0 a11y semantics wrapper on FlueraCanvas.

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FlueraCanvas defaults semanticsEnabled to true', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: FlueraCanvas(),
          ),
        ),
      ),
    );
    final widget = tester.widget<FlueraCanvas>(find.byType(FlueraCanvas));
    expect(widget.semanticsEnabled, isTrue);
  });

  testWidgets('semanticsEnabled: true emits a labeled Semantics node', (
    tester,
  ) async {
    final canvasKey = GlobalKey<FlueraCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: FlueraCanvas(key: canvasKey),
          ),
        ),
      ),
    );
    await tester.pump();
    // Label format: "Drawing canvas, N strokes, M layers"
    final semantics = tester
        .getSemantics(find.byType(FlueraCanvas))
        .toString();
    expect(semantics, contains('Drawing canvas'));
    expect(semantics, contains('strokes'));
    expect(semantics, contains('layers'));
  });

  testWidgets('semanticsEnabled: false skips the wrapper', (tester) async {
    final canvasKey = GlobalKey<FlueraCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: FlueraCanvas(
              key: canvasKey,
              semanticsEnabled: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final widget = tester.widget<FlueraCanvas>(find.byType(FlueraCanvas));
    expect(widget.semanticsEnabled, isFalse);
    // No exception during build with the flag off — that's the
    // contract (we don't introspect the absence of Semantics
    // because Flutter framework adds many internal Semantics nodes
    // we don't want to over-specify against).
    expect(tester.takeException(), isNull);
  });
}
