import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/models/canvas_layer.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

/// 💾 Binary Storage Format for Professional Canvas (v3)
///
/// Custom binary format for 80% smaller checkpoints and 5x faster loading.
/// v3 adds:
/// - Stroke/Shape/Text ID preservation (fixes delta tracking after restore)
/// - createdAt preservation for all elements
/// - Bounds checking in BinaryReader (graceful error on corruption)
/// - Uint32 point counts (supports strokes > 65535 points)
class BinaryCanvasFormat {
  /// Field `magicNumber`.
  static const int magicNumber = 0x4C4F4F50; // "LOOP"
  /// Field `version`.
  static const int version = 3;
  /// Field `headerSize`.
  static const int headerSize = 24;

  /// 📦 Encode multiple pages to binary format
  static Uint8List encodePages(Map<int, List<CanvasLayer>> pages) {
    final builder = BytesBuilder();

    // === HEADER (24 bytes) ===
    final header = ByteData(headerSize);
    header.setUint32(0, magicNumber, Endian.little);
    header.setUint16(4, version, Endian.little);
    header.setUint16(6, pages.length, Endian.little);
    // Future expansion: global metadata offset/size
    header.setUint64(8, 0, Endian.little);
    header.setUint64(16, 0, Endian.little);
    builder.add(header.buffer.asUint8List());

    // === PAGE TABLE ===
    // We'll write page entries: [pageIndex (2), layerCount (2), dataOffset (8), dataSize (4)]
    final pageTableOffset = builder.length;
    for (int i = 0; i < pages.length; i++) {
      builder.add(Uint8List(16)); // Reserve space
    }

    final pageEntries = <_PageEntry>[];

    // === PAGE DATA ===
    pages.forEach((pageIndex, layers) {
      final startOffset = builder.length;
      final pageData = encode(layers);
      builder.add(pageData);
      pageEntries.add(
        _PageEntry(
          index: pageIndex,
          count: layers.length,
          offset: startOffset,
          size: pageData.length,
        ),
      );
    });

    // === PATCH PAGE TABLE ===
    final finalData = builder.takeBytes();
    final finalView = ByteData.view(finalData.buffer);

    for (int i = 0; i < pageEntries.length; i++) {
      final entryOffset = pageTableOffset + (i * 16);
      final entry = pageEntries[i];
      finalView.setUint16(entryOffset, entry.index, Endian.little);
      finalView.setUint16(entryOffset + 2, entry.count, Endian.little);
      finalView.setUint64(entryOffset + 4, entry.offset, Endian.little);
      finalView.setUint32(entryOffset + 12, entry.size, Endian.little);
    }

    return finalData;
  }

  /// 📦 Encode a single canvas (list of layers) to binary format
  static Uint8List encode(List<CanvasLayer> layers) {
    final builder = BytesBuilder();

    // Layer count
    final countData = ByteData(4);
    countData.setUint32(0, layers.length, Endian.little);
    builder.add(countData.buffer.asUint8List());

    for (final layer in layers) {
      // Layer Header: [Id (string), Name (string), Flags (1), Opacity (4)]
      _writeString(builder, layer.id);
      _writeString(builder, layer.name);

      int flags = 0;
      if (layer.isVisible) flags |= 0x01;
      if (layer.isLocked) flags |= 0x02;
      builder.addByte(flags);

      final opacityData = ByteData(4);
      opacityData.setFloat32(0, layer.opacity, Endian.little);
      builder.add(opacityData.buffer.asUint8List());

      // Counts: [Strokes (4), Shapes (4), Texts (4), Images (4)]
      // 🛡️ Safety net: filter out 0-point stub strokes that shouldn't
      // have reached the encoder (paging race condition safeguard).
      final validStrokes =
          layer.strokes.where((s) => s.points.isNotEmpty).toList();
      final countsData = ByteData(16);
      countsData.setUint32(0, validStrokes.length, Endian.little);
      countsData.setUint32(4, layer.shapes.length, Endian.little);
      countsData.setUint32(8, layer.texts.length, Endian.little);
      countsData.setUint32(12, layer.images.length, Endian.little);
      builder.add(countsData.buffer.asUint8List());

      // 1. Strokes
      for (final stroke in validStrokes) {
        _writeStroke(builder, stroke);
      }

      // 2. Shapes
      for (final shape in layer.shapes) {
        _writeShape(builder, shape);
      }

      // 3. Texts
      for (final text in layer.texts) {
        _writeText(builder, text);
      }

      // 4. Images
      for (final image in layer.images) {
        _writeImage(builder, image);
      }
    }

    return builder.toBytes();
  }

