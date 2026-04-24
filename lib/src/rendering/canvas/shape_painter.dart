import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:fluera_canvas/fluera_canvas.dart';

/// Painter for geometric shapes
class ShapePainter {
  /// Draws a geometric shape
  static void drawShape(
    Canvas canvas,
    GeometricShape shape, {
    bool isPreview = false,
  }) {
    // 🛠️ FIX: For preview, preserve the original color's alpha but add slight transparency effect
    // Instead of forcing 0.5, multiply existing alpha by 0.7 for preview effect
    final previewColor = shape.color.withValues(alpha: shape.color.a * 0.8);

    final paint =
        Paint()
          ..color = isPreview ? previewColor : shape.color
          ..strokeWidth = shape.strokeWidth
          ..style = shape.filled ? PaintingStyle.fill : PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

    // Apply gradient shader if present.
    final shapeBounds = Rect.fromPoints(shape.startPoint, shape.endPoint);
    if (shape.filled && shape.fillGradient != null) {
      paint.shader = shape.fillGradient!.toShader(shapeBounds);
    } else if (!shape.filled && shape.strokeGradient != null) {
      paint.shader = shape.strokeGradient!.toShader(shapeBounds);
    }

    switch (shape.type) {
      case ShapeType.freehand:
        // Do not gestito qui (è un stroke normale)
        break;

      case ShapeType.line:
        _drawLine(canvas, shape, paint);
        break;

      case ShapeType.rectangle:
        _drawRectangle(canvas, shape, paint);
        break;

      case ShapeType.circle:
        _drawCircle(canvas, shape, paint);
        break;

      case ShapeType.triangle:
        _drawTriangle(canvas, shape, paint);
        break;

      case ShapeType.arrow:
        _drawArrow(canvas, shape, paint);
        break;

      case ShapeType.star:
        _drawStar(canvas, shape, paint);
        break;

      case ShapeType.heart:
        _drawHeart(canvas, shape, paint);
        break;

      case ShapeType.diamond:
        _drawDiamond(canvas, shape, paint);
        break;

      case ShapeType.pentagon:
        _drawPentagon(canvas, shape, paint);
        break;

      case ShapeType.hexagon:
        _drawHexagon(canvas, shape, paint);
        break;
    }
  }

  /// Draws a straight line
  static void _drawLine(Canvas canvas, GeometricShape shape, Paint paint) {
    canvas.drawLine(shape.startPoint, shape.endPoint, paint);
  }

  /// Draws a rectangle
  static void _drawRectangle(Canvas canvas, GeometricShape shape, Paint paint) {
    final rect = Rect.fromPoints(shape.startPoint, shape.endPoint);
    canvas.drawRect(rect, paint);
  }

  /// Draws a circle/ellipse
  static void _drawCircle(Canvas canvas, GeometricShape shape, Paint paint) {
    final center = Offset(
      (shape.startPoint.dx + shape.endPoint.dx) / 2,
      (shape.startPoint.dy + shape.endPoint.dy) / 2,
    );
    final radiusX = (shape.endPoint.dx - shape.startPoint.dx).abs() / 2;
    final radiusY = (shape.endPoint.dy - shape.startPoint.dy).abs() / 2;

    if ((radiusX - radiusY).abs() < 10) {
      // Cerchio perfetto
      final radius = (radiusX + radiusY) / 2;
      canvas.drawCircle(center, radius, paint);
    } else {
      // Ellisse
      final rect = Rect.fromCenter(
        center: center,
        width: radiusX * 2,
        height: radiusY * 2,
      );
      canvas.drawOval(rect, paint);
    }
  }

  /// Draws a triangle
  static void _drawTriangle(Canvas canvas, GeometricShape shape, Paint paint) {
    final path = Path();

    // Punto in alto al centro
    final topPoint = Offset(
      (shape.startPoint.dx + shape.endPoint.dx) / 2,
      shape.startPoint.dy,
    );

    // Due punti alla base
    final bottomLeft = Offset(shape.startPoint.dx, shape.endPoint.dy);
    final bottomRight = Offset(shape.endPoint.dx, shape.endPoint.dy);

    path.moveTo(topPoint.dx, topPoint.dy);
    path.lineTo(bottomRight.dx, bottomRight.dy);
    path.lineTo(bottomLeft.dx, bottomLeft.dy);
    path.close();

    canvas.drawPath(path, paint);
  }

  /// Draws an arrow
  static void _drawArrow(Canvas canvas, GeometricShape shape, Paint paint) {
    final dx = shape.endPoint.dx - shape.startPoint.dx;
    final dy = shape.endPoint.dy - shape.startPoint.dy;
    final angle = math.atan2(dy, dx);

    // Body of an arrow
    canvas.drawLine(shape.startPoint, shape.endPoint, paint);

    // Size of the tip
    final arrowHeadLength = shape.strokeWidth * 8;
    final arrowHeadAngle = 25 * math.pi / 180; // 25 gradi

    // Punta sinistra
    final leftArrowX =
        shape.endPoint.dx - arrowHeadLength * math.cos(angle - arrowHeadAngle);
    final leftArrowY =
        shape.endPoint.dy - arrowHeadLength * math.sin(angle - arrowHeadAngle);

    // Right point
    final rightArrowX =
        shape.endPoint.dx - arrowHeadLength * math.cos(angle + arrowHeadAngle);
    final rightArrowY =
        shape.endPoint.dy - arrowHeadLength * math.sin(angle + arrowHeadAngle);

    // Draw le punte
    final arrowPath =
        Path()
          ..moveTo(leftArrowX, leftArrowY)
          ..lineTo(shape.endPoint.dx, shape.endPoint.dy)
          ..lineTo(rightArrowX, rightArrowY);

    canvas.drawPath(arrowPath, paint..style = PaintingStyle.stroke);

    // Fill punta (opzionale)
    if (shape.filled) {
      final fillPath =
          Path()
            ..moveTo(leftArrowX, leftArrowY)
            ..lineTo(shape.endPoint.dx, shape.endPoint.dy)
            ..lineTo(rightArrowX, rightArrowY)
            ..close();

      canvas.drawPath(
        fillPath,
        Paint()
          ..color = shape.color
          ..style = PaintingStyle.fill,
      );
    }
  }

