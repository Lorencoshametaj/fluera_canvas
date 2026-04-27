// Per-brush configuration value classes.
//
// Before this file, `updateAndRender` accepted 13 individual optional
// parameters (`pencilBaseOpacity`, `fountainNibAngleDeg`, …) that had
// to be threaded identically through three layers (Backend → Service
// → FFI). Adding a single tunable meant editing four files in lockstep
// or risking silent default drift between Dart and native.
//
// Bundling the parameters as immutable `const`-constructible values
// gives us:
//   * one source of truth for defaults,
//   * `==`/`hashCode` so the throttle layer can early-out when the
//     config didn't change,
//   * a stable wire format the native side can rely on (the field
//     ORDER below mirrors the FFI ring/flat buffer slot order in
//     `native_stroke_ffi.dart`),
//   * room to grow without breaking the public `updateAndRender`
//     signature — adding a tunable means adding a `copyWith` field
//     here, not a new positional parameter on `GpuStrokeBackend`.
//
// The defaults match the literal values that lived inline in the old
// signature, so passing `const PencilConfig()` and `const FountainConfig()`
// is byte-for-byte equivalent to the previous default behaviour.

import 'package:meta/meta.dart';

/// Tuning knobs for the GPU pencil brush (graphite noise + pressure
/// gradient). All fields use the same units the GLSL pencil shader
/// expects. The `Min`/`Max` pressure pair clamps the raw pressure
/// curve before it is fed to the opacity ramp.
@immutable
class PencilConfig {
  /// Opacity at zero pressure. Lower = lighter strokes.
  final double baseOpacity;

  /// Opacity at full pressure. Higher = more saturated marks.
  final double maxOpacity;

  /// Lower bound of the pressure clamp before the ramp.
  final double minPressure;

  /// Upper bound of the pressure clamp before the ramp.
  final double maxPressure;

  const PencilConfig({
    this.baseOpacity = 0.4,
    this.maxOpacity = 0.8,
    this.minPressure = 0.5,
    this.maxPressure = 1.2,
  });

  /// Default-valued instance. Convenience for callers that don't tune
  /// the pencil — saves an allocation when the defaults are fine.
  static const PencilConfig defaults = PencilConfig();

  PencilConfig copyWith({
    double? baseOpacity,
    double? maxOpacity,
    double? minPressure,
    double? maxPressure,
  }) => PencilConfig(
    baseOpacity: baseOpacity ?? this.baseOpacity,
    maxOpacity: maxOpacity ?? this.maxOpacity,
    minPressure: minPressure ?? this.minPressure,
    maxPressure: maxPressure ?? this.maxPressure,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PencilConfig &&
          other.baseOpacity == baseOpacity &&
          other.maxOpacity == maxOpacity &&
          other.minPressure == minPressure &&
          other.maxPressure == maxPressure);

  @override
  int get hashCode =>
      Object.hash(baseOpacity, maxOpacity, minPressure, maxPressure);
}

/// Tuning knobs for the GPU fountain pen brush (ink bleed, fiber
/// texture, velocity-driven nib). The angle is in DEGREES, not
/// radians, to match the toolbar UI representation.
@immutable
class FountainPenConfig {
  /// How aggressively the stroke thins at low pressure. 0 = uniform
  /// width, 1 = nearly disappears at zero pressure.
  final double thinning;

  /// Nib rotation in degrees. The shader builds the calligraphic
  /// asymmetry off this axis.
  final double nibAngleDeg;

  /// Strength of the nib's directional bias. 0 = round nib, 1 =
  /// extreme calligraphy.
  final double nibStrength;

  /// How fast the pressure curve responds to velocity (0..1).
  final double pressureRate;

  /// Number of points at the entry of a stroke that get an
  /// exaggerated taper. Cosmetic — masks the fact the first sample
  /// always lands at full pressure.
  final int taperEntry;

  const FountainPenConfig({
    this.thinning = 0.5,
    this.nibAngleDeg = 30.0,
    this.nibStrength = 0.35,
    this.pressureRate = 0.275,
    this.taperEntry = 6,
  });

  static const FountainPenConfig defaults = FountainPenConfig();

  FountainPenConfig copyWith({
    double? thinning,
    double? nibAngleDeg,
    double? nibStrength,
    double? pressureRate,
    int? taperEntry,
  }) => FountainPenConfig(
    thinning: thinning ?? this.thinning,
    nibAngleDeg: nibAngleDeg ?? this.nibAngleDeg,
    nibStrength: nibStrength ?? this.nibStrength,
    pressureRate: pressureRate ?? this.pressureRate,
    taperEntry: taperEntry ?? this.taperEntry,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FountainPenConfig &&
          other.thinning == thinning &&
          other.nibAngleDeg == nibAngleDeg &&
          other.nibStrength == nibStrength &&
          other.pressureRate == pressureRate &&
          other.taperEntry == taperEntry);

  @override
  int get hashCode =>
      Object.hash(thinning, nibAngleDeg, nibStrength, pressureRate, taperEntry);
}
