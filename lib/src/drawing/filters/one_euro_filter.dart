/// 1️⃣ ADAPTIVE STROKE FILTERING (SMOOTHING)
///
/// One Euro Filter - Bilancia stability e reactivity based onlla speed
/// Riduce tremolii e micro-oscillazioni mantenendo responsività
///
/// Parametri chiave:
/// - minCutoff: frequenza di taglio minima (more bassa = more smooth)
/// - beta: coefficiente di speed (more alto = more reattivo)
/// - dCutoff: frequenza di taglio for the derivata
library;

import 'dart:ui';
import 'dart:math' as math;

/// One Euro Filter per smoothing adattivo of the stroke
class OneEuroFilter {
  final double minCutoff;
  final double beta;
  final double dCutoff;

  Offset? _lastFiltered;
  Offset? _lastRaw;
  Offset? _lastDx;
  int? _lastTime; // millisecondsSinceEpoch

  OneEuroFilter({this.minCutoff = 1.0, this.beta = 0.007, this.dCutoff = 1.0});

  /// Filters un nuovo punto of the stroke con adaptive smoothing
  Offset filter(Offset point, int timestamp) {
    final now = timestamp;

    // Primo punto - nessun filtraggio
    if (_lastFiltered == null || _lastRaw == null || _lastTime == null) {
      _lastFiltered = point;
      _lastRaw = point;
      _lastDx = Offset.zero;
      _lastTime = now;
      return point;
    }

    // Calculate delta tempo (timestamp in milliseconds)
    final dt = (now - _lastTime!) / 1000.0; // converti ms in secondi
    if (dt <= 0) {
      return _lastFiltered!;
    }

    // Calculate distanza dat the point precedente
    final distance = (point - _lastRaw!).distance;

    // Calculate derivata (speed del movimento)
    final dx = Offset(
      (point.dx - _lastRaw!.dx) / dt,
      (point.dy - _lastRaw!.dy) / dt,
    );

    // Filter la derivata
    final filteredDx = _filterDx(dx, dt);

    // Calculate speed (modulus of the derivative)
    final speed = math.sqrt(
      filteredDx.dx * filteredDx.dx + filteredDx.dy * filteredDx.dy,
    );

    // 🚀 CONTINUOUS ADAPTIVE SMOOTHING (Gap 7)
    //
    // Instead of discrete threshold branches, use smooth curves:
    //   - speedFactor: 0.0 (stationary) → 1.0 (very fast, ≥800 px/s)
    //   - distanceFactor: 0.0 (large movement) → 1.0 (micro, ≤1px)
    //
    // Fast + small → maximum reactivity (writing small characters)
    // Slow + large → maximum smoothing (long deliberate strokes)
    final speedFactor = (speed / 800.0).clamp(0.0, 1.0);
    final distanceFactor = (1.0 - distance / 5.0).clamp(0.0, 1.0);
    final reactivityNeed = math.max(speedFactor, distanceFactor);

    // β: 1x (default) → 6x (very reactive) based on reactivity need
    final adaptiveBeta = beta * (1.0 + reactivityNeed * 5.0);
    // minCutoff: 1x (default) → 4x (less filtering) based on reactivity need
    final adaptiveMinCutoff = minCutoff * (1.0 + reactivityNeed * 3.0);

    // Calculate cutoff adattivo basato sulla speed
    final cutoff = adaptiveMinCutoff + adaptiveBeta * speed;

    // Filter il punto
    final filtered = _filterPoint(point, cutoff, dt);

    // 🚀 CONTINUOUS LATENCY COMPENSATION
    // Blend towards raw point proportional to reactivity need.
    // reactivityNeed=0 → 0% blend, reactivityNeed=1 → 50% blend.
    Offset finalPoint = filtered;
    if (reactivityNeed > 0.3) {
      final blendFactor = (reactivityNeed - 0.3) * 0.7; // 0→0.49
      finalPoint = Offset(
        filtered.dx + (point.dx - filtered.dx) * blendFactor,
        filtered.dy + (point.dy - filtered.dy) * blendFactor,
      );
    }

    // Update stato
    _lastFiltered = finalPoint;
    _lastRaw = point;
    _lastDx = filteredDx;
    _lastTime = now;

    return finalPoint;
  }

  /// Filters la derivata (speed)
  Offset _filterDx(Offset dx, double dt) {
    if (_lastDx == null) {
      return dx;
    }

    final alpha = _calculateAlpha(dCutoff, dt);
    return Offset(
      alpha * dx.dx + (1 - alpha) * _lastDx!.dx,
      alpha * dx.dy + (1 - alpha) * _lastDx!.dy,
    );
  }

