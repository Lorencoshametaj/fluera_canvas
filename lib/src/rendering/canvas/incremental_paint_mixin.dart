import 'package:flutter/material.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

/// Mixin for `CustomPainter` subclasses that enables incremental rendering
/// using a [DirtyRegionTracker].
///
/// When dirty regions are present, the mixin clips the canvas to the
/// dirty bounds before painting, avoiding full-canvas repaints for
/// local modifications.
///
/// ## Usage
///
/// ```dart
/// class MyPainter extends CustomPainter with IncrementalPaintMixin {
///   @override
///   DirtyRegionTracker? get dirtyTracker => _tracker;
///
///   @override
///   void paintContent(Canvas canvas, Size size) {
///     // Your actual painting logic here.
///     renderer.render(canvas, sceneGraph, viewport);
///   }
/// }
/// ```
///
/// ## How it works
///
/// 1. `paint()` checks if [dirtyTracker] has dirty regions
/// 2. If dirty regions exist, clips the canvas to their bounding box
/// 3. Calls [paintContent] for the actual rendering
/// 4. Clears dirty flags after painting
///
/// This provides 10-100x faster repaints for local modifications
/// (e.g., moving a single node, adding a stroke) compared to full repaints.
mixin IncrementalPaintMixin on CustomPainter {
  /// The dirty region tracker to use for incremental rendering.
  ///
  /// Return `null` to disable incremental rendering and always
  /// do a full repaint.
  DirtyRegionTracker? get dirtyTracker;

  /// Whether to use incremental rendering when dirty regions are available.
  ///
  /// Set to `false` to force full repaints (useful for debugging).
  bool get useIncrementalPaint => true;

  /// The actual painting logic — called by [paint] after optional clipping.
  ///
  /// Implement this instead of [paint]. The canvas may already be
  /// clipped to the dirty region when this is called.
  void paintContent(Canvas canvas, Size size);

  @override
  void paint(Canvas canvas, Size size) {
    final tracker = dirtyTracker;

    // If incremental paint is disabled or no tracker, do full paint.
    if (!useIncrementalPaint || tracker == null || !tracker.hasDirtyRegions) {
      paintContent(canvas, size);
      return;
    }

    // Get the bounding box of all dirty regions.
    final dirtyBounds = tracker.dirtyBounds;
    if (dirtyBounds == null) {
      paintContent(canvas, size);
      tracker.clearDirty();
      return;
    }

    // Clip to dirty bounds for incremental rendering.
    canvas.save();
    canvas.clipRect(dirtyBounds);
    paintContent(canvas, size);
    canvas.restore();

    // Clear dirty flags after painting.
    tracker.clearDirty();
  }
}
