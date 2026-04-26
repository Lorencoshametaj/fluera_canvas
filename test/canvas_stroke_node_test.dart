import 'dart:ui' show Color, Offset;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CanvasStrokeNode', () {
    CanvasStroke makeStroke({
      bool smooth = true,
      int brushType = 0,
      PencilConfig pencil = PencilConfig.defaults,
      FountainPenConfig fountain = FountainPenConfig.defaults,
    }) {
      return CanvasStroke(
        points: List.unmodifiable(const [
          Offset(0, 0),
          Offset(10, 0),
          Offset(10, 20),
        ]),
        pressures: List.unmodifiable(const [0.5, 0.7, 0.9]),
        color: const Color(0xFF112233),
        baseWidth: 3.5,
        smooth: smooth,
        brushType: brushType,
        pencilConfig: pencil,
        fountainConfig: fountain,
      );
    }

    test('localBounds delegates to the wrapped stroke', () {
      final stroke = makeStroke();
      final node = CanvasStrokeNode(id: const NodeId('n-1'), stroke: stroke);
      expect(node.localBounds, stroke.bounds);
    });

    test('JSON round-trip preserves all stroke fields (defaults)', () {
      final stroke = makeStroke();
      final node = CanvasStrokeNode(id: const NodeId('n-1'), stroke: stroke);

      final json = node.toJson();
      expect(json['nodeType'], 'canvas_stroke');

      final restored = CanvasStrokeNode.fromJson(json);
      expect(restored.id, const NodeId('n-1'));
      expect(restored.stroke.points, stroke.points);
      expect(restored.stroke.pressures, stroke.pressures);
      expect(restored.stroke.color.toARGB32(), stroke.color.toARGB32());
      expect(restored.stroke.baseWidth, stroke.baseWidth);
      expect(restored.stroke.smooth, isTrue);
      expect(restored.stroke.brushType, 0);
      expect(restored.stroke.pencilConfig, PencilConfig.defaults);
      expect(restored.stroke.fountainConfig, FountainPenConfig.defaults);
    });

    test('JSON round-trip preserves non-default brush + tuning', () {
      final stroke = makeStroke(
        smooth: false,
        brushType: 7,
        pencil: const PencilConfig(
          baseOpacity: 0.1,
          maxOpacity: 0.95,
          minPressure: 0.2,
          maxPressure: 1.5,
        ),
        fountain: const FountainPenConfig(
          thinning: 0.8,
          nibAngleDeg: 45,
          nibStrength: 0.7,
          pressureRate: 0.6,
          taperEntry: 12,
        ),
      );
      final node = CanvasStrokeNode(id: const NodeId('n-2'), stroke: stroke);

      final restored = CanvasStrokeNode.fromJson(node.toJson());
      expect(restored.stroke.smooth, isFalse);
      expect(restored.stroke.brushType, 7);
      expect(restored.stroke.pencilConfig, stroke.pencilConfig);
      expect(restored.stroke.fountainConfig, stroke.fountainConfig);
    });

    test('factory dispatches via CanvasNodeFactory', () {
      final node = CanvasStrokeNode(
        id: const NodeId('n-3'),
        stroke: makeStroke(),
      );
      final restored = CanvasNodeFactory.fromJson(node.toJson());
      expect(restored, isA<CanvasStrokeNode>());
      expect(restored.id, const NodeId('n-3'));
    });

    test('clone yields a new id but shares the underlying CanvasStroke', () {
      final stroke = makeStroke();
      final node = CanvasStrokeNode(id: const NodeId('n-4'), stroke: stroke);
      final clone = node.clone();
      expect(clone, isA<CanvasStrokeNode>());
      expect(clone.id, isNot(node.id));
      expect((clone as CanvasStrokeNode).stroke, same(stroke));
    });

    test('compact JSON: defaults are omitted from the payload', () {
      final stroke = makeStroke();
      final node = CanvasStrokeNode(id: const NodeId('n-5'), stroke: stroke);
      final payload = node.toJson()['stroke'] as Map<String, dynamic>;
      expect(payload.containsKey('s'), isFalse,
          reason: 'smooth=true is the default; should be omitted');
      expect(payload.containsKey('bt'), isFalse,
          reason: 'brushType=0 is the default; should be omitted');
      expect(payload.containsKey('pc'), isFalse,
          reason: 'PencilConfig.defaults should be omitted');
      expect(payload.containsKey('fc'), isFalse,
          reason: 'FountainPenConfig.defaults should be omitted');
    });
  });
}
