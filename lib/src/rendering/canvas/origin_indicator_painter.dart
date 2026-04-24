import 'package:flutter/material.dart';

/// ✚ ORIGIN INDICATOR — crosshair sottile all'origine (0,0)
///
/// Draws a minimalist crosshair at the canvas origin point.
/// Visible only at zoom ≥ 0.3x to not disturb at extreme zoom levels.
/// Si adatta inversamente allo zoom: size costante sullo schermo.
///
/// 🚀 NO repaint: during pan/zoom — updated only on widget rebuild
/// (stroke change). Wrappato in RepaintBoundary per isolamento.
class OriginIndicatorPainter extends CustomPainter {
  final double scale;

  const OriginIndicatorPainter({required this.scale});

  @override
  void paint(Canvas canvas, Size size) {
    // Do not mostrare a zoom troppo basso (< 0.3x)
    if (scale < 0.3) return;

    // Size crosshair costante sullo schermo (30px)
    // We divide by scale so it always appears the same size
    final armLength = 30.0 / scale;
    final strokeWidth = 0.8 / scale;

    // Color: very faint gray
    final paint =
        Paint()
          ..color = const Color(0x30000000) // black at 19%
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round;

    // Linea orizzontale
    canvas.drawLine(Offset(-armLength, 0), Offset(armLength, 0), paint);

    // Linea verticale
    canvas.drawLine(Offset(0, -armLength), Offset(0, armLength), paint);

    // Puntino centrale (leggermente more visibile)
    final dotPaint =
        Paint()
          ..color = const Color(0x40000000) // black at 25%
          ..style = PaintingStyle.fill;
    final dotRadius = 1.5 / scale;
    canvas.drawCircle(Offset.zero, dotRadius, dotPaint);
  }

  @override
  bool shouldRepaint(OriginIndicatorPainter oldDelegate) {
    // Repaint only thef the zoom cambia significativamente
    return (oldDelegate.scale - scale).abs() > 0.05;
  }
}
