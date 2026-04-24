/// 🎯 ADVANCED ONE-EURO FILTER (PRO VERSION)
///
/// Implementazione avanzata del One-Euro Filter usato da Google e Apple
/// per input touch e VR. Bilancia perfettamente reactivity e stability.
///
/// Features:
/// - Adaptive cutoff basato su speed
/// - Separate filtering for X and Y
/// - Timestamp-based smoothing
/// - Filtered derivative for accurate speed calculation
library;

import 'dart:ui';
import 'dart:math' as math;

class AdvancedOneEuroFilter {
  final double freq; // Frequenza di campionamento (Hz)
  final double minCutoff; // Cutoff minimo (more basso = more smooth)
  final double beta; // Coefficiente speed (more alto = more reattivo)
  final double dCutoff; // Cutoff per derivata

  // State per X
  double _lastValueX = 0.0;
  double _lastDerivX = 0.0;
  bool _initializedX = false;

  // State per Y
  double _lastValueY = 0.0;
  double _lastDerivY = 0.0;
  bool _initializedY = false;

  // Timestamp
  DateTime? _lastTimestamp;

  AdvancedOneEuroFilter({
    this.freq = 120.0, // 120 Hz (8.3ms per frame)
    this.minCutoff = 1.0, // Baseline smoothing
    this.beta = 0.007, // Sensitivity a speed
    this.dCutoff = 1.0, // Smoothing per derivata
  });

  /// Filters un punto con timestamp
  Offset filter(Offset point, DateTime timestamp) {
    // Update frequenza based on timestamp reale
    double actualFreq = freq;
    if (_lastTimestamp != null) {
      final dt =
          timestamp.difference(_lastTimestamp!).inMicroseconds / 1000000.0;
      if (dt > 0) {
        actualFreq = 1.0 / dt;
      }
    }
    _lastTimestamp = timestamp;

    // Filter X e Y separatamente
    final filteredX = _filterValue(point.dx, actualFreq, isX: true);
    final filteredY = _filterValue(point.dy, actualFreq, isX: false);

    return Offset(filteredX, filteredY);
  }

  /// Filters un singolo valore (X o Y)
  double _filterValue(double value, double actualFreq, {required bool isX}) {
    // Recupera lo state corretto
    final lastValue = isX ? _lastValueX : _lastValueY;
    final lastDeriv = isX ? _lastDerivX : _lastDerivY;
    final initialized = isX ? _initializedX : _initializedY;

    // Prima volta: return diretto
    if (!initialized) {
      if (isX) {
        _lastValueX = value;
        _lastDerivX = 0.0;
        _initializedX = true;
      } else {
        _lastValueY = value;
        _lastDerivY = 0.0;
        _initializedY = true;
      }
      return value;
    }

    // Calculate derivata (speed)
    final deriv = (value - lastValue) * actualFreq;

    // Filter la derivata con cutoff fisso
    final alphaDeriv = _alpha(dCutoff, actualFreq);
    final filteredDeriv = _lowPass(deriv, lastDeriv, alphaDeriv);

    // Calculate cutoff adattivo basato su speed
    final cutoff = minCutoff + beta * filteredDeriv.abs();

    // Filter il valore
    final alphaValue = _alpha(cutoff, actualFreq);
    final filteredValue = _lowPass(value, lastValue, alphaValue);

    // Update state
    if (isX) {
      _lastValueX = filteredValue;
      _lastDerivX = filteredDeriv;
    } else {
      _lastValueY = filteredValue;
      _lastDerivY = filteredDeriv;
    }

    return filteredValue;
  }

  /// Low-pass filter: interpola tra valore precedente e nuovo
  double _lowPass(double x, double prev, double alpha) {
    return prev + alpha * (x - prev);
  }

  /// Calculates alpha (coefficiente di smoothing) dal cutoff
  double _alpha(double cutoff, double actualFreq) {
    final tau = 1.0 / (2.0 * math.pi * cutoff);
    final te = 1.0 / actualFreq;
    return 1.0 / (1.0 + tau / te);
  }

  /// Resets il filtro
  void reset() {
    _lastValueX = 0.0;
    _lastDerivX = 0.0;
    _initializedX = false;
    _lastValueY = 0.0;
    _lastDerivY = 0.0;
    _initializedY = false;
    _lastTimestamp = null;
  }

  /// Get la speed attuale (px/s)
  double getSpeed() {
    if (!_initializedX || !_initializedY) return 0.0;
    return math.sqrt(_lastDerivX * _lastDerivX + _lastDerivY * _lastDerivY);
  }
}