  /// 🔓 Decode binary data back to multiple pages
  static Map<int, List<CanvasLayer>> decodePages(Uint8List data) {
    final buffer = ByteData.view(data.buffer);

    final magic = buffer.getUint32(0, Endian.little);
    if (magic != magicNumber) throw FormatException('Invalid magic number');

    final fileVersion = buffer.getUint16(4, Endian.little);
    if (fileVersion > version) {
      throw FormatException('Unsupported version $fileVersion');
    }

    final pageCount = buffer.getUint16(6, Endian.little);
    final pages = <int, List<CanvasLayer>>{};

    for (int i = 0; i < pageCount; i++) {
      final entryOffset = headerSize + (i * 16);
      final pageIndex = buffer.getUint16(entryOffset, Endian.little);
      final offset = buffer.getUint64(entryOffset + 4, Endian.little);
      final size = buffer.getUint32(entryOffset + 12, Endian.little);

      final pageData = data.sublist(offset, offset + size);
      // 🔧 v3: Pass fileVersion to decoder for backward compat
      pages[pageIndex] = decode(pageData, fileVersion: fileVersion);
    }

    return pages;
  }

  /// 🔓 Decode binary data back to single canvas layers.
  /// [fileVersion] indica la versione del formato per backward compat.
  static List<CanvasLayer> decode(Uint8List data, {int? fileVersion}) {
    if (isBinaryFormat(data) && data.length >= headerSize) {
      // It's a full v2/v3 file with header, not just a raw layers block
      final pages = decodePages(data);
      return pages.values.first;
    }

    // 🔧 v3: Default to v3 since encode() always writes v3 format.
    // Only pass fileVersion=2 explicitly for legacy data.
    final isV3 = (fileVersion ?? 3) >= 3;

    final reader = _BinaryReader(data);
    final layers = <CanvasLayer>[];

    final layerCount = reader.readUint32();
    for (int i = 0; i < layerCount; i++) {
      final id = reader.readString();
      final name = reader.readString();
      final flags = reader.readByte();
      final opacity = reader.readFloat32();

      final strokeCount = reader.readUint32();
      final shapeCount = reader.readUint32();
      final textCount = reader.readUint32();
      final imageCount = reader.readUint32();

      final strokes = <ProStroke>[];
      for (int s = 0; s < strokeCount; s++) {
        strokes.add(_readStroke(reader, isV3: isV3));
      }

      final shapes = <GeometricShape>[];
      for (int h = 0; h < shapeCount; h++) {
        shapes.add(_readShape(reader, isV3: isV3));
      }

      final texts = <DigitalTextElement>[];
      for (int t = 0; t < textCount; t++) {
        texts.add(_readText(reader, isV3: isV3));
      }

      final images = <ImageElement>[];
      for (int img = 0; img < imageCount; img++) {
        images.add(_readImage(reader));
      }

      layers.add(
        CanvasLayer(
          id: id,
          name: name,
          strokes: strokes,
          shapes: shapes,
          texts: texts,
          images: images,
          isVisible: (flags & 0x01) != 0,
          isLocked: (flags & 0x02) != 0,
          opacity: opacity,
        ),
      );
    }

    return layers;
  }

  // === INTERNAL HELPERS ===

  static void _writeString(BytesBuilder builder, String s) {
    final bytes = utf8.encode(s);
    final lengthData = ByteData(2);
    lengthData.setUint16(0, bytes.length, Endian.little);
    builder.add(lengthData.buffer.asUint8List());
    builder.add(bytes);
  }

  /// 🔧 v3: Encode stroke ID + createdAt to preserve identity after restore
  static void _writeStroke(BytesBuilder builder, ProStroke stroke) {
    _writeString(builder, stroke.id); // 🔧 v3: ID preservation
    builder.add(
      _encodeUint32(stroke.createdAt.millisecondsSinceEpoch ~/ 1000),
    ); // 🔧 v3: createdAt (epoch seconds)
    builder.addByte(stroke.penType.index);
    builder.add(_encodeUint32(stroke.color.toARGB32()));
    builder.add(_encodeFloat32(stroke.baseWidth));
    builder.add(_encodeUint32(stroke.points.length)); // 🔧 v3→Fix #9: Uint32
    for (final point in stroke.points) {
      builder.add(_encodeFloat32(point.position.dx));
      builder.add(_encodeFloat32(point.position.dy));
      builder.add(_encodeFloat32(point.pressure));
      builder.add(_encodeUint32(point.timestamp));
    }
  }

