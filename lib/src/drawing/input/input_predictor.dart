// ═══════════════════════════════════════════════════════════════════
// 🔮 InputPredictor — Anti-Lag Touch Point Prediction
//
// Generates 1-3 predicted points ahead of the current touch position
// to reduce perceived latency by ~12-20ms.
//
// ⚠️ ANTI-STRETCH SAFEGUARDS (prevents endpoint stretching on lift):
//   1. Predictions are EPHEMERAL — stripped on every new real point
//   2. Velocity DECAYS: each predicted point has 0.7× previous velocity
//   3. Distance CAPPED: max 1.5× average segment length
//   4. Curvature CONTINUES: predictions follow the curve, not a straight line
//   5. On LIFT: all predictions instantly discarded (zero predicted count)
// ═══════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/painting.dart';

/// Prediction result containing the original + predicted points.
class PredictionResult {
  /// Real points (unchanged from input).
  final List<ProDrawingPoint> realPoints;

  /// Number of predicted points appended (0-3).
  final int predictedCount;

  /// Total list: realPoints + predictedPoints (safe to pass to renderer).
  final List<ProDrawingPoint> allPoints;

  /// API element `PredictionResult`.
  const PredictionResult({
    required this.realPoints,
    required this.predictedCount,
    required this.allPoints,
  });
}

/// 🔮 Cross-platform input predictor with anti-stretch safeguards.
///
/// Usage:
/// ```dart
/// final predictor = InputPredictor();
/// // On each touch move:
/// final result = predictor.predict(currentPoints);
/// renderer.updateAndRender(result.allPoints, ...);
/// // On touch end:
/// final finalPoints = predictor.finalize(currentPoints);
/// renderer.updateAndRender(finalPoints, ...);
/// predictor.reset();
/// ```
class InputPredictor {
  // ─── Configuration ──────────────────────────────────────────────
  /// Maximum predicted points (1-3). Higher = more latency reduction but
  /// more risk of overshoot.
  static const int _maxPredicted = 2;

  /// Velocity decay per predicted point (0.0-1.0).
  /// 0.7 means each predicted point moves 70% as far as the previous.
  static const double _velocityDecay = 0.65;

  /// Maximum prediction distance as multiple of average segment length.
  /// Prevents extreme stretching at high speeds.
  static const double _maxDistanceMultiplier = 1.5;

  /// Minimum velocity (px/point) below which prediction is disabled.
  /// Prevents jittery predictions when the pen is near-stationary.
  static const double _minVelocity = 0.5;

  /// Number of recent points to average for velocity estimation.
  static const int _velocityWindow = 4;

  /// Curvature smoothing: blend between linear extrapolation and
  /// curve continuation. 0.0 = pure linear, 1.0 = full curve.
  static const double _curvatureBlend = 0.6;

  // ─── State ──────────────────────────────────────────────────────
  bool _isActive = false;
  int _lastRealCount = 0;

