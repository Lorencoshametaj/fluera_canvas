import 'dart:math' as math;
import 'package:fluera_canvas/fluera_canvas.dart';

/// 🚀 Douglas-Peucker point simplification for LOD rendering.
///
/// Reduces stroke point count at low zoom while preserving visual shape.
/// Adapted for ProDrawingPoint (preserves pressure at kept points).
///
/// Performance: O(N log N) average, reduces 200 points → 10-20 at low zoom.
class PointSimplifier {
  /// Simplify a list of ProDrawingPoint using Douglas-Peucker algorithm.
  ///
  /// [points] — original stroke points (`List<dynamic>`, elements are `ProDrawingPoint`)
  /// [tolerance] — max perpendicular distance to discard a point (in world units)
  ///
  /// Returns simplified list keeping start, end, and visually significant points.
  static List<dynamic> simplify(List<dynamic> points, double tolerance) {
    final n = points.length;
    if (n <= 4) return points; // too few to simplify

    // Boolean mask: which points to keep
    final keep = List<bool>.filled(n, false);
    keep[0] = true;
    keep[n - 1] = true;

    // Iterative stack-based Douglas-Peucker (avoids stack overflow on long strokes)
    final stack = <int>[];
    stack.add(0);
    stack.add(n - 1);

    while (stack.length >= 2) {
      final end = stack.removeLast();
      final start = stack.removeLast();

      // Find the point with maximum distance from the line (start → end)
      double maxDist = 0;
      int maxIndex = start;

      final p1 = _pos(points[start]);
      final p2 = _pos(points[end]);

      for (int i = start + 1; i < end; i++) {
        final d = _perpendicularDistance(_pos(points[i]), p1, p2);
        if (d > maxDist) {
          maxDist = d;
          maxIndex = i;
        }
      }

      // If max distance exceeds tolerance, keep that point and recurse
      if (maxDist > tolerance) {
        keep[maxIndex] = true;
        // Push right segment first (processed second = depth-first)
        if (maxIndex - start > 1) {
          stack.add(start);
          stack.add(maxIndex);
        }
        if (end - maxIndex > 1) {
          stack.add(maxIndex);
          stack.add(end);
        }
      }
    }

    // Build result from kept points
    final result = <dynamic>[];
    for (int i = 0; i < n; i++) {
      if (keep[i]) result.add(points[i]);
    }
    return result;
  }

  /// Calculate the tolerance based on current zoom scale.
  /// Lower zoom → higher tolerance → more aggressive simplification.
  ///
  /// At zoom 0.8: tolerance = 2.5 world units → ~2px screen (invisible)
  /// At zoom 0.3: tolerance = 6.7 world units → ~2px screen (invisible)
  /// At zoom 0.1: tolerance = 20 world units → ~2px screen (invisible)
  static double toleranceForScale(double scale) {
    return 2.0 / scale;
  }

  /// Extract position from a dynamic point (ProDrawingPoint or Offset).
  static _Pos _pos(dynamic point) {
    if (point is ProDrawingPoint) {
      return _Pos(point.position.dx, point.position.dy);
    } else if (point is Map) {
      // Legacy format
      final pos = point['position'];
      if (pos is Map) {
        return _Pos(
          (pos['dx'] as num).toDouble(),
          (pos['dy'] as num).toDouble(),
        );
      }
    }
    return const _Pos(0, 0);
  }

  /// Perpendicular distance from point to line segment (p1 → p2).
  static double _perpendicularDistance(_Pos point, _Pos p1, _Pos p2) {
    final dx = p2.x - p1.x;
    final dy = p2.y - p1.y;
    final lenSq = dx * dx + dy * dy;

    if (lenSq < 1e-10) {
      // Degenerate line: distance to p1
      final ddx = point.x - p1.x;
      final ddy = point.y - p1.y;
      return math.sqrt(ddx * ddx + ddy * ddy);
    }

    // Cross product gives area of parallelogram
    final cross = ((point.x - p1.x) * dy - (point.y - p1.y) * dx).abs();
    return cross / math.sqrt(lenSq);
  }
}

/// Lightweight position class to avoid Offset allocation overhead.
class _Pos {
  final double x;
  final double y;
  const _Pos(this.x, this.y);
}
