/// ✍️ DYNAMIC PRESSURE MAPPING
///
/// Simulates variable pressure even without stylus:
/// - Slow strokes → "heavier" pen → thicker stroke
/// - Fast strokes → "lighter" pen → thinner stroke
/// - Effetto calligrafico naturale
///
/// Features:
/// - Velocity-based pressure
/// - Smooth pressure transitions
/// - Configureble sensitivity
library;

import 'dart:ui';
import 'dart:math' as math;

class DynamicPressureMapper {
  /// Range di pressione (0.0 = min, 1.0 = max)
  final double minPressure;
  final double maxPressure;

  /// Sensitivity alla speed (more alto = more sensibile)
  final double velocitySensitivity;

  /// Smoothing per transizioni pressione
  final double pressureSmoothing;

  /// Storia of pressure per smoothing
  double _lastPressure = 0.5;

  /// Storia speed per calcolo
  final List<_VelocityPoint> _velocityHistory = [];
  static const int _maxVelocityHistory = 5;

  DynamicPressureMapper({
    this.minPressure = 0.3,
    this.maxPressure = 1.0,
    this.velocitySensitivity = 5.0,
    this.pressureSmoothing = 0.3,
  });

  /// Calculates pressione based on speed
  double calculatePressure(Offset point, DateTime timestamp) {
    // Add punto alla storia
    _velocityHistory.add(_VelocityPoint(point, timestamp));
    if (_velocityHistory.length > _maxVelocityHistory) {
      _velocityHistory.removeAt(0);
    }

    // Calculate speed media
    final speed = _calculateAverageSpeed();

    // Mappa speed → pressione (inverso)
    // Speed alto = pressione bassa, speed basso = pressione alta
    final rawPressure = _velocityToPressure(speed);

    // Smooth pressure transitions
    final smoothedPressure = _smoothPressure(rawPressure);

    return smoothedPressure;
  }

  /// Calculates pressione da speed esistente
  double pressureFromSpeed(double speed) {
    final rawPressure = _velocityToPressure(speed);
    return _smoothPressure(rawPressure);
  }

  /// Mappa speed a pressione (inverso: veloce = leggero)
  double _velocityToPressure(double speed) {
    // Formula: pressure = 1 / (1 + speed * sensitivity)
    final normalized = 1.0 / (1.0 + speed * velocitySensitivity);

    // Clamp nel range configurato
    return (normalized * (maxPressure - minPressure) + minPressure).clamp(
      minPressure,
      maxPressure,
    );
  }

  /// Smooth pressure usando exponential moving average
  double _smoothPressure(double newPressure) {
    // EMA: smoothed = smoothed * (1 - alpha) + new * alpha
    final alpha = pressureSmoothing;
    _lastPressure = _lastPressure * (1.0 - alpha) + newPressure * alpha;
    return _lastPressure;
  }

  /// Calculates speed media dai punti recenti
  double _calculateAverageSpeed() {
    if (_velocityHistory.length < 2) return 0.0;

    double totalSpeed = 0.0;
    int count = 0;

    for (int i = 1; i < _velocityHistory.length; i++) {
      final prev = _velocityHistory[i - 1];
      final curr = _velocityHistory[i];

      final dt =
          curr.timestamp.difference(prev.timestamp).inMicroseconds / 1000000.0;
      if (dt > 0) {
        final distance = (curr.point - prev.point).distance;
        final speed = distance / dt; // px/s
        totalSpeed += speed;
        count++;
      }
    }

    return count > 0 ? totalSpeed / count : 0.0;
  }

  /// Calculates width of the stroke based on pressione
  double calculateStrokeWidth({
    required double basePressure,
    required double baseWidth,
    double minWidthMultiplier = 0.5,
    double maxWidthMultiplier = 1.5,
  }) {
    // Mappa pressione (0.0-1.0) → width multiplier
    final multiplier =
        minWidthMultiplier +
        (maxWidthMultiplier - minWidthMultiplier) * basePressure;

    return baseWidth * multiplier;
  }

  /// Simula effetto calligrafico con angolo
  double calculateCalligraphicWidth({
    required double basePressure,
    required double baseWidth,
    required Offset direction,
    double angleSensitivity = 0.3,
  }) {
    // Calculate angolo del movimento
    final angle = math.atan2(direction.dy, direction.dx);

    // Modula width based onll'angolo (effetto punta piatta)
    final angleModulation = 1.0 + math.sin(angle * 2) * angleSensitivity;

    // Combine pressure and angle
    final pressureWidth = calculateStrokeWidth(
      basePressure: basePressure,
      baseWidth: baseWidth,
    );

    return pressureWidth * angleModulation;
  }

  /// Get pressione attuale (smoothed)
  double getCurrentPressure() {
    return _lastPressure;
  }

  /// Resets lo stato
  void reset() {
    _velocityHistory.clear();
    _lastPressure = 0.5;
  }
}

/// Punto con speed e timestamp
class _VelocityPoint {
  final Offset point;
  final DateTime timestamp;

  _VelocityPoint(this.point, this.timestamp);
}
