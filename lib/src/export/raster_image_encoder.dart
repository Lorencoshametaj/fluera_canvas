/// 🖼️ RASTER IMAGE ENCODER — JPEG and WebP encoding from raw pixels.
///
/// Provides high-level encoding methods that first try native platform
/// encoding (via [RasterEncoderChannel]) for best quality, then fall
/// back to a pure-Dart BMP envelope as a last resort.
///
/// ```dart
/// final encoder = RasterImageEncoder();
/// final jpeg = await encoder.encodeJpeg(rgbaBytes, 800, 600, quality: 85);
/// ```
library;

import 'dart:typed_data';
import 'dart:ui' as ui;
import 'raster_encoder_channel.dart';

// =============================================================================
// RASTER IMAGE ENCODER
// =============================================================================

/// High-level image encoder with native fallback.
///
/// Encoding priority:
/// 1. Native platform encoder (JPEG/WebP via platform channels)
/// 2. Fallback: BMP format (universally supported, no compression)
class RasterImageEncoder {
  final RasterEncoderChannel _channel;

  /// Create an encoder with an optional custom channel.
  RasterImageEncoder({RasterEncoderChannel? channel})
    : _channel = channel ?? RasterEncoderChannel();

  /// Encode a [ui.Image] to JPEG bytes.
  ///
  /// Rasterizes the image to raw RGBA, then encodes via native codec.
  /// Falls back to PNG if native JPEG encoding is unavailable.
  ///
  /// [quality] — JPEG quality (0-100, default 85).
  Future<Uint8List?> encodeImageToJpeg(
    ui.Image image, {
    int quality = 85,
  }) async {
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) return null;

    final result = await _channel.encodeJpeg(
      rgba.buffer.asUint8List(),
      image.width,
      image.height,
      quality: quality,
    );

    if (result != null) return result;

    // Fallback: encode as BMP (no compression, but universally supported).
    return encodeBmp(rgba.buffer.asUint8List(), image.width, image.height);
  }

  /// Encode a [ui.Image] to WebP bytes.
  ///
  /// Rasterizes the image to raw RGBA, then encodes via native codec.
  /// Falls back to PNG if native WebP encoding is unavailable.
  ///
  /// [quality] — WebP quality (0-100, default 80).
  Future<Uint8List?> encodeImageToWebp(
    ui.Image image, {
    int quality = 80,
  }) async {
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) return null;

    final result = await _channel.encodeWebp(
      rgba.buffer.asUint8List(),
      image.width,
      image.height,
      quality: quality,
    );

    if (result != null) return result;

    // Fallback: encode as BMP.
    return encodeBmp(rgba.buffer.asUint8List(), image.width, image.height);
  }

  /// Encode raw RGBA pixels to JPEG via native encoder.
  ///
  /// Returns `null` if native encoding is not available.
  Future<Uint8List?> encodeRgbaToJpeg(
    Uint8List rgba,
    int width,
    int height, {
    int quality = 85,
  }) => _channel.encodeJpeg(rgba, width, height, quality: quality);

  /// Encode raw RGBA pixels to WebP via native encoder.
  ///
  /// Returns `null` if native encoding is not available.
  Future<Uint8List?> encodeRgbaToWebp(
    Uint8List rgba,
    int width,
    int height, {
    int quality = 80,
  }) => _channel.encodeWebp(rgba, width, height, quality: quality);

  // ---------------------------------------------------------------------------
  // BMP fallback
  // ---------------------------------------------------------------------------

  /// Encode raw RGBA pixels to BMP format (uncompressed).
  ///
  /// BMP is a simple format that any image viewer can open.
  /// Used as a fallback when native JPEG/WebP encoding is unavailable.
  ///
  /// This is public for testing — callers should prefer [encodeImageToJpeg]
  /// or [encodeImageToWebp] which delegate to native codecs.
  static Uint8List encodeBmp(Uint8List rgba, int width, int height) {
    // BMP stores rows bottom-to-top in BGRA order.
    final rowSize = width * 4;
    final paddedRowSize = (rowSize + 3) & ~3; // Pad to 4-byte boundary.
    final pixelDataSize = paddedRowSize * height;
    final headerSize = 54; // 14 (file header) + 40 (DIB header)
    final fileSize = headerSize + pixelDataSize;

    final bmp = ByteData(fileSize);
    int offset = 0;

    // ---- BMP File Header (14 bytes) ----
    bmp.setUint8(offset++, 0x42); // 'B'
    bmp.setUint8(offset++, 0x4D); // 'M'
    bmp.setUint32(offset, fileSize, Endian.little);
    offset += 4;
    bmp.setUint32(offset, 0, Endian.little); // Reserved
    offset += 4;
    bmp.setUint32(offset, headerSize, Endian.little); // Pixel data offset
    offset += 4;

    // ---- DIB Header (BITMAPINFOHEADER, 40 bytes) ----
    bmp.setUint32(offset, 40, Endian.little); // Header size
    offset += 4;
    bmp.setInt32(offset, width, Endian.little);
    offset += 4;
    bmp.setInt32(offset, height, Endian.little); // Positive = bottom-up
    offset += 4;
    bmp.setUint16(offset, 1, Endian.little); // Color planes
    offset += 2;
    bmp.setUint16(offset, 32, Endian.little); // Bits per pixel (BGRA)
    offset += 2;
    bmp.setUint32(offset, 0, Endian.little); // Compression (none)
    offset += 4;
    bmp.setUint32(offset, pixelDataSize, Endian.little);
    offset += 4;
    bmp.setInt32(offset, 2835, Endian.little); // H resolution (72 DPI)
    offset += 4;
    bmp.setInt32(offset, 2835, Endian.little); // V resolution (72 DPI)
    offset += 4;
    bmp.setUint32(offset, 0, Endian.little); // Colors in palette
    offset += 4;
    bmp.setUint32(offset, 0, Endian.little); // Important colors
    offset += 4;

    // ---- Pixel data (bottom-to-top, BGRA) ----
    for (int y = height - 1; y >= 0; y--) {
      for (int x = 0; x < width; x++) {
        final srcIdx = (y * width + x) * 4;
        bmp.setUint8(offset++, rgba[srcIdx + 2]); // B
        bmp.setUint8(offset++, rgba[srcIdx + 1]); // G
        bmp.setUint8(offset++, rgba[srcIdx + 0]); // R
        bmp.setUint8(offset++, rgba[srcIdx + 3]); // A
      }
      // Pad row to 4-byte boundary.
      final padding = paddedRowSize - rowSize;
      for (int p = 0; p < padding; p++) {
        bmp.setUint8(offset++, 0);
      }
    }

    return bmp.buffer.asUint8List();
  }
}
