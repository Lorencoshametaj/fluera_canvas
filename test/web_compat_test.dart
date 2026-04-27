/// Smoke test that exercises the public API without touching any
/// platform-specific path (no `dart:io`, no `file_selector`, no
/// asset bundles). Designed to be run on every target — VM,
/// Chrome (`flutter test -p chrome`), and WASM.
///
/// CI invocation:
/// ```
/// flutter test test/web_compat_test.dart            # VM
/// flutter test test/web_compat_test.dart -p chrome  # JS web
/// ```
library;

import 'dart:typed_data';
import 'dart:ui' show Color, Offset;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CanvasStroke makeStroke(int seed) => CanvasStroke(
    points: List<Offset>.unmodifiable([
      Offset(seed.toDouble(), 0),
      Offset(seed.toDouble() + 10, 10),
    ]),
    pressures: const [0.5, 0.7],
    color: Color(0xFF000000 + seed),
    baseWidth: 2.0,
  );

  Widget pump(GlobalKey<FlueraCanvasState> key, {Uint8List? initial}) =>
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: FlueraCanvas(key: key, initialBytes: initial),
          ),
        ),
      );

  group('web/wasm compat', () {
    testWidgets('FlueraCanvas builds + commits a stroke without dart:io', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStroke(makeStroke(1));
      expect(state.strokes, hasLength(1));
    });

    testWidgets('toBytes / loadFromBytes round-trip is web-safe', (
      tester,
    ) async {
      final keyA = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(keyA));
      keyA.currentState!.pushStrokes([makeStroke(1), makeStroke(2)]);
      final encoded = keyA.currentState!.toBytes();

      final keyB = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(keyB, initial: encoded));
      await tester.pumpAndSettle();
      expect(keyB.currentState!.strokes, hasLength(2));
    });

    testWidgets('selection / transform pipeline is web-safe', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStrokes([makeStroke(1), makeStroke(2)]);
      state.selectInRect(const Rect.fromLTRB(-100, -100, 1000, 1000));
      expect(state.selection.length, 2);
      state.mirrorSelection(Axis.horizontal);
      expect(state.undo(), isTrue);
    });

    testWidgets('group / ungroup / duplicate / Z-order all web-safe', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStrokes([makeStroke(1), makeStroke(2)]);
      state.selectInRect(const Rect.fromLTRB(-100, -100, 1000, 1000));
      final groupId = state.groupSelection();
      expect(groupId, isNotNull);
      expect(state.ungroupSelection(), 1);
      state.selectInRect(const Rect.fromLTRB(-100, -100, 1000, 1000));
      expect(state.duplicateSelection(), greaterThan(0));
    });

    testWidgets('lasso tool enum + props build on web', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: FlueraCanvas(
                key: key,
                tool: CanvasTool.lasso,
                snapToGrid: 16,
                smartGuidesEnabled: true,
              ),
            ),
          ),
        ),
      );
      expect(find.byType(FlueraCanvas), findsOneWidget);
    });
  });
}
