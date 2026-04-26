// ════════════════════════════════════════════════════════════════════════════
// CanvasSerializer — save/load the canvas as JSON or compact bytes.
//
// 0.6.0 introduces FCV0 v2: a layered binary format that mirrors the
// scene graph (`LayerNode` -> `CanvasStrokeNode`s) so a saved file
// round-trips not just strokes but layers (id, name, opacity, blend
// mode, visibility, lock state). `decodeBytes` still accepts FCV0 v1
// files transparently — they decode as a single synthetic layer.
//
// ── Binary v2 layout (little-endian) ──────────────────────────────────────
//   magic        : 'FCV0'        (4 bytes)
//   version      : uint16 = 2     (2 bytes)
//   layerCount   : uint32         (4 bytes)
//   per layer:
//       idLen      : uint16
//       id         : utf8 bytes
//       nameLen    : uint16
//       name       : utf8 bytes
//       flags      : uint8        (bit0 = isVisible, bit1 = isLocked)
//       opacity    : float32
//       blendMode  : uint8        (index into ui.BlendMode.values)
//       childCount : uint32
//       per child:
//           nodeType : uint8      (0 = canvas_stroke; reserved 1-15 for
//                                  text/image/shape which arrive in
//                                  Phases B-D)
//           — for nodeType=0 (canvas_stroke), v1-compatible stroke layout —
//           pointCount : uint32
//           color      : uint32 ARGB
//           baseWidth  : float32
//           xs/ys/prs  : float32[pointCount × 3]
//
// ── Binary v1 layout (legacy, still readable) ─────────────────────────────
//   magic    : 'FCV0'
//   version  : uint16 = 1
//   strokes  : uint32
//   per stroke: pointCount uint32, color uint32, baseWidth float32,
//               xs/ys/prs float32[pointCount × 3]
// ══════════════════════════════════════════════════════════════════════════

import 'dart:convert' show jsonDecode, jsonEncode, utf8;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Color, Offset;

import '../core/nodes/canvas_stroke_node.dart';
import '../core/nodes/layer_node.dart';
import '../core/scene_graph/node_id.dart';
import '../utils/uid.dart' show generateUid;
import 'fluera_canvas_widget.dart';

/// JSON / binary codec for the [FlueraCanvas] scene state.
///
/// `encodeBytes` and `decodeBytes` operate on the flat strokes list to
/// preserve the 0.5.0 entry points used by `toBytes` / `loadFromBytes`.
/// The new layer-aware entry points, `encodeBytesFromLayers` and
/// `decodeBytesToLayers`, expose the scene-graph payload directly so
/// future multi-layer save / restore flows have a stable surface.
class CanvasSerializer {
  CanvasSerializer._();

  // Binary constants.
  static const int _magic = 0x30564346; // 'FCV0' little-endian
  static const int _versionV1 = 1;
  static const int _versionV2 = 2;
  static const int _versionLatest = _versionV2;

  // ── Binary (flat strokes API — kept for 0.5.0 compatibility) ──────────

  /// Encode [strokes] as a compact little-endian byte array. The output
  /// is a v2 file with a single synthetic layer named "Layer 1" — the
  /// equivalent of saving a single-layer canvas.
  static Uint8List encodeBytes(List<CanvasStroke> strokes) {
    final layer = LayerNode(id: NodeId(generateUid()), name: 'Layer 1');
    for (final s in strokes) {
      layer.add(CanvasStrokeNode(id: NodeId(generateUid()), stroke: s));
    }
    final root = LayerNode(id: NodeId(generateUid()), name: 'Root');
    root.add(layer);
    return encodeBytesFromLayers(root);
  }

  /// Decode a byte array produced by [encodeBytes] (or any prior
  /// version). Returns a flat list of strokes across all layers. Throws
  /// [FormatException] on corrupt data or unsupported version.
  static List<CanvasStroke> decodeBytes(Uint8List bytes) {
    final root = decodeBytesToLayers(bytes);
    final out = <CanvasStroke>[];
    for (final layer in root.children.whereType<LayerNode>()) {
      for (final node in layer.children.whereType<CanvasStrokeNode>()) {
        out.add(node.stroke);
      }
    }
    return out;
  }

