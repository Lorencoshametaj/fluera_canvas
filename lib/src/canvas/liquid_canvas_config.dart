/// 🌊 LIQUID CANVAS — Physics configuration for fluid canvas interactions.
///
/// Tunable constants that control pan momentum, zoom spring-back,
/// elastic overshoot, and content reflow behavior.
///
/// DESIGN PRINCIPLES:
/// - All parameters have sensible defaults matching Procreate feel
/// - Immutable config — passed at construction time, not modified at runtime
/// - Zero performance cost when liquid physics are disabled
class LiquidCanvasConfig {
  /// Friction coefficient for pan momentum deceleration.
  /// Lower = slides further, higher = stops sooner.
  /// Procreate uses ~0.015 for a long, buttery glide.
  final double panFriction;

  /// Spring stiffness for zoom bounce-back (N/m equivalent).
  /// Higher = snappier return to limits, lower = lazier.
  final double zoomSpringStiffness;

  /// Spring damping ratio for zoom bounce-back.
  /// 1.0 = critical damping (no oscillation)
  /// < 1.0 = underdamped (slight oscillation — Procreate feel)
  /// > 1.0 = overdamped (sluggish return)
  final double zoomSpringDamping;

  /// Spring mass for zoom bounce-back (kg equivalent).
  /// Lighter = faster response, heavier = more inertial.
  final double zoomSpringMass;

  /// Minimum velocity (px/sec) to trigger pan momentum.
  /// Below this threshold, the canvas stops immediately on lift.
  final double momentumThreshold;

  /// Velocity (px/sec) below which the momentum animation stops.
  /// Lower = longer glide tail, higher = stops sooner.
  final double stopVelocity;

  /// Whether to allow elastic zoom overshoot beyond min/max limits.
  /// When true, pinching past limits briefly shows the beyond-limits view
  /// before springing back — the signature Procreate/iOS feel.
  final bool enableElasticZoom;

  /// Maximum elastic overshoot factor for zoom.
  /// 0.3 = can overshoot by 30% beyond limits before clamping.
  final double elasticZoomOvershoot;

  /// How much the zoom "resists" when past limits.
  /// Higher = harder to push past limits, lower = more elastic.
  /// This creates the rubber-band feel.
  final double elasticResistance;

  /// Whether liquid physics are enabled at all.
  /// When false, the canvas behaves like the original (instant stop).
  final bool enabled;

  // ============================================================================
  // 🎯 NODE DRAG SPRING
  // ============================================================================

  /// Spring stiffness for node drag snap-to-guide bounce.
  /// Higher = snappier landing, lower = lazier.
  final double nodeDragSpringStiffness;

  /// Spring damping for node drag snap-to-guide bounce.
  /// < critical damping = slight oscillation on landing.
  final double nodeDragSpringDamping;

  /// Friction for node drag fling (inertia after release).
  /// Lower = longer glide, higher = stops sooner.
  final double nodeDragFlingFriction;

  /// Minimum velocity (px/sec) to trigger node drag fling.
  final double nodeDragFlingThreshold;

  /// Maximum fling velocity (px/sec). Velocities above this are clamped.
  /// Prevents elements from flying off-screen with extreme flicks.
  final double nodeDragMaxFlingVelocity;

  /// Extra friction added per selected element (adaptive friction).
  /// Heavier selections decelerate faster: `friction + factor * count`.
  final double nodeDragAdaptiveFrictionFactor;

  /// Distance threshold (px) for mid-fling magnetic catch.
  /// When fling passes within this distance of a snap guide, it catches.
  final double nodeDragMidFlingSnapDistance;

  // ============================================================================
  // 🎯 PAN-TO-TARGET SPRING
  // ============================================================================

  /// Spring stiffness for programmatic pan-to-target animations.
  /// Used by animateOffsetTo / animateToTransform.
  final double panSpringStiffness;

  /// Spring damping for programmatic pan-to-target animations.
  final double panSpringDamping;

  /// 🧩 Opaque add-on config slot — canvas does not interpret this.
  ///
  /// Consumer packages may stash their own config object here (for example
  /// an add-on "content reflow" engine) and downcast it at call sites.
  /// Canvas core treats it as a black box so this field does not pull any
  /// engine-specific dependency into the SDK.
  final Object? reflow;

  /// API element `LiquidCanvasConfig`.
  const LiquidCanvasConfig({
    this.panFriction = 0.015,
    this.zoomSpringStiffness = 280.0,
    this.zoomSpringDamping = 18.0,
    this.zoomSpringMass = 1.0,
    this.momentumThreshold = 100.0,
    this.stopVelocity = 0.3,
    this.enableElasticZoom = true,
    this.elasticZoomOvershoot = 0.35,
    this.elasticResistance = 3.5,
    this.enabled = true,
    this.nodeDragSpringStiffness = 400.0,
    this.nodeDragSpringDamping = 28.0,
    this.nodeDragFlingFriction = 0.02,
    this.nodeDragFlingThreshold = 150.0,
    this.nodeDragMaxFlingVelocity = 4000.0,
    this.nodeDragAdaptiveFrictionFactor = 0.002,
    this.nodeDragMidFlingSnapDistance = 12.0,
    this.panSpringStiffness = 200.0,
    this.panSpringDamping = 22.0,
    this.reflow,
  });

  /// Disabled configuration — all physics off.
  static const disabled = LiquidCanvasConfig(enabled: false);

  /// Maximum allowed scale including overshoot
  double maxElasticScale(double maxScale) =>
      maxScale * (1.0 + elasticZoomOvershoot);

  /// Minimum allowed scale including overshoot
  double minElasticScale(double minScale) =>
      minScale * (1.0 - elasticZoomOvershoot * 0.5);
}
