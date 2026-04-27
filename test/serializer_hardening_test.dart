/// FCV0 reader hardening tests — every uint16 / uint32 length field is
/// now validated against the remaining buffer to reject malformed or
/// hostile files (truncated payload, allocation-bomb headers).
///
/// Each case crafts a minimal binary header that triggers exactly one
/// of the bounds checks introduced in 0.9.3 and asserts the reader
/// throws `FormatException` cleanly instead of crashing on OOM / OOB.
library;

import 'dart:typed_data';

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // FCV0 magic bytes, little-endian: 'F','C','V','0' → 0x30564346.
  void writeMagic(ByteData buf, int off) =>
      buf.setUint32(off, 0x30564346, Endian.little);

  group('CanvasSerializer hardening', () {
    test('rejects implausible layerCount (> 10000)', () {
      final buf = ByteData(64);
      writeMagic(buf, 0);
      buf.setUint16(4, 4, Endian.little); // version
      buf.setUint32(6, 0xFFFFFFFF, Endian.little); // 4 B layers — bomb
      expect(
        () => CanvasSerializer.decodeBytesFull(buf.buffer.asUint8List()),
        throwsFormatException,
      );
    });

    test('rejects pointCount that overflows the remaining buffer', () {
      // Build the smallest possible v3 file with 1 layer + 1 stroke,
      // then poison the pointCount field. Layer header layout:
      //   idLen u16, id bytes, nameLen u16, name bytes,
      //   flags u8 (visible|locked), opacity f32, blendMode u8,
      //   extBlendCode i32 (v3+), childCount u32.
      // Stroke payload layout: nodeType u8 + pointCount u32 + ...
      final buf = ByteData(256);
      var off = 0;
      writeMagic(buf, off); off += 4;
      buf.setUint16(off, 3, Endian.little); off += 2; // version 3
      buf.setUint32(off, 1, Endian.little); off += 4; // 1 layer
      buf.setUint16(off, 1, Endian.little); off += 2; // idLen=1
      buf.setUint8(off, 0x61); off += 1;              // id 'a'
      buf.setUint16(off, 1, Endian.little); off += 2; // nameLen=1
      buf.setUint8(off, 0x61); off += 1;              // name 'a'
      buf.setUint8(off, 0x01); off += 1;              // flags=visible
      buf.setFloat32(off, 1.0, Endian.little); off += 4; // opacity
      buf.setUint8(off, 0); off += 1;                 // blendMode u8
      buf.setInt32(off, 0, Endian.little); off += 4;  // extBlendCode v3
      buf.setUint32(off, 1, Endian.little); off += 4; // childCount=1
      buf.setUint8(off, 0); off += 1;                 // nodeType=stroke
      // Poison: pointCount = 0xFFFFFFFF → 16 GB attempted alloc.
      buf.setUint32(off, 0xFFFFFFFF, Endian.little);
      expect(
        () => CanvasSerializer.decodeBytesFull(buf.buffer.asUint8List()),
        throwsFormatException,
      );
    });

    test('rejects layer.idLen exceeding remaining buffer', () {
      final buf = ByteData(32);
      var off = 0;
      writeMagic(buf, off); off += 4;
      buf.setUint16(off, 3, Endian.little); off += 2;
      buf.setUint32(off, 1, Endian.little); off += 4;
      // Poison idLen = 0xFFFF (65 535) on a tiny buffer.
      buf.setUint16(off, 0xFFFF, Endian.little);
      expect(
        () => CanvasSerializer.decodeBytesFull(buf.buffer.asUint8List()),
        throwsFormatException,
      );
    });

    test('rejects garbage magic bytes', () {
      final buf = ByteData(16);
      buf.setUint32(0, 0xDEADBEEF, Endian.little);
      expect(
        () => CanvasSerializer.decodeBytesFull(buf.buffer.asUint8List()),
        throwsFormatException,
      );
    });

    test('rejects future version > supported', () {
      final buf = ByteData(16);
      writeMagic(buf, 0);
      buf.setUint16(4, 99, Endian.little); // v99
      expect(
        () => CanvasSerializer.decodeBytesFull(buf.buffer.asUint8List()),
        throwsFormatException,
      );
    });
  });
}