  /// Filters il punto con cutoff specificato
  Offset _filterPoint(Offset point, double cutoff, double dt) {
    final alpha = _calculateAlpha(cutoff, dt);
    return Offset(
      alpha * point.dx + (1 - alpha) * _lastFiltered!.dx,
      alpha * point.dy + (1 - alpha) * _lastFiltered!.dy,
    );
  }

  /// Calculates il coefficiente alpha for the low-pass filter
  double _calculateAlpha(double cutoff, double dt) {
    final tau = 1.0 / (2 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }

  /// Reset del filtro
  void reset() {
    _lastFiltered = null;
    _lastRaw = null;
    _lastDx = null;
    _lastTime = null;
  }
}

/// Kalman Filter per predizione e smoothing
class KalmanFilter {
  final double processNoise;
  final double measurementNoise;

  Offset _estimate = Offset.zero;
  double _errorCovariance = 1.0;

  KalmanFilter({this.processNoise = 0.01, this.measurementNoise = 0.1});

  /// Filters un nuovo punto
  Offset filter(Offset measurement) {
    // Prediction (assume constant velocity)
    final predictedEstimate = _estimate;
    final predictedCovariance = _errorCovariance + processNoise;

    // Update
    final kalmanGain =
        predictedCovariance / (predictedCovariance + measurementNoise);
    _estimate = Offset(
      predictedEstimate.dx +
          kalmanGain * (measurement.dx - predictedEstimate.dx),
      predictedEstimate.dy +
          kalmanGain * (measurement.dy - predictedEstimate.dy),
    );
    _errorCovariance = (1 - kalmanGain) * predictedCovariance;

    return _estimate;
  }

  /// Reset del filtro
  void reset() {
    _estimate = Offset.zero;
    _errorCovariance = 1.0;
  }
}

/// Moving Average Filter - Media mobile semplice
class MovingAverageFilter {
  final int windowSize;
  final List<Offset> _buffer = [];

  MovingAverageFilter({this.windowSize = 5});

  /// Filters un nuovo punto
  Offset filter(Offset point) {
    _buffer.add(point);
    if (_buffer.length > windowSize) {
      _buffer.removeAt(0);
    }

    // Calculate media
    double sumX = 0;
    double sumY = 0;
    for (final p in _buffer) {
      sumX += p.dx;
      sumY += p.dy;
    }

    return Offset(sumX / _buffer.length, sumY / _buffer.length);
  }

  /// Reset del filtro
  void reset() {
    _buffer.clear();
  }
}

/// Filtero combinato con selezione automatica
class AdaptiveStrokeFilter {
  late OneEuroFilter _oneEuro;
  late KalmanFilter _kalman;
  late MovingAverageFilter _movingAverage;

  FilterType _currentType = FilterType.oneEuro;

  AdaptiveStrokeFilter({
    FilterType initialType = FilterType.oneEuro,
    double oneEuroMinCutoff = 1.0,
    double oneEuroBeta = 0.007,
    int movingAverageWindow = 5,
  }) {
    _currentType = initialType;
    _oneEuro = OneEuroFilter(minCutoff: oneEuroMinCutoff, beta: oneEuroBeta);
    _kalman = KalmanFilter();
    _movingAverage = MovingAverageFilter(windowSize: movingAverageWindow);
  }

  /// Filters un punto with the filtro corrente
  Offset filter(Offset point, {DateTime? timestamp}) {
    final now = (timestamp ?? DateTime.now()).millisecondsSinceEpoch;
    switch (_currentType) {
      case FilterType.oneEuro:
        return _oneEuro.filter(point, now);
      case FilterType.kalman:
        return _kalman.filter(point);
      case FilterType.movingAverage:
        return _movingAverage.filter(point);
      case FilterType.none:
        return point;
    }
  }

  /// Change type of filtro
  void setFilterType(FilterType type) {
    if (_currentType != type) {
      reset();
      _currentType = type;
    }
  }

  /// Reset of all the filtri
  void reset() {
    _oneEuro.reset();
    _kalman.reset();
    _movingAverage.reset();
  }

  FilterType get currentType => _currentType;
}

/// Tipi di filtro disponibili
enum FilterType {
  oneEuro, // Bilanciato - raccomandato per uso generale
  kalman, // Predittivo - migliore for thetency compensation
  movingAverage, // Semplice - more veloce ma meno raffinato
  none, // Nessun filtro
}
