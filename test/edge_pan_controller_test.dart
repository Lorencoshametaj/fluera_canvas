import 'dart:ui' show Offset, Size;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubVsync implements TickerProvider {
  @override
  Ticker createTicker(TickerCallback onTick) => Ticker(onTick);
}

void main() {
  // `Ticker.start()` reaches into `SchedulerBinding.instance` — the
  // binding has to be initialised even for these widgetless tests.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('EdgePanController', () {
    test('does NOT start panning when pointer is centered', () {
      final controller = InfiniteCanvasController();
      final pan = EdgePanController(
        controller: controller,
        vsync: _StubVsync(),
        onTick: (_) {},
      );
      pan.update(
        pointerScreen: const Offset(400, 300),
        viewportSize: const Size(800, 600),
      );
      expect(pan.isPanning, isFalse);
    });

    test('starts panning when pointer enters the right-edge band', () {
      final controller = InfiniteCanvasController();
      final pan = EdgePanController(
        controller: controller,
        vsync: _StubVsync(),
        onTick: (_) {},
        edgeMargin: 60,
      );
      // 800 - 60 = 740 → anything beyond 740 is in the band.
      pan.update(
        pointerScreen: const Offset(770, 300),
        viewportSize: const Size(800, 600),
      );
      expect(pan.isPanning, isTrue);
      pan.stop();
      expect(pan.isPanning, isFalse);
    });

    test('starts panning at every edge (4 sides)', () {
      final controller = InfiniteCanvasController();
      final pan = EdgePanController(
        controller: controller,
        vsync: _StubVsync(),
        onTick: (_) {},
        edgeMargin: 50,
      );
      const size = Size(800, 600);
      for (final p in [
        const Offset(10, 300), // left
        const Offset(795, 300), // right
        const Offset(400, 5), // top
        const Offset(400, 595), // bottom
      ]) {
        pan.update(pointerScreen: p, viewportSize: size);
        expect(pan.isPanning, isTrue, reason: 'should pan at $p');
        pan.stop();
      }
    });

    test('stops panning when pointer leaves the band', () {
      final controller = InfiniteCanvasController();
      final pan = EdgePanController(
        controller: controller,
        vsync: _StubVsync(),
        onTick: (_) {},
      );
      const size = Size(800, 600);
      pan.update(pointerScreen: const Offset(780, 300), viewportSize: size);
      expect(pan.isPanning, isTrue);
      pan.update(pointerScreen: const Offset(400, 300), viewportSize: size);
      expect(pan.isPanning, isFalse);
    });

    test('stop() is idempotent', () {
      final controller = InfiniteCanvasController();
      final pan = EdgePanController(
        controller: controller,
        vsync: _StubVsync(),
        onTick: (_) {},
      );
      pan.stop();
      pan.stop();
      expect(pan.isPanning, isFalse);
    });

    test('zero-size viewport never triggers pan', () {
      final controller = InfiniteCanvasController();
      final pan = EdgePanController(
        controller: controller,
        vsync: _StubVsync(),
        onTick: (_) {},
      );
      pan.update(pointerScreen: const Offset(0, 0), viewportSize: Size.zero);
      expect(pan.isPanning, isFalse);
    });
  });
}