  /// 🔧 v3: Encode shape ID + createdAt per preservare identità
  static void _writeShape(BytesBuilder builder, GeometricShape shape) {
    _writeString(builder, shape.id); // 🔧 v3: ID preservation
    builder.add(
      _encodeUint32(shape.createdAt.millisecondsSinceEpoch ~/ 1000),
    ); // 🔧 v3: createdAt
    builder.addByte(shape.type.index);
    builder.add(_encodeUint32(shape.color.toARGB32()));
    builder.add(_encodeFloat32(shape.strokeWidth));
    builder.addByte(shape.filled ? 1 : 0);
    builder.add(_encodeFloat32(shape.startPoint.dx));
    builder.add(_encodeFloat32(shape.startPoint.dy));
    builder.add(_encodeFloat32(shape.endPoint.dx));
    builder.add(_encodeFloat32(shape.endPoint.dy));
  }

  /// 🔧 v3: Encode text ID + createdAt per preservare identità
  static void _writeText(BytesBuilder builder, DigitalTextElement text) {
    _writeString(builder, text.id); // 🔧 v3: ID preservation
    builder.add(
      _encodeUint32(text.createdAt.millisecondsSinceEpoch ~/ 1000),
    ); // 🔧 v3: createdAt
    _writeString(builder, text.text);
    builder.add(_encodeFloat32(text.position.dx));
    builder.add(_encodeFloat32(text.position.dy));
    builder.add(_encodeUint32(text.color.toARGB32()));
    builder.add(_encodeFloat32(text.fontSize));
    builder.addByte(text.fontWeight.index);
    builder.add(_encodeFloat32(text.scale));
    builder.addByte(text.isOCR ? 1 : 0);
    _writeString(builder, text.fontFamily ?? 'Roboto');
  }

  static void _writeImage(BytesBuilder builder, ImageElement image) {
    _writeString(builder, image.id);
    _writeString(builder, image.imagePath);
    builder.add(_encodeFloat32(image.position.dx));
    builder.add(_encodeFloat32(image.position.dy));
    builder.add(_encodeFloat32(image.scale));
    builder.add(_encodeFloat32(image.rotation));
    builder.add(_encodeFloat32(image.opacity));
    builder.add(_encodeUint16(image.pageIndex));
    // 🌐 v3.1: Cloud URLs for cross-device image loading
    _writeString(builder, image.storageUrl ?? '');
    _writeString(builder, image.thumbnailUrl ?? '');
    // 🖊️ v3.1: Drawing strokes attached to this image
    builder.add(_encodeUint32(image.drawingStrokes.length));
    for (final stroke in image.drawingStrokes) {
      _writeStroke(builder, stroke);
    }
  }

  static ImageElement _readImage(_BinaryReader reader) {
    final id = reader.readString();
    final path = reader.readString();
    final pos = Offset(reader.readFloat32(), reader.readFloat32());
    final scale = reader.readFloat32();
    final rotation = reader.readFloat32();
    final opacity = reader.readFloat32();
    final pageIndex = reader.readUint16();

    // 🌐 v3.1: Read cloud URLs if available (backward compat: catch EOF)
    String? storageUrl;
    String? thumbnailUrl;
    List<ProStroke> drawingStrokes = [];
    try {
      final url = reader.readString();
      if (url.isNotEmpty) storageUrl = url;
      final thumb = reader.readString();
      if (thumb.isNotEmpty) thumbnailUrl = thumb;
      // 🖊️ v3.1: Read drawing strokes attached to this image
      final strokeCount = reader.readUint32();
      for (int i = 0; i < strokeCount; i++) {
        drawingStrokes.add(_readStroke(reader));
      }
    } catch (_) {
      // Old binary data without URLs/strokes — safe to ignore
    }

    return ImageElement(
      id: id,
      imagePath: path,
      storageUrl: storageUrl,
      thumbnailUrl: thumbnailUrl,
      position: pos,
      scale: scale,
      rotation: rotation,
      opacity: opacity,
      pageIndex: pageIndex,
      createdAt: DateTime.now(),
      drawingStrokes: drawingStrokes,
    );
  }

  /// 🔧 v3: Legge stroke con ID e createdAt preservati.
  /// [isV3] controlla se leggere i nuovi campi (backward compat con v2).
  static ProStroke _readStroke(_BinaryReader reader, {bool isV3 = true}) {
    String id;
    DateTime createdAt;

    if (isV3) {
      id = reader.readString();
      final epochSec = reader.readUint32();
      createdAt = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
    } else {
      // v2 legacy: genera ID e timestamp come prima
      id = 's_${DateTime.now().microsecondsSinceEpoch}';
      createdAt = DateTime.now();
    }

    final penType = ProPenType.values[reader.readByte()];
    final color = Color(reader.readUint32());
    final width = reader.readFloat32();
    // 🔧 v3→Fix #9: Uint32 to support stroke with > 65535 points
    final pointCount = isV3 ? reader.readUint32() : reader.readUint16();

    final points = <ProDrawingPoint>[];
    for (int i = 0; i < pointCount; i++) {
      points.add(
        ProDrawingPoint(
          position: Offset(reader.readFloat32(), reader.readFloat32()),
          pressure: reader.readFloat32(),
          timestamp: reader.readUint32(),
        ),
      );
    }

    return ProStroke(
      id: id,
      points: points,
      color: color,
      baseWidth: width,
      penType: penType,
      createdAt: createdAt,
    );
  }

