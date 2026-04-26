import 'dart:ui';
import 'dart:math' as math;

/// Pro Stroke Stabilizer — String Pulling + Moving Average + Corner Detection.
///
/// Three-stage pipeline matching Procreate / Clip Studio quality:
///
/// 1. **String Pulling** — filters hand tremor by requiring minimum movement
/// 2. **Weighted Moving Average** — smooths the output with a sliding window
/// 3. **Corner Detection** — detects sharp direction changes and reduces
///    smoothing to preserve intentional corners
///
/// Level 0 = no smoothing (passthrough).
/// Level 10 = very heavy smoothing (40px string, dramatic straightening).
///
/// Set [elasticEnabled] to false to disable velocity-based string-length
/// modulation and the easeInOut catchup curve (returns to linear behaviour
/// — useful for hosts that want a deterministic stabilizer).
class StrokeStabilizer {
  /// Smoothing level (0 = none, 10 = maximum).
  int _level;

  /// Whether the velocity-driven string-length and easeInOut catchup are on.
  /// Engine integrators wire this from their `OrganicBehaviorEngine`.
  bool elasticEnabled;

  /// Last stabilized position (the "anchor" of the string).
  Offset? _lastStabilized;

  /// Velocity tracking for elastic string length.
  Offset? _previousRaw;
  int? _previousTimestamp;
  double _lastSpeed = 0.0;
  int _pointCount = 0;

  /// Moving average buffer (last N stabilized points).
  final List<Offset> _maBuffer = [];

  /// Pressure smoothing buffer.
  final List<double> _pressureBuffer = [];

  /// Direction tracking for corner detection.
  Offset? _lastDirection;

  /// Moving average window size (scales with level).
  int get _maWindow =>
      (_level <= 3)
          ? 3
          : (_level <= 6)
          ? 4
          : 5;

  /// String length in logical pixels, based on level.
  /// Elastic: velocity reduces string length (fast = responsive).
  double get _stringLength {
    if (_level == 0) return 0.0;
    final base = _level * 4.0;
    if (!elasticEnabled) return base;
    // Fast movement (>1200 px/s) reduces string length by up to 60%.
    final velocityFactor = 1.0 - (_lastSpeed / 1200.0).clamp(0.0, 0.6);
    return base * velocityFactor;
  }

  /// Catchup factor: how much of the excess distance we move per sample.
  /// Elastic: uses easeInOut curve instead of linear.
  double get _catchup {
    final linear = 0.70 - (_level * 0.035).clamp(0.0, 0.35);
    if (!elasticEnabled) return linear;
    final t = linear;
    return t * t * (3.0 - 2.0 * t); // Hermite smoothstep
  }

  StrokeStabilizer({int level = 0, this.elasticEnabled = true})
    : _level = level.clamp(0, 10);

  /// Current stabilizer level.
  int get level => _level;

  /// Update the stabilizer level.
  set level(int value) {
    _level = value.clamp(0, 10);
  }

