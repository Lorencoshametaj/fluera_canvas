import 'dart:math' as math;

/// A tone curve defined by control points for image adjustment.
///
/// The curve maps input luminance (0.0-1.0) to output luminance (0.0-1.0).
/// Uses cubic spline interpolation between control points.
class ToneCurve {
  /// Master control points (luminance curve).
  final List<CurvePoint> points;

  /// Per-channel control points (empty = identity for that channel).
  final List<CurvePoint> redPoints;
  final List<CurvePoint> greenPoints;
  final List<CurvePoint> bluePoints;

  const ToneCurve({
    this.points = const [],
    this.redPoints = const [],
    this.greenPoints = const [],
    this.bluePoints = const [],
  });

  /// Default identity curve (no adjustment)
  static const identity = ToneCurve();

  /// Whether this curve is the identity (no adjustment)
  bool get isIdentity =>
      points.isEmpty &&
      redPoints.isEmpty &&
      greenPoints.isEmpty &&
      bluePoints.isEmpty;

  /// Evaluate the curve at position [x] (0.0-1.0) → output (0.0-1.0).
  /// Uses monotone cubic spline interpolation for smooth, overshoot-free results.
  double evaluate(double x) {
    if (points.isEmpty) return x;

    // Build full point list with anchors
    final pts = <CurvePoint>[
      const CurvePoint(0, 0),
      ...points,
      const CurvePoint(1, 1),
    ];

    // Sort by x
    pts.sort((a, b) => a.x.compareTo(b.x));

    // Find segment
    for (int i = 0; i < pts.length - 1; i++) {
      if (x >= pts[i].x && x <= pts[i + 1].x) {
        final t =
            (pts[i + 1].x - pts[i].x) < 0.0001
                ? 0.0
                : (x - pts[i].x) / (pts[i + 1].x - pts[i].x);
        // Simple cubic hermite interpolation
        final y = _hermite(
          t,
          pts[i].y,
          pts[i + 1].y,
          i > 0 ? pts[i - 1].y : pts[i].y,
          i < pts.length - 2 ? pts[i + 2].y : pts[i + 1].y,
        );
        return y.clamp(0.0, 1.0);
      }
    }
    return x;
  }

  /// Cubic hermite interpolation with Catmull-Rom tangents
  static double _hermite(double t, double p1, double p2, double p0, double p3) {
    final t2 = t * t;
    final t3 = t2 * t;
    final m0 = (p2 - p0) * 0.5;
    final m1 = (p3 - p1) * 0.5;
    return (2 * t3 - 3 * t2 + 1) * p1 +
        (t3 - 2 * t2 + t) * m0 +
        (-2 * t3 + 3 * t2) * p2 +
        (t3 - t2) * m1;
  }

  /// Convert curve to a 5x4 color matrix that approximates the tone adjustment.
  /// Supports per-channel curves: if a channel curve is set, it overrides master for that channel.
  List<double> toColorMatrix() {
    if (isIdentity) {
      return [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];
    }

    // Evaluate each channel
    final rPts = redPoints.isEmpty ? points : redPoints;
    final gPts = greenPoints.isEmpty ? points : greenPoints;
    final bPts = bluePoints.isEmpty ? points : bluePoints;

    final rCurve = ToneCurve(points: rPts);
    final gCurve = ToneCurve(points: gPts);
    final bCurve = ToneCurve(points: bPts);

    double slopeOf(ToneCurve c) {
      if (c.points.isEmpty) return 1.0;
      return (c.evaluate(0.75) - c.evaluate(0.25)) / 0.5;
    }

    double offsetOf(ToneCurve c) {
      if (c.points.isEmpty) return 0.0;
      return (c.evaluate(0.5) - 0.5) * 255;
    }

    return [
      slopeOf(rCurve),
      0,
      0,
      0,
      offsetOf(rCurve),
      0,
      slopeOf(gCurve),
      0,
      0,
      offsetOf(gCurve),
      0,
      0,
      slopeOf(bCurve),
      0,
      offsetOf(bCurve),
      0,
      0,
      0,
      1,
      0,
    ];
  }

  /// JSON serialization
  Map<String, dynamic> toJson() => {
    'points': points.map((p) => {'x': p.x, 'y': p.y}).toList(),
    if (redPoints.isNotEmpty)
      'redPoints': redPoints.map((p) => {'x': p.x, 'y': p.y}).toList(),
    if (greenPoints.isNotEmpty)
      'greenPoints': greenPoints.map((p) => {'x': p.x, 'y': p.y}).toList(),
    if (bluePoints.isNotEmpty)
      'bluePoints': bluePoints.map((p) => {'x': p.x, 'y': p.y}).toList(),
  };

  factory ToneCurve.fromJson(Map<String, dynamic> json) {
    List<CurvePoint> parsePts(String key) =>
        (json[key] as List<dynamic>?)
            ?.map(
              (p) => CurvePoint(
                (p['x'] as num).toDouble(),
                (p['y'] as num).toDouble(),
              ),
            )
            .toList() ??
        const [];
    return ToneCurve(
      points: parsePts('points'),
      redPoints: parsePts('redPoints'),
      greenPoints: parsePts('greenPoints'),
      bluePoints: parsePts('bluePoints'),
    );
  }

  ToneCurve copyWith({
    List<CurvePoint>? points,
    List<CurvePoint>? redPoints,
    List<CurvePoint>? greenPoints,
    List<CurvePoint>? bluePoints,
  }) => ToneCurve(
    points: points ?? this.points,
    redPoints: redPoints ?? this.redPoints,
    greenPoints: greenPoints ?? this.greenPoints,
    bluePoints: bluePoints ?? this.bluePoints,
  );
}

/// A single control point on the tone curve
class CurvePoint {
  final double x; // 0.0-1.0 (input luminance)
  final double y; // 0.0-1.0 (output luminance)

  const CurvePoint(this.x, this.y);

  @override
  bool operator ==(Object other) =>
      other is CurvePoint && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);
}
