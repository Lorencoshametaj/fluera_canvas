import 'dart:ui';
import 'package:fluera_canvas/fluera_canvas.dart';

/// Renders a [PathNode] to a [Canvas].
///
/// Draws fill layers bottom-to-top, then stroke layers bottom-to-top.
/// Falls back to legacy single fill/stroke if the paint stack is empty.
class PathRenderer {
  PathRenderer._();

  /// Draw the path node's fill and stroke stack.
  static void drawPathNode(Canvas canvas, PathNode node) {
    final flutterPath = node.path.toFlutterPath();
    final bounds = node.path.computeBounds();

    // --- Fill stack ---
    if (node.fills.isNotEmpty) {
      for (final fill in node.fills) {
        _drawFillLayer(canvas, fill, flutterPath, bounds);
      }
    } else {
      _drawLegacyFill(canvas, node, flutterPath, bounds);
    }

    // --- Stroke stack ---
    if (node.strokes.isNotEmpty) {
      for (final stroke in node.strokes) {
        _drawStrokeLayer(canvas, stroke, flutterPath, bounds);
      }
    } else {
      _drawLegacyStroke(canvas, node, flutterPath, bounds);
    }
  }

  // ---------------------------------------------------------------------------
  // Stack-based rendering
  // ---------------------------------------------------------------------------

  /// Draw a single fill layer with proper opacity compositing.
  static void _drawFillLayer(
    Canvas canvas,
    FillLayer fill,
    Path path,
    Rect bounds,
  ) {
    if (!fill.isVisible) return;

    // Gradient + sub-1.0 opacity needs a saveLayer for correct compositing.
    if (fill.type == FillType.gradient &&
        fill.gradient != null &&
        fill.opacity < 1.0) {
      canvas.saveLayer(
        null,
        Paint()
          ..color = Color.fromARGB((fill.opacity * 255).round(), 255, 255, 255),
      );
      final paint =
          Paint()
            ..style = PaintingStyle.fill
            ..isAntiAlias = true
            ..shader = fill.gradient!.toShader(bounds)
            ..blendMode = fill.blendMode;
      canvas.drawPath(path, paint);
      canvas.restore();
      return;
    }

    final paint = fill.toPaint(bounds);
    if (paint != null) {
      canvas.drawPath(path, paint);
    }
  }

  /// Draw a single stroke layer with position, dash, and opacity handling.
  static void _drawStrokeLayer(
    Canvas canvas,
    StrokeLayer stroke,
    Path originalPath,
    Rect bounds,
  ) {
    if (!stroke.isVisible) return;
    if (stroke.color == null && stroke.gradient == null) return;

    // Build paint without the position/dash transformations.
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke.width
          ..strokeCap = stroke.cap
          ..strokeJoin = stroke.join
          ..strokeMiterLimit = 4.0
          ..isAntiAlias = true
          ..blendMode = stroke.blendMode;

    // Apply color or gradient.
    final needsOpacityLayer = stroke.opacity < 1.0 && stroke.gradient != null;
    if (stroke.gradient != null && bounds.isFinite && !bounds.isEmpty) {
      paint.shader = stroke.gradient!.toShader(bounds);
    } else if (stroke.color != null) {
      paint.color = stroke.color!.withValues(
        alpha: stroke.color!.a * stroke.opacity,
      );
    } else {
      return;
    }

    // Apply dash pattern (decompose path using PathMetrics).
    final drawPath =
        stroke.dashPattern != null && stroke.dashPattern!.isNotEmpty
            ? applyDashPattern(originalPath, stroke.dashPattern!)
            : originalPath;

    // Wrap in opacity layer for gradient.
    if (needsOpacityLayer) {
      canvas.saveLayer(
        null,
        Paint()
          ..color = Color.fromARGB(
            (stroke.opacity * 255).round(),
            255,
            255,
            255,
          ),
      );
    }

    // Draw based on stroke position.
    switch (stroke.position) {
      case StrokePosition.center:
        canvas.drawPath(drawPath, paint);
        break;

      case StrokePosition.inside:
        canvas.save();
        canvas.clipPath(originalPath);
        paint.strokeWidth = stroke.width * 2;
        canvas.drawPath(drawPath, paint);
        canvas.restore();
        break;

      case StrokePosition.outside:
        // Draw with doubled width, then erase the interior half using dstOut.
        canvas.saveLayer(null, Paint());
        paint.strokeWidth = stroke.width * 2;
        canvas.drawPath(drawPath, paint);
        // Erase the inside portion.
        canvas.drawPath(
          originalPath,
          Paint()
            ..style = PaintingStyle.fill
            ..blendMode = BlendMode.dstOut,
        );
        canvas.restore();
        break;
    }

    if (needsOpacityLayer) {
      canvas.restore();
    }
  }

  // ---------------------------------------------------------------------------
  // Dash pattern helper
  // ---------------------------------------------------------------------------

  /// Decompose a path into dashes using [PathMetrics].
  static Path applyDashPattern(Path source, List<double> pattern) {
    if (pattern.isEmpty) return source;

    final result = Path();
    for (final metric in source.computeMetrics()) {
      double distance = 0;
      int patIndex = 0;
      bool drawing = true;

      while (distance < metric.length) {
        final segLen = pattern[patIndex % pattern.length];
        final end = (distance + segLen).clamp(0.0, metric.length);

        if (drawing) {
          final extracted = metric.extractPath(distance, end);
          result.addPath(extracted, Offset.zero);
        }

        distance = end;
        patIndex++;
        drawing = !drawing;
      }
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Legacy fallback
  // ---------------------------------------------------------------------------

  static void _drawLegacyFill(
    Canvas canvas,
    PathNode node,
    Path path,
    Rect bounds,
  ) {
    // ignore: deprecated_member_use_from_same_package
    if (node.fillColor == null && node.fillGradient == null) return;
    final fillPaint = Paint()..style = PaintingStyle.fill;
    // ignore: deprecated_member_use_from_same_package
    if (node.fillGradient != null) {
      // ignore: deprecated_member_use_from_same_package
      fillPaint.shader = node.fillGradient!.toShader(bounds);
      // ignore: deprecated_member_use_from_same_package
    } else if (node.fillColor != null) {
      // ignore: deprecated_member_use_from_same_package
      fillPaint.color = node.fillColor!;
    }
    canvas.drawPath(path, fillPaint);
  }

  static void _drawLegacyStroke(
    Canvas canvas,
    PathNode node,
    Path path,
    Rect bounds,
  ) {
    // ignore: deprecated_member_use_from_same_package
    if (node.strokeColor == null && node.strokeGradient == null) return;
    final strokePaint =
        Paint()
          ..style = PaintingStyle.stroke
          // ignore: deprecated_member_use_from_same_package
          ..strokeWidth = node.strokeWidth
          // ignore: deprecated_member_use_from_same_package
          ..strokeCap = node.strokeCap
          // ignore: deprecated_member_use_from_same_package
          ..strokeJoin = node.strokeJoin;
    // ignore: deprecated_member_use_from_same_package
    if (node.strokeGradient != null) {
      // ignore: deprecated_member_use_from_same_package
      strokePaint.shader = node.strokeGradient!.toShader(bounds);
      // ignore: deprecated_member_use_from_same_package
    } else if (node.strokeColor != null) {
      // ignore: deprecated_member_use_from_same_package
      strokePaint.color = node.strokeColor!;
    }
    canvas.drawPath(path, strokePaint);
  }
}
