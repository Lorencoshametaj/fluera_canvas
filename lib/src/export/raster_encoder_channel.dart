/// 🖼️ RASTER ENCODER CHANNEL — Platform channel bridge for native image encoding.
///
/// Delegates JPEG and WebP encoding to native iOS/Android codecs via
/// platform channels for optimal performance and quality.
///
/// Falls back gracefully when native encoding is unavailable.
///
/// ```dart
/// final channel = RasterEncoderChannel();
/// final jpeg = await channel.encodeJpeg(rgbaBytes, 800, 600, quality: 85);
/// final webp = await channel.encodeWebp(rgbaBytes, 800, 600, quality: 80);
/// ```
library;

import 'dart:typed_data'; // ignore: unnecessary_import
import 'package:flutter/services.dart';

// =============================================================================
// RASTER ENCODER CHANNEL
// =============================================================================

/// Platform channel for native JPEG/WebP encoding.
///
/// Uses the platform's native image codecs (Core Graphics on iOS,
/// Android Bitmap on Android) for high-quality, efficient encoding.
class RasterEncoderChannel {
  static const _channel = MethodChannel('fluera_engine/image_encoder');

  /// Whether the native encoder is available.
  ///
  /// This is `null` until the first call to [_checkAvailability].
  bool? _available;

  /// Check if the native encoder is available on this platform.
  Future<bool> get isAvailable async {
    if (_available != null) return _available!;
    try {
      final result = await _channel.invokeMethod<bool>('isAvailable');
      _available = result ?? false;
    } catch (_) {
      _available = false;
    }
    return _available!;
  }

  /// Encode raw RGBA pixel data to JPEG.
  ///
  /// [rgba] — Raw RGBA pixel data (4 bytes per pixel).
  /// [width] — Image width in pixels.
  /// [height] — Image height in pixels.
  /// [quality] — JPEG quality (0-100, default 85).
  ///
  /// Returns the encoded JPEG bytes, or `null` if encoding failed.
  Future<Uint8List?> encodeJpeg(
    Uint8List rgba,
    int width,
    int height, {
    int quality = 85,
  }) async {
    if (!await isAvailable) return null;
    try {
      final result = await _channel.invokeMethod<Uint8List>('encodeJpeg', {
        'rgba': rgba,
        'width': width,
        'height': height,
        'quality': quality.clamp(0, 100),
      });
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Encode raw RGBA pixel data to WebP.
  ///
  /// [rgba] — Raw RGBA pixel data (4 bytes per pixel).
  /// [width] — Image width in pixels.
  /// [height] — Image height in pixels.
  /// [quality] — WebP quality (0-100, default 80).
  ///
  /// Returns the encoded WebP bytes, or `null` if encoding failed.
  Future<Uint8List?> encodeWebp(
    Uint8List rgba,
    int width,
    int height, {
    int quality = 80,
  }) async {
    if (!await isAvailable) return null;
    try {
      final result = await _channel.invokeMethod<Uint8List>('encodeWebp', {
        'rgba': rgba,
        'width': width,
        'height': height,
        'quality': quality.clamp(0, 100),
      });
      return result;
    } catch (_) {
      return null;
    }
  }
}
