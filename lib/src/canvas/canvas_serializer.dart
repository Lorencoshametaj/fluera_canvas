// ════════════════════════════════════════════════════════════════════════════
// CanvasSerializer — save/load the flat stroke list as JSON or bytes.
//
// The binary format is intentionally simple (no dependencies beyond
// `dart:typed_data`) so a consumer can persist / sync / diff canvases with
// zero ceremony. Strokes-only — for full scene graph (layers, groups,
// text, images, vector paths) use `fluera_engine` or the .fluera file
// format.
//
// ── Binary layout (little-endian) ─────────────────────────────────────────
//   magic    : 'FCV0'            (4 bytes)
//   version  : uint16              (2 bytes)
//   strokes  : uint32              (4 bytes)
//   [per stroke, strokes times]
//       points     : uint32         (4 bytes)
//       color      : uint32 ARGB    (4 bytes)
//       baseWidth  : float32        (4 bytes)
//       xs/ys/prs  : float32[points × 3]
// ══════════════════════════════════════════════════════════════════════════

import 'dart:convert' show jsonDecode, jsonEncode;
import 'dart:typed_data';
import 'dart:ui' show Color, Offset;

import 'fluera_canvas_widget.dart';

/// JSON / binary codec for the flat `List<CanvasStroke>` state of a
/// [FlueraCanvas]. All methods are pure (no I/O) — persist the returned
/// bytes / string with the storage of your choice (files, Hive, SQLite,
/// a REST endpoint, …).
class CanvasSerializer {
  CanvasSerializer._();

  // Binary constants.
  static const int _magic = 0x30564346; // 'FCV0' little-endian
  static const int _version = 1;

  // ── Binary ────────────────────────────────────────────────────────────

  /// Encode [strokes] as a compact little-endian byte array.
  static Uint8List encodeBytes(List<CanvasStroke> strokes) {
    int totalPoints = 0;
    for (final s in strokes) {
      totalPoints += s.points.length;
    }
    final headerBytes = 4 + 2 + 4;
    final perStrokeHeader = 4 + 4 + 4;
    final totalBytes =
        headerBytes + strokes.length * perStrokeHeader + totalPoints * 4 * 3;
    final buf = ByteData(totalBytes);
    int off = 0;
    buf.setUint32(off, _magic, Endian.little);
    off += 4;
    buf.setUint16(off, _version, Endian.little);
    off += 2;
    buf.setUint32(off, strokes.length, Endian.little);
    off += 4;
    for (final s in strokes) {
      final n = s.points.length;
      buf.setUint32(off, n, Endian.little);
      off += 4;
      buf.setUint32(off, s.color.toARGB32(), Endian.little);
      off += 4;
      buf.setFloat32(off, s.baseWidth, Endian.little);
      off += 4;
      for (int i = 0; i < n; i++) {
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

  /// Decode a byte array produced by [encodeBytes]. Throws
  /// [FormatException] on corrupt data or unsupported version.
  static List<CanvasStroke> decodeBytes(Uint8List bytes) {
    if (bytes.lengthInBytes < 10) {
      throw const FormatException('Canvas byte stream too short.');
    }
    final buf = bytes.buffer.asByteData(
      bytes.offsetInBytes,
      bytes.lengthInBytes,
    );
    int off = 0;
    final magic = buf.getUint32(off, Endian.little);
    off += 4;
    if (magic != _magic) {
      throw const FormatException('Bad magic header (expected FCV0).');
    }
    final version = buf.getUint16(off, Endian.little);
    off += 2;
    if (version > _version) {
      throw FormatException(
        'Canvas format version $version is newer than supported $_version.',
      );
    }
    final strokeCount = buf.getUint32(off, Endian.little);
    off += 4;
    final out = <CanvasStroke>[];
    for (int s = 0; s < strokeCount; s++) {
      final n = buf.getUint32(off, Endian.little);
      off += 4;
      final color = Color(buf.getUint32(off, Endian.little));
      off += 4;
      final width = buf.getFloat32(off, Endian.little);
      off += 4;
      final points = List<Offset>.filled(n, Offset.zero);
      final pressures = List<double>.filled(n, 0);
      for (int i = 0; i < n; i++) {
        final x = buf.getFloat32(off, Endian.little);
        off += 4;
        final y = buf.getFloat32(off, Endian.little);
        off += 4;
        final p = buf.getFloat32(off, Endian.little);
        off += 4;
        points[i] = Offset(x, y);
        pressures[i] = p;
      }
      out.add(
        CanvasStroke(
          points: List<Offset>.unmodifiable(points),
          pressures: List<double>.unmodifiable(pressures),
          color: color,
          baseWidth: width,
        ),
      );
    }
    return out;
  }

  // ── JSON ──────────────────────────────────────────────────────────────

  /// Encode [strokes] as a human-readable JSON string. Useful for debug
  /// and diff-friendly storage (git, REST APIs). ~10× larger than the
  /// binary form.
  static String encodeJson(List<CanvasStroke> strokes) {
    return jsonEncode({
      'v': _version,
      'strokes': strokes.map(_strokeToJson).toList(),
    });
  }

  /// Decode a JSON string produced by [encodeJson]. Throws
  /// [FormatException] on malformed input.
  static List<CanvasStroke> decodeJson(String source) {
    final root = jsonDecode(source);
    if (root is! Map) {
      throw const FormatException('Root must be a JSON object.');
    }
    final raw = root['strokes'];
    if (raw is! List) {
      throw const FormatException('Missing "strokes" array.');
    }
    return raw.cast<Map>().map(_strokeFromJson).toList();
  }

  static Map<String, dynamic> _strokeToJson(CanvasStroke s) {
    final xs = List<double>.filled(s.points.length, 0);
    final ys = List<double>.filled(s.points.length, 0);
    for (int i = 0; i < s.points.length; i++) {
      xs[i] = s.points[i].dx;
      ys[i] = s.points[i].dy;
    }
    return {
      'x': xs,
      'y': ys,
      'p': s.pressures,
      'c': s.color.toARGB32(),
      'w': s.baseWidth,
    };
  }

  static CanvasStroke _strokeFromJson(Map map) {
    final xs = (map['x'] as List).cast<num>();
    final ys = (map['y'] as List).cast<num>();
    final ps = (map['p'] as List).cast<num>();
    if (xs.length != ys.length || xs.length != ps.length) {
      throw const FormatException('Stroke arrays length mismatch.');
    }
    final points = <Offset>[
      for (int i = 0; i < xs.length; i++)
        Offset(xs[i].toDouble(), ys[i].toDouble()),
    ];
    return CanvasStroke(
      points: List<Offset>.unmodifiable(points),
      pressures: List<double>.unmodifiable(ps.map((e) => e.toDouble())),
      color: Color((map['c'] as num).toInt()),
      baseWidth: (map['w'] as num).toDouble(),
    );
  }
}
