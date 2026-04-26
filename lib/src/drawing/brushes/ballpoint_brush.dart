import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

/// 🚀 Characteristics and rendering of the OPTIMIZED Ballpoint brush
///
/// FEATURES:
/// - Constant width (does not vary with pressure)
/// - Uniform and opaque color
/// - Ideal for precise writing
/// - Ballpoint ink effect
class BallpointBrush {
  /// 🚀 Pre-allocated buffers to avoid per-stroke GC pressure.
  /// Shared across all ballpoint stroke renders (single-threaded paint).
  static Float64List _sxBuf = Float64List(512);
  static Float64List _syBuf = Float64List(512);

  static void _ensureBuffers(int n) {
    if (_sxBuf.length < n) {
      final sz = n * 2; // grow 2×
      _sxBuf = Float64List(sz);
      _syBuf = Float64List(sz);
    }
  }

  /// Displayed tool name
  static const String name = 'Biro';

  /// Representative icon
  static const IconData icon = Icons.edit;

  /// Default width multiplier
  static const double defaultWidthMultiplier = 1.0;

  /// Opacity of the stroke (0.0-1.0)
  static const double opacity = 1.0;

  /// StrokeCap to use
  static const StrokeCap strokeCap = StrokeCap.round;

  /// StrokeJoin to use
  static const StrokeJoin strokeJoin = StrokeJoin.round;

  /// Use pressure to vary the width?
  static const bool usePressureForWidth = false;

  /// Use pressure to vary opacity?
  static const bool usePressureForOpacity = false;

  /// Does it have blur effect?
  static const bool hasBlur = false;

  /// 🚀 Draw a stroke with OPTIMIZED ballpoint brush
  static void drawStroke(
    Canvas canvas,
    List<dynamic>
    points, // Can be List<Offset> or List with .offset and .pressure
    Color color,
    double baseWidth,
  ) {
    drawStrokeWithSettings(
      canvas,
      points,
      color,
      baseWidth,
      minPressure: 0.7,
      maxPressure: 1.1,
    );
  }

