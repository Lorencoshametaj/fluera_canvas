import 'dart:typed_data';

import 'package:flutter/material.dart' show Color, Offset, Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

void main() {
  group('CanvasStroke', () {
    test('bounds expand by half stroke width on each side', () {
      final stroke = CanvasStroke(
        points: const [Offset(10, 20), Offset(30, 40)],
        pressures: const [1.0, 1.0],
        color: const Color(0xFF000000),
        baseWidth: 4.0,
      );
      // Pad = baseWidth * 0.6 = 2.4
      expect(stroke.bounds.left, closeTo(7.6, 1e-6));
      expect(stroke.bounds.top, closeTo(17.6, 1e-6));
      expect(stroke.bounds.right, closeTo(32.4, 1e-6));
      expect(stroke.bounds.bottom, closeTo(42.4, 1e-6));
    });

    test('empty points → Rect.zero', () {
      final stroke = CanvasStroke(
        points: const [],
        pressures: const [],
        color: const Color(0xFF000000),
        baseWidth: 2.0,
      );
      expect(stroke.bounds, Rect.zero);
    });

    test('picture() is cached across calls', () {
      final stroke = CanvasStroke(
        points: const [Offset(0, 0), Offset(100, 100)],
        pressures: const [0.5, 0.5],
        color: const Color(0xFFFF0000),
        baseWidth: 2.0,
      );
      final p1 = stroke.picture();
      final p2 = stroke.picture();
      expect(identical(p1, p2), isTrue);
    });

    test('dispose() releases the cached picture', () {
      final stroke = CanvasStroke(
        points: const [Offset(0, 0), Offset(50, 50)],
        pressures: const [0.5, 0.5],
        color: const Color(0xFF00FF00),
        baseWidth: 2.0,
      );
      final p1 = stroke.picture();
      stroke.dispose();
      // After dispose the next call rebuilds — different identity.
      final p2 = stroke.picture();
      expect(identical(p1, p2), isFalse);
    });
  });

  group('CanvasSerializer', () {
    final strokes = <CanvasStroke>[
      CanvasStroke(
        points: const [Offset(1, 2), Offset(3, 4), Offset(5, 6)],
        pressures: const [0.1, 0.5, 0.9],
        color: const Color(0xFFAB12CD),
        baseWidth: 3.5,
      ),
      CanvasStroke(
        points: const [Offset(-100, -200), Offset(0, 0)],
        pressures: const [1.0, 1.0],
        color: const Color(0xFF00BBEE),
        baseWidth: 1.0,
      ),
    ];

    void expectStrokesClose(
      List<CanvasStroke> a,
      List<CanvasStroke> b, {
      double eps = 1e-5,
    }) {
      expect(a.length, b.length);
      for (int i = 0; i < a.length; i++) {
        expect(a[i].points.length, b[i].points.length);
        for (int j = 0; j < a[i].points.length; j++) {
          expect(a[i].points[j].dx, closeTo(b[i].points[j].dx, eps));
          expect(a[i].points[j].dy, closeTo(b[i].points[j].dy, eps));
          expect(a[i].pressures[j], closeTo(b[i].pressures[j], eps));
        }
        expect(a[i].color.toARGB32(), b[i].color.toARGB32());
        expect(a[i].baseWidth, closeTo(b[i].baseWidth, eps));
      }
    }

    test('binary roundtrip preserves all stroke data', () {
      final bytes = CanvasSerializer.encodeBytes(strokes);
      final decoded = CanvasSerializer.decodeBytes(bytes);
      // Binary uses float32 → tolerate ~1e-5 quantisation.
      expectStrokesClose(decoded, strokes);
    });

    test('JSON roundtrip preserves all stroke data', () {
      final json = CanvasSerializer.encodeJson(strokes);
      final decoded = CanvasSerializer.decodeJson(json);
      expectStrokesClose(decoded, strokes);
    });

    test('decodeBytes throws FormatException on bad magic', () {
      final bad = Uint8List.fromList(<int>[0xDE, 0xAD, 0xBE, 0xEF, 0, 0, 0, 0]);
      expect(() => CanvasSerializer.decodeBytes(bad), throwsFormatException);
    });

    test('empty stroke list roundtrips to empty list', () {
      final bytes = CanvasSerializer.encodeBytes(const []);
      expect(CanvasSerializer.decodeBytes(bytes), isEmpty);
    });
  });
}
