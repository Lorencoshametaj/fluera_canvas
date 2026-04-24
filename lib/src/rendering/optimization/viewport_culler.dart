import 'dart:math' as math;
import 'dart:ui';
import 'package:fluera_canvas/fluera_canvas.dart';
import './spatial_index.dart';

/// 🚀 VIEWPORT CULLER - Rendering optimization with spatial culling
///
/// PERFORMANCE:
/// - ✅ Draw SOLO visible elements in the viewport
/// - ✅ Spatial indexing for O(log n) search instead of O(n)
/// - ✅ Pre-calculated bounds for each stroke/shape
/// - ✅ Safety margin to avoid pop-in during pan
/// - 🚀 QuadTree for 10k+ strokes
///
/// ESEMPIO:
/// - Canvas 100k x 100k with 10,000 strokes
/// - Viewport 1080 x 1920 pixel
/// - Without culling: 10,000 rendered strokes = LAG
/// - With culling: ~50-100 rendered strokes = SMOOTH ✨
class ViewportCuller {
  /// Margin around the viewport to avoid pop-in during pan
  static const double viewportMargin = 1000.0;

  /// 🚀 QUADTREE: uses QuadTree when there are many strokes (> threshold)
  static const int quadTreeThreshold = 500;

  /// 🚀 Filtra strokes visibili - con supporto QuadTree per grandi quantity
  ///
  /// If spatialIndex is fornito e costruito, usa O(log n) query
  /// Otherwise use fallback O(n) with cached bounds
  static List<ProStroke> filterVisibleStrokesOptimized(
    List<ProStroke> strokes,
    Rect viewport, {
    double margin = viewportMargin,
    SpatialIndexManager? spatialIndex,
  }) {
    if (strokes.isEmpty) return [];

    // 🚀 If we have a spatial index and there are many strokes, use QuadTree
    if (spatialIndex != null &&
        spatialIndex.isBuilt &&
        strokes.length > quadTreeThreshold) {
      return spatialIndex.queryVisibleStrokes(viewport, margin: margin);
    }

    // Fallback: filtering lineare O(n) ma con bounds cachati O(1) per stroke
    return filterVisibleStrokes(strokes, viewport, margin: margin);
  }

  /// 🚀 Filtra shapes visibili - con supporto QuadTree per grandi quantity
  static List<GeometricShape> filterVisibleShapesOptimized(
    List<GeometricShape> shapes,
    Rect viewport, {
    double margin = viewportMargin,
    SpatialIndexManager? spatialIndex,
  }) {
    if (shapes.isEmpty) return [];

    // 🚀 If we have a spatial index, use QuadTree
    if (spatialIndex != null &&
        spatialIndex.isBuilt &&
        shapes.length > quadTreeThreshold) {
      return spatialIndex.queryVisibleShapes(viewport, margin: margin);
    }

    // Fallback: filtering lineare
    return filterVisibleShapes(shapes, viewport, margin: margin);
  }

  /// Checks se uno stroke is visible in the viewport
  /// 🚀 USA BOUNDS CACHATI for performance O(1) invece di O(n)
  static bool isStrokeVisible(
    ProStroke stroke,
    Rect viewport, {
    double margin = viewportMargin,
  }) {
    // 🚀 Use cached bounds from the stroke (O(1) after first call)
    final bounds = stroke.bounds;
    if (bounds == Rect.zero) return false;

    // Espandi viewport con margine
    final expandedViewport = viewport.inflate(margin);

    // Check intersezione
    return expandedViewport.overlaps(bounds);
  }

  /// Checks if a shape is visible in the viewport
  static bool isShapeVisible(
    GeometricShape shape,
    Rect viewport, {
    double margin = viewportMargin,
  }) {
    final bounds = getShapeBounds(shape);

    // Espandi viewport con margine
    final expandedViewport = viewport.inflate(margin);

    return expandedViewport.overlaps(bounds);
  }

  /// Filters list of strokes per visibility
  static List<ProStroke> filterVisibleStrokes(
    List<ProStroke> strokes,
    Rect viewport, {
    double margin = viewportMargin,
  }) {
    if (strokes.isEmpty) return [];

    return strokes
        .where((stroke) => isStrokeVisible(stroke, viewport, margin: margin))
        .toList();
  }

