import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

void main() {
  group('CanvasStroke.toJson / fromJson', () {
    test('default-config round trip preserves geometry + color + width', () {
      final stroke = CanvasStroke(
        points: const [Offset(1, 2), Offset(3, 4), Offset(5, 6)],
        pressures: const [0.1, 0.5, 0.9],
        color: const Color(0xFF112233),
        baseWidth: 4.5,
      );
      final round = CanvasStroke.fromJson(stroke.toJson());
      expect(round.points, stroke.points);
      expect(round.pressures, stroke.pressures);
      expect(round.color.toARGB32(), stroke.color.toARGB32());
      expect(round.baseWidth, stroke.baseWidth);
      expect(round.smooth, stroke.smooth);
      expect(round.brushType, stroke.brushType);
    });

    test('non-default smooth flag survives round trip', () {
      final stroke = CanvasStroke(
        points: const [Offset(0, 0), Offset(1, 1)],
        pressures: const [0.5, 0.5],
        color: const Color(0xFF000000),
        baseWidth: 2,
        smooth: false,
      );
      final round = CanvasStroke.fromJson(stroke.toJson());
      expect(round.smooth, false);
    });

    test('non-default brushType survives round trip', () {
      final stroke = CanvasStroke(
        points: const [Offset(0, 0), Offset(1, 1)],
        pressures: const [0.5, 0.5],
        color: const Color(0xFF000000),
        baseWidth: 2,
        brushType: 7,
      );
      final round = CanvasStroke.fromJson(stroke.toJson());
      expect(round.brushType, 7);
    });

    test('non-default pencilConfig survives round trip', () {
      const cfg = PencilConfig(
        baseOpacity: 0.7,
        maxOpacity: 0.95,
        minPressure: 0.1,
        maxPressure: 0.9,
      );
      final stroke = CanvasStroke(
        points: const [Offset(0, 0), Offset(1, 1)],
        pressures: const [0.5, 0.5],
        color: const Color(0xFF000000),
        baseWidth: 2,
        brushType: 2,
        pencilConfig: cfg,
      );
      final round = CanvasStroke.fromJson(stroke.toJson());
      expect(round.pencilConfig, cfg);
    });

    test('non-default fountainConfig survives round trip', () {
      const cfg = FountainPenConfig(
        thinning: 0.7,
        nibAngleDeg: 45,
        nibStrength: 0.5,
        pressureRate: 0.3,
        taperEntry: 8,
      );
      final stroke = CanvasStroke(
        points: const [Offset(0, 0), Offset(1, 1)],
        pressures: const [0.5, 0.5],
        color: const Color(0xFF000000),
        baseWidth: 2,
        brushType: 3,
        fountainConfig: cfg,
      );
      final round = CanvasStroke.fromJson(stroke.toJson());
      expect(round.fountainConfig, cfg);
    });

    test('fromJson rejects mismatched array lengths', () {
      expect(
        () => CanvasStroke.fromJson({
          'x': [1.0, 2.0],
          'y': [1.0],
          'p': [0.5, 0.5],
          'c': 0xFF000000,
          'w': 2.0,
        }),
        throwsFormatException,
      );
    });

    test('toJson omits default-valued optional fields for compactness', () {
      final stroke = CanvasStroke(
        points: const [Offset(0, 0), Offset(1, 1)],
        pressures: const [0.5, 0.5],
        color: const Color(0xFF000000),
        baseWidth: 2,
      );
      final json = stroke.toJson();
      expect(json.containsKey('s'), false, reason: 'smooth=true is default');
      expect(json.containsKey('bt'), false, reason: 'brushType=0 is default');
      expect(json.containsKey('pc'), false);
      expect(json.containsKey('fc'), false);
    });
  });
}
