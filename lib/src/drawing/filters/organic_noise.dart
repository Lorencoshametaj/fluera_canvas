/// 🌱 ORGANIC NOISE — Simplex 2D + fractal Brownian motion utilities.
///
/// Provides spatially-coherent noise for emergent organicity across the engine:
/// - [simplexNoise2D]: standard 2D Simplex noise, returns [-1, 1]
/// - [fbm]: multi-octave fractal Brownian motion for natural textures
/// - [biologicalTremor]: 1/f noise modulated by velocity (hand tremor)
///
/// All functions are pure, deterministic, and allocation-free.
/// The permutation table is pre-computed at startup (256 entries).
///
/// Performance: O(1) per sample, no heap allocations, suitable for paint().
library;

import 'dart:math' as math;

/// Organic noise generator — zero-allocation, deterministic Simplex 2D.
class OrganicNoise {
  OrganicNoise._();

  // ─── Permutation table (pre-computed, immutable) ─────────────────────

  static final List<int> _perm = _buildPermutation();
  static final List<int> _perm12 = List<int>.generate(
    512,
    (i) => _perm[i] % 12,
  );

  static List<int> _buildPermutation() {
    const source = <int>[
      151,
      160,
      137,
      91,
      90,
      15,
      131,
      13,
      201,
      95,
      96,
      53,
      194,
      233,
      7,
      225,
      140,
      36,
      103,
      30,
      69,
      142,
      8,
      99,
      37,
      240,
      21,
      10,
      23,
      190,
      6,
      148,
      247,
      120,
      234,
      75,
      0,
      26,
      197,
      62,
      94,
      252,
      219,
      203,
      117,
      35,
      11,
      32,
      57,
      177,
      33,
      88,
      237,
      149,
      56,
      87,
      174,
      20,
      125,
      136,
      171,
      168,
      68,
      175,
      74,
      165,
      71,
      134,
      139,
      48,
      27,
      166,
      77,
      146,
      158,
      231,
      83,
      111,
      229,
      122,
      60,
      211,
      133,
      230,
      220,
      105,
      92,
      41,
      55,
      46,
      245,
      40,
      244,
      102,
      143,
      54,
      65,
      25,
      63,
      161,
      1,
      216,
      80,
      73,
      209,
      76,
      132,
      187,
      208,
      89,
      18,
      169,
      200,
      196,
      135,
      130,
      116,
      188,
      159,
      86,
      164,
      100,
      109,
      198,
      173,
      186,
      3,
      64,
      52,
      217,
      226,
      250,
      124,
      123,
      5,
      202,
      38,
      147,
      118,
      126,
      255,
      82,
      85,
      212,
      207,
      206,
      59,
      227,
      47,
      16,
      58,
      17,
      182,
      189,
      28,
      42,
      223,
      183,
      170,
      213,
      119,
      248,
      152,
      2,
      44,
      154,
      163,
      70,
      221,
      153,
      101,
      155,
      167,
      43,
      172,
      9,
      129,
      22,
      39,
      253,
      19,
      98,
      108,
      110,
      79,
      113,
      224,
      232,
      178,
      185,
      112,
      104,
      218,
      246,
      97,
      228,
      251,
      34,
      242,
      193,
      238,
      210,
      144,
      12,
      191,
      179,
      162,
      241,
      81,
      51,
      145,
      235,
      249,
      14,
      239,
      107,
      49,
      192,
      214,
      31,
      181,
      199,
      106,
      157,
      184,
      84,
      204,
      176,
      115,
      121,
      50,
      45,
      127,
      4,
      150,
      254,
      138,
      236,
      205,
      93,
      222,
      114,
      67,
      29,
      24,
      72,
      243,
      141,
      128,
      195,
      78,
      66,
      215,
      61,
      156,
      180,
    ];
    // Double the table for wrapping without modulo
    return List<int>.generate(512, (i) => source[i & 255]);
  }

