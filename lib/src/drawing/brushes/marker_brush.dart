import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

/// 🖊️ Marker Brush — Flat-tip marker with miter-join triangle strip
///
/// RENDERING PARITY: Uses the SAME miter-join triangle strip approach
/// as the GPU (Vulkan/Metal) tessellateMarker, ensuring the live stroke
/// and committed stroke look identical.
///
/// CHARACTERISTICS:
/// - 🖊️ Constant width (baseWidth × 2.5, no pressure variation)
/// - 🖊️ Uniform opacity (0.7)
/// - 🖊️ Miter-join outlines from smoothed positions
/// - 🖊️ drawVertices triangle strip (matches GPU exactly)
class MarkerBrush {
  static const String name = 'Marker';
  static const IconData icon = Icons.format_paint_rounded;
  static const double baseWidthMultiplier = 2.5;
  static const double baseOpacity = 0.7;
  static const StrokeCap strokeCap = StrokeCap.round;
  static const StrokeJoin strokeJoin = StrokeJoin.round;

  /// Draw marker stroke with default settings
  static void drawStroke(
    Canvas canvas,
    List<dynamic> points,
    Color color,
    double baseWidth,
  ) {
    drawStrokeWithSettings(
      canvas,
      points,
      color,
      baseWidth,
      opacity: baseOpacity,
      flatness: 0.4,
    );
  }

  /// 🎛️ Draw with customizable settings (miter-join triangle strip)
  ///
  /// Uses the SAME algorithm as GPU tessellateMarker:
  /// 1. EMA position smoothing (bidirectional, α=0.35)
  /// 2. Miter-join tangent averaging at each point
  /// 3. Constant-width left/right outline
  /// 4. Triangle strip via drawVertices (zero overlap)
  static void drawStrokeWithSettings(
    Canvas canvas,
    List<dynamic> points,
    Color color,
    double baseWidth, {
    required double opacity,
    double flatness = 0.4,
  }) {
    if (points.isEmpty) return;

    final markerWidth = baseWidth * baseWidthMultiplier;
    final halfW = markerWidth * 0.5;

    if (points.length == 1) {
      final offset = StrokeOptimizer.getOffset(points.first);
      final rect = Rect.fromCenter(
        center: offset,
        width: markerWidth,
        height: markerWidth * (1.0 - flatness * 0.6),
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = color.withValues(alpha: opacity * color.a)
          ..style = PaintingStyle.fill,
      );
      return;
    }

    final n = points.length;

    // ── Extract positions ──
    final px = List<double>.filled(n, 0);
    final py = List<double>.filled(n, 0);
    for (int i = 0; i < n; i++) {
      final o = StrokeOptimizer.getOffset(points[i]);
      px[i] = o.dx;
      py[i] = o.dy;
    }

    // ── Catmull-Rom spline dense sampling (matches GPU tessellateMarker) ──
    // Densely sample a smooth cubic spline through all input points at ~1.5px
    // intervals. This produces an inherently smooth centerline — no post-
    // smoothing needed, and the perpendicular offsets produce smooth borders.
    const sampleStep = 1.5;

    final denseX = <double>[];
    final denseY = <double>[];

    for (int seg = 0; seg < n - 1; seg++) {
      final i0 = (seg > 0) ? seg - 1 : 0;
      final i1 = seg;
      final i2 = seg + 1;
      final i3 = (seg + 2 < n) ? seg + 2 : n - 1;

      final x0 = px[i0], y0 = py[i0];
      final x1 = px[i1], y1 = py[i1];
      final x2 = px[i2], y2 = py[i2];
      final x3 = px[i3], y3 = py[i3];

      final segDx = x2 - x1, segDy = y2 - y1;
      final segLen = math.sqrt(segDx * segDx + segDy * segDy);
      final nSamples = math.max(2, (segLen / sampleStep).toInt() + 1);

      for (int s = 0; s < nSamples; s++) {
        if (seg < n - 2 && s == nSamples - 1) continue;

        final t = s / (nSamples - 1);
        final t2 = t * t;
        final t3 = t2 * t;

        final cx = 0.5 * ((2.0 * x1) +
                          (-x0 + x2) * t +
                          (2.0 * x0 - 5.0 * x1 + 4.0 * x2 - x3) * t2 +
                          (-x0 + 3.0 * x1 - 3.0 * x2 + x3) * t3);
        final cy = 0.5 * ((2.0 * y1) +
                          (-y0 + y2) * t +
                          (2.0 * y0 - 5.0 * y1 + 4.0 * y2 - y3) * t2 +
                          (-y0 + 3.0 * y1 - 3.0 * y2 + y3) * t3);
        denseX.add(cx);
        denseY.add(cy);
      }
    }
    denseX.add(px[n - 1]);
    denseY.add(py[n - 1]);

    final dn = denseX.length;
    if (dn < 2) return;

    // ── Perpendicular offsets on dense spline samples ──
    final leftX = List<double>.filled(dn, 0);
    final leftY = List<double>.filled(dn, 0);
    final rightX = List<double>.filled(dn, 0);
    final rightY = List<double>.filled(dn, 0);

    for (int i = 0; i < dn; i++) {
      double tx = 0, ty = 0;
      if (i > 0) {
        tx += denseX[i] - denseX[i - 1];
        ty += denseY[i] - denseY[i - 1];
      }
      if (i < dn - 1) {
        tx += denseX[i + 1] - denseX[i];
        ty += denseY[i + 1] - denseY[i];
      }
      final tLen = math.sqrt(tx * tx + ty * ty);
      if (tLen > 0.0001) {
        tx /= tLen;
        ty /= tLen;
      } else {
        tx = 1;
        ty = 0;
      }
      final perpX = -ty;
      final perpY = tx;
      leftX[i] = denseX[i] + perpX * halfW;
      leftY[i] = denseY[i] + perpY * halfW;
      rightX[i] = denseX[i] - perpX * halfW;
      rightY[i] = denseY[i] - perpY * halfW;
    }

    // ── Build triangle strip as drawVertices ──
    final ma = (opacity * color.a).clamp(0.0, 1.0);
    final c = color.withValues(alpha: ma);
    final vertCount = (dn - 1) * 6;
    final positions = List<Offset>.filled(vertCount, Offset.zero);
    final colors = List<Color>.filled(vertCount, c);
    int vi = 0;

    for (int i = 0; i < dn - 1; i++) {
      positions[vi++] = Offset(leftX[i], leftY[i]);
      positions[vi++] = Offset(rightX[i], rightY[i]);
      positions[vi++] = Offset(leftX[i + 1], leftY[i + 1]);
      positions[vi++] = Offset(rightX[i], rightY[i]);
      positions[vi++] = Offset(leftX[i + 1], leftY[i + 1]);
      positions[vi++] = Offset(rightX[i + 1], rightY[i + 1]);
    }

    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      colors: colors,
    );

    canvas.drawVertices(
      vertices,
      ui.BlendMode.srcOver,
      Paint()..style = PaintingStyle.fill,
    );
  }
}