  /// Draws a 5-pointed star
  static void _drawStar(Canvas canvas, GeometricShape shape, Paint paint) {
    final center = Offset(
      (shape.startPoint.dx + shape.endPoint.dx) / 2,
      (shape.startPoint.dy + shape.endPoint.dy) / 2,
    );
    final radiusX = (shape.endPoint.dx - shape.startPoint.dx).abs() / 2;
    final radiusY = (shape.endPoint.dy - shape.startPoint.dy).abs() / 2;
    final radius = (radiusX + radiusY) / 2;

    final path = Path();
    const points = 5;
    final innerRadius = radius * 0.4;

    for (int i = 0; i < points * 2; i++) {
      final angle = (i * math.pi / points) - math.pi / 2;
      final r = i.isEven ? radius : innerRadius;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    canvas.drawPath(path, paint);
  }

  /// Draws a heart
  static void _drawHeart(Canvas canvas, GeometricShape shape, Paint paint) {
    final width = (shape.endPoint.dx - shape.startPoint.dx).abs();
    final height = (shape.endPoint.dy - shape.startPoint.dy).abs();
    final centerX = (shape.startPoint.dx + shape.endPoint.dx) / 2;
    final topY = shape.startPoint.dy;

    final path = Path();

    // Parte superiore sinistra
    path.moveTo(centerX, topY + height * 0.3);
    path.cubicTo(
      centerX - width * 0.3,
      topY,
      centerX - width * 0.5,
      topY + height * 0.1,
      centerX - width * 0.5,
      topY + height * 0.3,
    );
    path.cubicTo(
      centerX - width * 0.5,
      topY + height * 0.5,
      centerX - width * 0.3,
      topY + height * 0.7,
      centerX,
      topY + height,
    );

    // Upper right part
    path.cubicTo(
      centerX + width * 0.3,
      topY + height * 0.7,
      centerX + width * 0.5,
      topY + height * 0.5,
      centerX + width * 0.5,
      topY + height * 0.3,
    );
    path.cubicTo(
      centerX + width * 0.5,
      topY + height * 0.1,
      centerX + width * 0.3,
      topY,
      centerX,
      topY + height * 0.3,
    );

    canvas.drawPath(path, paint);
  }

  /// Draws a diamond
  static void _drawDiamond(Canvas canvas, GeometricShape shape, Paint paint) {
    final centerX = (shape.startPoint.dx + shape.endPoint.dx) / 2;
    final centerY = (shape.startPoint.dy + shape.endPoint.dy) / 2;

    final path = Path();
    path.moveTo(centerX, shape.startPoint.dy); // Top
    path.lineTo(shape.endPoint.dx, centerY); // Right
    path.lineTo(centerX, shape.endPoint.dy); // Bottom
    path.lineTo(shape.startPoint.dx, centerY); // Left
    path.close();

    canvas.drawPath(path, paint);
  }

  /// Draws a pentagon
  static void _drawPentagon(Canvas canvas, GeometricShape shape, Paint paint) {
    final center = Offset(
      (shape.startPoint.dx + shape.endPoint.dx) / 2,
      (shape.startPoint.dy + shape.endPoint.dy) / 2,
    );
    final radiusX = (shape.endPoint.dx - shape.startPoint.dx).abs() / 2;
    final radiusY = (shape.endPoint.dy - shape.startPoint.dy).abs() / 2;
    final radius = (radiusX + radiusY) / 2;

    final path = Path();
    const sides = 5;

    for (int i = 0; i < sides; i++) {
      final angle = (i * 2 * math.pi / sides) - math.pi / 2;
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    canvas.drawPath(path, paint);
  }

  /// Draws a hexagon
  static void _drawHexagon(Canvas canvas, GeometricShape shape, Paint paint) {
    final center = Offset(
      (shape.startPoint.dx + shape.endPoint.dx) / 2,
      (shape.startPoint.dy + shape.endPoint.dy) / 2,
    );
    final radiusX = (shape.endPoint.dx - shape.startPoint.dx).abs() / 2;
    final radiusY = (shape.endPoint.dy - shape.startPoint.dy).abs() / 2;
    final radius = (radiusX + radiusY) / 2;

    final path = Path();
    const sides = 6;

    for (int i = 0; i < sides; i++) {
      final angle = (i * 2 * math.pi / sides) - math.pi / 2;
      final x = center.dx + radius * math.cos(angle);
      final y = center.dy + radius * math.sin(angle);

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    canvas.drawPath(path, paint);
  }
}
