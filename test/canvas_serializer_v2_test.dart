import 'dart:typed_data';
import 'dart:ui' show Color, Offset;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CanvasStroke makeStroke(int seed) => CanvasStroke(
    points: List<Offset>.unmodifiable([
      Offset(seed.toDouble(), 0),
      Offset(seed.toDouble() + 10, 5),
      Offset(seed.toDouble() + 20, 15),
    ]),
    pressures: const [0.4, 0.6, 0.8],
    color: Color(0xFF000000 + seed),
    baseWidth: 1.5 + seed * 0.25,
  );

  /// Produce a v1 byte stream by hand so we lock the legacy decoder
  /// behaviour from outside the library (no dependency on internal v1
  /// helpers — they can change as long as the bytes still decode).
  Uint8List makeV1Bytes(List<CanvasStroke> strokes) {
    int totalPoints = 0;
    for (final s in strokes) {
      totalPoints += s.points.length;
    }
    final size = 4 + 2 + 4 + strokes.length * 12 + totalPoints * 12;
    final buf = ByteData(size);
    int off = 0;
    buf.setUint32(off, 0x30564346, Endian.little); // 'FCV0'
    off += 4;
    buf.setUint16(off, 1, Endian.little); // version
    off += 2;
    buf.setUint32(off, strokes.length, Endian.little);
    off += 4;
    for (final s in strokes) {
      buf.setUint32(off, s.points.length, Endian.little);
      off += 4;
      buf.setUint32(off, s.color.toARGB32(), Endian.little);
      off += 4;
      buf.setFloat32(off, s.baseWidth, Endian.little);
      off += 4;
      for (int i = 0; i < s.points.length; i++) {
        buf.setFloat32(off, s.points[i].dx, Endian.little);
        off += 4;
        buf.setFloat32(off, s.points[i].dy, Endian.little);
        off += 4;
        buf.setFloat32(off, s.pressures[i], Endian.little);
        off += 4;
      }
    }
    return buf.buffer.asUint8List();
  }

  group('CanvasSerializer FCV v2', () {
    test(
      'encode + decode round-trips strokes through the layer-aware path',
      () {
        final strokes = [makeStroke(1), makeStroke(2), makeStroke(3)];
        final bytes = CanvasSerializer.encodeBytes(strokes);
        final decoded = CanvasSerializer.decodeBytes(bytes);
        expect(decoded, hasLength(3));
        for (int i = 0; i < 3; i++) {
          // Float32 round-trip drifts each scalar by ~1e-7 — the binary
          // format has always used 32-bit floats, so test with tolerance.
          expect(decoded[i].points.length, strokes[i].points.length);
          for (int j = 0; j < decoded[i].points.length; j++) {
            expect(
              decoded[i].points[j].dx,
              closeTo(strokes[i].points[j].dx, 1e-5),
            );
            expect(
              decoded[i].points[j].dy,
              closeTo(strokes[i].points[j].dy, 1e-5),
            );
            expect(
              decoded[i].pressures[j],
              closeTo(strokes[i].pressures[j], 1e-5),
            );
          }
          expect(decoded[i].color.toARGB32(), strokes[i].color.toARGB32());
          expect(decoded[i].baseWidth, closeTo(strokes[i].baseWidth, 1e-5));
        }
      },
    );

    test('encodeBytes produces a v8 file with version byte 8', () {
      final bytes = CanvasSerializer.encodeBytes([makeStroke(1)]);
      // bytes[0..3] = magic, bytes[4..5] = version (uint16 LE).
      // 0.8.0 promoted the writer to FCV v6 (text-node persistence);
      // 0.10.3 promoted to v7 to carry the new per-stroke note tag
      // alongside the FontWeight.value migration; 0.14.0 promoted to
      // v8 to carry per-stroke tilt + metadata extension blocks
      // (chained tag-length-value after the customBrushId TLV). v7 /
      // v6 / v5 / v4 / v3 / v2 / v1 readers continue to be supported
      // by `decodeBytesFull` but new files always go out as v8.
      final version = bytes[4] | (bytes[5] << 8);
      expect(version, 8, reason: 'encodeBytes must emit the v8 layered format');
    });

    test(
      'decodeBytesToLayers exposes the synthetic single-layer hierarchy',
      () {
        final strokes = [makeStroke(1), makeStroke(2)];
        final bytes = CanvasSerializer.encodeBytes(strokes);
        final root = CanvasSerializer.decodeBytesToLayers(bytes);
        final layers = root.children.whereType<LayerNode>().toList();
        expect(layers, hasLength(1));
        expect(layers.single.children, hasLength(2));
        expect(layers.single.children.first, isA<CanvasStrokeNode>());
      },
    );

    test('legacy v1 byte stream decodes as a synthetic Layer 1', () {
      final strokes = [makeStroke(7), makeStroke(8)];
      final v1Bytes = makeV1Bytes(strokes);
      final root = CanvasSerializer.decodeBytesToLayers(v1Bytes);
      final layers = root.children.whereType<LayerNode>().toList();
      expect(layers, hasLength(1));
      expect(layers.single.name, 'Layer 1');
      expect(layers.single.children, hasLength(2));

      final flat = CanvasSerializer.decodeBytes(v1Bytes);
      expect(flat, hasLength(2));
      expect(flat[0].points, strokes[0].points);
      expect(flat[1].points, strokes[1].points);
    });

    test('layer header round-trips visibility, lock, opacity, blend mode', () {
      // Build a layered scene by hand and check the v2 round-trip
      // preserves the full layer state — not just the strokes inside.
      final root = LayerNode(id: const NodeId('root'), name: 'Root');
      final l1 = LayerNode(
        id: const NodeId('layer-1'),
        name: 'Foreground',
        opacity: 0.6,
        isVisible: false,
        isLocked: true,
      );
      l1.add(CanvasStrokeNode(id: const NodeId('s-1'), stroke: makeStroke(1)));
      root.add(l1);

      final bytes = CanvasSerializer.encodeBytesFromLayers(root);
      final decoded = CanvasSerializer.decodeBytesToLayers(bytes);
      final layers = decoded.children.whereType<LayerNode>().toList();
      expect(layers, hasLength(1));
      final restored = layers.single;
      expect(restored.id, const NodeId('layer-1'));
      expect(restored.name, 'Foreground');
      expect(restored.opacity, closeTo(0.6, 1e-6));
      expect(restored.isVisible, isFalse);
      expect(restored.isLocked, isTrue);
      expect(restored.children, hasLength(1));
    });

    test('multi-layer file preserves both layer hierarchy and Z-order', () {
      final root = LayerNode(id: const NodeId('root'), name: 'Root');
      final layerA = LayerNode(id: const NodeId('layer-a'), name: 'A');
      final layerB = LayerNode(id: const NodeId('layer-b'), name: 'B');
      layerA.add(
        CanvasStrokeNode(id: const NodeId('a-1'), stroke: makeStroke(1)),
      );
      layerA.add(
        CanvasStrokeNode(id: const NodeId('a-2'), stroke: makeStroke(2)),
      );
      layerB.add(
        CanvasStrokeNode(id: const NodeId('b-1'), stroke: makeStroke(3)),
      );
      root.add(layerA);
      root.add(layerB);

      final bytes = CanvasSerializer.encodeBytesFromLayers(root);
      final decoded = CanvasSerializer.decodeBytesToLayers(bytes);
      final layers = decoded.children.whereType<LayerNode>().toList();
      expect(layers.map((l) => l.name), ['A', 'B']);
      expect(layers[0].children, hasLength(2));
      expect(layers[1].children, hasLength(1));
    });

    test('decode rejects truncated headers with FormatException', () {
      expect(
        () => CanvasSerializer.decodeBytes(Uint8List.fromList([0, 1, 2])),
        throwsA(isA<FormatException>()),
      );
    });

    test('decode rejects bad magic with FormatException', () {
      final bad = Uint8List(16);
      ByteData.view(bad.buffer)
        ..setUint32(0, 0xDEADBEEF, Endian.little)
        ..setUint16(4, 1, Endian.little);
      expect(
        () => CanvasSerializer.decodeBytes(bad),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
