// ════════════════════════════════════════════════════════════════════════════
// CanvasSerializer — save/load the canvas as JSON or compact bytes.
//
// 0.6.0 introduces FCV0 v2: a layered binary format that mirrors the
// scene graph (`LayerNode` -> `CanvasStrokeNode`s) so a saved file
// round-trips not just strokes but layers (id, name, opacity, blend
// mode, visibility, lock state).
//
// 0.6.1 bumps the format to v3, adding per-layer extended blend mode
// codes (the 9 Photoshop-grade modes that `ui.BlendMode` cannot
// express — see `FlueraBlendMode`). v2 files decode transparently
// (extBlendCode defaults to 0 = none); v1 files still decode as a
// single synthetic layer.
//
// 0.7.1 bumps the format to v4, adding a new child nodeType `2` for
// `ImageNode` so canvases that imported images via `FlueraImageTool`
// now persist them. v3 readers still throw on type=2 (forward-incompat
// is the desired behaviour — host app needs the matching writer).
//
// ── Binary v4 layout (little-endian) ──────────────────────────────────────
//   magic        : 'FCV0'        (4 bytes)
//   version      : uint16 = 4     (2 bytes)
//   layerCount   : uint32         (4 bytes)
//   per layer:
//       idLen        : uint16
//       id           : utf8 bytes
//       nameLen      : uint16
//       name         : utf8 bytes
//       flags        : uint8        (bit0 = isVisible, bit1 = isLocked)
//       opacity      : float32
//       blendMode    : uint8        (index into ui.BlendMode.values)
//       extBlendCode : int32        (0 = none, 100..108 =
//                                    FlueraBlendMode extended modes)
//       childCount   : uint32
//       per child:
//           nodeType : uint8        (0 = canvas_stroke;
//                                    2 = image (v4+);
//                                    reserved 1, 3-15)
//           — for nodeType=0, v1-compatible stroke layout —
//           pointCount : uint32
//           color      : uint32 ARGB
//           baseWidth  : float32
//           xs/ys/prs  : float32[pointCount × 3]
//           — for nodeType=2 (v4+), image payload —
//           nodeIdLen      : uint16
//           nodeId         : utf8 bytes (NodeId of the ImageNode)
//           imagePathLen   : uint16
//           imagePath      : utf8 bytes (cache key)
//           posX, posY     : float32 × 2 (ImageElement.position)
//           scale          : float32     (ImageElement.scale)
//           rotation       : float32     (ImageElement.rotation)
//           opacity        : float32     (ImageElement.opacity)
//           imgW, imgH     : float32 × 2 (ImageNode.imageSize)
//           flags          : uint8       (reserved, 0)
//           localTransform : float32 × 16 (Matrix4 storage)
//           bytesLen       : uint32
//           bytes          : uint8[bytesLen]   (PNG / JPG / WebP / …)
//
// ── Binary v3 layout (legacy, still readable) ─────────────────────────────
//   Same as v4 but child loop only handles nodeType=0; nodeType=2
//   throws `FormatException`.
//
// ── Binary v2 layout (legacy, still readable) ─────────────────────────────
//   Same as v3 but without the `extBlendCode` field per layer.
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
import 'dart:ui' show Color, Offset, Size;

