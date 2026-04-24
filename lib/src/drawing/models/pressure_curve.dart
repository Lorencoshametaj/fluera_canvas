import 'package:flutter/material.dart';

/// 🎛️ Phase 4A: Pressure Curve — remaps raw stylus pressure to output pressure
///
/// Uses cubic Bézier evaluation in normalized [0,1]×[0,1] space.
/// The curve maps input pressure (x-axis) to output pressure (y-axis).
///
/// Control points define the shape:
/// - p0 is always (0, 0) — zero pressure stays zero
/// - p3 is always (1, 1) — max pressure stays max
/// - p1, p2 are user-draggable control points
///
/// Presets:
///   linear  → straight diagonal (no remapping)
///   soft    → gentle response, easier light strokes
///   firm    → heavy response, needs more pressure
///   sCurve  → dead zone at extremes, responsive in middle
///   heavy   → very heavy, for users who press hard
class PressureCurve {
  /// The two interior control points of the cubic Bézier.
  /// p0=(0,0) and p3=(1,1) are implicit.
  final Offset p1;
  final Offset p2;

  const PressureCurve({
    this.p1 = const Offset(0.25, 0.25),
    this.p2 = const Offset(0.75, 0.75),
  });

  // ─── Named Presets ───

  /// Linear: no remapping (identity)
  static const linear = PressureCurve(
    p1: Offset(0.25, 0.25),
    p2: Offset(0.75, 0.75),
  );

  /// Soft: light pressure produces more output
  static const soft = PressureCurve(
    p1: Offset(0.15, 0.45),
    p2: Offset(0.55, 0.90),
  );

  /// Firm: requires heavier pressure for output
  static const firm = PressureCurve(
    p1: Offset(0.45, 0.10),
    p2: Offset(0.85, 0.55),
  );

  /// S-Curve: dead zones at extremes, responsive middle
  static const sCurve = PressureCurve(
    p1: Offset(0.25, 0.05),
    p2: Offset(0.75, 0.95),
  );

  /// Heavy: very aggressive, for hard pressers
  static const heavy = PressureCurve(
    p1: Offset(0.60, 0.05),
    p2: Offset(0.95, 0.40),
  );

  /// All named presets for UI display
  static const Map<String, PressureCurve> presets = {
    'linear': linear,
    'soft': soft,
    'firm': firm,
    'sCurve': sCurve,
    'heavy': heavy,
  };

  /// Evaluate the cubic Bézier at parameter [t] ∈ [0, 1].
  /// Returns the Y value (output pressure).
  ///
  /// The curve is: B(t) = (1-t)³·P0 + 3(1-t)²t·P1 + 3(1-t)t²·P2 + t³·P3
  /// We solve for the t that gives us our input x, then read the y.
  double evaluate(double rawPressure) {
    final x = rawPressure.clamp(0.0, 1.0);

    // For endpoints, return directly
    if (x <= 0.0) return 0.0;
    if (x >= 1.0) return 1.0;

    // Find t for given x using Newton's method
    final t = _solveForT(x);

    // Evaluate y at that t
    return _bezierY(t).clamp(0.0, 1.0);
  }

  /// Cubic Bézier X component: B_x(t)
  double _bezierX(double t) {
    final mt = 1.0 - t;
    return 3.0 * mt * mt * t * p1.dx +
        3.0 * mt * t * t * p2.dx +
        t * t * t; // p3.dx = 1.0
  }

  /// Cubic Bézier Y component: B_y(t)
  double _bezierY(double t) {
    final mt = 1.0 - t;
    return 3.0 * mt * mt * t * p1.dy +
        3.0 * mt * t * t * p2.dy +
        t * t * t; // p3.dy = 1.0
  }

  /// Derivative of B_x(t) for Newton's method
  double _bezierXDerivative(double t) {
    final mt = 1.0 - t;
    return 3.0 * mt * mt * p1.dx +
        6.0 * mt * t * (p2.dx - p1.dx) +
        3.0 * t * t * (1.0 - p2.dx);
  }

  /// Solve B_x(t) = x using Newton's method (fast convergence for Bézier)
  double _solveForT(double x) {
    // Initial guess: t ≈ x (good for near-linear curves)
    double t = x;

    // 6 iterations of Newton's method (sufficient for double precision)
    for (int i = 0; i < 6; i++) {
      final error = _bezierX(t) - x;
      final deriv = _bezierXDerivative(t);

      if (deriv.abs() < 1e-10) break; // Avoid division by zero
      t -= error / deriv;
      t = t.clamp(0.0, 1.0);

      if (error.abs() < 1e-7) break; // Converged
    }

    return t;
  }

  /// Check if this is effectively a linear curve (identity)
  bool get isLinear {
    const eps = 0.01;
    return (p1.dx - 0.25).abs() < eps &&
        (p1.dy - 0.25).abs() < eps &&
        (p2.dx - 0.75).abs() < eps &&
        (p2.dy - 0.75).abs() < eps;
  }

  /// Find the closest named preset (or null if custom)
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

  // ─── Serialization ───

  Map<String, dynamic> toJson() => {
    'p1x': _round3(p1.dx),
    'p1y': _round3(p1.dy),
    'p2x': _round3(p2.dx),
    'p2y': _round3(p2.dy),
  };

  factory PressureCurve.fromJson(Map<String, dynamic>? json) {
    if (json == null) return PressureCurve.linear;
    return PressureCurve(
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
      other is PressureCurve && p1 == other.p1 && p2 == other.p2;

  @override
  int get hashCode => Object.hash(p1, p2);
}
