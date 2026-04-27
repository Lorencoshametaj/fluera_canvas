// Tests for FCV0 v3 — extended-blend-mode side-table round-trip + v2 / v1
// backward-read.
//
// V3 adds a per-layer `extBlendCode: int32` slot that carries the
// `FlueraBlendMode.code` for the 9 Photoshop-grade extended modes the
// commercial GPU compositor handles. v2 / v1 readers must continue to
// decode without a code (treated as "no extended mode").

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' show Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

void main() {
  group('CanvasSerializer FCV0 v3', () {
    test(
      'encodeBytesFromLayers + decodeBytesFull round-trip standard mode',
      () {
        final root = LayerNode(id: NodeId('root'), name: 'Root');
        final layer = LayerNode(
          id: NodeId('L1'),
          name: 'Pencil',
          opacity: 0.7,
          blendMode: ui.BlendMode.multiply,
        );
        layer.add(
          CanvasStrokeNode(
            id: NodeId('S1'),
            stroke: CanvasStroke(
              points: const [Offset(0, 0), Offset(10, 10)],
              pressures: const [0.5, 0.9],
              color: const ui.Color(0xFFAB12CD),
              baseWidth: 4.5,
            ),
          ),
        );
        root.add(layer);

        final bytes = CanvasSerializer.encodeBytesFromLayers(root);
        final result = CanvasSerializer.decodeBytesFull(bytes);

        expect(
          result.extendedCodes,
          isEmpty,
          reason: 'standard blend modes should not populate the side-table',
        );
        final decodedLayers =
            result.root.children.whereType<LayerNode>().toList();
        expect(decodedLayers, hasLength(1));
        expect(decodedLayers.first.id.value, 'L1');
        expect(decodedLayers.first.name, 'Pencil');
        expect(decodedLayers.first.opacity, closeTo(0.7, 1e-6));
        expect(decodedLayers.first.blendMode, ui.BlendMode.multiply);
        final strokeNodes =
            decodedLayers.first.children.whereType<CanvasStrokeNode>().toList();
        expect(strokeNodes, hasLength(1));
        expect(strokeNodes.first.stroke.color.toARGB32(), 0xFFAB12CD);
      },
    );

    test(
      'encodeBytesFromLayers + decodeBytesFull round-trip extended mode',
      () {
        final root = LayerNode(id: NodeId('root'), name: 'Root');
        final l1 = LayerNode(id: NodeId('L1'), name: 'Bg');
        final l2 = LayerNode(
          id: NodeId('L2'),
          name: 'Linear Burn FX',
          // Underlying blendMode kept on the closest standard so the
          // file decodes sensibly even when no GPU compositor is wired.
          blendMode: ui.BlendMode.multiply,
        );
        root.add(l1);
        root.add(l2);

        final ext = <NodeId, FlueraBlendMode>{
          l2.id: FlueraBlendMode.linearBurn,
        };

        final bytes = CanvasSerializer.encodeBytesFromLayers(
          root,
          extendedCodes: ext,
        );
        final decoded = CanvasSerializer.decodeBytesFull(bytes);

        // Side-table should contain exactly the one extended layer.
        expect(decoded.extendedCodes, hasLength(1));
        expect(decoded.extendedCodes[NodeId('L2')], FlueraBlendMode.linearBurn);
        // The standard-mode layer should NOT appear in the side-table.
        expect(decoded.extendedCodes[NodeId('L1')], isNull);
      },
    );

    test('decodeBytesFull on v2 file yields empty extendedCodes', () {
      // Synthesize a v2 file by hand: magic + version=2 + 1 layer with
      // 0 strokes. v2 layout: idLen + id + nameLen + name + flags +
      // opacity(f32) + blendMode(u8) + childCount(u32). No
      // extBlendCode field.
      final bb = BytesBuilder();
      void u32(int v) {
        final b = ByteData(4)..setUint32(0, v, Endian.little);
        bb.add(b.buffer.asUint8List());
      }

      void u16(int v) {
        final b = ByteData(2)..setUint16(0, v, Endian.little);
        bb.add(b.buffer.asUint8List());
      }

      void u8(int v) => bb.addByte(v);
      void f32(double v) {
        final b = ByteData(4)..setFloat32(0, v, Endian.little);
        bb.add(b.buffer.asUint8List());
      }

      u32(0x30564346); // 'FCV0' little-endian
      u16(2); // version v2
      u32(1); // layerCount
      // Layer header (v2): id="L1", name="Layer 1", flags=1 (visible),
      // opacity=1.0, blendMode=srcOver (index 3).
      u16(2);
      bb.add('L1'.codeUnits);
      u16(7);
      bb.add('Layer 1'.codeUnits);
      u8(0x01);
      f32(1.0);
      u8(ui.BlendMode.srcOver.index);
      u32(0); // childCount = 0

      final bytes = bb.toBytes();
      final decoded = CanvasSerializer.decodeBytesFull(bytes);
      expect(decoded.extendedCodes, isEmpty);
      final layers = decoded.root.children.whereType<LayerNode>().toList();
      expect(layers, hasLength(1));
      expect(layers.first.name, 'Layer 1');
      expect(layers.first.blendMode, ui.BlendMode.srcOver);
    });

    test('decodeBytesFull on v1 file surfaces a single synthetic layer', () {
      // v1: magic + version=1 + strokeCount=0.
      final bb = BytesBuilder();
      void u32(int v) {
        final b = ByteData(4)..setUint32(0, v, Endian.little);
        bb.add(b.buffer.asUint8List());
      }

      void u16(int v) {
        final b = ByteData(2)..setUint16(0, v, Endian.little);
        bb.add(b.buffer.asUint8List());
      }

      u32(0x30564346);
      u16(1);
      u32(0);

      final bytes = bb.toBytes();
      final decoded = CanvasSerializer.decodeBytesFull(bytes);
      expect(decoded.extendedCodes, isEmpty);
      final layers = decoded.root.children.whereType<LayerNode>().toList();
      expect(layers, hasLength(1));
      expect(layers.first.name, 'Layer 1');
    });

    test('decodeBytesFull rejects unknown future versions', () {
      // version=99
      final bb = BytesBuilder();
      void u32(int v) {
        final b = ByteData(4)..setUint32(0, v, Endian.little);
        bb.add(b.buffer.asUint8List());
      }

      void u16(int v) {
        final b = ByteData(2)..setUint16(0, v, Endian.little);
        bb.add(b.buffer.asUint8List());
      }

      u32(0x30564346);
      u16(99);
      u32(0);

      expect(
        () => CanvasSerializer.decodeBytesFull(bb.toBytes()),
        throwsFormatException,
      );
    });

    test('extended code outside the 100..108 range is dropped silently', () {
      // Forge a v3 file with an unknown extBlendCode (e.g. 200) so we
      // confirm the decoder ignores it instead of crashing the load.
      final bb = BytesBuilder();
      void u32(int v) {
        final b = ByteData(4)..setUint32(0, v, Endian.little);
        bb.add(b.buffer.asUint8List());
      }

      void i32(int v) {
        final b = ByteData(4)..setInt32(0, v, Endian.little);
        bb.add(b.buffer.asUint8List());
      }

      void u16(int v) {
        final b = ByteData(2)..setUint16(0, v, Endian.little);
        bb.add(b.buffer.asUint8List());
      }

      void u8(int v) => bb.addByte(v);
      void f32(double v) {
        final b = ByteData(4)..setFloat32(0, v, Endian.little);
        bb.add(b.buffer.asUint8List());
      }

      u32(0x30564346);
      u16(3); // v3
      u32(1); // 1 layer
      u16(2);
      bb.add('LX'.codeUnits);
      u16(0); // empty name
      u8(0x01); // flags: visible
      f32(1.0);
      u8(ui.BlendMode.srcOver.index);
      i32(200); // unknown extBlendCode
      u32(0); // 0 children

      final decoded = CanvasSerializer.decodeBytesFull(bb.toBytes());
      // Unknown code should NOT register a side-table entry — the
      // decoder rejects anything that isn't a recognised
      // FlueraBlendMode.isExtended value.
      expect(decoded.extendedCodes, isEmpty);
    });
  });
}
