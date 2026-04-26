import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/nodes/image_node.dart';

/// MVP painter for [ImageNode]s on the free `fluera_canvas` core.
///
/// Decoded `ui.Image`s are stored in a process-wide cache keyed by
/// [ImageElement.imagePath] — the consumer (or the image tool) decodes
/// once and registers the resulting handle here, then every subsequent
/// paint pass blits via `Canvas.drawImageRect`. No LOD, no native
/// image processor, no colour adjustments — those live in
/// `fluera_engine`'s richer `ImagePainter` (depends on
/// `ImageMemoryManager` + `NativeImageProcessor`, not extractable to
/// the free SDK).
///
/// Cache discipline: callers that load an image MUST also call
/// [evict] when the corresponding node is permanently removed (e.g.
/// after the history evictor drops the op that owned it). Otherwise
/// the GPU resource leaks for the lifetime of the process.
class ImageNodePainter {
  ImageNodePainter._();

  static final Map<String, ui.Image> _cache = <String, ui.Image>{};

  /// Register a decoded [image] under [imagePath]. Replaces any
  /// previous handle stored under the same key (the previous handle
  /// is disposed). Returns the new handle for fluent use.
  static ui.Image cache(String imagePath, ui.Image image) {
    final old = _cache[imagePath];
    if (!identical(old, image)) {
      old?.dispose();
    }
    _cache[imagePath] = image;
    return image;
  }

  /// Look up the cached `ui.Image` for [imagePath], or `null` when
  /// nothing has been registered yet.
  static ui.Image? get(String imagePath) => _cache[imagePath];

  /// True if [imagePath] has a cached handle.
  static bool isCached(String imagePath) => _cache.containsKey(imagePath);

  /// Drop the cached handle for [imagePath]. Idempotent.
  static void evict(String imagePath) {
    final image = _cache.remove(imagePath);
    image?.dispose();
  }

  /// Drop every cached handle (testing convenience).
  @visibleForTesting
  static void clearCache() {
    for (final image in _cache.values) {
      image.dispose();
    }
    _cache.clear();
  }

  /// Paint [node] into [canvas] in **world coordinates**. The caller
  /// is expected to have already applied the camera transform; this
  /// painter only applies the per-image position / scale / rotation
  /// taken from `node.imageElement` and `node.localTransform` is
  /// folded in via `concat` so that future selection-driven
  /// translate/rotate/scale ops show up correctly.
  ///
  /// No-op when the underlying `ui.Image` hasn't been registered yet
  /// (e.g. during the first frame after a file pick — the codec is
  /// async and the cache is populated post-decode).
  static void paint(Canvas canvas, ImageNode node) {
    final element = node.imageElement;
    final image = _cache[element.imagePath];
    if (image == null) return;
    canvas.save();
    if (!_isIdentity(node.localTransform.storage)) {
      canvas.transform(node.localTransform.storage);
    }
    final pos = element.position;
    canvas.translate(pos.dx, pos.dy);
    final w = node.imageSize.width > 0
        ? node.imageSize.width
        : image.width.toDouble();
    final h = node.imageSize.height > 0
        ? node.imageSize.height
        : image.height.toDouble();
    if (element.rotation != 0.0) {
      canvas.translate(w * element.scale * 0.5, h * element.scale * 0.5);
      canvas.rotate(element.rotation);
      canvas.translate(-w * element.scale * 0.5, -h * element.scale * 0.5);
    }
    if (element.scale != 1.0) {
      canvas.scale(element.scale);
    }
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dst = Rect.fromLTWH(0, 0, w, h);
    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (element.opacity != 1.0) {
      paint.color = Color.fromRGBO(0, 0, 0, element.opacity);
      canvas.saveLayer(dst, paint);
      canvas.drawImageRect(
        image,
        src,
        dst,
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
    } else {
      canvas.drawImageRect(image, src, dst, paint);
    }
    canvas.restore();
  }

  static bool _isIdentity(List<double> s) {
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
}
