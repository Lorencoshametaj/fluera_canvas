/// 🎯 POST-STROKE OPTIMIZER
///
/// Refines the stroke after it was completed:
/// - Uniform resampling (punti a distanza costante)
/// - Finale Bézier pass to eliminate micromovimenti
/// - Anti-aliasing migliorato
///
/// Features:
/// - Douglas-Peucker simplification
/// - Uniform point distribution
/// - Final smoothing pass
library;

import 'dart:ui';
import 'dart:math' as math;

class PostStrokeOptimizer {
  /// Tolleranza per simplification (more alta = more aggressiva)
  final double simplificationTolerance;

  /// Distanza target for aiform resampling
  final double targetPointDistance;

  /// Enable final Bézier pass
  final bool enableFinalSmoothing;

  PostStrokeOptimizer({
    this.simplificationTolerance = 0.5,
    this.targetPointDistance = 3.0,
    this.enableFinalSmoothing = true,
  });

  /// Optimize un tratto completo
  List<Offset> optimize(List<Offset> points) {
    if (points.length < 3) return points;

    // Step 1: Douglas-Peucker simplification
    var optimized = _douglasPeucker(points, simplificationTolerance);

    // Step 2: Uniform resampling
    optimized = _uniformResample(optimized, targetPointDistance);

    // Step 3: Final smoothing pass
    if (enableFinalSmoothing && optimized.length >= 3) {
      optimized = _finalSmoothingPass(optimized);
    }

    return optimized;
  }

  /// Douglas-Peucker algorithm per simplification
  List<Offset> _douglasPeucker(List<Offset> points, double tolerance) {
    if (points.length < 3) return points;

    // Find punto more distante from the linea start-end
    double maxDistance = 0.0;
    int maxIndex = 0;

    final start = points.first;
    final end = points.last;

    for (int i = 1; i < points.length - 1; i++) {
      final distance = _perpendicularDistance(points[i], start, end);
      if (distance > maxDistance) {
        maxDistance = distance;
        maxIndex = i;
      }
    }

    // If max distance > tolerance, ricorsione
    if (maxDistance > tolerance) {
      // Ricorsione sulle due parti
      final left = _douglasPeucker(points.sublist(0, maxIndex + 1), tolerance);
      final right = _douglasPeucker(points.sublist(maxIndex), tolerance);

      // Merge (rimuovi il punto duplicato)
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      // All points are close to the line, keep only start and end
      return [start, end];
    }
  }

  /// Distanza perpendicolare da un punto a una linea
  double _perpendicularDistance(
    Offset point,
    Offset lineStart,
    Offset lineEnd,
  ) {
    final dx = lineEnd.dx - lineStart.dx;
    final dy = lineEnd.dy - lineStart.dy;

    if (dx == 0 && dy == 0) {
      // Linea degenere (un punto)
      return (point - lineStart).distance;
    }

    // Formula: |det| / |v|
    final det =
        (dx * (lineStart.dy - point.dy) - (lineStart.dx - point.dx) * dy).abs();
    final norm = math.sqrt(dx * dx + dy * dy);

    return det / norm;
  }

  /// Uniform resampling: distribuisce punti a distanza costante
  List<Offset> _uniformResample(List<Offset> points, double targetDistance) {
    if (points.length < 2) return points;

    final resampled = <Offset>[points.first];
    double accumulatedDistance = 0.0;

    for (int i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final segmentDistance = (curr - prev).distance;

      accumulatedDistance += segmentDistance;

      // If accumulato >= target, aggiungi punto
      while (accumulatedDistance >= targetDistance) {
        // Interpola punto a distanza esatta
        final excess = accumulatedDistance - targetDistance;
        final ratio = (segmentDistance - excess) / segmentDistance;
        final newPoint = Offset.lerp(prev, curr, ratio)!;

        resampled.add(newPoint);
        accumulatedDistance -= targetDistance;
      }
    }

    // Always add the last point
    if (resampled.last != points.last) {
      resampled.add(points.last);
    }

    return resampled;
  }

  /// Final smoothing pass: applica lieve Bézier to eliminate micromovimenti
  List<Offset> _finalSmoothingPass(List<Offset> points) {
    if (points.length < 3) return points;

    final smoothed = <Offset>[points.first];

    for (int i = 1; i < points.length - 1; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final next = points[i + 1];

      // Media pesata: 25% prev, 50% curr, 25% next
      final smoothedPoint = Offset(
        prev.dx * 0.25 + curr.dx * 0.5 + next.dx * 0.25,
        prev.dy * 0.25 + curr.dy * 0.5 + next.dy * 0.25,
      );

      smoothed.add(smoothedPoint);
    }

    smoothed.add(points.last);
    return smoothed;
  }

  /// Calculates lunghezza totale del path
  double calculatePathLength(List<Offset> points) {
    if (points.length < 2) return 0.0;

    double totalLength = 0.0;
    for (int i = 1; i < points.length; i++) {
      totalLength += (points[i] - points[i - 1]).distance;
    }
    return totalLength;
  }

  /// Calculates smoothness (more basso = more smooth)
  double calculateSmoothness(List<Offset> points) {
    if (points.length < 3) return 0.0;

    double totalCurvature = 0.0;
    for (int i = 1; i < points.length - 1; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final next = points[i + 1];

      // Calculate angolo
      final v1 = curr - prev;
      final v2 = next - curr;

      final angle = math.atan2(v2.dy, v2.dx) - math.atan2(v1.dy, v1.dx);
      totalCurvature += angle.abs();
    }

    return totalCurvature / (points.length - 2);
  }
}