  /// 🎛️ Draw with custom parameters from the dialog
  static void drawStrokeWithSettings(
    Canvas canvas,
    List<dynamic> points,
    Color color,
    double baseWidth, {
    required double minPressure,
    required double maxPressure,
    bool isLive = false,
    Path? cachedPath, // ignored — we use our own outline cache
  }) {
    if (points.isEmpty) return;

    if (points.length == 1) {
      final offset = StrokeOptimizer.getOffset(points.first);
      final paint = PaintPool.getFillPaint(color: color);
      canvas.drawCircle(offset, baseWidth * 0.5, paint);
      return;
    }

    // Ballpoint = constant width (midpoint of pressure range).
    final adjustedWidth =
        baseWidth * (minPressure + 0.5 * (maxPressure - minPressure));
    final halfW = adjustedWidth * 0.5;
    final fillPaint = PaintPool.getFillPaint(color: color);

    // ─────────────────────────────────────────────────────────────────
    // 🚀 FAST PATH: try cached outline for committed strokes.
    // The outline path includes smoothing + tangent computation +
    // left/right contour, cached once per stroke via Expando.
    // Cost: O(1) drawPath + 2× drawCircle vs O(N) full recomputation.
    // ─────────────────────────────────────────────────────────────────
    if (!isLive && points is List<Object>) {
      final cached = _outlineCache[points];
      if (cached != null) {
        // Replay cached outline + start/end circles
        canvas.drawCircle(cached.startCenter, halfW, fillPaint);
        canvas.drawCircle(cached.endCenter, halfW, fillPaint);
        canvas.drawPath(cached.outlinePath, fillPaint);
        return;
      }
    }

    // ─── SLOW PATH: compute smoothing → dense Catmull-Rom outline ──
    // 🚀 Uses static Float64List buffers to avoid per-stroke allocations
    // that cause GC pressure spikes on mid-range GPUs (Adreno 619).
    final n = points.length;
    _ensureBuffers(n);
    final sx = _sxBuf;
    final sy = _syBuf;
    for (int i = 0; i < n; i++) {
      final off = StrokeOptimizer.getOffset(points[i]);
      sx[i] = off.dx;
      sy[i] = off.dy;
    }

    // 2-pass bi-directional EMA (alpha=0.25) — matches C++ Vulkan
    if (n >= 4) {
      const double alpha = 0.25;
      for (int pass = 0; pass < 2; pass++) {
        for (int i = 1; i < n - 1; i++) {
          sx[i] = sx[i - 1] * alpha + sx[i] * (1.0 - alpha);
          sy[i] = sy[i - 1] * alpha + sy[i] * (1.0 - alpha);
        }
        for (int i = n - 2; i > 0; i--) {
          sx[i] = sx[i + 1] * alpha + sx[i] * (1.0 - alpha);
          sy[i] = sy[i + 1] * alpha + sy[i] * (1.0 - alpha);
        }
      }
    }

    // ─── Catmull-Rom dense sampling of the smoothed centerline ─────
    // Instead of building the outline from sparse smoothed points (which
    // produces visible straight segments), we densely sample a Catmull-Rom
    // spline through ALL smoothed points at ~1.5px intervals. This produces
    // an inherently smooth centerline — matching the C++ marker technique.
    const double sampleStep = 1.5;
    final List<double> denseX = [];
    final List<double> denseY = [];

    if (n >= 2) {
      for (int seg = 0; seg < n - 1; seg++) {
        final int i0 = seg > 0 ? seg - 1 : 0;
        final int i1 = seg;
        final int i2 = seg + 1;
        final int i3 = seg + 2 < n ? seg + 2 : n - 1;

        final double x0 = sx[i0], y0 = sy[i0];
        final double x1 = sx[i1], y1 = sy[i1];
        final double x2 = sx[i2], y2 = sy[i2];
        final double x3 = sx[i3], y3 = sy[i3];

        final double segDx = x2 - x1, segDy = y2 - y1;
        final double segLen = math.sqrt(segDx * segDx + segDy * segDy);
        final int nSamples = math.max(2, (segLen / sampleStep).ceil() + 1);

        for (int s = 0; s < nSamples; s++) {
          // Skip last sample except on final segment (avoid duplicates)
          if (seg < n - 2 && s == nSamples - 1) continue;

          final double t = s / (nSamples - 1);
          final double t2 = t * t;
          final double t3 = t2 * t;

          // Catmull-Rom basis (tension = 0.5)
          final double cx = 0.5 * ((2.0 * x1) +
              (-x0 + x2) * t +
              (2.0 * x0 - 5.0 * x1 + 4.0 * x2 - x3) * t2 +
              (-x0 + 3.0 * x1 - 3.0 * x2 + x3) * t3);
          final double cy = 0.5 * ((2.0 * y1) +
              (-y0 + y2) * t +
              (2.0 * y0 - 5.0 * y1 + 4.0 * y2 - y3) * t2 +
              (-y0 + 3.0 * y1 - 3.0 * y2 + y3) * t3);

          denseX.add(cx);
          denseY.add(cy);
        }
      }
    }

    final int dn = denseX.length;

    // Smoothed start/end centers (from dense samples)
    final startCenter = dn > 0
        ? Offset(denseX[0], denseY[0])
        : Offset(sx[0], sy[0]);
    final endCenter = dn > 0
        ? Offset(denseX[dn - 1], denseY[dn - 1])
        : Offset(sx[n - 1], sy[n - 1]);

    // Full circles at start and end (matching C++ generateCircle)
    canvas.drawCircle(startCenter, halfW, fillPaint);
    canvas.drawCircle(endCenter, halfW, fillPaint);

    // Outline path from dense samples (left contour → right contour)
    if (dn >= 2) {
      // Compute tangents on dense samples
      final List<double> dtx = List<double>.filled(dn, 0.0);
      final List<double> dty = List<double>.filled(dn, 0.0);
      for (int i = 0; i < dn; i++) {
        double tdx = 0, tdy = 0;
        if (i > 0) { tdx += denseX[i] - denseX[i - 1]; tdy += denseY[i] - denseY[i - 1]; }
        if (i < dn - 1) { tdx += denseX[i + 1] - denseX[i]; tdy += denseY[i + 1] - denseY[i]; }
        final double tlen = math.sqrt(tdx * tdx + tdy * tdy);
        if (tlen > 0.001) {
          dtx[i] = tdx / tlen;
          dty[i] = tdy / tlen;
        } else {
          dtx[i] = 1.0;
          dty[i] = 0.0;
        }
      }

      final path = Path();
      path.moveTo(denseX[0] + (-dty[0]) * halfW, denseY[0] + dtx[0] * halfW);

      for (int i = 1; i < dn; i++) {
        final dnx = -dty[i], dny = dtx[i];
        path.lineTo(denseX[i] + dnx * halfW, denseY[i] + dny * halfW);
      }

      for (int i = dn - 1; i >= 0; i--) {
        final dnx = -dty[i], dny = dtx[i];
        path.lineTo(denseX[i] - dnx * halfW, denseY[i] - dny * halfW);
      }

      path.close();
      canvas.drawPath(path, fillPaint);

      // 🚀 Cache the outline for committed strokes (non-live).
      // Keyed by the points list (identity-based via Expando).
      if (!isLive && points is List<Object>) {
        _outlineCache[points] = _CachedOutline(
          outlinePath: path,
          startCenter: startCenter,
          endCenter: endCenter,
        );
      }
    }
  }

