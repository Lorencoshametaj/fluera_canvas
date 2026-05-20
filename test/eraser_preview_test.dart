// Smoke test for the existing `showEraserPreview` flag on FlueraCanvas.
//
// The eraser-preview overlay was wired pre-0.13.0 with default `true`.
// This test documents the contract: the flag is honoured, defaults to
// true, and the canvas rebuilds without crash when toggled.

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FlueraCanvas defaults showEraserPreview to true', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: FlueraCanvas(tool: CanvasTool.erase),
          ),
        ),
      ),
    );
    final widget = tester.widget<FlueraCanvas>(find.byType(FlueraCanvas));
    expect(widget.showEraserPreview, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('FlueraCanvas builds with showEraserPreview: false (opt-out)', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: FlueraCanvas(
              tool: CanvasTool.erase,
              showEraserPreview: false,
            ),
          ),
        ),
      ),
    );
    final widget = tester.widget<FlueraCanvas>(find.byType(FlueraCanvas));
    expect(widget.showEraserPreview, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cursorPerTool override is honoured by MouseRegion', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: FlueraCanvas(
              cursorPerTool: const {
                CanvasTool.draw: SystemMouseCursors.cell,
              },
            ),
          ),
        ),
      ),
    );
    // Find the MouseRegion mounted by FlueraCanvas (desktop-only).
    final regions = tester.widgetList<MouseRegion>(find.byType(MouseRegion));
    final hasCellCursor =
        regions.any((r) => r.cursor == SystemMouseCursors.cell);
    // On Linux/Web/macOS/Win the desktop wrapper mounts; the
    // override should be visible. On mobile-only test environments
    // it wouldn't, but `flutter test` runs on desktop VM so this
    // should always succeed in CI.
    expect(hasCellCursor, isTrue,
        reason: 'cursorPerTool[draw] = cell must reach MouseRegion.cursor');
  });
}