  /// Stabilize a raw input point. Returns the smoothed position.
  ///
  /// For level 0, returns the raw point unchanged (zero-cost fast path).
  /// [timestampUs] optional microsecond timestamp (avoids `DateTime.now`
  /// syscall on the hot path).
  Offset stabilize(Offset rawPoint, {int? timestampUs}) {
    if (_level == 0) return rawPoint;

    // Track velocity from consecutive raw points.
    final nowUs = timestampUs ?? DateTime.now().microsecondsSinceEpoch;
    if (_previousRaw != null && _previousTimestamp != null) {
      final dtSec = (nowUs - _previousTimestamp!) / 1000000.0;
      if (dtSec > 0 && dtSec < 0.1) {
        _lastSpeed = (rawPoint - _previousRaw!).distance / dtSec;
      }
    }
    _previousRaw = rawPoint;
    _previousTimestamp = nowUs;

    // First point: anchor at raw position.
    if (_lastStabilized == null) {
      _lastStabilized = rawPoint;
      _pointCount = 1;
      _maBuffer.clear();
      _maBuffer.add(rawPoint);
      _lastDirection = null;
      return rawPoint;
    }
    _pointCount++;

    // ═══════════════════════════════════════════════════════════════
    // STAGE 1: String Pulling
    // ═══════════════════════════════════════════════════════════════
    final anchor = _lastStabilized!;
    final dx = rawPoint.dx - anchor.dx;
    final dy = rawPoint.dy - anchor.dy;
    final dist = math.sqrt(dx * dx + dy * dy);

    // Warmup: ramp string length from 0→100% over first 4 points.
    const warmupPoints = 4;
    final warmupFactor =
        _pointCount >= warmupPoints ? 1.0 : _pointCount / warmupPoints;

    // ═══════════════════════════════════════════════════════════════
    // STAGE 3: Corner Detection — reduce string on sharp turns
    // ═══════════════════════════════════════════════════════════════
    double cornerScale = 1.0;
    if (dist > 0.5) {
      final currentDir = Offset(dx / dist, dy / dist);
      if (_lastDirection != null) {
        // Dot product: 1.0 = same direction, -1.0 = reversed.
        final dot =
            currentDir.dx * _lastDirection!.dx +
            currentDir.dy * _lastDirection!.dy;
        // Sharp turn (dot < 0.5 = >60° change) → reduce string to 30%.
        if (dot < 0.5) {
          cornerScale = 0.3 + 0.7 * ((dot + 1.0) / 1.5).clamp(0.0, 1.0);
        }
      }
      _lastDirection = currentDir;
    }

    final sLen = _stringLength * warmupFactor * cornerScale;

    Offset stringPulled;
    if (dist <= sLen) {
      // Lazy follow — always move a bit toward raw point.
      final baseLazy = 0.30 - (_level * 0.015);
      final lazyRatio = baseLazy * (dist / (sLen + 0.001));
      stringPulled = Offset(
        anchor.dx + dx * lazyRatio,
        anchor.dy + dy * lazyRatio,
      );
    } else {
      // Standard string pulling: move by excess * catchup.
      final excess = dist - sLen;
      final move = excess * _catchup;
      final ratio = move / dist;
      stringPulled = Offset(anchor.dx + dx * ratio, anchor.dy + dy * ratio);
    }

    _lastStabilized = stringPulled;

    // ═══════════════════════════════════════════════════════════════
    // STAGE 2: Weighted Moving Average — smooth the output
    // ═══════════════════════════════════════════════════════════════
    _maBuffer.add(stringPulled);
    final window = _maWindow;
    if (_maBuffer.length > window) {
      _maBuffer.removeAt(0);
    }

    // Weighted average: most recent points have higher weight.
    // Weights: [1, 2, 3, ...N] → newest = highest.
    double sumX = 0, sumY = 0, sumW = 0;
    for (int i = 0; i < _maBuffer.length; i++) {
      final w = (i + 1).toDouble();
      sumX += _maBuffer[i].dx * w;
      sumY += _maBuffer[i].dy * w;
      sumW += w;
    }

    // At sharp corners, reduce MA blending to preserve the corner.
    final maBlend = cornerScale < 0.8 ? cornerScale : 1.0;
    final maResult = Offset(sumX / sumW, sumY / sumW);

    // Blend: at corners, prefer string-pulled; at straights, prefer MA.
    final result = Offset(
      stringPulled.dx * (1.0 - maBlend) + maResult.dx * maBlend,
      stringPulled.dy * (1.0 - maBlend) + maResult.dy * maBlend,
    );

    return result;
  }

  /// Smooth pressure using a weighted moving average (same window as position).
  double stabilizePressure(double rawPressure) {
    if (_level == 0) return rawPressure;

    _pressureBuffer.add(rawPressure);
    final window = _maWindow;
    if (_pressureBuffer.length > window) {
      _pressureBuffer.removeAt(0);
    }

    // Weighted average: newest = highest weight.
    double sum = 0, sumW = 0;
    for (int i = 0; i < _pressureBuffer.length; i++) {
      final w = (i + 1).toDouble();
      sum += _pressureBuffer[i] * w;
      sumW += w;
    }
    return sum / sumW;
  }

  /// Generate catch-up points from stabilized → actual final position.
  /// Call this on stroke end to close the gap caused by stabilizer lag.
  /// Returns N interpolated offsets with easeOutQuad for natural deceleration.
  List<Offset> finalize(Offset finalRawPoint, {int steps = 4}) {
    if (_level == 0 || _lastStabilized == null) return [];

    final from = _lastStabilized!;
    final dx = finalRawPoint.dx - from.dx;
    final dy = finalRawPoint.dy - from.dy;
    final dist = math.sqrt(dx * dx + dy * dy);

    // Skip if already close enough (< 2px gap).
    if (dist < 2.0) return [];

    final points = <Offset>[];
    for (int i = 1; i <= steps; i++) {
      final t = i / steps;
      // EaseOutQuad: fast start, gentle stop.
      final ease = 1.0 - (1.0 - t) * (1.0 - t);
      points.add(Offset(from.dx + dx * ease, from.dy + dy * ease));
    }
    return points;
  }

  /// Reset the stabilizer for a new stroke.
  void reset() {
    _lastStabilized = null;
    _previousRaw = null;
    _previousTimestamp = null;
    _lastSpeed = 0.0;
    _pointCount = 0;
    _maBuffer.clear();
    _pressureBuffer.clear();
    _lastDirection = null;
  }
}
