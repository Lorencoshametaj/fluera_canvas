import 'package:flutter/material.dart';

/// 🚀 Costruttore di Path Optimizeti
///
/// RESPONSIBILITIES:
/// - ✅ Builds a SINGLE Path instead of N separate segments
/// - ✅ Catmull-Rom spline for professional smoothness
/// - ✅ Riduce draw calls da 100+ a 1
///
/// PERFORMANCE:
/// - Path unificato = 1 drawPath() invece di N drawPath()
/// - No repeated allocation of temporary Paths
/// - GPU rendering ottimizzato
class OptimizedPathBuilder {
  /// 🚀 Builds un Path ottimizzato con Catmull-Rom spline
  ///
  /// [points] Lista di punti (Offset o oggetti con .offset)
  /// [closeLoop] Se true, chiude il path collegando last point al primo
  static Path buildSmoothPath(List<dynamic> points, {bool closeLoop = false}) {
    final path = Path();

    if (points.isEmpty) return path;

    final firstOffset = _getOffset(points.first);
    path.moveTo(firstOffset.dx, firstOffset.dy);

    if (points.length == 1) {
      // Punto singolo: non serve path
      return path;
    } else if (points.length == 2) {
      // Due punti: linea diretta
      final secondOffset = _getOffset(points[1]);
      path.lineTo(secondOffset.dx, secondOffset.dy);
    } else if (points.length == 3) {
      // Tre punti: quadratic bezier per smoothness
      final p1 = _getOffset(points[1]);
      final p2 = _getOffset(points[2]);
      path.quadraticBezierTo(p1.dx, p1.dy, p2.dx, p2.dy);
    } else {
      // 🚀 Catmull-Rom spline for ultra-smooth curves
      // ALL segments in a SINGLE path!
      for (int i = 0; i < points.length - 1; i++) {
        final p0 = i > 0 ? _getOffset(points[i - 1]) : _getOffset(points[i]);
        final p1 = _getOffset(points[i]);
        final p2 = _getOffset(points[i + 1]);
        final p3 =
            i < points.length - 2
                ? _getOffset(points[i + 2])
                : _getOffset(points[i + 1]);

        // Calculate punti di controllo Catmull-Rom
        final cp1x = p1.dx + (p2.dx - p0.dx) / 6;
        final cp1y = p1.dy + (p2.dy - p0.dy) / 6;
        final cp2x = p2.dx - (p3.dx - p1.dx) / 6;
        final cp2y = p2.dy - (p3.dy - p1.dy) / 6;

        path.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
      }
    }

    if (closeLoop && points.length > 2) {
      path.close();
    }

    return path;
  }

  // ── Incremental path cache (zero rebuild per frame) ──
  static Path _cachedIncrPath = Path();
  static int _cachedIncrCount = 0;

  /// 🚀 Incremental Catmull-Rom path builder.
  ///
  /// Caches the path and appends only NEW segments since the last call.
  /// Cost: O(ΔN) per frame instead of O(N).
  /// Auto-resets when stroke restarts (point count decreases).
  static Path buildSmoothPathIncremental(List<dynamic> points) {
    if (points.isEmpty) {
      resetIncrementalPath();
      return _cachedIncrPath;
    }

    // Reset if new stroke (point count decreased or very small)
    if (points.length < _cachedIncrCount || points.length <= 2) {
      resetIncrementalPath();
    }

    // Full rebuild for very short strokes
    if (points.length <= 3) {
      _cachedIncrPath = buildSmoothPath(points);
      _cachedIncrCount = points.length;
      return _cachedIncrPath;
    }

    // First time or after reset — build from scratch
    if (_cachedIncrCount <= 2) {
      _cachedIncrPath = buildSmoothPath(points);
      _cachedIncrCount = points.length;
      return _cachedIncrPath;
    }

    // Append only new Catmull-Rom segments
    // Start from last cached segment (need i-1 for p0 context)
    final startIdx = _cachedIncrCount - 1;
    for (int i = startIdx; i < points.length - 1; i++) {
      final p0 = i > 0 ? _getOffset(points[i - 1]) : _getOffset(points[i]);
      final p1 = _getOffset(points[i]);
      final p2 = _getOffset(points[i + 1]);
      final p3 =
          i < points.length - 2
              ? _getOffset(points[i + 2])
              : _getOffset(points[i + 1]);

      final cp1x = p1.dx + (p2.dx - p0.dx) / 6;
      final cp1y = p1.dy + (p2.dy - p0.dy) / 6;
      final cp2x = p2.dx - (p3.dx - p1.dx) / 6;
      final cp2y = p2.dy - (p3.dy - p1.dy) / 6;

      _cachedIncrPath.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
    }

    _cachedIncrCount = points.length;
    return _cachedIncrPath;
  }

  /// Reset incremental path cache (call on stroke end/start).
  static void resetIncrementalPath() {
    _cachedIncrPath = Path();
    _cachedIncrCount = 0;
  }

  /// 🚀 Builds un Path con cerchi unificati (per giunzioni)
  ///
  /// [points] Lista di punti dove disegnare cerchi
  /// [radii] Lista di raggi corrispondenti (stesso length di points)
  static Path buildCirclesPath(List<Offset> points, List<double> radii) {
    final path = Path();

    for (int i = 0; i < points.length; i++) {
      final radius = i < radii.length ? radii[i] : radii.last;
      path.addOval(Rect.fromCircle(center: points[i], radius: radius));
    }

    return path;
  }

  /// 🚀 Builds Path lineare semplice (per evidenziatore)
  ///
  /// [points] Lista di punti
  static Path buildLinearPath(List<dynamic> points) {
    final path = Path();

    if (points.isEmpty) return path;

    final firstOffset = _getOffset(points.first);
    path.moveTo(firstOffset.dx, firstOffset.dy);

    for (int i = 1; i < points.length; i++) {
      final offset = _getOffset(points[i]);
      path.lineTo(offset.dx, offset.dy);
    }

    return path;
  }

  /// Estrae Offset da un punto (gestisce sia Offset che oggetti con .offset)
  static Offset _getOffset(dynamic point) {
    if (point is Offset) return point;
    return point.offset;
  }

  /// Calculates la lunghezza approssimativa del path
  static double estimatePathLength(List<dynamic> points) {
    if (points.length < 2) return 0;

    double length = 0;
    for (int i = 0; i < points.length - 1; i++) {
      final p1 = _getOffset(points[i]);
      final p2 = _getOffset(points[i + 1]);
      length += (p2 - p1).distance;
    }
    return length;
  }
}
