// Tests for the 0.16.0 FlueraStrings i18n delegate.

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget _wrap({
    required GlobalKey<FlueraCanvasState> canvasKey,
    FlueraStrings? globalExtension,
    FlueraStrings? localStrings,
  }) {
    return MaterialApp(
      theme: ThemeData(
        useMaterial3: true,
        extensions: globalExtension == null ? null : [globalExtension],
      ),
      home: Scaffold(
        body: Column(
          children: [
            SizedBox(
              height: 200,
              child: FlueraCanvas(key: canvasKey),
            ),
            FlueraCanvasToolbar(
              canvasKey: canvasKey,
              tool: CanvasTool.draw,
              onToolChanged: (_) {},
              color: const Color(0xFF000000),
              onColorChanged: (_) {},
              strokeWidth: 2.5,
              onStrokeWidthChanged: (_) {},
              showLayers: true,
              strings: localStrings,
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('default strings are English', (tester) async {
    final key = GlobalKey<FlueraCanvasState>();
    await tester.pumpWidget(_wrap(canvasKey: key));
    expect(find.byTooltip('Pen'), findsOneWidget);
    expect(find.byTooltip('Erase'), findsOneWidget);
    expect(find.byTooltip('Layers'), findsOneWidget);
    expect(find.byTooltip('Undo'), findsOneWidget);
  });

  testWidgets('global ThemeData extension translates the toolbar', (
    tester,
  ) async {
    final key = GlobalKey<FlueraCanvasState>();
    await tester.pumpWidget(
      _wrap(
        canvasKey: key,
        globalExtension: const FlueraStrings(
          toolPen: 'Penna',
          toolErase: 'Gomma',
          layersTooltip: 'Livelli',
          undoTooltip: 'Annulla',
        ),
      ),
    );
    expect(find.byTooltip('Penna'), findsOneWidget);
    expect(find.byTooltip('Gomma'), findsOneWidget);
    expect(find.byTooltip('Livelli'), findsOneWidget);
    expect(find.byTooltip('Annulla'), findsOneWidget);
    // Default English strings are gone for the overridden fields.
    expect(find.byTooltip('Pen'), findsNothing);
  });

  testWidgets('local strings prop wins over global extension', (
    tester,
  ) async {
    final key = GlobalKey<FlueraCanvasState>();
    await tester.pumpWidget(
      _wrap(
        canvasKey: key,
        globalExtension: const FlueraStrings(toolPen: 'GLOBAL'),
        localStrings: const FlueraStrings(toolPen: 'LOCAL'),
      ),
    );
    expect(find.byTooltip('LOCAL'), findsOneWidget);
    expect(find.byTooltip('GLOBAL'), findsNothing);
  });
}
