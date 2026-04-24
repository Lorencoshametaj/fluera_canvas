import 'dart:ui' as ui;
import 'package:flutter/services.dart';

/// 🎨 Type of texture applicable to brushes
enum TextureType {
  none, // No texture
  pencilGrain, // Pencil grain on rough paper
  charcoal, // Heavy charcoal
  watercolor, // Watercolor stains
  canvas, // Canvas weave pattern
  kraft, // Kraft paper with fibers
}

/// 🔄 Texture rotation behavior along the stroke
enum TextureRotationMode {
  /// No rotation — texture is axis-aligned (paper-like grain)
  fixed,

  /// Rotate texture to follow stroke direction (default)
  followStroke,

  /// Random rotation per stroke for organic variation
  random,
}

/// 🎨 Professional Brush Texture System
///
/// Loads and caches tileable grayscale textures as `ui.Image`.
/// Textures are applied to strokes via `ImageShader` with `BlendMode.modulate`.
///
/// Singleton cache: each texture is loaded once into memory.
class BrushTexture {
  BrushTexture._();

  // Singleton cache of loaded textures
  static final Map<TextureType, ui.Image?> _cache = {};
  static final Map<TextureType, bool> _loading = {};

  /// Asset path for each texture type
  static const Map<TextureType, String> _assetPaths = {
    TextureType.pencilGrain: 'assets/textures/pencil_grain.png',
    TextureType.charcoal: 'assets/textures/charcoal.png',
    TextureType.watercolor: 'assets/textures/watercolor.png',
    TextureType.canvas: 'assets/textures/canvas_weave.png',
    TextureType.kraft: 'assets/textures/kraft_paper.png',
  };

  /// Package name used for asset resolution when consumed as a dependency.
  static const String _packageName = 'fluera_engine';

  /// Loads a texture asynchronously with caching.
  /// Returns `null` if the type is `none` or if loading fails.
  static Future<ui.Image?> load(TextureType type) async {
    if (type == TextureType.none) return null;

    // Cache hit
    if (_cache.containsKey(type)) return _cache[type];

    // Prevent duplicate loads
    if (_loading[type] == true) return null;
    _loading[type] = true;

    try {
      final path = _assetPaths[type];
      if (path == null) return null;

      // Try package-prefixed path first (required when consumed as a
      // dependency), then fall back to bare path (when running directly
      // from within the package).
      late final ByteData data;
      try {
        data = await rootBundle.load('packages/$_packageName/$path');
      } catch (_) {
        data = await rootBundle.load(path);
      }
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _cache[type] = frame.image;
      return frame.image;
    } catch (e) {
      _cache[type] = null;
      return null;
    } finally {
      _loading[type] = false;
    }
  }

  /// Get texture from the cache (sincrono, null if not caricata)
  static ui.Image? getCached(TextureType type) {
    return _cache[type];
  }

  /// Pre-load all textures (call at canvas startup)
  static Future<void> preloadAll() async {
    final futures = TextureType.values
        .where((t) => t != TextureType.none)
        .map((t) => load(t));
    await Future.wait(futures);
  }

  /// Creates un Paint con ImageShader for the texture
  ///
  /// [textureImage] L'immagine texture caricata
  /// [intensity] Intensità of the texture (0.0 = nessun effetto, 1.0 = pieno)
  /// [scale] Scala of the texture (1.0 = size originale)
  static ui.Paint? createTexturePaint({
    required ui.Image textureImage,
    double intensity = 1.0,
    double scale = 1.0,
  }) {
    final matrix = Matrix4.diagonal3Values(scale, scale, 1.0);

    final shader = ui.ImageShader(
      textureImage,
      ui.TileMode.repeated,
      ui.TileMode.repeated,
      matrix.storage,
    );

    return ui.Paint()
      ..shader = shader
      ..blendMode = ui.BlendMode.modulate
      ..color = ui.Color.fromARGB((intensity * 255).round(), 255, 255, 255);
  }

  /// Apply texture to a canvas over a path already drawn.
  ///
  /// Use `saveLayer` + `BlendMode.modulate` to mask the stroke
  /// with the texture grayscale.
  static void applyTextureToPath({
    required ui.Canvas canvas,
    required ui.Path path,
    required ui.Image textureImage,
    double intensity = 1.0,
    double scale = 1.0,
  }) {
    if (intensity <= 0.0) return;

    final texturePaint = createTexturePaint(
      textureImage: textureImage,
      intensity: intensity,
      scale: scale,
    );
    if (texturePaint == null) return;

    // The path is il bounds of the area su cui applicare la texture
    final bounds = path.getBounds();

    // Save layer per compositing
    canvas.saveLayer(bounds, ui.Paint());
    canvas.drawPath(path, texturePaint);
    canvas.restore();
  }

  /// Libera tutte le texture from the cache
  static void dispose() {
    for (final img in _cache.values) {
      img?.dispose();
    }
    _cache.clear();
  }
}
