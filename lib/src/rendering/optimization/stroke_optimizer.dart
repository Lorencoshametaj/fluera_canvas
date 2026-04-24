import 'package:flutter/material.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

/// 🚀 Optimizetore di Strokes per ridurre draw calls
///
/// RESPONSIBILITIES:
/// - ✅ Calculate average widths/opacity instead of per-segment
/// - ✅ Smoothing ottimizzato
/// - ✅ Riduzione dati for performance
///
/// PERFORMANCE:
/// - From N different Paint configurations → 1 Paint configuration
/// - Efficient smoothing with weighted average
class StrokeOptimizer {
  /// 🚀 Calculate larghezza MEDIA da una list of larghezze
  ///
  /// Invece di disegnare ogni segmento with therghezza diversa,
  /// uses an average width for the entire stroke.
  /// This permette A SINGLE drawPath() instead of N.
  static double calculateAverageWidth(List<double> widths) {
    if (widths.isEmpty) return 0;

    double total = 0;
    for (final width in widths) {
      total += width;
    }
    return total / widths.length;
  }

  /// 🚀 Calculate opacity MEDIA da una list of opacity
  static double calculateAverageOpacity(List<double> opacities) {
    if (opacities.isEmpty) return 1.0;

    double total = 0;
    for (final opacity in opacities) {
      total += opacity;
    }
    return total / opacities.length;
  }

  /// 🚀 Optimized width smoothing
  ///
  /// Use weighted average for smooth transitions without too many calculations
  static List<double> smoothWidths(List<double> widths) {
    if (widths.length < 3) return widths;

    final smoothed = <double>[];

    // Primo punto: invariato
    smoothed.add(widths.first);

    // Punti intermedi: weighted average (more peso at the point corrente)
    for (int i = 1; i < widths.length - 1; i++) {
      final avg = (widths[i - 1] + widths[i] * 2 + widths[i + 1]) / 4;
      smoothed.add(avg);
    }

    // Ultimo punto: invariato
    smoothed.add(widths.last);

    return smoothed;
  }

  /// 🚀 Opacity smoothing (same logic as widths)
  static List<double> smoothOpacities(List<double> opacities) {
    if (opacities.length < 3) return opacities;

    final smoothed = <double>[];
    smoothed.add(opacities.first);

    for (int i = 1; i < opacities.length - 1; i++) {
      final avg = (opacities[i - 1] + opacities[i] * 2 + opacities[i + 1]) / 4;
      smoothed.add(avg);
    }

    smoothed.add(opacities.last);
    return smoothed;
  }

  /// Calculates larghezze basate su pressione
  ///
  /// [points] Punti with pressure
  /// [baseWidth] Larghezza base
  /// [minFactor] Fattore minimo moltiplicativo
  /// [maxFactor] Fattore massimo moltiplicativo
  static List<double> calculatePressureWidths(
    List<dynamic> points,
    double baseWidth, {
    double minFactor = 0.3,
    double maxFactor = 1.5,
  }) {
    final widths = <double>[];

    for (final point in points) {
      final pressure = _getPressure(point);
      final factor = minFactor + (pressure * (maxFactor - minFactor));
      widths.add(baseWidth * factor);
    }

    return widths;
  }

  /// Calculates opacity basate su pressione
  ///
  /// [points] Punti with pressure
  /// [baseOpacity] Opacity base
  /// [maxOpacity] Opacity massima
  static List<double> calculatePressureOpacities(
    List<dynamic> points,
    double baseOpacity,
    double maxOpacity,
  ) {
    final opacities = <double>[];

    for (final point in points) {
      final pressure = _getPressure(point);
      opacities.add(baseOpacity + (pressure * (maxOpacity - baseOpacity)));
    }

    return opacities;
  }

  /// Estrae pressione da un punto (default 0.5 if not disponibile)
  /// Uses type check instead of try/catch — avoids exception overhead in hot path.
  static double _getPressure(dynamic point) {
    if (point is Offset) return 0.5;
    if (point is ProDrawingPoint) return point.pressure;
    return 0.5;
  }

  /// Estrae Offset da un punto
  static Offset getOffset(dynamic point) {
    if (point is Offset) return point;
    return point.offset;
  }

  /// Riduce number of punti for performance (sampling)
  ///
  /// [points] Punti originali
  /// [targetCount] Numero target di punti (0 = nessuna riduzione)
  static List<dynamic> reducePoints(List<dynamic> points, int targetCount) {
    if (targetCount <= 0 || points.length <= targetCount) {
      return points;
    }

    final reduced = <dynamic>[];
    final step = points.length / targetCount;

    for (int i = 0; i < targetCount; i++) {
      final index = (i * step).floor();
      if (index < points.length) {
        reduced.add(points[index]);
      }
    }

    // Always includi l'last point
    if (reduced.last != points.last) {
      reduced.add(points.last);
    }

    return reduced;
  }
}