  /// 🔧 v3: Legge shape con ID e createdAt preservati.
  static GeometricShape _readShape(_BinaryReader reader, {bool isV3 = true}) {
    String id;
    DateTime createdAt;

    if (isV3) {
      id = reader.readString();
      final epochSec = reader.readUint32();
      createdAt = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
    } else {
      id = 'h_${DateTime.now().microsecondsSinceEpoch}';
      createdAt = DateTime.now();
    }

    final type = ShapeType.values[reader.readByte()];
    final color = Color(reader.readUint32());
    final width = reader.readFloat32();
    final filled = reader.readByte() == 1;
    final start = Offset(reader.readFloat32(), reader.readFloat32());
    final end = Offset(reader.readFloat32(), reader.readFloat32());

    return GeometricShape(
      id: id,
      type: type,
      startPoint: start,
      endPoint: end,
      color: color,
      strokeWidth: width,
      filled: filled,
      createdAt: createdAt,
    );
  }

  /// 🔧 v3: Legge text con ID e createdAt preservati.
  static DigitalTextElement _readText(
    _BinaryReader reader, {
    bool isV3 = true,
  }) {
    String id;
    DateTime createdAt;

    if (isV3) {
      id = reader.readString();
      final epochSec = reader.readUint32();
      createdAt = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
    } else {
      id = 't_${DateTime.now().microsecondsSinceEpoch}';
      createdAt = DateTime.now();
    }

    final text = reader.readString();
    final pos = Offset(reader.readFloat32(), reader.readFloat32());
    final color = Color(reader.readUint32());
    final fontSize = reader.readFloat32();
    final weight = FontWeight.values[reader.readByte()];
    final scale = reader.readFloat32();
    final isOCR = reader.readByte() == 1;
    final fontFamily = reader.readString();

    return DigitalTextElement(
      id: id,
      text: text,
      position: pos,
      color: color,
      fontSize: fontSize,
      fontWeight: weight,
      fontFamily: fontFamily,
      scale: scale,
      isOCR: isOCR,
      createdAt: createdAt,
    );
  }

  static Uint8List _encodeUint32(int value) {
    final b = ByteData(4);
    b.setUint32(0, value, Endian.little);
    return b.buffer.asUint8List();
  }

  static Uint8List _encodeUint16(int value) {
    final b = ByteData(2);
    b.setUint16(0, value, Endian.little);
    return b.buffer.asUint8List();
  }

  static Uint8List _encodeFloat32(double value) {
    final b = ByteData(4);
    b.setFloat32(0, value, Endian.little);
    return b.buffer.asUint8List();
  }

  /// API element `isBinaryFormat`.
  static bool isBinaryFormat(Uint8List data) {
    if (data.length < 4) return false;
    final magic = ByteData.view(data.buffer).getUint32(0, Endian.little);
    return magic == magicNumber;
  }
}

/// 🔧 v3→Fix #7: BinaryReader con bounds checking
class _BinaryReader {
  final Uint8List data;
  final ByteData _view;
  int _offset = 0;

  _BinaryReader(this.data) : _view = ByteData.view(data.buffer);

  /// Checks che ci siano abbastanza bytes disponibili
  void _ensureAvailable(int bytes) {
    if (_offset + bytes > data.length) {
      throw FormatException(
        'Binary data corrupted: expected $bytes bytes at offset $_offset, '
        'but only ${data.length - _offset} available (total: ${data.length})',
      );
    }
  }

  int readByte() {
    _ensureAvailable(1);
    return data[_offset++];
  }

  int readUint16() {
    _ensureAvailable(2);
    final v = _view.getUint16(_offset, Endian.little);
    _offset += 2;
    return v;
  }

  int readUint32() {
    _ensureAvailable(4);
    final v = _view.getUint32(_offset, Endian.little);
    _offset += 4;
    return v;
  }

  double readFloat32() {
    _ensureAvailable(4);
    final v = _view.getFloat32(_offset, Endian.little);
    _offset += 4;
    return v;
  }

  String readString() {
    final len = readUint16();
    _ensureAvailable(len);
    final bytes = data.sublist(_offset, _offset + len);
    _offset += len;
    return utf8.decode(bytes);
  }
}

class _PageEntry {
  final int index;
  final int count;
  final int offset;
  final int size;
  _PageEntry({
    required this.index,
    required this.count,
    required this.offset,
    required this.size,
  });
}