  /// 🚀 Cached outline paths keyed by points list identity.
  /// Expando: auto-cleaned when the ProStroke (and its points list) is GC'd.
  static final Expando<_CachedOutline> _outlineCache =
      Expando<_CachedOutline>('ballpointOutline');


  /// Build a Catmull-Rom sub-path starting from [startIndex].
  static Path _buildSubPath(List<dynamic> points, int startIndex) {
    final path = Path();
    if (startIndex >= points.length) return path;
    final first = StrokeOptimizer.getOffset(points[startIndex]);
    path.moveTo(first.dx, first.dy);
    if (startIndex >= points.length - 1) return path;

    for (int i = startIndex; i < points.length - 1; i++) {
      final p0 =
          i > 0
              ? StrokeOptimizer.getOffset(points[i - 1])
              : StrokeOptimizer.getOffset(points[i]);
      final p1 = StrokeOptimizer.getOffset(points[i]);
      final p2 = StrokeOptimizer.getOffset(points[i + 1]);
      final p3 =
          i < points.length - 2
              ? StrokeOptimizer.getOffset(points[i + 2])
              : StrokeOptimizer.getOffset(points[i + 1]);
      path.cubicTo(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
        p2.dx,
        p2.dy,
      );
    }
    return path;
  }

  /// Build a Catmull-Rom sub-path from pre-smoothed Offsets.
  static Path _buildSubPathFromOffsets(List<Offset> pts, int startIndex) {
    final path = Path();
    if (startIndex >= pts.length) return path;
    path.moveTo(pts[startIndex].dx, pts[startIndex].dy);
    if (startIndex >= pts.length - 1) return path;

    for (int i = startIndex; i < pts.length - 1; i++) {
      final p0 = i > 0 ? pts[i - 1] : pts[i];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = i < pts.length - 2 ? pts[i + 2] : pts[i + 1];
      path.cubicTo(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
        p2.dx,
        p2.dy,
      );
    }
    return path;
  }

  /// Calculates the width for a specific point (ballpoint = constant)
  static double calculateWidth(double baseWidth, double pressure) {
    return baseWidth; // Constant width
  }

  /// Calculates the opacity for a specific point (ballpoint = opaque)
  static double calculateOpacity(double pressure) {
    return opacity; // Constant opacity
  }
}

/// 🚀 Cached outline data for ballpoint stroke fast path.
/// Stores the pre-computed outline path and start/end circle centers.
class _CachedOutline {
  final Path outlinePath;
  final Offset startCenter;
  final Offset endCenter;

  const _CachedOutline({
    required this.outlinePath,
    required this.startCenter,
    required this.endCenter,
  });
}
