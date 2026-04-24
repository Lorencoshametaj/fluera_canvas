/// 🚀 PREDICTIVE STROKE RENDERER (ANTI-LAG)
///
/// Reduces perceived drawing latency by predicting the next 2-3 points
/// using quadratic extrapolation (velocity + acceleration).
///
/// STRATEGY:
/// 1. Track last 5 canvas-space points with microsecond timestamps
/// 2. Compute velocity (px/frame) and acceleration (Δv/frame)
/// 3. Extrapolate: predicted = last + v·Δt + 0.5·a·Δt²
/// 4. Draw a fading "ghost trail" that is replaced by the real stroke
///
/// IMPROVEMENT OVER V1:
/// - Quadratic extrapolation follows curves better than linear
/// - Pressure prediction via linear extrapolation of last 3 pressures
/// - Canvas-space math (no screen→canvas conversion needed)
/// - Int microsecond timestamps for consistency with engine
library;

import 'dart:ui';
import 'dart:math' as math;

/// A predicted point with both position and pressure.
class PredictedPoint {
  final Offset position;
  final double pressure;
  const PredictedPoint(this.position, this.pressure);
}

class PredictiveRenderer {
  /// Number of points to predict ahead.
  final int predictedPointsCount;

  /// Base opacity of the ghost trail (fades per predicted point).
  final double ghostOpacity;

  /// Velocity decay factor (0–1). Higher = predicted trail extends further.
  final double velocityDecay;

  /// Recent point history for velocity/acceleration calculation.
  final List<_PointWithTime> _recentPoints = [];
  static const int _maxRecentPoints = 6;

  PredictiveRenderer({
    this.predictedPointsCount = 2,
    this.ghostOpacity = 0.08,
    this.velocityDecay = 0.7,
  });

  // 🚀 CACHED objects for rendering (avoids allocation every frame)
  final Paint _ghostPaint =
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
  final Path _ghostPath = Path();

  /// Adds a canvas-space point with microsecond timestamp and pressure.
  void addPoint(Offset canvasPoint, int timestampUs, {double pressure = 0.5}) {
    _recentPoints.add(_PointWithTime(canvasPoint, timestampUs, pressure));
    if (_recentPoints.length > _maxRecentPoints) {
      _recentPoints.removeAt(0);
    }
  }

  /// Predict the next points using quadratic extrapolation.
  ///
  /// Returns [PredictedPoint]s with both position and pressure.
  /// Returns empty list if not enough history or speed is too low.
  List<PredictedPoint> predictWithPressure() {
    if (_recentPoints.length < 3) return const [];

    final velocity = _calculateVelocity();
    final acceleration = _calculateAcceleration();

    if (velocity.distance < 0.05) return const [];

    final lastPoint = _recentPoints.last;
    final predicted = <PredictedPoint>[];

    Offset currentVelocity = velocity;
    Offset currentPoint = lastPoint.point;

    // Pressure extrapolation: linear from last 3 pressures
    final pressureSlope = _calculatePressureSlope();
    double currentPressure = lastPoint.pressure;

    for (int i = 0; i < predictedPointsCount; i++) {
      // Quadratic: p_next = p + v + 0.5*a
      currentPoint = currentPoint + currentVelocity + acceleration * 0.5;
      currentVelocity = (currentVelocity + acceleration) * velocityDecay;
      currentPressure = (currentPressure + pressureSlope).clamp(0.1, 1.0);
      predicted.add(PredictedPoint(currentPoint, currentPressure));
    }

    return predicted;
  }

  /// Legacy API: predict positions only.
  List<Offset> predictNextPoints() {
    return predictWithPressure().map((p) => p.position).toList();
  }

  /// Whether enough history exists for meaningful prediction.
  bool get canPredict => _recentPoints.length >= 3;

  /// Draws the ghost trail (predicted stroke extension).
  ///
  /// [canvas] Canvas to draw on (already in canvas-space transform)
  /// [basePaint] The active brush paint (color, strokeWidth)
  /// [predictedPoints] Output from [predictNextPoints]
  void drawGhostTrail(
    Canvas canvas,
    Paint basePaint,
    List<Offset> predictedPoints,
  ) {
    if (predictedPoints.isEmpty || _recentPoints.isEmpty) return;

    // 🎯 FIX: Suppress ghost trail at low speeds — it's perceptible as a
    // "chasing" artifact during slow writing. Only show at moderate+ speed
    // where the latency reduction is actually beneficial.
    final velocity = _calculateVelocity();
    if (velocity.distance < 2.0) return; // < 2 px/frame → invisible ghost

    final lastActualPoint = _recentPoints.last.point;
    final count = predictedPoints.length;

    _ghostPath.reset();
    _ghostPath.moveTo(lastActualPoint.dx, lastActualPoint.dy);

    for (int i = 0; i < count; i++) {
      _ghostPath.lineTo(predictedPoints[i].dx, predictedPoints[i].dy);
    }

    // Very subtle ghost — 2% opacity, 70% width, slight blur
    _ghostPaint
      ..color = basePaint.color.withValues(alpha: ghostOpacity * 0.35)
      ..strokeWidth = basePaint.strokeWidth * 0.7
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5);

