import 'dart:convert';
import 'dart:typed_data';

// =============================================================================
// 📦 FLUERA FILE FORMAT v4 — Sectioned binary format with lazy loading
//
// Structure:
//   [Header: 32 bytes] → magic, version, flags, section count, TOC offset
//   [Section 0: N bytes] → metadata (JSON)
//   [Section 1: N bytes] → thumbnail (PNG bytes)
//   [Section 2: N bytes] → page directory (page count + names)
//   [Section 3..N: N bytes] → page data (scene graph JSON per page)
//   [Section N+1..M: N bytes] → asset blobs (images, fonts)
//   [TOC: section_count × 24 bytes] → section descriptors
//
// Features:
//   • Random-access section loading — read only what's needed
//   • Incremental save — re-write only dirty sections
//   • CRC32 per section for corruption detection
//   • Extensible section types for future additions
// =============================================================================

/// Magic bytes: "NBLA" (Fluera)
const int _magic = 0x4E424C41;

/// Current format version.
const int _currentVersion = 4;

// ─────────────────────────────────────────────────────────────────────────────
// SECTION TYPES
// ─────────────────────────────────────────────────────────────────────────────

/// Types of sections in a Fluera file.
enum SectionType {
  /// File metadata (name, author, created/modified dates).
  metadata(0),

  /// Thumbnail image (PNG bytes for quick preview).
  thumbnail(1),

  /// Page directory listing page IDs and names.
  pageDirectory(2),

  /// A single page's scene graph data.
  pageData(3),

  /// Binary asset blob (image, font, etc.).
  assetBlob(4),

  /// Style/token data.
  styleData(5),

  /// Animation timeline data.
  animationData(6),

  /// Prototype flow data.
  prototypeData(7);

  final int code;
  const SectionType(this.code);

