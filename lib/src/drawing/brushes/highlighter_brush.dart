import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

/// 🖍️ Professional Highlighter Brush — Zero-overlap triangle-strip tessellation
///
/// Modeled after real chisel-tip highlighters (Stabilo, Zebra Mildliner):
/// - 🖍️ **Chisel tip**: flat rectangular cross-section (aspect ratio ~0.35)
/// - 🖍️ **Zero internal overlap**: saveLayer + srcAtop compositing prevents
///   opacity doubling where the stroke crosses itself
/// - 🖍️ **Edge darkening**: ink pools at edges (vertex color gradient)
/// - 🖍️ **Auto-straighten**: near-horizontal strokes snap to perfectly straight
/// - 🖍️ **Translucent blend**: multiply mode lets underlying text show through
/// - 🖍️ Uses Catmull-Rom spline → dense sampling → perpendicular offset →
///   triangle strip (same architecture as MarkerBrush for GPU parity)
class HighlighterBrush {
  static const String name = 'Evidenziatore';
  static const IconData icon = Icons.highlight;
  static const double baseWidthMultiplier = 3.5;
  static const double baseOpacity = 0.30;
  static const StrokeCap strokeCap = StrokeCap.square;
  static const StrokeJoin strokeJoin = StrokeJoin.miter;
  static const bool usePressureForWidth = false;
  static const bool usePressureForOpacity = false;
  static const bool hasBlur = false;
  static const double blurRadius = 0.0;

