// ════════════════════════════════════════════════════════════════════════════
// 🖐️ PalmRejectionPolicy — injectable palm-rejection / handedness hook
//
// The gesture detector decides whether a touch is a stylus, a palm, or a
// legitimate finger by asking the injected [PalmRejectionPolicy]. Canvas core
// ships only a no-op default so the SDK stays lean — consumer packages (e.g.
// fluera_engine) provide a real implementation that tracks stylus state,
// learns palm size, rejects elliptical contacts, etc.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:ui' show Offset, Size, Rect;

/// Why a touch was rejected (surfaced to debug overlays / telemetry).
enum PalmRejectionReason {
  /// A stylus is active or we're within the post-stylus cooldown window.
  temporal,

  /// The contact patch is unusually elongated (finger/palm vs. stylus tip).
  areaRatio,

  /// The finger landed too slowly — typical of a palm descending.
  velocity,

  /// Two or more pointers are down simultaneously.
  multiPoint,

  /// The touch is too close to the stylus position (wrist guard).
  wristGuard,

  /// The touch fell inside a statically-excluded corner.
  staticZone,

  /// The stylus was hovering nearby — anything else is probably a palm.
  hover,

  /// The touch has a flat pressure curve (no finger-tip dynamics).
  pressureCurve,

  /// The touch barely moved in the first few tens of ms — palm at rest.
  drift,
}

/// Hook the gesture detector calls at key moments of the pointer lifecycle
/// to let consumers veto palms and record handedness telemetry.
///
/// The default implementation is a no-op: every [shouldRejectTouch] returns
/// `false`, every record method does nothing. Override the methods you care
/// about.
class PalmRejectionPolicy {
  /// Method `PalmRejectionPolicy`.
  const PalmRejectionPolicy();

  /// Called on every stylus hover event (pen above the screen, not touching).
  void onStylusHover(Offset position) {}

  /// Called when the stylus leaves the hover range.
  void onStylusHoverExit() {}

  /// Called when the stylus contacts the screen.
  void onStylusDown(Offset position) {}

  /// Called on every stylus move while in contact.
  void onStylusMove(Offset position) {}

  /// Called when the stylus lifts.
  void onStylusUp() {}

  /// Upfront decision: should this touch be rejected immediately? Consumers
  /// typically apply temporal + area-ratio + velocity + wrist-guard tests.
  bool shouldRejectTouch({
    required Offset position,
    required double radiusMajor,
    required double radiusMinor,
    required Size screenSize,
    required double speed,
    Rect? uiSafeZone,
  }) => false;

  /// Hint that auto-calibration should run (every N rejections, for example).
  void triggerAutoCalibration(Size screenSize) {}

  /// Start tracking drift for a pointer accepted at [position].
  void beginDriftTracking(int pointer, Offset position) {}

  /// Record a pressure sample for deferred flat-curve detection.
  ///
  /// Returns `true` if the pointer should be rejected retroactively (e.g.
  /// the curve turned out too flat to be a fingertip).
  bool recordPressureSample(int pointer, double pressure) => false;

  /// Ask whether the pointer has drifted enough to still be considered a
  /// legitimate touch. Returns `true` if it has NOT drifted — reject it.
  bool checkDrift(int pointer, Offset position, double radiusMajor) => false;

  /// Record that a touch was rejected after the fact (debug overlay / stats).
  void recordDeferredRejection(
    Offset position,
    PalmRejectionReason reason,
    double radiusMajor,
  ) {}

  /// Clear all per-pointer tracking state for [pointer] (e.g. on pointer up
  /// or cancel).
  void clearPointerTracking(int pointer) {}

  /// Clear timestamp history used to detect multi-finger down bursts.
  void clearRecentFingerDownTimestamps() {}

  /// Record the horizontal direction of a stroke, used by consumers that
  /// auto-detect handedness from user behaviour.
  void recordStrokeDirection(double deltaX) {}
}

/// Shared no-op instance used by the gesture detector when the caller has
/// not wired up a custom policy.
const PalmRejectionPolicy noopPalmRejectionPolicy = PalmRejectionPolicy();