  // ─── Simplex 2D gradients ────────────────────────────────────────────

  static const _grad3 = <double>[
    1,
    1,
    0,
    -1,
    1,
    0,
    1,
    -1,
    0,
    -1,
    -1,
    0,
    1,
    0,
    1,
    -1,
    0,
    1,
    1,
    0,
    -1,
    -1,
    0,
    -1,
    0,
    1,
    1,
    0,
    -1,
    1,
    0,
    1,
    -1,
    0,
    -1,
    -1,
  ];

  static const _f2 = 0.5 * (1.7320508075688772 - 1.0); // (sqrt(3) - 1) / 2
  static const _g2 = (3.0 - 1.7320508075688772) / 6.0; // (3 - sqrt(3)) / 6

  // ─── Public API ──────────────────────────────────────────────────────

  /// 2D Simplex noise. Returns a value in [-1, 1].
  ///
  /// Deterministic: same (x, y) always produces the same output.
  /// O(1) per call, zero allocations.
  static double simplexNoise2D(double xin, double yin) {
    final s = (xin + yin) * _f2;
    final i = (xin + s).floor();
    final j = (yin + s).floor();

    final t = (i + j) * _g2;
    final x0 = xin - (i - t);
    final y0 = yin - (j - t);

    int i1, j1;
    if (x0 > y0) {
      i1 = 1;
      j1 = 0;
    } else {
      i1 = 0;
      j1 = 1;
    }

    final x1 = x0 - i1 + _g2;
    final y1 = y0 - j1 + _g2;
    final x2 = x0 - 1.0 + 2.0 * _g2;
    final y2 = y0 - 1.0 + 2.0 * _g2;

    final ii = i & 255;
    final jj = j & 255;
    final gi0 = _perm12[ii + _perm[jj]];
    final gi1 = _perm12[ii + i1 + _perm[jj + j1]];
    final gi2 = _perm12[ii + 1 + _perm[jj + 1]];

    double n0, n1, n2;

    var t0 = 0.5 - x0 * x0 - y0 * y0;
    if (t0 < 0) {
      n0 = 0.0;
    } else {
      t0 *= t0;
      n0 = t0 * t0 * (_grad3[gi0 * 3] * x0 + _grad3[gi0 * 3 + 1] * y0);
    }

    var t1 = 0.5 - x1 * x1 - y1 * y1;
    if (t1 < 0) {
      n1 = 0.0;
    } else {
      t1 *= t1;
      n1 = t1 * t1 * (_grad3[gi1 * 3] * x1 + _grad3[gi1 * 3 + 1] * y1);
    }

    var t2 = 0.5 - x2 * x2 - y2 * y2;
    if (t2 < 0) {
      n2 = 0.0;
    } else {
      t2 *= t2;
      n2 = t2 * t2 * (_grad3[gi2 * 3] * x2 + _grad3[gi2 * 3 + 1] * y2);
    }

    // Scale to [-1, 1]
    return 70.0 * (n0 + n1 + n2);
  }

  /// Fractal Brownian Motion — multi-octave Simplex noise.
  ///
  /// [octaves] Number of noise layers (3–6 typical).
  /// [lacunarity] Frequency multiplier per octave (default 2.0).
  /// [gain] Amplitude multiplier per octave (default 0.5).
  ///
  /// Returns value approximately in [-1, 1].
  static double fbm(
    double x,
    double y, {
    int octaves = 4,
    double lacunarity = 2.0,
    double gain = 0.5,
  }) {
    double value = 0.0;
    double amplitude = 1.0;
    double frequency = 1.0;
    double maxAmplitude = 0.0;

    for (int i = 0; i < octaves; i++) {
      value += amplitude * simplexNoise2D(x * frequency, y * frequency);
      maxAmplitude += amplitude;
      amplitude *= gain;
      frequency *= lacunarity;
    }

    return value / maxAmplitude;
  }

