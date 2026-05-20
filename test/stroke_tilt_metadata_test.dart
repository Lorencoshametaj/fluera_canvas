// Tests for the 0.14.0 CanvasStroke extensions:
//   - per-point tilt channel (Offset(tiltX, tiltY) radians)
//   - per-point twist channel (radians) — data structure ready, no
//     gesture capture in 0.14.0 (consumers can construct strokes
//     programmatically with twists if needed)
//   - opaque metadata bag (round-trip via JSON inside FCV0 v8)
//
// Coverage: assertion enforcement, FCV0 v8 round-trip, mixed
// presence (tilt-only / metadata-only / both), getMeta convenience.

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

CanvasStroke _stroke({
  List<Offset>? pts,
  List<Offset>? tilts,
  List<double>? twists,
  Map<String, dynamic>? metadata,
}) {
  final p = pts ?? const [Offset(10, 10), Offset(60, 60), Offset(110, 30)];
  return CanvasStroke(
    points: p,
    pressures: List.filled(p.length, 0.5),
    color: const Color(0xFF1A1A1A),
    baseWidth: 3,
    tilts: tilts,
    twists: twists,
    metadata: metadata,
  );
}

void main() {
  group('CanvasStroke field invariants', () {
    test('default stroke has null tilts / twists / metadata', () {
      final s = _stroke();
      expect(s.tilts, isNull);
      expect(s.twists, isNull);
      expect(s.metadata, isNull);
    });

    test('tilts.length must match points.length', () {
      expect(
        () => _stroke(tilts: const [Offset(0.1, 0.2)]),
        throwsAssertionError,
      );
    });

    test('twists.length must match points.length', () {
      expect(
        () => _stroke(twists: const [0.5]),
        throwsAssertionError,
      );
    });

    test('getMeta returns typed value or default', () {
      final s = _stroke(metadata: {'author': 'lorenzo', 'count': 42});
      expect(s.getMeta<String>('author'), 'lorenzo');
      expect(s.getMeta<int>('count'), 42);
      expect(s.getMeta<bool>('missing', false), false);
      expect(s.getMeta<String>('count'), isNull); // type mismatch
    });
  });

  group('FCV0 v8 round-trip', () {
    test('tilt channel survives encode → decode', () {
      final tilts = const [
        Offset(0.1, 0.2),
        Offset(0.3, -0.4),
        Offset(-0.5, 0.0),
      ];
      final original = _stroke(tilts: tilts);
      final bytes = CanvasSerializer.encodeBytes([original]);
      final decoded = CanvasSerializer.decodeBytes(bytes);
      expect(decoded.length, 1);
      expect(decoded.first.tilts, isNotNull);
      expect(decoded.first.tilts!.length, tilts.length);
      for (int i = 0; i < tilts.length; i++) {
        expect(decoded.first.tilts![i].dx, closeTo(tilts[i].dx, 1e-5));
        expect(decoded.first.tilts![i].dy, closeTo(tilts[i].dy, 1e-5));
      }
    });

    test('metadata round-trips JSON-encodable values', () {
      final meta = <String, dynamic>{
        'author': 'lorenzo',
        'count': 42,
        'flagged': true,
        'tags': ['draft', 'final'],
        'nested': {'x': 1.5, 'y': -2.5},
      };
      final original = _stroke(metadata: meta);
      final bytes = CanvasSerializer.encodeBytes([original]);
      final decoded = CanvasSerializer.decodeBytes(bytes);
      expect(decoded.first.metadata, isNotNull);
      expect(decoded.first.metadata!['author'], 'lorenzo');
      expect(decoded.first.metadata!['count'], 42);
      expect(decoded.first.metadata!['flagged'], true);
      expect(decoded.first.metadata!['tags'], ['draft', 'final']);
      expect(decoded.first.metadata!['nested'], {'x': 1.5, 'y': -2.5});
    });

    test('null tilts / twists / metadata stay null after round-trip', () {
      final original = _stroke();
      final bytes = CanvasSerializer.encodeBytes([original]);
      final decoded = CanvasSerializer.decodeBytes(bytes);
      expect(decoded.first.tilts, isNull);
      expect(decoded.first.twists, isNull);
      expect(decoded.first.metadata, isNull);
    });

    test('tilt + metadata coexist on the same stroke', () {
      final original = _stroke(
        tilts: const [Offset(0.1, 0.2), Offset(0.3, 0.4), Offset(0.5, 0.6)],
        metadata: const {'note': 'mixed'},
      );
      final bytes = CanvasSerializer.encodeBytes([original]);
      final decoded = CanvasSerializer.decodeBytes(bytes);
      expect(decoded.first.tilts, isNotNull);
      expect(decoded.first.tilts!.length, 3);
      expect(decoded.first.metadata?['note'], 'mixed');
    });
  });
}
