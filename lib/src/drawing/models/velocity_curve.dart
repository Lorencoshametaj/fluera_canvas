import 'package:flutter/material.dart';

/// Remaps a normalized stylus velocity [0..1] (velocity / velocityReference,
/// clamped) to the brush's effective speed factor. Same cubic-Bézier shape
/// as [PressureCurve] (p0=(0,0), p3=(1,1) implicit; p1, p2 are the control
/// points), so UI and serialization follow the same pattern.
///
/// The curve is consumed by [FountainPenBrush] (and eventually ballpoint /
/// pencil) where the speed factor modulates width: thick at low speed,
/// thinner at high speed. Gentler curves produce more uniform strokes;
/// aggressive curves exaggerate the swoosh at fast motion like GoodNotes.
class VelocityCurve {
  final Offset p1;
  final Offset p2;

  const VelocityCurve({
    this.p1 = const Offset(0.25, 0.25),
    this.p2 = const Offset(0.75, 0.75),
  });

  /// Linear mapping — no remapping at all.
  static const linear = VelocityCurve(
    p1: Offset(0.25, 0.25),
    p2: Offset(0.75, 0.75),
  );

  /// Gentle — slow pickup of the thin effect. Width stays closer to base
  /// for a wider velocity range; good for careful handwriting.
  static const gentle = VelocityCurve(
    p1: Offset(0.35, 0.10),
    p2: Offset(0.85, 0.55),
  );

  /// GoodNotes-like — balanced response with a pronounced mid-range
  /// thinning. Calibrated by eye against GoodNotes fountain pen.
  static const goodnotes = VelocityCurve(
    p1: Offset(0.20, 0.15),
    p2: Offset(0.55, 0.85),
  );

  /// Aggressive — strong swoosh at medium speed, very thin at high speed.
  /// Best for calligraphy / expressive signatures.
  static const aggressive = VelocityCurve(
    p1: Offset(0.10, 0.30),
    p2: Offset(0.35, 0.95),
  );

  static const Map<String, VelocityCurve> presets = {
    'linear': linear,
    'gentle': gentle,
    'goodnotes': goodnotes,
    'aggressive': aggressive,
  };

  double evaluate(double normalized) {
    final x = normalized.clamp(0.0, 1.0);
    if (x <= 0.0) return 0.0;
    if (x >= 1.0) return 1.0;
    final t = _solveForT(x);
    return _bezierY(t).clamp(0.0, 1.0);
  }

  double _bezierX(double t) {
    final mt = 1.0 - t;
    return 3.0 * mt * mt * t * p1.dx + 3.0 * mt * t * t * p2.dx + t * t * t;
  }

  double _bezierY(double t) {
    final mt = 1.0 - t;
    return 3.0 * mt * mt * t * p1.dy + 3.0 * mt * t * t * p2.dy + t * t * t;
  }

  double _bezierXDerivative(double t) {
    final mt = 1.0 - t;
    return 3.0 * mt * mt * p1.dx +
        6.0 * mt * t * (p2.dx - p1.dx) +
        3.0 * t * t * (1.0 - p2.dx);
  }

  double _solveForT(double x) {
    double t = x;
    for (int i = 0; i < 6; i++) {
      final error = _bezierX(t) - x;
      final deriv = _bezierXDerivative(t);
      if (deriv.abs() < 1e-10) break;
      t -= error / deriv;
      t = t.clamp(0.0, 1.0);
      if (error.abs() < 1e-7) break;
    }
    return t;
  }

  bool get isLinear {
    const eps = 0.01;
    return (p1.dx - 0.25).abs() < eps &&
        (p1.dy - 0.25).abs() < eps &&
        (p2.dx - 0.75).abs() < eps &&
        (p2.dy - 0.75).abs() < eps;
  }

  String? get presetName {
    const eps = 0.02;
    for (final entry in presets.entries) {
      if ((p1.dx - entry.value.p1.dx).abs() < eps &&
          (p1.dy - entry.value.p1.dy).abs() < eps &&
          (p2.dx - entry.value.p2.dx).abs() < eps &&
          (p2.dy - entry.value.p2.dy).abs() < eps) {
        return entry.key;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'p1x': _round3(p1.dx),
    'p1y': _round3(p1.dy),
    'p2x': _round3(p2.dx),
    'p2y': _round3(p2.dy),
  };

  factory VelocityCurve.fromJson(Map<String, dynamic>? json) {
    if (json == null) return VelocityCurve.linear;
    return VelocityCurve(
      p1: Offset(
        (json['p1x'] as num?)?.toDouble() ?? 0.25,
        (json['p1y'] as num?)?.toDouble() ?? 0.25,
      ),
      p2: Offset(
        (json['p2x'] as num?)?.toDouble() ?? 0.75,
        (json['p2y'] as num?)?.toDouble() ?? 0.75,
      ),
    );
  }

  static double _round3(double v) => (v * 1000).roundToDouble() / 1000;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is VelocityCurve && p1 == other.p1 && p2 == other.p2;

  @override
  int get hashCode => Object.hash(p1, p2);
}
