// ============================================================================
// 📦 FLUERA FILE EXPORT SERVICE — Bridges FlueraFileWriter ↔ BinaryCanvasFormat
//
// Builds a complete .fluera file from canvas state and reads it back.
// Uses BinaryCanvasFormat (v3) for compact layer serialization and
// FlueraFileWriter for the sectioned container with TOC + CRC32.
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/models/canvas_layer.dart';
import 'binary_canvas_format.dart';
import 'fluera_file_format.dart';

/// Service for building and reading `.fluera` files.
///
/// ```dart
/// // Export
/// final bytes = await FlueraFileExportService.buildFlueraFile(
///   layers: layerController.layers,
///   title: 'My Design',
/// );
/// File('design.fluera').writeAsBytesSync(bytes);
///
/// // Import
/// final loaded = FlueraFileExportService.loadFlueraFile(bytes);
/// layerController.clearAllAndLoadLayers(loaded.layers);
/// ```
class FlueraFileExportService {
  FlueraFileExportService._();

  // ─────────────────────────────────────────────────────────────────────────
  // EXPORT — Build a .fluera file
  // ─────────────────────────────────────────────────────────────────────────

  /// Build a complete `.fluera` file from canvas state.
  ///
  /// The file contains:
  /// - **Metadata** — title, dates, canvas settings
  /// - **Page directory** — listing of all pages
  /// - **Page data** — binary-encoded layers (via [BinaryCanvasFormat])
  /// - **Asset blobs** — embedded image file bytes (when available)
  ///
  /// Image assets are embedded by reading files from [ImageElement.imagePath].
  /// When files are inaccessible, images are referenced by path only.
  static Future<Uint8List> buildFlueraFile({
    required List<CanvasLayer> layers,
    String? title,
    String? backgroundColor,
    String? paperType,
  }) async {
    final writer = FlueraFileWriter();

    // ── 1. Metadata ──────────────────────────────────────────────────────
    final now = DateTime.now().toIso8601String();
    writer.addMetadata({
      'title': title ?? 'Untitled',
      'createdAt': now,
      'modifiedAt': now,
      if (backgroundColor != null) 'backgroundColor': backgroundColor,
      if (paperType != null) 'paperType': paperType,
      'engineVersion': 'fluera_engine/4.0',
      'layerCount': layers.length,
    });

    // ── 2. Page directory ────────────────────────────────────────────────
    writer.addPageDirectory([
      {'id': 'page_0', 'name': title ?? 'Page 1', 'layerCount': layers.length},
    ]);

    // ── 3. Page data (binary-encoded layers) ─────────────────────────────
    // Uses BinaryCanvasFormat for compact encoding (80% smaller than JSON,
    // 5x faster to load). Preserves all element IDs and timestamps.
    final layerBytes = BinaryCanvasFormat.encode(layers);
    writer.addSection(
      PreparedSection(
        type: SectionType.pageData,
        data: layerBytes,
        tag: 0, // page index
      ),
    );

    // ── 4. Asset blobs (embedded images) ─────────────────────────────────
    await _embedImageAssets(writer, layers);

    return writer.build();
  }