  static SectionType fromCode(int code) {
    return SectionType.values.firstWhere(
      (e) => e.code == code,
      orElse: () => SectionType.metadata,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SECTION DESCRIPTOR — Entry in the Table of Contents
// ─────────────────────────────────────────────────────────────────────────────

/// Describes a section's location and integrity in the file.
///
/// Each entry is 28 bytes:
///   - type:     4 bytes (SectionType code)
///   - offset:   8 bytes (byte offset from file start)
///   - length:   8 bytes (section data length)
///   - checksum: 4 bytes (CRC32 of section data)
///   - tag:      4 bytes (user-defined tag, e.g. page index or asset ID hash)
class SectionDescriptor {
  final SectionType type;
  final int offset;
  final int length;
  final int checksum;
  final int tag;

  const SectionDescriptor({
    required this.type,
    required this.offset,
    required this.length,
    required this.checksum,
    this.tag = 0,
  });

  /// Encode descriptor into 28 bytes.
  Uint8List encode() {
    final data = ByteData(28);
    data.setUint32(0, type.code, Endian.little);
    data.setUint64(4, offset, Endian.little);
    data.setUint64(12, length, Endian.little);
    data.setUint32(20, checksum, Endian.little);
    data.setUint32(24, tag, Endian.little);
    return data.buffer.asUint8List();
  }

  /// Decode descriptor from byte data at the given offset.
  factory SectionDescriptor.decode(ByteData data, int byteOffset) {
    return SectionDescriptor(
      type: SectionType.fromCode(data.getUint32(byteOffset, Endian.little)),
      offset: data.getUint64(byteOffset + 4, Endian.little),
      length: data.getUint64(byteOffset + 12, Endian.little),
      checksum: data.getUint32(byteOffset + 20, Endian.little),
      tag: data.getUint32(byteOffset + 24, Endian.little),
    );
  }

  @override
  String toString() =>
      'Section(${type.name}, offset=$offset, len=$length, crc=$checksum)';
}

// ─────────────────────────────────────────────────────────────────────────────
// FILE HEADER — First 32 bytes of the file
// ─────────────────────────────────────────────────────────────────────────────

/// The Fluera file header (32 bytes).
///
/// Layout:
///   [0..3]   magic (0x4E424C41 = "NBLA")
///   [4..7]   version (uint32)
///   [8..11]  flags (uint32, reserved)
///   [12..15] section count (uint32)
///   [16..23] TOC offset (uint64, byte offset to Table of Contents)
///   [24..31] reserved (8 bytes, zero-filled)
class FlueraFileHeader {
  final int version;
  final int flags;
  final int sectionCount;
  final int tocOffset;

  const FlueraFileHeader({
    this.version = _currentVersion,
    this.flags = 0,
    required this.sectionCount,
    required this.tocOffset,
  });

  /// Encode header to 32 bytes.
  Uint8List encode() {
    final data = ByteData(32);
    data.setUint32(0, _magic, Endian.little);
    data.setUint32(4, version, Endian.little);
    data.setUint32(8, flags, Endian.little);
    data.setUint32(12, sectionCount, Endian.little);
    data.setUint64(16, tocOffset, Endian.little);
    // [24..31] reserved = 0
    return data.buffer.asUint8List();
  }

  /// Decode header from raw bytes.
  factory FlueraFileHeader.decode(Uint8List bytes) {
    if (bytes.length < 32) {
      throw const FormatException('File too small for Fluera header');
    }
    final data = ByteData.sublistView(bytes, 0, 32);
    final magic = data.getUint32(0, Endian.little);
    if (magic != _magic) {
      throw FormatException(
        'Invalid magic bytes: 0x${magic.toRadixString(16)} '
        '(expected 0x${_magic.toRadixString(16)})',
      );
    }
    return FlueraFileHeader(
      version: data.getUint32(4, Endian.little),
      flags: data.getUint32(8, Endian.little),
      sectionCount: data.getUint32(12, Endian.little),
      tocOffset: data.getUint64(16, Endian.little),
    );
  }

  /// Check if raw bytes start with the Fluera magic.
  static bool isFlueraFile(Uint8List bytes) {
    if (bytes.length < 4) return false;
    final data = ByteData.sublistView(bytes, 0, 4);
    return data.getUint32(0, Endian.little) == _magic;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TABLE OF CONTENTS — Section index at the end of the file
// ─────────────────────────────────────────────────────────────────────────────

/// Table of Contents: array of [SectionDescriptor]s for random access.
class FlueraFileTOC {
  final List<SectionDescriptor> sections;

  const FlueraFileTOC(this.sections);

  /// Find all sections of a given type.
  List<SectionDescriptor> ofType(SectionType type) =>
      sections.where((s) => s.type == type).toList();

  /// Find a section by type and tag.
  SectionDescriptor? find(SectionType type, {int tag = 0}) {
    for (final s in sections) {
      if (s.type == type && s.tag == tag) return s;
    }
    return null;
  }

  /// Encode the TOC as bytes.
  Uint8List encode() {
    final builder = BytesBuilder(copy: false);
    for (final section in sections) {
      builder.add(section.encode());
    }
    return builder.toBytes();
  }

  /// Decode the TOC from raw bytes.
  factory FlueraFileTOC.decode(Uint8List bytes, int sectionCount) {
    final data = ByteData.sublistView(bytes);
    final sections = <SectionDescriptor>[];
    for (var i = 0; i < sectionCount; i++) {
      sections.add(SectionDescriptor.decode(data, i * 28));
    }
    return FlueraFileTOC(sections);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CRC32 — Integrity check
// ─────────────────────────────────────────────────────────────────────────────

/// Simple CRC32 for section integrity.
class _CRC32 {
  static final List<int> _table = _generateTable();

  static List<int> _generateTable() {
    final table = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      var crc = i;
      for (var j = 0; j < 8; j++) {
        if (crc & 1 != 0) {
          crc = (crc >> 1) ^ 0xEDB88320;
        } else {
          crc >>= 1;
        }
      }
      table[i] = crc;
    }
    return table;
  }

  static int compute(Uint8List data) {
    var crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc = _table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFF;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FLUERA FILE WRITER — Build/write Fluera files
// ─────────────────────────────────────────────────────────────────────────────

/// A prepared section ready for writing.
class PreparedSection {
  final SectionType type;
  final Uint8List data;
  final int tag;
  final bool dirty;

  PreparedSection({
    required this.type,
    required this.data,
    this.tag = 0,
    this.dirty = true,
  });

  int get checksum => _CRC32.compute(data);
}

/// Writes Fluera files with support for incremental saves.
///
/// ```dart
/// final writer = FlueraFileWriter();
/// writer.addSection(PreparedSection(
///   type: SectionType.metadata,
///   data: utf8.encode(jsonEncode({'name': 'My Design'})),
/// ));
/// writer.addSection(PreparedSection(
///   type: SectionType.pageData,
///   data: utf8.encode(jsonEncode(sceneGraph.toJson())),
///   tag: 0, // page index
/// ));
/// final bytes = writer.build();
/// ```
class FlueraFileWriter {
  final List<PreparedSection> _sections = [];

  /// Add a section to the file.
  void addSection(PreparedSection section) {
    _sections.add(section);
  }

  /// Add a JSON metadata section.
  void addMetadata(Map<String, dynamic> metadata) {
    addSection(
      PreparedSection(
        type: SectionType.metadata,
        data: Uint8List.fromList(utf8.encode(jsonEncode(metadata))),
      ),
    );
  }

  /// Add a thumbnail section.
  void addThumbnail(Uint8List pngBytes) {
    addSection(PreparedSection(type: SectionType.thumbnail, data: pngBytes));
  }

  /// Add a page directory section.
  void addPageDirectory(List<Map<String, dynamic>> pages) {
    addSection(
      PreparedSection(
        type: SectionType.pageDirectory,
        data: Uint8List.fromList(utf8.encode(jsonEncode(pages))),
      ),
    );
  }

  /// Add a page data section.
  void addPageData(int pageIndex, Map<String, dynamic> sceneGraphJson) {
    addSection(
      PreparedSection(
        type: SectionType.pageData,
        data: Uint8List.fromList(utf8.encode(jsonEncode(sceneGraphJson))),
        tag: pageIndex,
      ),
    );
  }

  /// Add a binary asset blob.
  void addAssetBlob(int assetIdHash, Uint8List data) {
    addSection(
      PreparedSection(
        type: SectionType.assetBlob,
        data: data,
        tag: assetIdHash,
      ),
    );
  }

  /// Build the complete file as bytes.
  ///
  /// Layout: [Header] [Section0] [Section1] ... [SectionN] [TOC]
  Uint8List build() {
    final builder = BytesBuilder(copy: false);

    // Reserve space for header (32 bytes) — will be written at the end
    final headerPlaceholder = Uint8List(32);
    builder.add(headerPlaceholder);

    // Write sections and track descriptors
    final descriptors = <SectionDescriptor>[];
    for (final section in _sections) {
      final offset = builder.length;
      builder.add(section.data);
      descriptors.add(
        SectionDescriptor(
          type: section.type,
          offset: offset,
          length: section.data.length,
          checksum: section.checksum,
          tag: section.tag,
        ),
      );
    }

    // Write TOC
    final tocOffset = builder.length;
    final toc = FlueraFileTOC(descriptors);
    builder.add(toc.encode());

    // Build the final bytes
    final bytes = builder.toBytes();

    // Write the header in-place
    final header = FlueraFileHeader(
      sectionCount: descriptors.length,
      tocOffset: tocOffset,
    );
    final headerBytes = header.encode();
    for (var i = 0; i < 32; i++) {
      bytes[i] = headerBytes[i];
    }

    return bytes;
  }

  /// Incremental save: given existing file bytes and dirty sections,
  /// produce a new file that re-uses unchanged sections.
  ///
  /// Sections with [dirty = true] are replaced; others are copied from
  /// [existingBytes] using the old TOC's offsets.
  static Uint8List incrementalSave({
    required Uint8List existingBytes,
    required List<PreparedSection> dirtySections,
  }) {
    // Parse existing file
    final header = FlueraFileHeader.decode(existingBytes);
    final tocBytes = Uint8List.sublistView(
      existingBytes,
      header.tocOffset,
      header.tocOffset + header.sectionCount * 28,
    );
    final toc = FlueraFileTOC.decode(tocBytes, header.sectionCount);

    // Build dirty section map: (type, tag) → PreparedSection
    final dirtyMap = <String, PreparedSection>{};
    for (final s in dirtySections) {
      dirtyMap['${s.type.code}:${s.tag}'] = s;
    }

    // Rebuild file
    final writer = FlueraFileWriter();
    for (final desc in toc.sections) {
      final key = '${desc.type.code}:${desc.tag}';
      final dirty = dirtyMap[key];
      if (dirty != null) {
        writer.addSection(dirty);
      } else {
        // Copy existing section data
        final sectionData = Uint8List.sublistView(
          existingBytes,
          desc.offset,
          desc.offset + desc.length,
        );
        writer.addSection(
          PreparedSection(
            type: desc.type,
            data: sectionData,
            tag: desc.tag,
            dirty: false,
          ),
        );
      }
    }

    // Add any new sections not in the original file
    for (final entry in dirtyMap.entries) {
      final found = toc.sections.any(
        (d) => '${d.type.code}:${d.tag}' == entry.key,
      );
      if (!found) {
        writer.addSection(entry.value);
      }
    }

    return writer.build();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FLUERA FILE READER — Read/parse Fluera files with lazy section loading
// ─────────────────────────────────────────────────────────────────────────────

/// Reads Fluera files with lazy, section-level access.
///
/// ```dart
/// final reader = FlueraFileReader(fileBytes);
/// final metadata = reader.readMetadata();
/// final thumbnail = reader.readThumbnail();
/// // Only load page 3 when the user navigates to it:
/// final page3 = reader.readPageData(3);
/// ```
class FlueraFileReader {
  final Uint8List _bytes;
  final FlueraFileHeader header;
  final FlueraFileTOC toc;

  FlueraFileReader._(this._bytes, this.header, this.toc);

  factory FlueraFileReader(Uint8List bytes) {
    final header = FlueraFileHeader.decode(bytes);

    // Validate TOC bounds
    final tocEnd = header.tocOffset + header.sectionCount * 28;
    if (tocEnd > bytes.length) {
      throw FormatException(
        'TOC extends past file end: $tocEnd > ${bytes.length}',
      );
    }

    final tocBytes = Uint8List.sublistView(bytes, header.tocOffset, tocEnd);
    final toc = FlueraFileTOC.decode(tocBytes, header.sectionCount);
    return FlueraFileReader._(bytes, header, toc);
  }

  /// Read raw bytes for a section, with CRC32 validation.
  Uint8List readSection(SectionDescriptor desc) {
    if (desc.offset + desc.length > _bytes.length) {
      throw FormatException(
        'Section extends past file end: '
        '${desc.offset + desc.length} > ${_bytes.length}',
      );
    }
    final data = Uint8List.sublistView(
      _bytes,
      desc.offset,
      desc.offset + desc.length,
    );
    // Validate checksum
    final actualCrc = _CRC32.compute(data);
    if (actualCrc != desc.checksum) {
      throw FormatException(
        'CRC32 mismatch for ${desc.type.name} section: '
        'expected 0x${desc.checksum.toRadixString(16)}, '
        'got 0x${actualCrc.toRadixString(16)}',
      );
    }
    return data;
  }

  /// Read and parse the metadata section.
  Map<String, dynamic>? readMetadata() {
    final desc = toc.find(SectionType.metadata);
    if (desc == null) return null;
    final data = readSection(desc);
    return jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
  }

  /// Read the thumbnail (raw PNG bytes).
  Uint8List? readThumbnail() {
    final desc = toc.find(SectionType.thumbnail);
    if (desc == null) return null;
    return readSection(desc);
  }

  /// Read the page directory.
  List<Map<String, dynamic>>? readPageDirectory() {
    final desc = toc.find(SectionType.pageDirectory);
    if (desc == null) return null;
    final data = readSection(desc);
    final list = jsonDecode(utf8.decode(data)) as List;
    return list.cast<Map<String, dynamic>>();
  }

  /// Read a page's scene graph data by page index (lazy — only loads this page).
  Map<String, dynamic>? readPageData(int pageIndex) {
    final desc = toc.find(SectionType.pageData, tag: pageIndex);
    if (desc == null) return null;
    final data = readSection(desc);
    return jsonDecode(utf8.decode(data)) as Map<String, dynamic>;
  }

  /// Read a binary asset blob by its ID hash.
  Uint8List? readAssetBlob(int assetIdHash) {
    final desc = toc.find(SectionType.assetBlob, tag: assetIdHash);
    if (desc == null) return null;
    return readSection(desc);
  }

  /// Get all page indices available in the file.
  List<int> get pageIndices =>
      toc.ofType(SectionType.pageData).map((d) => d.tag).toList()..sort();

  /// Total number of sections.
  int get sectionCount => toc.sections.length;

  /// Total file size in bytes.
  int get fileSize => _bytes.length;

  /// File format version.
  int get version => header.version;

  /// Whether this is a valid Fluera file.
  static bool isValid(Uint8List bytes) => FlueraFileHeader.isFlueraFile(bytes);

  /// File statistics.
  Map<String, dynamic> stats() {
    final sectionsByType = <String, int>{};
    var totalDataBytes = 0;
    for (final s in toc.sections) {
      sectionsByType[s.type.name] = (sectionsByType[s.type.name] ?? 0) + 1;
      totalDataBytes += s.length;
    }
    return {
      'version': version,
      'fileSize': fileSize,
      'sectionCount': sectionCount,
      'totalDataBytes': totalDataBytes,
      'overheadBytes': fileSize - totalDataBytes,
      'sectionsByType': sectionsByType,
    };
  }
}
