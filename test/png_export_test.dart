/// Coverage for the infinite-canvas-aware `renderToImage` overhaul:
/// every [FlueraExportBounds] mode, the legacy positional signature,
/// and the empty-canvas / empty-selection sentinel paths.
library;

import 'dart:ui' show Color, Offset, Rect;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CanvasStroke makeStroke(double x, double y, {double size = 20}) =>
      CanvasStroke(
        points: List<Offset>.unmodifiable([
          Offset(x, y),
          Offset(x + size, y + size),
        ]),
        pressures: const [0.7, 0.7],
        color: const Color(0xFF1A73E8),
        baseWidth: 2.0,
      );

  Widget pump(GlobalKey<FlueraCanvasState> key) => MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 600,
        height: 400,
        child: FlueraCanvas(key: key),
      ),
    ),
  );

  group('renderToImage', () {
    testWidgets('legacy viewport signature returns the requested size', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final image = await key.currentState!.renderToImage(
        width: 320,
        height: 240,
      );
      expect(image.width, 320);
      expect(image.height, 240);
      image.dispose();
    });

    testWidgets('viewport mode requires both width and height', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      expect(
        () => key.currentState!.renderToImage(),
        throwsArgumentError,
      );
    });

    testWidgets('allContent rasterises every node, off-screen included', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      // Place strokes WAY off-screen — the legacy implementation
      // would still pick them up because it iterates `_strokes`,
      // but the bounds rect must enclose them.
      state.pushStroke(makeStroke(0, 0));
      state.pushStroke(makeStroke(2000, 1500));
      await tester.pump();

      final bounds = state.contentBoundsWorld;
      expect(bounds.width, greaterThanOrEqualTo(2000));
      expect(bounds.height, greaterThanOrEqualTo(1500));

      final image = await state.renderToImage(
        bounds: FlueraExportBounds.allContent,
      );
      expect(image.width, greaterThanOrEqualTo(2000));
      expect(image.height, greaterThanOrEqualTo(1500));
      image.dispose();
    });

    testWidgets('allContent + pixelRatio 2.0 doubles the output size', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStroke(makeStroke(10, 10));
      state.pushStroke(makeStroke(110, 110));
      await tester.pump();

      final base = await state.renderToImage(
        bounds: FlueraExportBounds.allContent,
      );
      final hi = await state.renderToImage(
        bounds: FlueraExportBounds.allContent,
        pixelRatio: 2.0,
      );
      expect(hi.width, closeTo(base.width * 2, 2));
      expect(hi.height, closeTo(base.height * 2, 2));
      base.dispose();
      hi.dispose();
    });

    testWidgets('empty-canvas allContent returns a 1x1 sentinel', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final image = await key.currentState!.renderToImage(
        bounds: FlueraExportBounds.allContent,
      );
      expect(image.width, 1);
      expect(image.height, 1);
      image.dispose();
    });

    testWidgets('selection mode returns sentinel when nothing selected', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStroke(makeStroke(50, 50));
      await tester.pump();
      final image = await state.renderToImage(
        bounds: FlueraExportBounds.selection,
      );
      expect(image.width, 1);
      expect(image.height, 1);
      image.dispose();
    });

    testWidgets('custom region rasterises the requested rect', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStroke(makeStroke(0, 0));
      await tester.pump();

      final image = await state.renderToImage(
        bounds: FlueraExportBounds.custom,
        region: const Rect.fromLTWH(0, 0, 100, 80),
        pixelRatio: 1.0,
      );
      expect(image.width, 100);
      expect(image.height, 80);
      image.dispose();
    });

    testWidgets('custom region rejects null / empty rects', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      expect(
        () => state.renderToImage(bounds: FlueraExportBounds.custom),
        throwsArgumentError,
      );
      expect(
        () => state.renderToImage(
          bounds: FlueraExportBounds.custom,
          region: Rect.zero,
        ),
        throwsArgumentError,
      );
    });

    testWidgets('rejects pixelRatio outside [0.05, 32.0]', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStroke(makeStroke(0, 0));
      await tester.pump();
      expect(
        () => state.renderToImage(
          bounds: FlueraExportBounds.allContent,
          pixelRatio: 0.001,
        ),
        throwsArgumentError,
      );
      expect(
        () => state.renderToImage(
          bounds: FlueraExportBounds.allContent,
          pixelRatio: 100.0,
        ),
        throwsArgumentError,
      );
    });

    testWidgets('rejects output size > 16 384 px on a side', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      // 1 000 px region × pixelRatio 32 → 32 000 px output → reject.
      expect(
        () => state.renderToImage(
          bounds: FlueraExportBounds.custom,
          region: const Rect.fromLTWH(0, 0, 1000, 1000),
          pixelRatio: 32.0,
        ),
        throwsArgumentError,
      );
    });

    testWidgets('padding inflates the bounds in world-px', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStroke(makeStroke(0, 0));
      state.pushStroke(makeStroke(100, 100));
      await tester.pump();

      final tight = await state.renderToImage(
        bounds: FlueraExportBounds.allContent,
      );
      final padded = await state.renderToImage(
        bounds: FlueraExportBounds.allContent,
        padding: 50,
      );
      // Padding adds 50 world-px on each side → +100 to width / height.
      expect(padded.width, greaterThan(tight.width));
      expect(padded.height, greaterThan(tight.height));
      tight.dispose();
      padded.dispose();
    });
  });
}