  /// Build a `.fluera` file with multi-page support.
  static Future<Uint8List> buildFlueraFileMultiPage({
    required Map<int, List<CanvasLayer>> pages,
    String? title,
    String? backgroundColor,
    String? paperType,
  }) async {
    final writer = FlueraFileWriter();

    // ── 1. Metadata ──────────────────────────────────────────────────────
    final now = DateTime.now().toIso8601String();
    final totalLayers = pages.values.fold<int>(0, (sum, l) => sum + l.length);
    writer.addMetadata({
      'title': title ?? 'Untitled',
      'createdAt': now,
      'modifiedAt': now,
      if (backgroundColor != null) 'backgroundColor': backgroundColor,
      if (paperType != null) 'paperType': paperType,
      'engineVersion': 'fluera_engine/4.0',
      'pageCount': pages.length,
      'layerCount': totalLayers,
    });

    // ── 2. Page directory ────────────────────────────────────────────────
    final pageDir = <Map<String, dynamic>>[];
    for (final entry in pages.entries) {
      pageDir.add({
        'id': 'page_${entry.key}',
        'name': 'Page ${entry.key + 1}',
        'layerCount': entry.value.length,
      });
    }
    writer.addPageDirectory(pageDir);

    // ── 3. Page data per page ────────────────────────────────────────────
    for (final entry in pages.entries) {
      final layerBytes = BinaryCanvasFormat.encode(entry.value);
      writer.addSection(
        PreparedSection(
          type: SectionType.pageData,
          data: layerBytes,
          tag: entry.key,
        ),
      );
    }

    // ── 4. Asset blobs ──────────────────────────────────────────────────
    final allLayers = pages.values.expand((l) => l).toList();
    await _embedImageAssets(writer, allLayers);

    return writer.build();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // IMPORT — Load a .fluera file
  // ─────────────────────────────────────────────────────────────────────────

  /// Load canvas data from a `.fluera` file.
  ///
  /// Returns a [FlueraFileLoadResult] containing layers, metadata, and
  /// any embedded asset blobs.
  static FlueraFileLoadResult loadFlueraFile(Uint8List bytes) {
    final reader = FlueraFileReader(bytes);

    // ── 1. Metadata ──────────────────────────────────────────────────────
    final metadata = reader.readMetadata() ?? {};

    // ── 2. Page directory ────────────────────────────────────────────────
    final pageDir = reader.readPageDirectory();

    // ── 3. Load all pages ────────────────────────────────────────────────
    final pages = <int, List<CanvasLayer>>{};
    for (final pageIndex in reader.pageIndices) {
      final desc = reader.toc.find(SectionType.pageData, tag: pageIndex);
      if (desc == null) continue;
      final pageBytes = reader.readSection(desc);
      // Copy the bytes: readSection returns a sublistView into the file buffer,
      // but BinaryCanvasFormat._BinaryReader uses ByteData.view(data.buffer)
      // which refers to the ENTIRE underlying buffer. A copy ensures _BinaryReader
      // reads from offset 0 of the section data, not offset 0 of the whole file.
      pages[pageIndex] = BinaryCanvasFormat.decode(
        Uint8List.fromList(pageBytes),
      );
    }

    // ── 4. Collect asset blobs ──────────────────────────────────────────
    final assetBlobs = <int, Uint8List>{};
    for (final desc in reader.toc.ofType(SectionType.assetBlob)) {
      assetBlobs[desc.tag] = reader.readSection(desc);
    }

    // Flatten to single list for convenience
    final allLayers = pages.values.expand((l) => l).toList();

    return FlueraFileLoadResult(
      layers: allLayers,
      pages: pages,
      metadata: metadata,
      pageDirectory: pageDir,
      assetBlobs: assetBlobs,
      version: reader.version,
      stats: reader.stats(),
    );
  }

  /// Check if the given bytes represent a valid `.fluera` file.
  static bool isFlueraFile(Uint8List bytes) => FlueraFileReader.isValid(bytes);

  // ─────────────────────────────────────────────────────────────────────────
  // INTERNAL — Image asset embedding
  // ─────────────────────────────────────────────────────────────────────────

  /// Embed image files as asset blob sections.
  ///
  /// Each image is stored with tag = hashCode of its path, so the reader
  /// can match blobs back to ImageElements via [FlueraFileLoadResult.getAssetForPath].
  static Future<void> _embedImageAssets(
    FlueraFileWriter writer,
    List<CanvasLayer> layers,
  ) async {
    final seenPaths = <String>{};

    for (final layer in layers) {
      for (final image in layer.images) {
        final path = image.imagePath;
        if (path.isEmpty || seenPaths.contains(path)) continue;
        seenPaths.add(path);

        try {
          final file = File(path);
          if (await file.exists()) {
            final fileBytes = await file.readAsBytes();
            if (fileBytes.isNotEmpty) {
              writer.addAssetBlob(path.hashCode, fileBytes);
            }
          }
        } catch (_) {
          // File not accessible — skip embedding, image will be path-only
        }
      }
    }
  }
}

// =============================================================================
// LOAD RESULT
// =============================================================================

/// Result of loading a `.fluera` file.
class FlueraFileLoadResult {
  /// All layers across all pages (flattened for single-page use).
  final List<CanvasLayer> layers;

  /// Layers organized by page index.
  final Map<int, List<CanvasLayer>> pages;

  /// File metadata (title, dates, canvas settings).
  final Map<String, dynamic> metadata;

  /// Page directory listing.
  final List<Map<String, dynamic>>? pageDirectory;

  /// Embedded asset blobs (key = imagePath.hashCode).
  final Map<int, Uint8List> assetBlobs;

  /// File format version.
  final int version;

  /// File statistics.
  final Map<String, dynamic> stats;

  const FlueraFileLoadResult({
    required this.layers,
    required this.pages,
    required this.metadata,
    this.pageDirectory,
    required this.assetBlobs,
    required this.version,
    required this.stats,
  });

  /// Title from metadata.
  String get title => metadata['title'] as String? ?? 'Untitled';

  /// Background color from metadata.
  String? get backgroundColor => metadata['backgroundColor'] as String?;

  /// Paper type from metadata.
  String? get paperType => metadata['paperType'] as String?;

  /// Total number of pages.
  int get pageCount => pages.length;

  /// Whether this file has embedded image assets.
  bool get hasAssets => assetBlobs.isNotEmpty;

  /// Look up an embedded asset for a given image path.
  Uint8List? getAssetForPath(String imagePath) =>
      assetBlobs[imagePath.hashCode];
}