import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../core/models/image_element.dart';
import '../core/models/digital_text_element.dart';
import '../core/nodes/canvas_stroke_node.dart';
import '../core/nodes/image_node.dart';
import '../core/nodes/layer_node.dart';
import '../core/nodes/text_node.dart';
import '../core/scene_graph/node_id.dart';
import '../rendering/canvas/image_node_painter.dart';
import '../utils/uid.dart' show generateUid;
import 'fluera_blend_mode.dart';
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
  static const int _versionV3 = 3;
  static const int _versionV4 = 4;
  static const int _versionV5 = 5;
  static const int _versionV6 = 6;
  static const int _versionLatest = _versionV6;

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

  /// Encode the full scene graph rooted at [root] as a v3 byte array.
  /// Children that are not `CanvasStrokeNode` (text / image / shape —
  /// not yet writable in 0.6.0 Phase A) are silently skipped; future
  /// phases extend the writer to cover them.
  ///
  /// [extendedCodes] is the canvas-state side-table mapping layer ids
  /// to Photoshop-grade extended blend modes. Pass `null` (or an empty
  /// map) when no layer is on an extended mode — the per-layer
  /// `extBlendCode` slot is written as 0 in that case. v3 readers
  /// re-hydrate the side-table from this field.
  static Uint8List encodeBytesFromLayers(
    LayerNode root, {
    Map<NodeId, FlueraBlendMode>? extendedCodes,
  }) {
    // ImageNodes whose source bytes were never registered with
    // [ImageNodePainter.cacheWithBytes] are skipped — we have no way
    // to round-trip them. Pre-compute the writable children per
    // layer so the size + write passes agree.
    bool hasBytes(ImageNode n) =>
        ImageNodePainter.bytesFor(n.imageElement.imagePath) != null;

    // First pass: precompute size so we can allocate the buffer once.
    int size = 4 + 2 + 4; // magic + version + layerCount
    final layers = root.children.whereType<LayerNode>().toList(growable: false);
    for (final layer in layers) {
      size += _layerHeaderByteSizeV3(layer);
      size += 4; // childCount
      for (final c in layer.children) {
        if (c is CanvasStrokeNode) {
          size += 1 + _strokePayloadByteSize(c.stroke);
        } else if (c is ImageNode && hasBytes(c)) {
          size += 1 + _imagePayloadByteSize(c);
        } else if (c is TextNode) {
          size += 1 + _textPayloadByteSize(c);
        }
      }
    }

    final buf = ByteData(size);
    int off = 0;

    buf.setUint32(off, _magic, Endian.little);
    off += 4;
    buf.setUint16(off, _versionV6, Endian.little);
    off += 2;
    buf.setUint32(off, layers.length, Endian.little);
    off += 4;

    for (final layer in layers) {
      final extMode = extendedCodes?[layer.id];
      // Side-table only stores extended choices; if the layer is on a
      // standard blend mode (or absent from the table) we write 0.
      final extCode =
          (extMode != null && extMode.isExtended) ? extMode.code : 0;
      off = _writeLayerHeaderV3(buf, off, layer, extCode);
      // Count writable children: strokes always, images only when their
      // source bytes are available.
      int childCount = 0;
      for (final c in layer.children) {
        if (c is CanvasStrokeNode) {
          childCount++;
        } else if (c is ImageNode && hasBytes(c)) {
          childCount++;
        } else if (c is TextNode) {
          childCount++;
        }
      }
      buf.setUint32(off, childCount, Endian.little);
      off += 4;

      for (final c in layer.children) {
        if (c is CanvasStrokeNode) {
          buf.setUint8(off, 0); // nodeType: canvas_stroke
          off += 1;
          off = _writeStrokePayload(buf, off, c.stroke);
        } else if (c is ImageNode && hasBytes(c)) {
          buf.setUint8(off, 2); // nodeType: image
          off += 1;
          off = _writeImagePayload(buf, off, c);
        } else if (c is TextNode) {
          buf.setUint8(off, 1); // nodeType: text
          off += 1;
          off = _writeTextPayload(buf, off, c);
        }
      }
    }

    return buf.buffer.asUint8List();
  }

  /// Decode a byte array (v1, v2 or v3) into a fresh `LayerNode` root
  /// with the original layer hierarchy. v1 files are surfaced as a
  /// single "Layer 1" so legacy consumers don't observe a difference.
  ///
  /// Extended-blend-mode codes (v3+ only) are silently discarded by
  /// this entry point. Use [decodeBytesFull] when you need to
  /// re-hydrate the canvas-state side-table for Photoshop-grade modes.
  static LayerNode decodeBytesToLayers(Uint8List bytes) {
    return decodeBytesFull(bytes).root;
  }

  /// Decode a byte array (v1, v2 or v3) into both the layer tree AND
  /// the extended-blend-mode side-table that pairs with it.
  ///
  /// For v3 files the side-table reflects whichever layers carried a
  /// Photoshop-grade extended mode at save time. For v1 / v2 files (and
  /// for v3 files where every layer was on a standard `ui.BlendMode`)
  /// the side-table is empty — the caller should leave its own
  /// `_extendedBlendModes` map empty after a load.
  static DecodeResult decodeBytesFull(Uint8List bytes) {
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
    final extendedCodes = <NodeId, FlueraBlendMode>{};
    final imageBlobs = <String, Uint8List>{};

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
      return DecodeResult(root, extendedCodes, imageBlobs);
    }

    // v2 / v3 / v4 layered.
    final layerCount = buf.getUint32(off, Endian.little);
    off += 4;
    // Sanity guard: a malformed or hostile file declaring billions of
    // layers would otherwise allocate / loop forever before tripping
    // on later parse errors. 10 000 is comfortably above any
    // legitimate use case (Notability tops out at ~50).
    if (layerCount > 10000) {
      throw FormatException(
        'fluera_canvas: file declares an implausible layer count '
        '($layerCount); refusing to allocate. File likely corrupt.',
      );
    }
    for (int li = 0; li < layerCount; li++) {
      final layerResult = _readLayerHeader(buf, off, version: version);
      off = layerResult.endOffset;
      final layer = layerResult.layer;
      // Re-hydrate side-table only when the file actually recorded an
      // extended code AND it maps to a known FlueraBlendMode value.
      // Unknown codes are ignored so a future-version writer that
      // introduces new modes doesn't crash old readers.
      if (layerResult.extBlendCode != 0) {
        final mode = FlueraBlendMode.fromCode(layerResult.extBlendCode);
        if (mode.isExtended) {
          extendedCodes[layer.id] = mode;
        }
      }
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
          case 1:
            // TextNodes are v6+. Reject early on older files so a
            // corrupt v5 stream doesn't silently mis-parse.
            if (version < _versionV6) {
              throw FormatException(
                'nodeType=1 (text) requires file version >= $_versionV6 '
                '(file version: $version) at byte offset ${off - 1}',
              );
            }
            final result = _readTextPayload(buf, off);
            layer.add(result.node);
            off = result.endOffset;
            break;
          case 2:
            // ImageNodes are v4+. Reject early on older files so a
            // corrupt v3 stream doesn't silently mis-parse.
            if (version < _versionV4) {
              throw FormatException(
                'nodeType=2 (image) requires file version >= $_versionV4 '
                '(file version: $version) at byte offset ${off - 1}',
              );
            }
            final result = _readImagePayload(buf, off, version: version);
            layer.add(result.node);
            imageBlobs[result.node.imageElement.imagePath] = result.bytes;
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
    return DecodeResult(root, extendedCodes, imageBlobs);
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
  //
  // V2 vs V3: V3 appends a 4-byte `extBlendCode` field after the
  // `blendMode` byte. We keep separate `_*V2` and `_*V3` helpers because
  // V2 readers must still tolerate older files in the wild (we never
  // re-write them — files are forward-promoted to V3 only on save).

  static int _layerHeaderByteSizeV3(LayerNode layer) {
    final idBytes = utf8.encode(layer.id);
    final nameBytes = utf8.encode(layer.name);
    return 2 +
        idBytes.length +
        2 +
        nameBytes.length +
        1 + // flags
        4 + // opacity
        1 + // blendMode
        4; // extBlendCode (v3+)
  }

  static int _writeLayerHeaderV3(
    ByteData buf,
    int off,
    LayerNode layer,
    int extBlendCode,
  ) {
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
    buf.setInt32(off, extBlendCode, Endian.little);
    off += 4;
    return off;
  }

  /// Reads a layer header that was written under either V2 or V3 layout.
  /// V3 adds the 4-byte `extBlendCode` after `blendMode`; V2 omits it.
  /// Returns the header data + the extended code (0 for V2).
  static _LayerHeaderResult _readLayerHeader(
    ByteData buf,
    int off, {
    required int version,
  }) {
    final idLen = buf.getUint16(off, Endian.little);
    off += 2;
    if (idLen > buf.lengthInBytes - off) {
      throw FormatException(
        'fluera_canvas: layer id length $idLen exceeds remaining bytes '
        '(${buf.lengthInBytes - off}). File likely truncated.',
      );
    }
    final idBytes = Uint8List(idLen);
    for (int i = 0; i < idLen; i++) {
      idBytes[i] = buf.getUint8(off + i);
    }
    off += idLen;
    final id = utf8.decode(idBytes);

    final nameLen = buf.getUint16(off, Endian.little);
    off += 2;
    if (nameLen > buf.lengthInBytes - off) {
      throw FormatException(
        'fluera_canvas: layer name length $nameLen exceeds remaining '
        'bytes (${buf.lengthInBytes - off}). File likely truncated.',
      );
    }
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

    int extBlendCode = 0;
    if (version >= _versionV3) {
      extBlendCode = buf.getInt32(off, Endian.little);
      off += 4;
    }

    final blendMode =
        blendModeIdx >= 0 && blendModeIdx < ui.BlendMode.values.length
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
    return _LayerHeaderResult(layer, off, extBlendCode);
  }

  // ── Text payload (v6+) ────────────────────────────────────────────────
  //
  // We stash `DigitalTextElement` as JSON-in-binary rather than a custom
  // packed layout: the model has 25+ fields with nested `DigitalTextSpan`
  // arrays, and the existing `toJson/fromJson` already round-trip every
  // styled property faithfully. Trade-off — a text-heavy canvas is ~30%
  // larger than a hypothetical packed binary, but the writer is robust
  // to future field additions on `DigitalTextElement` without bumping
  // the format version.

  static int _textPayloadByteSize(TextNode node) {
    final idBytes = utf8.encode(node.id);
    final json = jsonEncode(node.textElement.toJson());
    final jsonBytes = utf8.encode(json);
    return 2 + // nodeIdLen
        idBytes.length +
        4 + // jsonLen
        jsonBytes.length +
        4 * 16; // localTransform storage (Float32 × 16)
  }

  static int _writeTextPayload(ByteData buf, int off, TextNode node) {
    final idBytes = utf8.encode(node.id);
    final json = jsonEncode(node.textElement.toJson());
    final jsonBytes = utf8.encode(json);

    buf.setUint16(off, idBytes.length, Endian.little);
    off += 2;
    for (int i = 0; i < idBytes.length; i++) {
      buf.setUint8(off + i, idBytes[i]);
    }
    off += idBytes.length;

    buf.setUint32(off, jsonBytes.length, Endian.little);
    off += 4;
    for (int i = 0; i < jsonBytes.length; i++) {
      buf.setUint8(off + i, jsonBytes[i]);
    }
    off += jsonBytes.length;

    final m = node.localTransform.storage;
    for (int i = 0; i < 16; i++) {
      buf.setFloat32(off, m[i], Endian.little);
      off += 4;
    }
    return off;
  }

  static _TextPayloadResult _readTextPayload(ByteData buf, int off) {
    final idLen = buf.getUint16(off, Endian.little);
    off += 2;
    final idBytes = Uint8List(idLen);
    for (int i = 0; i < idLen; i++) {
      idBytes[i] = buf.getUint8(off + i);
    }
    off += idLen;
    final id = utf8.decode(idBytes);

    final jsonLen = buf.getUint32(off, Endian.little);
    off += 4;
    final jsonBytes = Uint8List(jsonLen);
    for (int i = 0; i < jsonLen; i++) {
      jsonBytes[i] = buf.getUint8(off + i);
    }
    off += jsonLen;
    final json = utf8.decode(jsonBytes);
    final element = DigitalTextElement.fromJson(
      jsonDecode(json) as Map<String, dynamic>,
    );

    final storage = Float64List(16);
    for (int i = 0; i < 16; i++) {
      storage[i] = buf.getFloat32(off, Endian.little);
      off += 4;
    }
    final node = TextNode(id: NodeId(id), textElement: element);
    final m = Matrix4.fromFloat64List(storage);
    if (!_isIdentityMatrix(m)) {
      node.localTransform = m;
      node.invalidateTransformCache();
    }
    return _TextPayloadResult(node, off);
  }

  // ── Image payload (v4+) ───────────────────────────────────────────────

  static int _imagePayloadByteSize(ImageNode node) {
    final bytes = ImageNodePainter.bytesFor(node.imageElement.imagePath);
    if (bytes == null) return 0;
    final idBytes = utf8.encode(node.id);
    final pathBytes = utf8.encode(node.imageElement.imagePath);
    int size =
        2 + // nodeIdLen
        idBytes.length +
        2 + // imagePathLen
        pathBytes.length +
        4 +
        4 + // posX, posY
        4 + // scale
        4 + // rotation
        4 + // opacity
        4 +
        4 + // imgW, imgH
        1 + // flags
        4 * 16 + // localTransform storage
        4 + // bytesLen
        bytes.length;
    // v5+: trailing annotation block. annotationCount: uint32 followed
    // by `annotationCount` raw stroke payloads (image-local coords).
    size += 4; // annotationCount
    for (final ann in node.annotations) {
      size += _strokePayloadByteSize(ann.stroke);
    }
    return size;
  }

  static int _writeImagePayload(ByteData buf, int off, ImageNode node) {
    final bytes = ImageNodePainter.bytesFor(node.imageElement.imagePath)!;
    final idBytes = utf8.encode(node.id);
    final pathBytes = utf8.encode(node.imageElement.imagePath);

    buf.setUint16(off, idBytes.length, Endian.little);
    off += 2;
    for (int i = 0; i < idBytes.length; i++) {
      buf.setUint8(off + i, idBytes[i]);
    }
    off += idBytes.length;

    buf.setUint16(off, pathBytes.length, Endian.little);
    off += 2;
    for (int i = 0; i < pathBytes.length; i++) {
      buf.setUint8(off + i, pathBytes[i]);
    }
    off += pathBytes.length;

    final el = node.imageElement;
    buf.setFloat32(off, el.position.dx, Endian.little);
    off += 4;
    buf.setFloat32(off, el.position.dy, Endian.little);
    off += 4;
    buf.setFloat32(off, el.scale, Endian.little);
    off += 4;
    buf.setFloat32(off, el.rotation, Endian.little);
    off += 4;
    buf.setFloat32(off, el.opacity, Endian.little);
    off += 4;
    buf.setFloat32(off, node.imageSize.width, Endian.little);
    off += 4;
    buf.setFloat32(off, node.imageSize.height, Endian.little);
    off += 4;
    buf.setUint8(off, 0); // flags reserved
    off += 1;

    final m = node.localTransform.storage;
    for (int i = 0; i < 16; i++) {
      buf.setFloat32(off, m[i], Endian.little);
      off += 4;
    }

    buf.setUint32(off, bytes.length, Endian.little);
    off += 4;
    for (int i = 0; i < bytes.length; i++) {
      buf.setUint8(off + i, bytes[i]);
    }
    off += bytes.length;

    // v5+: trailing annotation block. Stroke payloads are written in
    // image-local coords (the same coord system the runtime stores
    // them in) so loading is a pure copy — no transform pass.
    buf.setUint32(off, node.annotations.length, Endian.little);
    off += 4;
    for (final ann in node.annotations) {
      off = _writeStrokePayload(buf, off, ann.stroke);
    }
    return off;
  }

  static _ImagePayloadResult _readImagePayload(
    ByteData buf,
    int off, {
    required int version,
  }) {
    final idLen = buf.getUint16(off, Endian.little);
    off += 2;
    final idBytes = Uint8List(idLen);
    for (int i = 0; i < idLen; i++) {
      idBytes[i] = buf.getUint8(off + i);
    }
    off += idLen;
    final id = utf8.decode(idBytes);

    final pathLen = buf.getUint16(off, Endian.little);
    off += 2;
    final pathBytes = Uint8List(pathLen);
    for (int i = 0; i < pathLen; i++) {
      pathBytes[i] = buf.getUint8(off + i);
    }
    off += pathLen;
    final imagePath = utf8.decode(pathBytes);

    final posX = buf.getFloat32(off, Endian.little);
    off += 4;
    final posY = buf.getFloat32(off, Endian.little);
    off += 4;
    final scale = buf.getFloat32(off, Endian.little);
    off += 4;
    final rotation = buf.getFloat32(off, Endian.little);
    off += 4;
    final opacity = buf.getFloat32(off, Endian.little);
    off += 4;
    final imgW = buf.getFloat32(off, Endian.little);
    off += 4;
    final imgH = buf.getFloat32(off, Endian.little);
    off += 4;
    // Skip flags byte (reserved in v4).
    off += 1;

    final storage = Float64List(16);
    for (int i = 0; i < 16; i++) {
      storage[i] = buf.getFloat32(off, Endian.little);
      off += 4;
    }

    final blobLen = buf.getUint32(off, Endian.little);
    off += 4;
    // Reject any blob length that exceeds the remaining buffer —
    // protects against malformed files that would otherwise allocate
    // up to 4 GB via `Uint8List(blobLen)`.
    if (blobLen > buf.lengthInBytes - off) {
      throw FormatException(
        'fluera_canvas: image blob length $blobLen exceeds remaining '
        'bytes (${buf.lengthInBytes - off}). File likely corrupt.',
      );
    }
    final blob = Uint8List(blobLen);
    for (int i = 0; i < blobLen; i++) {
      blob[i] = buf.getUint8(off + i);
    }
    off += blobLen;

    final element = ImageElement(
      id: id,
      imagePath: imagePath,
      position: Offset(posX, posY),
      scale: scale,
      rotation: rotation,
      opacity: opacity,
      createdAt: DateTime.now(),
      pageIndex: 0,
    );
    final node = ImageNode(
      id: NodeId(id),
      imageElement: element,
      imageSize: Size(imgW, imgH),
    );
    final m = Matrix4.fromFloat64List(storage);
    if (!_isIdentityMatrix(m)) {
      node.localTransform = m;
      node.invalidateTransformCache();
    }

    // v5+: read trailing annotation block and re-attach as
    // CanvasStrokeNode children of the image. Strokes are stored in
    // image-local coords; consumers paint them under the same
    // transform stack the bitmap uses.
    if (version >= _versionV5) {
      final annCount = buf.getUint32(off, Endian.little);
      off += 4;
      for (int ai = 0; ai < annCount; ai++) {
        final annResult = _readStrokePayload(buf, off);
        node.annotations.add(
          CanvasStrokeNode(id: NodeId(generateUid()), stroke: annResult.stroke),
        );
        off = annResult.endOffset;
      }
    }

    return _ImagePayloadResult(node, blob, off);
  }

  static bool _isIdentityMatrix(Matrix4 m) {
    final s = m.storage;
    return s[0] == 1 &&
        s[1] == 0 &&
        s[2] == 0 &&
        s[3] == 0 &&
        s[4] == 0 &&
        s[5] == 1 &&
        s[6] == 0 &&
        s[7] == 0 &&
        s[8] == 0 &&
        s[9] == 0 &&
        s[10] == 1 &&
        s[11] == 0 &&
        s[12] == 0 &&
        s[13] == 0 &&
        s[14] == 0 &&
        s[15] == 1;
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
    // Each point is 12 bytes (x + y + pressure float32). Reject any
    // count that cannot possibly fit in the remaining buffer to
    // protect against malformed / hostile files that would otherwise
    // allocate gigabytes via `List<Offset>.filled(n, ...)`.
    final color = Color(buf.getUint32(off, Endian.little));
    off += 4;
    final width = buf.getFloat32(off, Endian.little);
    off += 4;
    final remaining = buf.lengthInBytes - off;
    if (n * 12 > remaining) {
      throw FormatException(
        'fluera_canvas: stroke point count $n exceeds remaining bytes '
        '($remaining). File likely truncated or corrupt.',
      );
    }
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
  _LayerHeaderResult(this.layer, this.endOffset, this.extBlendCode);
  final LayerNode layer;
  final int endOffset;

  /// Stable `FlueraBlendMode.code` for the extended Photoshop mode the
  /// layer was on at save time. `0` means "no extended mode" — the
  /// caller should not register an entry for this layer in the canvas
  /// state side-table. Always `0` for files written under V2 or older.
  final int extBlendCode;
}

/// Result of [CanvasSerializer.decodeBytesFull]. Carries the layer tree
/// alongside the canvas-state side-table for Photoshop-grade extended
/// blend modes (codes 100..108 in `FlueraBlendMode`) and the image
/// blob side-table that pairs every embedded `ImageNode` with its
/// original encoded bytes.
///
/// Callers should re-hydrate their `_extendedBlendModes` map from
/// [extendedCodes] after replacing the scene-graph root with [root] —
/// see `FlueraCanvasState.loadFromBytes` for the canonical wiring —
/// and feed each `(imagePath, bytes)` entry from [imageBlobs] into
/// `ImageNodePainter.decodeAndCache` so the GPU handles get reborn.
class DecodeResult {
  /// Method `root`.
  DecodeResult(this.root, this.extendedCodes, this.imageBlobs);

  /// Fresh `LayerNode` root with the original layer hierarchy.
  final LayerNode root;

  /// Side-table mapping layer ids to extended blend modes. Empty when
  /// the file was v1 / v2 or when every layer was on a standard
  /// `ui.BlendMode` at save time.
  final Map<NodeId, FlueraBlendMode> extendedCodes;

  /// Side-table mapping `ImageElement.imagePath` to the original
  /// encoded asset bytes (PNG / JPG / WebP / …). Empty when the file
  /// was v1 / v2 / v3 (those formats can't carry image payloads).
  final Map<String, Uint8List> imageBlobs;
}

class _StrokePayloadResult {
  _StrokePayloadResult(this.stroke, this.endOffset);
  final CanvasStroke stroke;
  final int endOffset;
}

class _ImagePayloadResult {
  _ImagePayloadResult(this.node, this.bytes, this.endOffset);
  final ImageNode node;
  final Uint8List bytes;
  final int endOffset;
}

class _TextPayloadResult {
  _TextPayloadResult(this.node, this.endOffset);
  final TextNode node;
  final int endOffset;
}
