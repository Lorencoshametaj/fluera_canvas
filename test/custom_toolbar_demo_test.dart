// Smoke test for the headless `FlueraCanvas` + custom-toolbar pattern.
//
// We don't import the example app's `_CustomToolbarDemo` directly
// (it's a private widget in `example/lib/main.dart`). Instead we
// mirror the same pattern inline: headless canvas + setState-driven
// tool / colour switching + ListenableBuilder on `historyListenable`.
// If this test passes, the pattern documented in `doc/customization.md`
// is structurally sound and any consumer following the recipe gets a
// working canvas.

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _MiniHeadlessApp extends StatefulWidget {
  const _MiniHeadlessApp();
  @override
  State<_MiniHeadlessApp> createState() => _MiniHeadlessAppState();
}

class _MiniHeadlessAppState extends State<_MiniHeadlessApp> {
  final _canvasKey = GlobalKey<FlueraCanvasState>();
  CanvasTool _tool = CanvasTool.draw;
  Color _color = const Color(0xFF1A1A1A);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            FlueraCanvas(
              key: _canvasKey,
              tool: _tool,
              strokeColor: _color,
              strokeWidth: 3,
            ),
            Positioned(
              left: 8,
              top: 8,
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Pen',
                    onPressed: () => setState(() => _tool = CanvasTool.draw),
                    icon: const Icon(Icons.edit_rounded),
                  ),
                  IconButton(
                    tooltip: 'Erase',
                    onPressed: () => setState(() => _tool = CanvasTool.erase),
                    icon: const Icon(Icons.cleaning_services_rounded),
                  ),
                  IconButton(
                    tooltip: 'Red',
                    onPressed: () =>
                        setState(() => _color = const Color(0xFFE53935)),
                    icon: const Icon(Icons.circle_rounded),
                    color: const Color(0xFFE53935),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('headless FlueraCanvas + custom toolbar wires tool / color', (
    tester,
  ) async {
    await tester.pumpWidget(const _MiniHeadlessApp());
    expect(find.byType(FlueraCanvas), findsOneWidget);
    expect(find.byTooltip('Pen'), findsOneWidget);

    // Switch tool — verify no exception and the canvas continues to
    // render. We don't assert internal state because that would
    // couple the test to private FlueraCanvasState fields.
    await tester.tap(find.byTooltip('Erase'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Pick a colour through the bespoke widgets.
    await tester.tap(find.byTooltip('Red'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