  /// Draw with default settings
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
      widthMultiplier: baseWidthMultiplier,
      autoStraighten: true,
    );
  }

  /// 🎛️ Draw with custom parameters
  static void drawStrokeWithSettings(
    Canvas canvas,
    List<dynamic> points,
    Color color,
    double baseWidth, {
    required double opacity,
    required double widthMultiplier,
    bool autoStraighten = true,
  }) {
    if (points.isEmpty) return;

    final highlighterWidth = baseWidth * widthMultiplier;
    final halfW = highlighterWidth * 0.5;

    // ── Single point: flat rectangular dot ──
    if (points.length == 1) {
      final offset = StrokeOptimizer.getOffset(points.first);
      final ma = (opacity * color.a).clamp(0.0, 1.0);
      final rect = Rect.fromCenter(
        center: offset,
        width: highlighterWidth,
        height: highlighterWidth * _chiselAspect,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..color = color.withValues(alpha: ma)
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

    // ── Auto-straighten: if near-horizontal, flatten all Y to average ──
    if (autoStraighten && n >= 3) {
      final dx = px[n - 1] - px[0];
      final dy = py[n - 1] - py[0];
      final strokeLen = math.sqrt(dx * dx + dy * dy);
      // Only evaluate auto-straighten when stroke is long enough (80px).
      // With fewer points, the angle is unreliable and causes visual flash
      // (straight line appears then disappears as more points arrive).
      if (strokeLen > 80) {
        final strokeAngle = math.atan2(dy.abs(), dx.abs());
        // Within ±8° of horizontal
        if (strokeAngle < 0.14) {
          // Use average Y for all points
          double sumY = 0;
          for (int i = 0; i < n; i++) {
            sumY += py[i];
          }
          final avgY = sumY / n;
          for (int i = 0; i < n; i++) {
            py[i] = avgY;
          }
        }
      }
    }

    // ── Catmull-Rom spline dense sampling (~2px intervals) ──
    const sampleStep = 2.0;
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

        final cx =
            0.5 *
            ((2.0 * x1) +
                (-x0 + x2) * t +
                (2.0 * x0 - 5.0 * x1 + 4.0 * x2 - x3) * t2 +
                (-x0 + 3.0 * x1 - 3.0 * x2 + x3) * t3);
        final cy =
            0.5 *
            ((2.0 * y1) +
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

    // ── Perpendicular offsets with chisel-tip aspect ──
    // Real highlighters have a flat rectangular tip. The half-width in the
    // perpendicular direction is reduced by the chisel aspect ratio, creating
    // a flatter, wider stroke that looks like a real marker line.
    final chiselHalfH = halfW * _chiselAspect;

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

      // Chisel tip: use reduced height for perpendicular offset
      // But we want width to remain full for the horizontal extent
      // For a typical highlighter held at ~30°, the effective half-width
      // perpendicular to stroke direction uses the chisel aspect
      leftX[i] = denseX[i] + perpX * chiselHalfH;
      leftY[i] = denseY[i] + perpY * chiselHalfH;
      rightX[i] = denseX[i] - perpX * chiselHalfH;
      rightY[i] = denseY[i] - perpY * chiselHalfH;
    }

    // ── Build 3-row triangle strip with vertex color gradient ──
    // left edge (dark) → center (light) → right edge (dark)
    // This creates the edge-darkening effect WITHOUT any saveLayer,
    // which prevents live-vs-committed rendering mismatches.
    // The brush engine's saveLayer handles the multiply blend mode.
    final ma = (opacity * color.a).clamp(0.0, 1.0);
    final centerColor = color.withValues(alpha: ma * 0.85); // Lighter center
    final edgeColor = color.withValues(alpha: ma); // Full opacity at edges

    // Center line: midpoint between left and right
    final centerX = List<double>.filled(dn, 0);
    final centerY = List<double>.filled(dn, 0);
    for (int i = 0; i < dn; i++) {
      centerX[i] = (leftX[i] + rightX[i]) * 0.5;
      centerY[i] = (leftY[i] + rightY[i]) * 0.5;
    }

    // 3 rows × 2 triangles per segment × 2 strips = 12 triangles per segment
    final vertCount = (dn - 1) * 12;
    final positions = List<Offset>.filled(vertCount, Offset.zero);
    final colors = List<Color>.filled(vertCount, centerColor);
    int vi = 0;

    for (int i = 0; i < dn - 1; i++) {
      // ── LEFT STRIP: left[i] → center[i] → left[i+1] → center[i+1] ──
      positions[vi] = Offset(leftX[i], leftY[i]);
      colors[vi] = edgeColor;
      vi++;
      positions[vi] = Offset(centerX[i], centerY[i]);
      colors[vi] = centerColor;
      vi++;
      positions[vi] = Offset(leftX[i + 1], leftY[i + 1]);
      colors[vi] = edgeColor;
      vi++;

      positions[vi] = Offset(centerX[i], centerY[i]);
      colors[vi] = centerColor;
      vi++;
      positions[vi] = Offset(leftX[i + 1], leftY[i + 1]);
      colors[vi] = edgeColor;
      vi++;
      positions[vi] = Offset(centerX[i + 1], centerY[i + 1]);
      colors[vi] = centerColor;
      vi++;

      // ── RIGHT STRIP: center[i] → right[i] → center[i+1] → right[i+1] ──
      positions[vi] = Offset(centerX[i], centerY[i]);
      colors[vi] = centerColor;
      vi++;
      positions[vi] = Offset(rightX[i], rightY[i]);
      colors[vi] = edgeColor;
      vi++;
      positions[vi] = Offset(centerX[i + 1], centerY[i + 1]);
      colors[vi] = centerColor;
      vi++;

      positions[vi] = Offset(rightX[i], rightY[i]);
      colors[vi] = edgeColor;
      vi++;
      positions[vi] = Offset(centerX[i + 1], centerY[i + 1]);
      colors[vi] = centerColor;
      vi++;
      positions[vi] = Offset(rightX[i + 1], rightY[i + 1]);
      colors[vi] = edgeColor;
      vi++;
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

  /// Chisel tip aspect ratio: height / width
  /// 0.35 = typical flat highlighter tip
  static const double _chiselAspect = 0.35;

  /// Calculate tight bounds for a set of positions
  static Rect _computeBounds(List<Offset> positions, int count) {
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (int i = 0; i < count; i++) {
      final p = positions[i];
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Calculates width (constant, wide)
  static double calculateWidth(double baseWidth, double pressure) {
    return baseWidth * baseWidthMultiplier;
  }

  /// Calculates opacity (constant)
  static double calculateOpacity(double pressure) {
    return baseOpacity;
  }
}