  // ── Binary (layer-aware API — 0.6.0+) ─────────────────────────────────

  /// Encode the full scene graph rooted at [root] as a v2 byte array.
  /// Children that are not `CanvasStrokeNode` (text / image / shape —
  /// not yet writable in 0.6.0 Phase A) are silently skipped; future
  /// phases extend the writer to cover them.
  static Uint8List encodeBytesFromLayers(LayerNode root) {
    // First pass: precompute size so we can allocate the buffer once.
    int size = 4 + 2 + 4; // magic + version + layerCount
    final layers =
        root.children.whereType<LayerNode>().toList(growable: false);
    for (final layer in layers) {
      size += _layerHeaderByteSize(layer);
      size += 4; // childCount
      for (final c in layer.children) {
        if (c is CanvasStrokeNode) {
          size += 1 + _strokePayloadByteSize(c.stroke);
        }
        // Other node types skipped in v2 Phase A.
      }
    }

    final buf = ByteData(size);
    int off = 0;

    buf.setUint32(off, _magic, Endian.little);
    off += 4;
    buf.setUint16(off, _versionV2, Endian.little);
    off += 2;
    buf.setUint32(off, layers.length, Endian.little);
    off += 4;

    for (final layer in layers) {
      off = _writeLayerHeader(buf, off, layer);
      // Count writable children only (CanvasStrokeNodes for now).
      int childCount = 0;
      for (final c in layer.children) {
        if (c is CanvasStrokeNode) childCount++;
      }
      buf.setUint32(off, childCount, Endian.little);
      off += 4;

      for (final c in layer.children) {
        if (c is CanvasStrokeNode) {
          buf.setUint8(off, 0); // nodeType: canvas_stroke
          off += 1;
          off = _writeStrokePayload(buf, off, c.stroke);
        }
      }
    }

    return buf.buffer.asUint8List();
  }

  /// Decode a byte array (v1 or v2) into a fresh `LayerNode` root with
  /// the original layer hierarchy. v1 files are surfaced as a single
  /// "Layer 1" so legacy consumers don't observe a difference.
  static LayerNode decodeBytesToLayers(Uint8List bytes) {
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
    if (version > _versionLatest) {
      throw FormatException(
        'Canvas format version $version is newer than supported $_versionLatest.',
      );
    }

    final root = LayerNode(id: NodeId(generateUid()), name: 'Root');

    if (version == _versionV1) {
      // Legacy single-flat-list. Wrap in one synthetic layer so the
      // scene graph shape is always layer/stroke even for old files.
      final layer = LayerNode(id: NodeId(generateUid()), name: 'Layer 1');
      final strokeCount = buf.getUint32(off, Endian.little);
      off += 4;
      for (int s = 0; s < strokeCount; s++) {
        final result = _readStrokePayload(buf, off);
        layer.add(
          CanvasStrokeNode(id: NodeId(generateUid()), stroke: result.stroke),
        );
        off = result.endOffset;
      }
      root.add(layer);
      return root;
    }

    // v2 layered.
    final layerCount = buf.getUint32(off, Endian.little);
    off += 4;
    for (int li = 0; li < layerCount; li++) {
      final layerResult = _readLayerHeader(buf, off);
      off = layerResult.endOffset;
      final layer = layerResult.layer;
      final childCount = buf.getUint32(off, Endian.little);
      off += 4;
      for (int ci = 0; ci < childCount; ci++) {
        final nodeType = buf.getUint8(off);
        off += 1;
        switch (nodeType) {
          case 0:
            final result = _readStrokePayload(buf, off);
            layer.add(
              CanvasStrokeNode(
                id: NodeId(generateUid()),
                stroke: result.stroke,
              ),
            );
            off = result.endOffset;
            break;
          default:
            throw FormatException(
              'Unsupported child nodeType $nodeType at byte offset ${off - 1}',
            );
        }
      }
      root.add(layer);
    }
    return root;
  }

  // ── JSON ──────────────────────────────────────────────────────────────