  /// Biological hand tremor — 1/f noise inversely modulated by velocity.
  ///
  /// [arcLength] Cumulative distance along the stroke (px).
  /// [velocity] Current drawing velocity (px/s). Higher = less tremor.
  /// [seed] Per-stroke seed for variation between strokes.
  ///
  /// Returns tremor offset in [-1, 1]. Multiply by desired pixel amplitude.
  /// Typical usage: `tremor * 0.3` for ±0.3px lateral offset.
  static double biologicalTremor(
    double arcLength,
    double velocity, {
    double seed = 0.0,
  }) {
    // Velocity-dependent amplitude: tremor decreases with speed
    // At 0 px/s: amplitude 1.0 (maximum tremor)
    // At 800 px/s: amplitude ~0.15 (minimal tremor)
    final velocityDamping = 1.0 / (1.0 + velocity / 200.0);

    // Multi-frequency tremor (1/f spectrum):
    // Low freq (muscle groups ~3–5 Hz equivalent)
    // Mid freq (finger micro-tremor ~8–12 Hz equivalent)
    // High freq (physiological noise ~15–25 Hz equivalent)
    final freq1 = arcLength * 0.02 + seed;
    final freq2 = arcLength * 0.07 + seed * 1.7;
    final freq3 = arcLength * 0.15 + seed * 2.3;

    final tremor =
        simplexNoise2D(freq1, seed) * 0.5 + // low freq, high amplitude
        simplexNoise2D(freq2, seed + 100) * 0.3 + // mid freq
        simplexNoise2D(freq3, seed + 200) * 0.2; // high freq, low amplitude

    return tremor * velocityDamping;
  }

  /// Muscle fatigue factor — increases tremor amplitude over long strokes.
  ///
  /// [pointCount] Number of points drawn so far in the current stroke.
  /// Returns multiplier in [1.0, 1.3]. Kicks in after 200 points,
  /// plateaus at 1.3× after 500 points.
  static double fatigueFactor(int pointCount) {
    if (pointCount < 200) return 1.0;
    final t = ((pointCount - 200) / 300.0).clamp(0.0, 1.0);
    return 1.0 + t * 0.3;
  }

  /// Breathing modulation — ultra-slow sinusoidal pressure variation.
  ///
  /// [arcLength] Cumulative arc length along the stroke.
  /// Returns value in [-1, 1]. Frequency ~0.2Hz equivalent at typical
  /// drawing speeds (~200px/s → period ~1000px arc length).
  static double breathingModulation(double arcLength) {
    return math.sin(arcLength * 0.006283); // 2π / 1000
  }

  /// 🌱 Organic pressure S-curve — softens extremes, expands mid-range.
  ///
  /// Mimics the nonlinear feel of real pen/paper interaction:
  /// - Very light touches (0–0.15): slightly boosted (easier to start marks)
  /// - Mid-range (0.3–0.7): expanded (more control in the sweet spot)
  /// - Heavy pressure (0.85–1.0): slightly compressed (harder to max out)
  ///
  /// [pressure] Raw pressure in [0, 1].
  /// [amount] Blend factor (0 = linear, 1 = full S-curve). Default 0.3.
  /// Returns pressure in [0, 1].
  ///
  /// The curve uses Hermite smoothstep: 3t² - 2t³
  static double organicPressureCurve(double pressure, {double amount = 0.3}) {
    // Clamp input
    final p = pressure.clamp(0.0, 1.0);

    // Hermite smoothstep S-curve: soft entry and exit
    final t = p * p * (3.0 - 2.0 * p);

    // Slight lift at very low pressure (touch threshold)
    // Below 0.1 raw → add +0.02 so faint marks are visible
    final liftBoost = (1.0 - (p * 10.0).clamp(0.0, 1.0)) * 0.02;

    // Blend: (1-amount) × linear + amount × S-curve + lift
    final curved = (1.0 - amount) * p + amount * t + liftBoost;

    return curved.clamp(0.0, 1.0);
  }
}