  /// Filters list of shapes per visibility
  static List<GeometricShape> filterVisibleShapes(
    List<GeometricShape> shapes,
    Rect viewport, {
    double margin = viewportMargin,
  }) {
    if (shapes.isEmpty) return [];

    return shapes
        .where((shape) => isShapeVisible(shape, viewport, margin: margin))
        .toList();
  }

  /// Calculates bounds di uno stroke
  static Rect? getStrokeBounds(ProStroke stroke) {
    if (stroke.points.isEmpty) return null;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final point in stroke.points) {
      if (point.position.dx < minX) minX = point.position.dx;
      if (point.position.dy < minY) minY = point.position.dy;
      if (point.position.dx > maxX) maxX = point.position.dx;
      if (point.position.dy > maxY) maxY = point.position.dy;
    }

    // Add padding for the stroke width
    final padding = stroke.baseWidth * 2;

    return Rect.fromLTRB(
      minX - padding,
      minY - padding,
      maxX + padding,
      maxY + padding,
    );
  }

  /// Calculates bounds di una shape
  static Rect getShapeBounds(GeometricShape shape) {
    final padding = shape.strokeWidth * 2;

    return Rect.fromPoints(shape.startPoint, shape.endPoint).inflate(padding);
  }

  /// Calculates current viewport in canvas coordinates.
  /// When [rotation] is non-zero, inflates the viewport to cover the
  /// rotated screen area (axis-aligned bounding box of the rotated rect).
  static Rect calculateViewport(
    Size screenSize,
    Offset canvasOffset,
    double canvasScale, {
    double rotation = 0.0,
  }) {
    if (rotation == 0.0) {
      // Fast path: no rotation — original math
      final topLeft = (-canvasOffset) / canvasScale;
      final bottomRight = Offset(
        topLeft.dx + (screenSize.width / canvasScale),
        topLeft.dy + (screenSize.height / canvasScale),
      );
      return Rect.fromPoints(topLeft, bottomRight);
    }

    // 🌀 ROTATION-AWARE: Transform all 4 screen corners to canvas space.
    // The rendering transform is: translate(offset) → rotate(θ) → scale(s)
    // Inverse: undo scale → undo rotate → undo translate
    //   canvasPoint = rotate(-θ, (screenPoint - offset)) / scale
    final cosR = math.cos(-rotation);
    final sinR = math.sin(-rotation);

    Offset screenToCanvas(double sx, double sy) {
      final tx = sx - canvasOffset.dx;
      final ty = sy - canvasOffset.dy;
      final rx = tx * cosR - ty * sinR;
      final ry = tx * sinR + ty * cosR;
      return Offset(rx / canvasScale, ry / canvasScale);
    }

    // Transform all 4 screen corners
    final c0 = screenToCanvas(0, 0);
    final c1 = screenToCanvas(screenSize.width, 0);
    final c2 = screenToCanvas(screenSize.width, screenSize.height);
    final c3 = screenToCanvas(0, screenSize.height);

    // Axis-aligned bounding box of the rotated viewport in canvas space
    double minX = c0.dx, maxX = c0.dx, minY = c0.dy, maxY = c0.dy;
    for (final c in [c1, c2, c3]) {
      if (c.dx < minX) minX = c.dx;
      if (c.dx > maxX) maxX = c.dx;
      if (c.dy < minY) minY = c.dy;
      if (c.dy > maxY) maxY = c.dy;
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// 🔍 ADAPTIVE LOD: Skip strokes that are too small to be visible.
  ///
  /// At low zoom levels, tiny strokes (e.g., dots, small marks) occupy
  /// sub-pixel area on screen and are invisible. Skipping them saves
  /// rendering time without any visual change.
  ///
  /// **Safety**: This NEVER modifies stroke geometry. Strokes are either
  /// rendered at full fidelity or skipped entirely. No path simplification.
  ///
  /// [minScreenPixels] — minimum screen-space size to render (default: 1.5px).
  /// A stroke whose largest dimension × scale < this threshold is skipped.
  static List<ProStroke> applyAdaptiveLOD(
    List<ProStroke> strokes,
    double canvasScale, {
    double minScreenPixels = 1.5,
  }) {
    if (strokes.isEmpty || canvasScale >= 0.5) return strokes;

    return strokes.where((stroke) {
      final bounds = stroke.bounds;
      if (bounds == Rect.zero) return false;
      // Largest canvas-space dimension → screen pixels
      final screenSize =
          (bounds.width > bounds.height ? bounds.width : bounds.height) *
          canvasScale;
      return screenSize >= minScreenPixels;
    }).toList();
  }
}