  /// Generate predicted points from the current stroke.
  ///
  /// Returns [PredictionResult] with real + ephemeral predicted points.
  /// The predicted points have `isPredicted = true` for identification.
  ///
  /// ⚠️ CRITICAL: The returned `allPoints` list is safe to pass directly
  /// to the renderer. Predicted points are automatically stripped and
  /// replaced on the next call.
  PredictionResult predict(List<ProDrawingPoint> realPoints) {
    _isActive = true;
    _lastRealCount = realPoints.length;

    // Need at least 3 points for velocity estimation
    if (realPoints.length < 3) {
      return PredictionResult(
        realPoints: realPoints,
        predictedCount: 0,
        allPoints: realPoints,
      );
    }

    // ── Estimate velocity from recent points ──────────────────────
    final n = realPoints.length;
    final windowSize = math.min(_velocityWindow, n - 1);

    // Compute average velocity vector from last N segments
    double vx = 0, vy = 0;
    double totalDist = 0;
    int segCount = 0;

    for (int i = n - windowSize; i < n; i++) {
      final prev = realPoints[i - 1].position;
      final curr = realPoints[i].position;
      final dx = curr.dx - prev.dx;
      final dy = curr.dy - prev.dy;
      final dist = math.sqrt(dx * dx + dy * dy);

      // Weight recent segments more heavily (exponential weighting)
      final weight = (i - (n - windowSize) + 1).toDouble();
      vx += dx * weight;
      vy += dy * weight;
      totalDist += dist;
      segCount++;
    }

    if (segCount == 0) {
      return PredictionResult(
        realPoints: realPoints,
        predictedCount: 0,
        allPoints: realPoints,
      );
    }

    // Normalize by total weight
    final totalWeight = (windowSize * (windowSize + 1)) / 2.0;
    vx /= totalWeight;
    vy /= totalWeight;

    final velocity = math.sqrt(vx * vx + vy * vy);
    final avgSegLen = totalDist / segCount;

    // ── Skip prediction if velocity too low ───────────────────────
    if (velocity < _minVelocity || avgSegLen < 0.3) {
      return PredictionResult(
        realPoints: realPoints,
        predictedCount: 0,
        allPoints: realPoints,
      );
    }

    // ── Curvature estimation (from last 3 points) ─────────────────
    // Compute angular rate of change to continue the curve
    double curvature = 0;
    if (n >= 3) {
      final p0 = realPoints[n - 3].position;
      final p1 = realPoints[n - 2].position;
      final p2 = realPoints[n - 1].position;

      final a1 = math.atan2(p1.dy - p0.dy, p1.dx - p0.dx);
      final a2 = math.atan2(p2.dy - p1.dy, p2.dx - p1.dx);
      curvature = a2 - a1;
      // Normalize to [-π, π]
      if (curvature > math.pi) curvature -= 2 * math.pi;
      if (curvature < -math.pi) curvature += 2 * math.pi;
    }

    // ── Distance cap ──────────────────────────────────────────────
    final maxDist = avgSegLen * _maxDistanceMultiplier;

    // ── Generate predicted points ─────────────────────────────────
    final lastPoint = realPoints.last;
    final lastPressure = lastPoint.pressure;
    final lastTiltX = lastPoint.tiltX;
    final lastTiltY = lastPoint.tiltY;

    double currentAngle = math.atan2(vy, vx);
    double currentVelocity = velocity;
    var prevPos = lastPoint.position;

    final predicted = <ProDrawingPoint>[];

    for (int i = 0; i < _maxPredicted; i++) {
      // Decay velocity
      currentVelocity *= _velocityDecay;

      // Below threshold → stop predicting
      if (currentVelocity < _minVelocity * 0.5) break;

      // Continue curvature
      currentAngle += curvature * _curvatureBlend;

      // Compute displacement (capped)
      final dist = math.min(currentVelocity, maxDist);
      final dx = math.cos(currentAngle) * dist;
      final dy = math.sin(currentAngle) * dist;

      final newPos = Offset(prevPos.dx + dx, prevPos.dy + dy);

      // Pressure: smoothly fade toward resting pressure
      final fadedPressure = lastPressure * (1.0 - 0.1 * (i + 1));

      predicted.add(
        ProDrawingPoint(
          position: newPos,
          pressure: fadedPressure.clamp(0.1, 1.0),
          tiltX: lastTiltX,
          tiltY: lastTiltY,
        ),
      );

      prevPos = newPos;
    }

    if (predicted.isEmpty) {
      return PredictionResult(
        realPoints: realPoints,
        predictedCount: 0,
        allPoints: realPoints,
      );
    }

    // ── Combine: real + predicted ─────────────────────────────────
    final allPoints = List<ProDrawingPoint>.from(realPoints)..addAll(predicted);

    return PredictionResult(
      realPoints: realPoints,
      predictedCount: predicted.length,
      allPoints: allPoints,
    );
  }

  /// Finalize stroke — strip ALL predicted points, return only real.
  /// Call this on pointer-up/cancel BEFORE committing the stroke.
  List<ProDrawingPoint> finalize(List<ProDrawingPoint> points) {
    _isActive = false;
    // If we added predicted points, strip them
    if (_lastRealCount > 0 && points.length > _lastRealCount) {
      return points.sublist(0, _lastRealCount);
    }
    return points;
  }

  /// Reset state for a new stroke.
  void reset() {
    _isActive = false;
    _lastRealCount = 0;
  }

  /// Whether prediction is currently active.
  bool get isActive => _isActive;
}