  /// Encode [strokes] as a human-readable JSON string. Useful for debug
  /// and diff-friendly storage (git, REST APIs). ~10× larger than the
  /// binary form. Format pinned to v1 for backward compatibility — the
  /// JSON shape is unchanged from 0.5.0.
  static String encodeJson(List<CanvasStroke> strokes) {
    return jsonEncode({
      'v': _versionV1,
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

  // ── Layer header ──────────────────────────────────────────────────────

  static int _layerHeaderByteSize(LayerNode layer) {
    final idBytes = utf8.encode(layer.id);
    final nameBytes = utf8.encode(layer.name);
    return 2 +
        idBytes.length +
        2 +
        nameBytes.length +
        1 + // flags
        4 + // opacity
        1; // blendMode
  }

  static int _writeLayerHeader(ByteData buf, int off, LayerNode layer) {
    final idBytes = utf8.encode(layer.id);
    final nameBytes = utf8.encode(layer.name);
    buf.setUint16(off, idBytes.length, Endian.little);
    off += 2;
    for (int i = 0; i < idBytes.length; i++) {
      buf.setUint8(off + i, idBytes[i]);
    }
    off += idBytes.length;
    buf.setUint16(off, nameBytes.length, Endian.little);
    off += 2;
    for (int i = 0; i < nameBytes.length; i++) {
      buf.setUint8(off + i, nameBytes[i]);
    }
    off += nameBytes.length;

    int flags = 0;
    if (layer.isVisible) flags |= 0x01;
    if (layer.isLocked) flags |= 0x02;
    buf.setUint8(off, flags);
    off += 1;
    buf.setFloat32(off, layer.opacity, Endian.little);
    off += 4;
    buf.setUint8(off, layer.blendMode.index);
    off += 1;
    return off;
  }

  static _LayerHeaderResult _readLayerHeader(ByteData buf, int off) {
    final idLen = buf.getUint16(off, Endian.little);
    off += 2;
    final idBytes = Uint8List(idLen);
    for (int i = 0; i < idLen; i++) {
      idBytes[i] = buf.getUint8(off + i);
    }
    off += idLen;
    final id = utf8.decode(idBytes);

    final nameLen = buf.getUint16(off, Endian.little);
    off += 2;
    final nameBytes = Uint8List(nameLen);
    for (int i = 0; i < nameLen; i++) {
      nameBytes[i] = buf.getUint8(off + i);
    }
    off += nameLen;
    final name = utf8.decode(nameBytes);

    final flags = buf.getUint8(off);
    off += 1;
    final opacity = buf.getFloat32(off, Endian.little);
    off += 4;
    final blendModeIdx = buf.getUint8(off);
    off += 1;

    final blendMode = blendModeIdx >= 0 &&
            blendModeIdx < ui.BlendMode.values.length
        ? ui.BlendMode.values[blendModeIdx]
        : ui.BlendMode.srcOver;

    final layer = LayerNode(
      id: NodeId(id),
      name: name,
      opacity: opacity,
      blendMode: blendMode,
      isVisible: (flags & 0x01) != 0,
      isLocked: (flags & 0x02) != 0,
    );
    return _LayerHeaderResult(layer, off);
  }

  // ── Stroke payload (v1-compatible) ────────────────────────────────────

  static int _strokePayloadByteSize(CanvasStroke s) {
    return 4 + 4 + 4 + s.points.length * 4 * 3;
  }

  static int _writeStrokePayload(ByteData buf, int off, CanvasStroke s) {
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
    return off;
  }

  static _StrokePayloadResult _readStrokePayload(ByteData buf, int off) {
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
    return _StrokePayloadResult(
      CanvasStroke(
        points: List<Offset>.unmodifiable(points),
        pressures: List<double>.unmodifiable(pressures),
        color: color,
        baseWidth: width,
      ),
      off,
    );
  }

  // ── JSON helpers (v1, stable) ─────────────────────────────────────────

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

class _LayerHeaderResult {
  _LayerHeaderResult(this.layer, this.endOffset);
  final LayerNode layer;
  final int endOffset;
}

class _StrokePayloadResult {
  _StrokePayloadResult(this.stroke, this.endOffset);
  final CanvasStroke stroke;
  final int endOffset;
}