    canvas.drawPath(_ghostPath, _ghostPaint);
    _ghostPaint.maskFilter = null;
  }

  /// Frame time in seconds used for prediction step size.
  /// Default: 1/60 (60fps). Set to 1/120 on 120Hz devices via
  /// FrameBudgetManager's detected refresh rate.
  double frameTimeSeconds = 1.0 / 60.0;

  // ─── VELOCITY & ACCELERATION ───────────────────────────────────────

  /// Calculate velocity in canvas-pixels per frame.
  Offset _calculateVelocity() {
    if (_recentPoints.length < 2) return Offset.zero;

    // Use last 3 points for smoothed velocity
    final n = _recentPoints.length;
    final start = math.max(0, n - 3);

    double totalVelX = 0.0;
    double totalVelY = 0.0;
    int count = 0;

    for (int i = start + 1; i < n; i++) {
      final dt =
          (_recentPoints[i].timestampUs - _recentPoints[i - 1].timestampUs) /
          1000000.0;
      if (dt > 0.0001) {
        totalVelX +=
            (_recentPoints[i].point.dx - _recentPoints[i - 1].point.dx) / dt;
        totalVelY +=
            (_recentPoints[i].point.dy - _recentPoints[i - 1].point.dy) / dt;
        count++;
      }
    }

    if (count == 0) return Offset.zero;

    // Convert px/s → px/frame using actual device frame time
    return Offset(
      (totalVelX / count) * frameTimeSeconds,
      (totalVelY / count) * frameTimeSeconds,
    );
  }

  /// Calculate acceleration (Δvelocity per frame).
  Offset _calculateAcceleration() {
    if (_recentPoints.length < 4) return Offset.zero;

    final n = _recentPoints.length;

    // Velocity at two different time windows
    Offset v1 = Offset.zero;
    Offset v2 = Offset.zero;

    // v1: from points [n-4] → [n-3]
    final dt1 =
        (_recentPoints[n - 3].timestampUs - _recentPoints[n - 4].timestampUs) /
        1000000.0;
    if (dt1 > 0.0001) {
      v1 = Offset(
        (_recentPoints[n - 3].point.dx - _recentPoints[n - 4].point.dx) / dt1,
        (_recentPoints[n - 3].point.dy - _recentPoints[n - 4].point.dy) / dt1,
      );
    }

    // v2: from points [n-2] → [n-1]
    final dt2 =
        (_recentPoints[n - 1].timestampUs - _recentPoints[n - 2].timestampUs) /
        1000000.0;
    if (dt2 > 0.0001) {
      v2 = Offset(
        (_recentPoints[n - 1].point.dx - _recentPoints[n - 2].point.dx) / dt2,
        (_recentPoints[n - 1].point.dy - _recentPoints[n - 2].point.dy) / dt2,
      );
    }

    // Δv in px/s², then convert to px/frame²
    final totalDt =
        (_recentPoints[n - 1].timestampUs - _recentPoints[n - 3].timestampUs) /
        1000000.0;
    if (totalDt < 0.001) return Offset.zero;

    return Offset(
      ((v2.dx - v1.dx) / totalDt) * frameTimeSeconds * frameTimeSeconds,
      ((v2.dy - v1.dy) / totalDt) * frameTimeSeconds * frameTimeSeconds,
    );
  }

  /// Linear regression slope of the last 3 pressure values.
  double _calculatePressureSlope() {
    final n = _recentPoints.length;
    if (n < 3) return 0.0;

    final p0 = _recentPoints[n - 3].pressure;
    final p1 = _recentPoints[n - 2].pressure;
    final p2 = _recentPoints[n - 1].pressure;

    // Simple finite difference: (p2 - p0) / 2
    return (p2 - p0) / 2.0;
  }

  /// Current speed in px/s (for external consumers).
  double getCurrentSpeed() {
    final velocity = _calculateVelocity();
    return velocity.distance * 60.0; // px/frame → px/s
  }

  /// Current movement direction (unit vector), or zero if stationary.
  Offset getDirection() {
    if (_recentPoints.length < 2) return Offset.zero;

    final last = _recentPoints.last.point;
    final prev = _recentPoints[_recentPoints.length - 2].point;
    final direction = last - prev;

    if (direction.distance < 0.01) return Offset.zero;
    return direction / direction.distance;
  }

  /// Resets all history (call on stroke end / new stroke).
  void reset() {
    _recentPoints.clear();
  }
}

/// Internal point with microsecond timestamp and pressure.
class _PointWithTime {
  final Offset point;
  final int timestampUs;
  final double pressure;

  const _PointWithTime(this.point, this.timestampUs, this.pressure);
}
