import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import './liquid_canvas_config.dart';
import '../rendering/lod_config.dart';

/// Persistence hook for the rotation-lock preference.
///
/// Canvas core ships no default implementation — callers that want the
/// rotation lock to survive across sessions set
/// [InfiniteCanvasController.rotationLockPersistence] with their own
/// storage-backed implementation (e.g. shared_preferences, SQLite).
abstract class RotationLockPersistence {
  /// Return the stored lock preference, or `null` if nothing has been
  /// persisted yet (the controller falls back to its default in that case).
  Future<bool?> load();

  /// Persist [value] asynchronously. Errors are the caller's responsibility.
  Future<void> save(bool value);
}

/// 🎬 A single keyframe in a multi-phase camera animation.
///
/// Used by [InfiniteCanvasController.animateMultiPhase] to define
/// sequential camera positions (offset + scale) with per-phase
/// duration and easing curve.
class CameraKeyframe {
  /// Target viewport offset at the end of this phase.
  final Offset targetOffset;

  /// Target zoom scale at the end of this phase.
  final double targetScale;

  /// Target rotation in radians at the end of this phase.
  /// null = keep current rotation (no banking).
  final double? targetRotation;

  /// Duration of this phase in seconds.
  final double durationSeconds;

  /// Easing curve for this phase.
  final Curve curve;

  const CameraKeyframe({
    required this.targetOffset,
    required this.targetScale,
    this.targetRotation,
    this.durationSeconds = 0.4,
    this.curve = Curves.easeInOutCubic,
  });
}

/// 🌊 Controller for infinite canvas with zoom, pan, and liquid physics.
///
/// DESIGN PRINCIPLES:
/// - Momentum deceleration after pan lift (FrictionSimulation)
/// - Spring-back when zoom exceeds min/max bounds (SpringSimulation)
/// - Elastic overshoot: briefly shows beyond-limits view before springing back
/// - Immediate stop on new touch (zero latency response)
/// - All physics driven by a single Ticker for battery efficiency
/// - Backward compatible: works identically without attaching a ticker
///
/// ARCHITECTURE:
/// - Extends ChangeNotifier for widget reactivity (AnimatedBuilder, painters)
/// - Physics state machine: IDLE → MOMENTUM / SPRING → IDLE
/// - Ticker callback drives all active simulations each frame
class InfiniteCanvasController extends ChangeNotifier {
  // ============================================================================
  // 🎯 CORE STATE
  // ============================================================================

  Offset _offset = Offset.zero;
  double _scale = 1.0;
  double _rotation = 0.0; // radians, clockwise

  // Zoom limits (logical bounds — elastic overshoot can exceed these)
  static const double _minScale = 0.1;
  static const double _maxScale = 5.0;

  /// Tracks whether we're past zoom limits (for one-shot haptic).
  bool _wasAtZoomLimit = false;

  /// Callback fired once when zoom crosses min/max boundary.
  /// Set by the widget to trigger haptic feedback.
  VoidCallback? onZoomLimitReached;

  /// 🚀 Callback fired when zoom crosses LOD tier boundaries (0.2x, 0.5x).
  /// Used to invalidate tile cache and force repaint for LOD transitions.
  VoidCallback? onLodTierChanged;

  /// Track the last LOD tier to detect boundary crossings.
  int _lastLodTier = 0;

  /// 🚀 Callback fired when all physics animations settle.
  /// Used by the canvas to trigger LOD precomputation at the new zoom level.
  VoidCallback? onAnimationSettle;

  /// 🔑 Callback fired when gesture/animation ends (isPanning goes true→false).
  /// Used to force a child widget rebuild so DrawingPainter re-renders at
  /// the new LOD tier (the Transform child is cached by AnimatedBuilder).
  VoidCallback? onGestureEnd;

  // Getters
  Offset get offset => _offset;
  double get scale => _scale;
  double get rotation => _rotation;

  /// 🚀 Current pan velocity from active momentum simulation.
  /// Returns Offset.zero if no momentum is active.
  Offset get panVelocity {
    if (!_isMomentumActive || _panSimX == null || _panSimY == null) {
      return Offset.zero;
    }
    return Offset(
      _panSimX!.dx(_momentumStartTime),
      _panSimY!.dx(_momentumStartTime),
    );
  }

  // 🌀 Rotation lock (default: LOCKED for first-time users)
  bool _rotationLocked =
      true; // 🔒 Locked by default — simpler first experience
  bool get rotationLocked => _rotationLocked;
  set rotationLocked(bool value) {
    _rotationLocked = value;
    notifyListeners();
    // Persist through the injected hook, if any. Canvas core intentionally
    // does not ship a storage implementation — consumers wire this up.
    rotationLockPersistence?.save(value);
  }

  /// Optional persistence hook for [rotationLocked]. Set from the consumer
  /// side to keep the preference across app launches.
  RotationLockPersistence? rotationLockPersistence;

  /// Load the persisted rotation lock state through
  /// [rotationLockPersistence]. If no persistence hook is registered, or
  /// the hook returns `null`, the controller keeps its default.
  Future<void> loadPersistedState() async {
    final hook = rotationLockPersistence;
    if (hook == null) return;
    final locked = await hook.load();
    if (locked != null && locked != _rotationLocked) {
      _rotationLocked = locked;
      notifyListeners();
    }
  }

  // ============================================================================
  // 🌊 LIQUID PHYSICS
  // ============================================================================

  /// Physics configuration (injectable, immutable)
  LiquidCanvasConfig _liquidConfig = const LiquidCanvasConfig();
  LiquidCanvasConfig get liquidConfig => _liquidConfig;
  set liquidConfig(LiquidCanvasConfig config) {
    _liquidConfig = config;
  }

  /// Ticker provided by the widget tree (TickerProviderStateMixin)
  Ticker? _ticker;
  Duration _lastTickTime = Duration.zero;

  // — Pan momentum state —
  FrictionSimulation? _panSimX;
  FrictionSimulation? _panSimY;
  double _momentumStartTime = 0;
  bool _isMomentumActive = false;

  // — Zoom spring state —
  SpringSimulation? _zoomSim;
  double _springStartTime = 0;
  bool _isZoomSpringActive = false;
  Offset _zoomSpringFocalPoint = Offset.zero;
  double _zoomSpringStartScale = 1.0;

  // — Rotation momentum state —
  FrictionSimulation? _rotationSim;
  double _rotationMomentumStartTime = 0;
  bool _isRotationMomentumActive = false;

  // — Rotation spring state —
  SpringSimulation? _rotationSpring;
  bool _isRotationSpringActive = false;

  // — Zoom momentum state (Gap 4) —
  FrictionSimulation? _zoomMomentumSim;
  double _zoomMomentumStartTime = 0;
  bool _isZoomMomentumActive = false;
  Offset _zoomMomentumFocalPoint = Offset.zero;

  // — Wormhole Dive state —
  bool _isDiveActive = false;
  double _diveElapsed = 0;
  double _diveDuration = 0.5; // seconds
  Offset _diveStartOffset = Offset.zero;
  double _diveStartScale = 1.0;
  Offset _diveTargetOffset = Offset.zero;
  double _diveTargetScale = 1.0;
  VoidCallback? _onDiveComplete;

  /// Curve for the dive animation — fast entry, smooth deceleration.
  static const Cubic _diveCurve = Cubic(0.16, 1.0, 0.3, 1.0);

  // — Multi-phase flight state —
  bool _isFlightActive = false;
  double _flightElapsed = 0;
  double _flightTotalDuration = 0;
  List<CameraKeyframe> _flightKeyframes = [];
  List<double> _flightPhaseEnds = []; // cumulative end times
  List<Offset> _flightPhaseStartOffsets = [];
  List<double> _flightPhaseStartScales = [];
  int _flightCurrentPhase = 0;
  double _flightProgressValue = 0.0;
  VoidCallback? _onFlightComplete;
  void Function(int phaseIndex)? _onFlightPhaseChanged;

  /// 🎯 Cluster IDs of the active flight (for connection-specific glow + DOF).
  String? _flightSourceClusterId;
  String? _flightTargetClusterId;

  /// 🎬 Landing pulse state — expanding ring at target after flight completes.
  bool _landingPulseActive = false;
  double _landingPulseElapsed = 0;
  Offset _landingPulseCenter = Offset.zero;
  static const double _landingPulseDuration = 0.35;

  /// 🚩 Phase start rotations (for rotation interpolation during flight).
  List<double> _flightPhaseStartRotations = [];

  /// Whether any physics animation is running.
  bool get isAnimating =>
      _isMomentumActive ||
      _isZoomSpringActive ||
      _isZoomMomentumActive ||
      _isRotationMomentumActive ||
      _isRotationSpringActive ||
      _isPanSpringActive ||
      _isDiveActive ||
      _isFlightActive;

  /// 🌀 Wormhole Dive progress (0.0 = idle/not diving, 0.0→1.0 during dive).
  ///
  /// Painters use this to apply depth-of-field blur on non-target elements
  /// and to render cinematic effects during the dive animation.
  double get diveProgress => _isDiveActive ? _diveProgressValue : 0.0;

  /// 🎬 Multi-phase flight progress (0.0 = idle, 0.0→1.0 during flight).
  ///
  /// Painters use this to render speed-glow effects along the active
  /// connection and vignette during Hyper-Jump.
  double get flightProgress => _isFlightActive ? _flightProgressValue : 0.0;

  /// Current flight phase index (0-based). -1 if no flight is active.
  int get flightPhase => _isFlightActive ? _flightCurrentPhase : -1;

  /// 🎯 Source cluster ID of the active flight (null if no flight).
  String? get flightSourceClusterId =>
      _isFlightActive ? _flightSourceClusterId : null;

  /// 🎯 Target cluster ID of the active flight (null if no flight).
  String? get flightTargetClusterId =>
      _isFlightActive ? _flightTargetClusterId : null;

  /// 🎬 Landing pulse progress (0.0—1.0). 0.0 when not active.
  double get landingPulseProgress =>
      _landingPulseActive
          ? (_landingPulseElapsed / _landingPulseDuration).clamp(0.0, 1.0)
          : 0.0;

  /// 🎬 Landing pulse center (canvas coordinates).
  Offset get landingPulseCenter => _landingPulseCenter;
  double _diveProgressValue = 0.0;

  /// 🚀 Whether the canvas is actively gesturing (pan/zoom/rotation)
  /// or running any physics animation (momentum, spring-back).
  /// Painters use this to skip expensive work during all gesture types.
  bool _isPanning = false;
  bool get isPanning =>
      _isPanning ||
      _isMomentumActive ||
      _isRotationMomentumActive ||
      _isRotationSpringActive ||
      _isZoomSpringActive ||
      _isZoomMomentumActive;
  set isPanning(bool value) {
    final wasActive = _isPanning;
    _isPanning = value;
    // 🔑 When gesture ends with no momentum, fire callback so the widget
    // rebuilds the DrawingPainter child at the new scale/LOD tier.
    if (wasActive && !value && !_isMomentumActive) {
      notifyListeners();
      onGestureEnd?.call();
    }
  }

  /// Request a repaint for all painters listening to this controller.
  ///
  /// Use when external state (e.g. image list) has changed and painters
  /// need to re-render, but a full widget rebuild is unnecessary.
  void markNeedsPaint() => notifyListeners();

  // ============================================================================
  // 🎛️ CORE API
  // ============================================================================

  /// Apply offset (pan)
  void setOffset(Offset newOffset) {
    _offset = newOffset;
    notifyListeners();
  }

  /// Apply zoom with hard clamp (no elastic overshoot)
  void setScale(double newScale) {
    _scale = newScale.clamp(_minScale, _maxScale);
    notifyListeners();
    _checkLodTier();
  }

  /// Apply combined transform (zoom + pan + rotation) with optional elastic bounds.
  ///
  /// When [elastic] is true and liquid physics are enabled, the scale
  /// is allowed to overshoot the limits with increasing resistance,
  /// creating the signature rubber-band feel.
  void updateTransform({
    required Offset offset,
    required double scale,
    double? rotation,
    bool elastic = false,
  }) {
    final oldScale = _scale;
    _offset = offset;
    if (rotation != null && !_rotationLocked) _rotation = rotation;
    if (elastic && _liquidConfig.enabled && _liquidConfig.enableElasticZoom) {
      _scale = _applyElasticClamp(scale);
      final isAtLimit = scale < _minScale || scale > _maxScale;
      if (isAtLimit && !_wasAtZoomLimit) {
        onZoomLimitReached?.call();
      }
      _wasAtZoomLimit = isAtLimit;
    } else {
      _scale = scale.clamp(_minScale, _maxScale);
      _wasAtZoomLimit = false;
    }

    // 📐 1x CROSSING HAPTIC: Subtle click when zoom crosses 1.0x.
    // Gives the user a tactile reference for "actual size".
    if ((oldScale < 1.0 && _scale >= 1.0) ||
        (oldScale > 1.0 && _scale <= 1.0)) {
      HapticFeedback.selectionClick();
    }

    notifyListeners();
    _checkLodTier();
  }

  /// Check if zoom crossed an LOD tier boundary and fire callback.
  /// Uses hysteresis to prevent flickering at boundaries.
  void _checkLodTier() {
    final tier = computeLodTier(_scale, _lastLodTier);
    if (tier != _lastLodTier) {
      // 📳 GRADUATED HAPTIC: different feedback for direction & magnitude
      final tierDelta = (tier - _lastLodTier).abs();
      if (tierDelta >= 2) {
        // Jump 2 tiers (e.g. 0→2): medium impact — noticeable shift
        HapticFeedback.mediumImpact();
      } else if (tier > _lastLodTier) {
        // Zooming OUT (quality decreasing): light tap
        HapticFeedback.lightImpact();
      } else {
        // Zooming IN (quality increasing): subtle click
        HapticFeedback.selectionClick();
      }
      _lastLodTier = tier;
      onLodTierChanged?.call();
    }
  }

  /// Preview what scale value [updateTransform] would actually apply.
  ///
  /// When elastic zoom is enabled, returns the elastically-clamped value.
  /// Otherwise returns the hard-clamped value. Does NOT mutate state.
  double getEffectiveScale(double rawScale, {bool elastic = true}) {
    if (elastic && _liquidConfig.enabled && _liquidConfig.enableElasticZoom) {
      return _applyElasticClamp(rawScale);
    }
    return rawScale.clamp(_minScale, _maxScale);
  }

  /// Reset to initial view
  void reset() {
    stopAnimation();
    _offset = Offset.zero;
    _scale = 1.0;
    _rotation = 0.0;
    notifyListeners();
  }

  /// 🎯 Center the viewport on the canvas origin (0,0)
  void centerCanvas(
    Size viewportSize, {
    Size canvasSize = const Size(5000, 5000),
  }) {
    _offset = Offset(viewportSize.width / 2, viewportSize.height / 2);
    notifyListeners();
  }

  /// Convert screen coordinates to canvas coordinates
  Offset screenToCanvas(Offset screenPoint) {
    if (_rotation == 0.0) {
      return (screenPoint - _offset) / _scale;
    }
    // Undo translate → undo rotate → undo scale
    final translated = screenPoint - _offset;
    final cosR = math.cos(-_rotation);
    final sinR = math.sin(-_rotation);
    final rotated = Offset(
      translated.dx * cosR - translated.dy * sinR,
      translated.dx * sinR + translated.dy * cosR,
    );
    return rotated / _scale;
  }

  /// Convert canvas coordinates to screen coordinates
  Offset canvasToScreen(Offset canvasPoint) {
    if (_rotation == 0.0) {
      return canvasPoint * _scale + _offset;
    }
    // Scale → rotate → translate
    final scaled = canvasPoint * _scale;
    final cosR = math.cos(_rotation);
    final sinR = math.sin(_rotation);
    final rotated = Offset(
      scaled.dx * cosR - scaled.dy * sinR,
      scaled.dx * sinR + scaled.dy * cosR,
    );
    return rotated + _offset;
  }

  // ============================================================================
  // 🌊 LIQUID PHYSICS — Ticker Lifecycle
  // ============================================================================

  /// Attach a ticker from the widget tree for physics animations.
  /// Call from initState() — the State must use TickerProviderStateMixin.
  void attachTicker(TickerProvider vsync) {
    _ticker?.dispose();
    _ticker = vsync.createTicker(_onTick);
  }

  /// Detach the ticker. Call from dispose().
  void detachTicker() {
    _ticker?.dispose();
    _ticker = null;
    _isMomentumActive = false;
    _isZoomSpringActive = false;
  }

  // ============================================================================
  // 🌊 LIQUID PHYSICS — Pan Momentum
  // ============================================================================

  /// Launch pan momentum from terminal velocity (called on gesture end).
  ///
  /// Uses [FrictionSimulation] for natural exponential deceleration.
  /// The simulation is driven per-axis for independent X/Y damping.
  void startMomentum(Offset velocity) {
    if (!_liquidConfig.enabled) return;
    if (_ticker == null) return;

    // Don't start momentum for tiny velocities
    final speed = velocity.distance;
    if (speed < _liquidConfig.momentumThreshold) return;

    // Create friction simulations for each axis
    _panSimX = FrictionSimulation(
      _liquidConfig.panFriction,
      _offset.dx,
      velocity.dx,
    );
    _panSimY = FrictionSimulation(
      _liquidConfig.panFriction,
      _offset.dy,
      velocity.dy,
    );

    _isMomentumActive = true;
    _momentumStartTime = 0;
    _lastTickTime = Duration.zero;
    _ensureTickerRunning();
  }

  /// Immediately stop all running animations.
  /// Call on new touch-down for instant response.
  void stopAnimation() {
    _isMomentumActive = false;
    _isZoomSpringActive = false;
    _isZoomMomentumActive = false;
    _isRotationMomentumActive = false;
    _isRotationSpringActive = false;
    _isPanSpringActive = false;
    _isTransformSpringActive = false;
    _isDiveActive = false;
    _diveProgressValue = 0.0;
    _onDiveComplete = null;
    _isFlightActive = false;
    _flightProgressValue = 0.0;
    _flightKeyframes = [];
    _onFlightComplete = null;
    _onFlightPhaseChanged = null;
    _panSimX = null;
    _panSimY = null;
    _zoomSim = null;
    _zoomMomentumSim = null;
    _rotationSim = null;
    _rotationSpring = null;
    _panSpringSimX = null;
    _panSpringSimY = null;
    if (_ticker?.isTicking ?? false) {
      _ticker!.stop();
    }
  }

  // ============================================================================
  // 🌊 LIQUID PHYSICS — Zoom Spring-Back
  // ============================================================================

  /// Start spring animation to bounce zoom back to limits.
  ///
  /// Called when the gesture ends with the scale beyond [_minScale, _maxScale].
  /// The focal point is preserved so the spring-back feels anchored.
  void startZoomSpringBack(Offset focalPointScreen) {
    if (!_liquidConfig.enabled || !_liquidConfig.enableElasticZoom) return;
    if (_ticker == null) return;

    // Determine target: clamp to nearest limit
    final targetScale = _scale.clamp(_minScale, _maxScale);
    if ((_scale - targetScale).abs() < 0.001) return; // Already within bounds

    final spring = SpringDescription(
      mass: _liquidConfig.zoomSpringMass,
      stiffness: _liquidConfig.zoomSpringStiffness,
      damping: _liquidConfig.zoomSpringDamping,
    );

    _zoomSim = SpringSimulation(
      spring,
      _scale, // current position
      targetScale, // target position
      0.0, // initial velocity (at rest relative to spring)
    );

    _zoomSpringFocalPoint = focalPointScreen;
    _zoomSpringStartScale = _scale;
    _isZoomSpringActive = true;
    _springStartTime = 0;
    _lastTickTime = Duration.zero;
    _ensureTickerRunning();
  }

  /// 🎯 Animate zoom to a specific scale, centered on a focal point.
  ///
  /// Used by double-tap zoom: smoothly springs from the current scale to
  /// [targetScale], keeping the [focalPointScreen] visually anchored.
  /// The animation is driven by the same ticker as zoom spring-back.
  void animateZoomTo(double targetScale, Offset focalPointScreen) {
    if (_ticker == null) return;

    // Clamp target within allowed bounds
    final clampedTarget = targetScale.clamp(_minScale, _maxScale);
    if ((_scale - clampedTarget).abs() < 0.001) return; // Already there

    // 🏎️ Snappy spring with subtle micro-bounce for premium feel.
    // Stiffer than spring-back (intentional zoom should feel decisive).
    // Slightly underdamped (~0.54 ratio) for a tiny satisfying overshoot.
    const spring = SpringDescription(
      mass: 1.0,
      stiffness: 220.0, // Fast arrival (was 180)
      damping: 16.0, // Underdamped (was 22) — micro-bounce on landing
    );

    _zoomSim = SpringSimulation(
      spring,
      _scale, // current
      clampedTarget, // target
      0.0, // start at rest
    );

    _zoomSpringFocalPoint = focalPointScreen;
    _zoomSpringStartScale = _scale;
    _isZoomSpringActive = true;
    _springStartTime = 0;
    _lastTickTime = Duration.zero;
    _ensureTickerRunning();
  }

  // ============================================================================
  // 🌊 LIQUID PHYSICS — Pan-to-Target Spring
  // ============================================================================

  // — Pan spring state —
  SpringSimulation? _panSpringSimX;
  SpringSimulation? _panSpringSimY;
  double _panSpringStartTime = 0;
  bool _isPanSpringActive = false;

  // — Combined transform spring state —
  bool _isTransformSpringActive = false;

  /// 🎯 Animate pan offset to a target position with spring physics.
  ///
  /// Used for "scroll-to-selection", "scroll-to-origin", or any
  /// programmatic camera move that should feel organic.
  void animateOffsetTo(Offset targetOffset, {Offset velocity = Offset.zero}) {
    if (_ticker == null) return;

    final config = _liquidConfig;
    if ((targetOffset - _offset).distance < 0.5) return; // Already there

    final spring = SpringDescription(
      mass: 1.0,
      stiffness: config.panSpringStiffness,
      damping: config.panSpringDamping,
    );

    _panSpringSimX = SpringSimulation(
      spring,
      _offset.dx,
      targetOffset.dx,
      velocity.dx,
    );
    _panSpringSimY = SpringSimulation(
      spring,
      _offset.dy,
      targetOffset.dy,
      velocity.dy,
    );

    _isPanSpringActive = true;
    _isTransformSpringActive = false;
    _panSpringStartTime = 0;
    _lastTickTime = Duration.zero;
    _ensureTickerRunning();
  }

  /// 🎯 Animate both offset and scale to target values simultaneously.
  ///
  /// Used for "fit selection in viewport", "fit all content", or any
  /// combined camera transition. The [focalPoint] (in screen coords)
  /// stays visually anchored during the animation.
  void animateToTransform({
    required Offset targetOffset,
    required double targetScale,
    Offset? focalPoint,
  }) {
    if (_ticker == null) return;

    final clampedScale = targetScale.clamp(_minScale, _maxScale);
    final offsetDist = (targetOffset - _offset).distance;
    final scaleDist = (_scale - clampedScale).abs();
    if (offsetDist < 0.5 && scaleDist < 0.001) return; // Already there

    final config = _liquidConfig;

    final spring = SpringDescription(
      mass: 1.0,
      stiffness: config.panSpringStiffness,
      damping: config.panSpringDamping,
    );

    _panSpringSimX = SpringSimulation(spring, _offset.dx, targetOffset.dx, 0.0);
    _panSpringSimY = SpringSimulation(spring, _offset.dy, targetOffset.dy, 0.0);

    // Reuse zoom spring for the scale component
    final zoomSpring = SpringDescription(
      mass: config.zoomSpringMass,
      stiffness: config.panSpringStiffness,
      damping: config.panSpringDamping,
    );

    _zoomSim = SpringSimulation(zoomSpring, _scale, clampedScale, 0.0);
    _zoomSpringFocalPoint = focalPoint ?? Offset.zero;
    _zoomSpringStartScale = _scale;

    _isPanSpringActive = true;
    _isTransformSpringActive = true;
    _isZoomSpringActive = true;
    _panSpringStartTime = 0;
    _springStartTime = 0;
    _lastTickTime = Duration.zero;
    _ensureTickerRunning();
  }

  // ============================================================================
  // 🌀 WORMHOLE DIVE — Cinematic Zoom-Into-Node Animation
  // ============================================================================

  /// 🌀 Animate the canvas camera to "dive into" a node, framing it at 1:1.
  ///
  /// Computes the target offset and scale so that [nodeWorldRect] fills
  /// the [viewportSize] while maintaining aspect ratio (contain fit).
  /// The animation uses a cinematic ease curve for a "camera dive" feel.
  ///
  /// [onComplete] fires exactly once when the dive reaches t=1.0.
  /// Use it to trigger the seamless handoff to the viewer screen.
  ///
  /// During the dive, [diveProgress] ramps from 0.0 to 1.0 — painters
  /// can read this to apply depth-of-field blur on non-target elements.
  void animateDiveTo({
    required Rect nodeWorldRect,
    required Size viewportSize,
    double durationSeconds = 0.5,
    VoidCallback? onComplete,
  }) {
    if (_ticker == null) return;
    if (nodeWorldRect.isEmpty || viewportSize.isEmpty) return;

    // Stop any running animations first
    stopAnimation();

    // ── Compute target transform ──
    // Scale: fit the node rect into the viewport (contain)
    final scaleX = viewportSize.width / nodeWorldRect.width;
    final scaleY = viewportSize.height / nodeWorldRect.height;
    final targetScale = math.min(scaleX, scaleY).clamp(_minScale, _maxScale);

    // Offset: center the node in the viewport
    final targetOffset = Offset(
      viewportSize.width / 2 - nodeWorldRect.center.dx * targetScale,
      viewportSize.height / 2 - nodeWorldRect.center.dy * targetScale,
    );

    // ── Store dive parameters ──
    _diveStartOffset = _offset;
    _diveStartScale = _scale;
    _diveTargetOffset = targetOffset;
    _diveTargetScale = targetScale;
    _diveDuration = durationSeconds;
    _diveElapsed = 0;
    _diveProgressValue = 0.0;
    _onDiveComplete = onComplete;
    _isDiveActive = true;

    _lastTickTime = Duration.zero;
    _ensureTickerRunning();
  }

  /// Cancel a running dive without firing onComplete.
  void cancelDive() {
    if (!_isDiveActive) return;
    _isDiveActive = false;
    _diveProgressValue = 0.0;
    _onDiveComplete = null;
    notifyListeners();
  }

  // ============================================================================
  // 🎬 MULTI-PHASE FLIGHT — Cinematic Camera Sequences
  // ============================================================================

  /// 🎬 Animate the camera through a sequence of keyframes.
  ///
  /// Each [CameraKeyframe] defines a target offset + scale with its own
  /// duration and easing curve. The animation smoothly interpolates through
  /// all phases in sequence.
  ///
  /// Used for:
  /// - **Cinematic Flight**: zoom-out → pan along connection → zoom-in
  /// - **Hyper-Jump**: dramatic zoom-out → transit → zoom-in with LOD
  ///
  /// [onComplete] fires when the last keyframe is reached.
  /// [onPhaseChanged] fires at each phase transition (for haptics).
  void animateMultiPhase({
    required List<CameraKeyframe> keyframes,
    VoidCallback? onComplete,
    void Function(int phaseIndex)? onPhaseChanged,
    String? sourceClusterId,
    String? targetClusterId,
  }) {
    if (_ticker == null) return;
    if (keyframes.isEmpty) return;

    // Stop any running animations first
    stopAnimation();

    _flightKeyframes = keyframes;
    _onFlightComplete = onComplete;
    _onFlightPhaseChanged = onPhaseChanged;
    _flightSourceClusterId = sourceClusterId;
    _flightTargetClusterId = targetClusterId;

    // Pre-compute cumulative phase end times
    _flightPhaseEnds = [];
    double cumulative = 0;
    for (final kf in keyframes) {
      cumulative += kf.durationSeconds;
      _flightPhaseEnds.add(cumulative);
    }
    _flightTotalDuration = cumulative;

    // Pre-compute start positions for each phase
    _flightPhaseStartOffsets = [_offset];
    _flightPhaseStartScales = [_scale];
    _flightPhaseStartRotations = [_rotation];
    for (int i = 0; i < keyframes.length - 1; i++) {
      _flightPhaseStartOffsets.add(keyframes[i].targetOffset);
      _flightPhaseStartScales.add(keyframes[i].targetScale);
      _flightPhaseStartRotations.add(
        keyframes[i].targetRotation ?? _flightPhaseStartRotations.last,
      );
    }

    _flightElapsed = 0;
    _flightCurrentPhase = 0;
    _flightProgressValue = 0.0;
    _isFlightActive = true;

    _lastTickTime = Duration.zero;
    _ensureTickerRunning();
  }

  /// Cancel a running flight without firing onComplete.
  void cancelFlight() {
    if (!_isFlightActive) return;
    _isFlightActive = false;
    _flightProgressValue = 0.0;
    _flightKeyframes = [];
    _onFlightComplete = null;
    _onFlightPhaseChanged = null;
    _flightSourceClusterId = null;
    _flightTargetClusterId = null;
    _flightPhaseStartRotations = [];
    _landingPulseActive = false;
    notifyListeners();
  }

  // ============================================================================
  // 🌊 LIQUID PHYSICS — Rotation Momentum
  // ============================================================================

  /// Launch rotation momentum from terminal angular velocity.
  /// Called on gesture end when the user was rotating the canvas.
  void startRotationMomentum(double angularVelocity) {
    if (!_liquidConfig.enabled) return;
    if (_ticker == null) return;
    if (_rotationLocked) return;

    // Don't start for small angular velocities (prevent accidental spin)
    if (angularVelocity.abs() < 0.5) return;

    // Cap angular velocity to prevent wild spins from noisy gesture data
    final clampedVelocity = angularVelocity.clamp(-3.0, 3.0);

    _rotationSim = FrictionSimulation(
      _liquidConfig.panFriction * 4.0, // High friction — rotation dies fast
      _rotation,
      clampedVelocity,
    );

    _isRotationMomentumActive = true;
    _rotationMomentumStartTime = 0;
    _lastTickTime = Duration.zero;
    _ensureTickerRunning();
  }

  // ============================================================================
  // 🌊 LIQUID PHYSICS — Zoom Momentum (Gap 4)
  // ============================================================================

  /// Launch zoom momentum from terminal pinch velocity.
  ///
  /// Called on gesture end when the user was actively zooming.
  /// Uses [FrictionSimulation] on **log-scale** for natural multiplicative
  /// deceleration (zoom 2x→ 4x feels the same as 0.5x→0.25x).
  /// The focal point is preserved so the momentum feels anchored.
  void startZoomMomentum(double scaleVelocity, Offset focalPointScreen) {
    if (!_liquidConfig.enabled) return;
    if (_ticker == null) return;

    // Don't start for small velocities (threshold in scale-units/second)
    if (scaleVelocity.abs() < 0.3) return;

    // If already past limits, skip momentum and let spring-back handle it
    if (_scale < _minScale || _scale > _maxScale) return;

    // Friction on log-scale: log(scale) + velocity → exp() back to scale.
    // This gives multiplicative deceleration (2x→4x feels same as 0.5x→0.25x).
    final logScale = math.log(_scale);
    final logVelocity = scaleVelocity / _scale; // Convert to log-space velocity

    _zoomMomentumSim = FrictionSimulation(
      _liquidConfig.panFriction *
          2.5, // 🏎️ Lower friction → longer, premium glide
      logScale,
      logVelocity,
    );

    _zoomMomentumFocalPoint = focalPointScreen;
    _isZoomMomentumActive = true;
    _zoomMomentumStartTime = 0;
    _lastTickTime = Duration.zero;
    _ensureTickerRunning();
  }

  // 📐 Clean scale levels for snap-to-grid on zoom settle
  static const List<double> _cleanScales = [
    0.1,
    0.15,
    0.2,
    0.25,
    0.33,
    0.5,
    0.67,
    0.75,
    1.0,
    1.25,
    1.5,
    2.0,
    2.5,
    3.0,
    4.0,
    5.0,
  ];
  static const double _cleanScaleSnapThreshold = 0.04; // 4% tolerance

  /// Check if scale is near a "clean" level (1.0x, 0.5x, 2.0x, etc.)
  /// Returns the clean scale if within threshold, null otherwise.
  double? _checkCleanScale(double scale) {
    for (final clean in _cleanScales) {
      if ((scale - clean).abs() / clean < _cleanScaleSnapThreshold) {
        return clean;
      }
    }
    return null;
  }

  // — Rotation spring state (for animated reset / snap) —
  double _rotationSpringStartTime = 0;
  double _rotationSpringTarget = 0.0;

  /// Snap rotation back to 0° with a spring animation.
  void resetRotation() {
    _animateRotationTo(0.0);
  }

  /// Animate rotation to a target angle with a spring.
  /// [initialVelocity] allows seamless handoff from momentum → spring.
  void _animateRotationTo(
    double targetRotation, {
    double initialVelocity = 0.0,
  }) {
    if (_ticker == null) return;
    if ((_rotation - targetRotation).abs() < 0.001) {
      _rotation = targetRotation;
      notifyListeners();
      return;
    }

    // 🏎️ Slightly underdamped: creates a subtle micro-bounce before settling.
    // Feels alive — like a precision mechanical detent, not a dead stop.
    // Critical damping would be ~34.6 (2 * √(1 * 300)); 18 is about 0.52 ratio.
    final spring = SpringDescription(
      mass: 1.0,
      stiffness: 300.0,
      damping: 18.0, // Underdamped (was 22) — ~1 subtle overshoot then settle
    );

    _rotationSpring = SpringSimulation(
      spring,
      _rotation, // current
      targetRotation, // target
      initialVelocity, // carry momentum velocity for seamless handoff
    );

    _rotationSpringTarget = targetRotation;
    _isRotationSpringActive = true;
    _isRotationMomentumActive = false; // Cancel any momentum
    _rotationSim = null;
    _rotationSpringStartTime = 0;
    _lastTickTime = Duration.zero;
    _ensureTickerRunning();
  }

  // 🌀 Snap angles: 0°, 45°, 90°, 135°, 180°, 225°, 270°, 315°
  static const double _snapThreshold =
      0.18; // ~10° tolerance (matches gesture magnetic zone)
  static const List<double> _snapAngles = [
    0.0,
    math.pi / 4, // 45°
    math.pi / 2, // 90°
    3 * math.pi / 4, // 135°
    math.pi, // 180°
    -3 * math.pi / 4, // -135° / 225°
    -math.pi / 2, // -90° / 270°
    -math.pi / 4, // -45° / 315°
    -math.pi, // -180°
  ];

  /// Check if the current rotation is close to a snap angle.
  /// Returns the snap angle if within threshold, null otherwise.
  double? checkSnapAngle(double rotation) {
    for (final snap in _snapAngles) {
      if ((rotation - snap).abs() < _snapThreshold) {
        return snap;
      }
    }
    return null;
  }

  /// Convert rotation in radians to degrees string for display.
  String get rotationDegrees {
    final degrees = (_rotation * 180.0 / math.pi) % 360;
    final normalized = degrees < 0 ? degrees + 360 : degrees;
    return '${normalized.toStringAsFixed(1)}°';
  }

  // ============================================================================
  // 🌊 LIQUID PHYSICS — Ticker Callback
  // ============================================================================

  void _onTick(Duration elapsed) {
    if (!isAnimating) {
      _ticker?.stop();
      return;
    }

    // Calculate delta time in seconds
    final double t;
    if (_lastTickTime == Duration.zero) {
      t = 0.016; // First frame: assume 60fps
      _lastTickTime = elapsed;
    } else {
      t = (elapsed - _lastTickTime).inMicroseconds / 1000000.0;
      _lastTickTime = elapsed;
    }

    bool needsNotify = false;

    // — PAN MOMENTUM —
    if (_isMomentumActive && _panSimX != null && _panSimY != null) {
      _momentumStartTime += t;

      final newX = _panSimX!.x(_momentumStartTime);
      final newY = _panSimY!.x(_momentumStartTime);

      // Check if momentum has effectively stopped
      final vx = _panSimX!.dx(_momentumStartTime).abs();
      final vy = _panSimY!.dx(_momentumStartTime).abs();

      if (vx < _liquidConfig.stopVelocity && vy < _liquidConfig.stopVelocity) {
        _isMomentumActive = false;
        _panSimX = null;
        _panSimY = null;
        needsNotify = true; // 🚀 SCROLL OPT: Final repaint with isPanning=false
      } else {
        _offset = Offset(newX, newY);
        needsNotify = true;
      }
    }

    // — ZOOM SPRING-BACK —
    if (_isZoomSpringActive && _zoomSim != null) {
      _springStartTime += t;

      final newScale = _zoomSim!.x(_springStartTime);

      // Apply focal-point-preserving zoom (rotation-aware)
      // screenToCanvas: undo translate → undo rotate → undo scale
      final translated = _zoomSpringFocalPoint - _offset;
      final cosR = math.cos(-_rotation);
      final sinR = math.sin(-_rotation);
      final unrotated = Offset(
        translated.dx * cosR - translated.dy * sinR,
        translated.dx * sinR + translated.dy * cosR,
      );
      final focalCanvas = unrotated / _scale;

      _scale = newScale;

      // canvasToScreen: scale → rotate → translate
      final scaled = focalCanvas * _scale;
      final cosRf = math.cos(_rotation);
      final sinRf = math.sin(_rotation);
      final rotated = Offset(
        scaled.dx * cosRf - scaled.dy * sinRf,
        scaled.dx * sinRf + scaled.dy * cosRf,
      );
      _offset = _zoomSpringFocalPoint - rotated;

      needsNotify = true;

      // Check if spring has settled
      if (_zoomSim!.isDone(_springStartTime)) {
        _scale = _scale.clamp(_minScale, _maxScale);
        // Recalculate offset for the exact clamped scale
        final settledScaled = focalCanvas * _scale;
        final settledRotated = Offset(
          settledScaled.dx * cosRf - settledScaled.dy * sinRf,
          settledScaled.dx * sinRf + settledScaled.dy * cosRf,
        );
        _offset = _zoomSpringFocalPoint - settledRotated;
        _isZoomSpringActive = false;
        _zoomSim = null;
        needsNotify = true;
      }
    }

    // — ZOOM MOMENTUM (Gap 4) —
    if (_isZoomMomentumActive && _zoomMomentumSim != null) {
      _zoomMomentumStartTime += t;

      // Simulation runs in log-space; convert back to linear scale
      final logScale = _zoomMomentumSim!.x(_zoomMomentumStartTime);
      final newScale = math.exp(logScale);
      final logVelocity = _zoomMomentumSim!.dx(_zoomMomentumStartTime).abs();

      // Focal-point-preserving zoom (same math as spring-back)
      final translated = _zoomMomentumFocalPoint - _offset;
      final cosR = math.cos(-_rotation);
      final sinR = math.sin(-_rotation);
      final unrotated = Offset(
        translated.dx * cosR - translated.dy * sinR,
        translated.dx * sinR + translated.dy * cosR,
      );
      final focalCanvas = unrotated / _scale;

      _scale = newScale;

      final scaled = focalCanvas * _scale;
      final cosRf = math.cos(_rotation);
      final sinRf = math.sin(_rotation);
      final rotated = Offset(
        scaled.dx * cosRf - scaled.dy * sinRf,
        scaled.dx * sinRf + scaled.dy * cosRf,
      );
      _offset = _zoomMomentumFocalPoint - rotated;

      needsNotify = true;

      // Stop conditions: very slow, or past limits (let spring-back handle)
      // 🏎️ Raised threshold from 0.01 to 0.03 — stops cleaner, no "crawling"
      if (logVelocity < 0.03 || newScale < _minScale || newScale > _maxScale) {
        _isZoomMomentumActive = false;
        _zoomMomentumSim = null;

        // If past limits, trigger spring-back for seamless elastic bounce
        if (newScale < _minScale || newScale > _maxScale) {
          startZoomSpringBack(_zoomMomentumFocalPoint);
        } else {
          // 📐 CLEAN SCALE SNAP: If settled near a round level, snap to it.
          // Gives a Figma-quality "landing on grid" feel.
          final cleanScale = _checkCleanScale(_scale);
          if (cleanScale != null && cleanScale != _scale) {
            // Use zoom spring to animate to exact clean scale
            animateZoomTo(cleanScale, _zoomMomentumFocalPoint);
            HapticFeedback.selectionClick(); // Subtle confirm
          }
        }
      }
    }

    // — ROTATION MOMENTUM —
    if (_isRotationMomentumActive && _rotationSim != null) {
      _rotationMomentumStartTime += t;

      final newRotation = _rotationSim!.x(_rotationMomentumStartTime);
      final angularV = _rotationSim!.dx(_rotationMomentumStartTime).abs();

      // 🧲 MID-FLING MAGNETIC CATCH: When momentum slows enough near a
      // snap angle, "catch" it with a spring animation instead of waiting
      // for full stop. Creates a ball-bearing detent feel.
      if (angularV < 0.3 && angularV > 0.001) {
        final snapAngle = checkSnapAngle(newRotation);
        if (snapAngle != null) {
          _rotation = newRotation; // Set current position
          _isRotationMomentumActive = false;
          _rotationSim = null;
          // 🏎️ Spring to exact snap angle with carried velocity (seamless handoff)
          final direction = (snapAngle - newRotation).sign;
          _animateRotationTo(snapAngle, initialVelocity: direction * angularV);
          HapticFeedback.selectionClick(); // Subtle confirm
          needsNotify = true;
          // Skip to next section — spring will handle the rest
        }
      }

      // Normal stop: momentum fully exhausted
      if (_isRotationMomentumActive && angularV < 0.001) {
        _rotation = newRotation;
        _isRotationMomentumActive = false;
        _rotationSim = null;
      } else if (_isRotationMomentumActive) {
        _rotation = newRotation;
      }
      needsNotify = true;
    }

    // — ROTATION SPRING (animated reset/snap) —
    if (_isRotationSpringActive && _rotationSpring != null) {
      _rotationSpringStartTime += t;

      _rotation = _rotationSpring!.x(_rotationSpringStartTime);
      needsNotify = true;

      if (_rotationSpring!.isDone(_rotationSpringStartTime)) {
        _rotation = _rotationSpringTarget;
        _isRotationSpringActive = false;
        _rotationSpring = null;
        needsNotify = true;
      }
    }

    // — PAN SPRING (programmatic camera move) —
    if (_isPanSpringActive &&
        _panSpringSimX != null &&
        _panSpringSimY != null) {
      _panSpringStartTime += t;

      final newX = _panSpringSimX!.x(_panSpringStartTime);
      final newY = _panSpringSimY!.x(_panSpringStartTime);

      // When running a combined transform spring, the zoom spring
      // handles offset via focal-point anchoring. For pan-only spring,
      // we drive offset directly here.
      if (!_isTransformSpringActive) {
        _offset = Offset(newX, newY);
      }

      needsNotify = true;

      final doneX = _panSpringSimX!.isDone(_panSpringStartTime);
      final doneY = _panSpringSimY!.isDone(_panSpringStartTime);
      if (doneX && doneY) {
        if (!_isTransformSpringActive) {
          _offset = Offset(newX, newY);
        }
        _isPanSpringActive = false;
        _isTransformSpringActive = false;
        _panSpringSimX = null;
        _panSpringSimY = null;
        needsNotify = true;
      }
    }

    // — WORMHOLE DIVE (cinematic zoom-into-node) —
    if (_isDiveActive) {
      _diveElapsed += t;
      final rawT = (_diveElapsed / _diveDuration).clamp(0.0, 1.0);
      // Apply cinematic curve
      _diveProgressValue = _diveCurve.transform(rawT);
      final p = _diveProgressValue;

      // Interpolate offset and scale
      _offset = Offset.lerp(_diveStartOffset, _diveTargetOffset, p)!;
      _scale = _diveStartScale + (_diveTargetScale - _diveStartScale) * p;

      needsNotify = true;

      if (rawT >= 1.0) {
        // Snap to exact target
        _offset = _diveTargetOffset;
        _scale = _diveTargetScale;
        _isDiveActive = false;
        _diveProgressValue = 1.0;
        final cb = _onDiveComplete;
        _onDiveComplete = null;
        // Fire callback AFTER updating state
        cb?.call();
        needsNotify = true;
      }
    }

    // — MULTI-PHASE FLIGHT (cinematic camera sequence) —
    if (_isFlightActive && _flightKeyframes.isNotEmpty) {
      _flightElapsed += t;
      _flightProgressValue = (_flightElapsed / _flightTotalDuration).clamp(
        0.0,
        1.0,
      );

      // Determine current phase
      int phase = 0;
      for (int i = 0; i < _flightPhaseEnds.length; i++) {
        if (_flightElapsed <= _flightPhaseEnds[i]) {
          phase = i;
          break;
        }
        if (i == _flightPhaseEnds.length - 1) {
          phase = i;
        }
      }

      // Fire phase-change callback
      if (phase != _flightCurrentPhase) {
        _flightCurrentPhase = phase;
        _onFlightPhaseChanged?.call(phase);
      }

      // Compute local t within current phase
      final phaseStart = phase > 0 ? _flightPhaseEnds[phase - 1] : 0.0;
      final phaseEnd = _flightPhaseEnds[phase];
      final phaseDuration = phaseEnd - phaseStart;
      final localT =
          phaseDuration > 0
              ? ((_flightElapsed - phaseStart) / phaseDuration).clamp(0.0, 1.0)
              : 1.0;

      // Apply easing curve for this phase
      final kf = _flightKeyframes[phase];
      final easedT = kf.curve.transform(localT);

      // Interpolate offset and scale
      final startOffset = _flightPhaseStartOffsets[phase];
      final startScale = _flightPhaseStartScales[phase];
      _offset = Offset.lerp(startOffset, kf.targetOffset, easedT)!;
      _scale = startScale + (kf.targetScale - startScale) * easedT;

      // Interpolate rotation (if targetRotation is set for this phase)
      if (kf.targetRotation != null && _flightPhaseStartRotations.isNotEmpty) {
        final startRot = _flightPhaseStartRotations[phase];
        _rotation = startRot + (kf.targetRotation! - startRot) * easedT;
      }

      needsNotify = true;

      // Check if flight is complete
      if (_flightElapsed >= _flightTotalDuration) {
        // Snap to exact final target
        final lastKf = _flightKeyframes.last;
        _offset = lastKf.targetOffset;
        _scale = lastKf.targetScale;
        if (lastKf.targetRotation != null) {
          _rotation = lastKf.targetRotation!;
        }
        _isFlightActive = false;
        _flightProgressValue = 1.0;

        // 🎯 Trigger landing pulse at target center
        // Compute target center from scale+offset
        if (_flightTargetClusterId != null) {
          // Center of viewport in canvas space
          _landingPulseCenter = Offset(
            -_offset.dx / _scale,
            -_offset.dy / _scale,
          );
          _landingPulseActive = true;
          _landingPulseElapsed = 0;
        }

        final cb = _onFlightComplete;
        _onFlightComplete = null;
        _onFlightPhaseChanged = null;
        cb?.call();
        needsNotify = true;
      }
    }

    // — LANDING PULSE (expanding ring animation) —
    if (_landingPulseActive) {
      _landingPulseElapsed += t;
      if (_landingPulseElapsed >= _landingPulseDuration) {
        _landingPulseActive = false;
      }
      needsNotify = true;
    }

    if (needsNotify) {
      notifyListeners();
    }

    // Stop ticker if all simulations are done
    if (!isAnimating) {
      _ticker?.stop();
      // 🚀 Notify that all animations have settled (LOD precompute, etc.)
      onAnimationSettle?.call();
      // 🔑 Fire gesture-end: isPanning is now false (momentum ended),
      // triggering widget rebuild for LOD refresh.
      onGestureEnd?.call();
    }
  }

  // ============================================================================
  // 🌊 LIQUID PHYSICS — Helpers
  // ============================================================================

  /// Ensure the ticker is running (idempotent — safe to call multiple times).
  void _ensureTickerRunning() {
    if (_ticker != null && !_ticker!.isTicking) {
      _lastTickTime = Duration.zero;
      _ticker!.start();
    }
  }

  /// Apply rubber-band elastic clamping for zoom.
  ///
  /// When the scale is within bounds, returns it unchanged.
  /// When beyond bounds, applies logarithmic resistance so the user can
  /// "pull" past the limit but with increasing difficulty.
  double _applyElasticClamp(double rawScale) {
    final config = _liquidConfig;
    final minElastic = config.minElasticScale(_minScale);
    final maxElastic = config.maxElasticScale(_maxScale);

    if (rawScale >= _minScale && rawScale <= _maxScale) {
      return rawScale;
    }

    if (rawScale > _maxScale) {
      // How far past the limit (0.0 = at limit, 1.0+ = way past)
      final overshoot = (rawScale - _maxScale) / _maxScale;
      // 🎯 FIX: Cap overshoot — elastic is ~11% (5.0→5.55x) for liquid rubber-band,
      // but locks quickly (no asymptotic creep). The fast cap keeps drift bounded.
      final cappedOvershoot = overshoot.clamp(0.0, 0.15);
      // Logarithmic resistance: diminishing overshoot
      final dampedOvershoot =
          cappedOvershoot / (1.0 + cappedOvershoot * config.elasticResistance);
      return (_maxScale * (1.0 + dampedOvershoot)).clamp(_maxScale, maxElastic);
    }

    // rawScale < _minScale
    final undershoot = (_minScale - rawScale) / _minScale;
    // 🎯 FIX: Same cap for undershoot (zoom out past min)
    final cappedUndershoot = undershoot.clamp(0.0, 0.15);
    final dampedUndershoot =
        cappedUndershoot / (1.0 + cappedUndershoot * config.elasticResistance);
    return (_minScale * (1.0 - dampedUndershoot)).clamp(minElastic, _minScale);
  }

  // ============================================================================
  // 🔍 ADAPTIVE ZOOM PRESETS
  // ============================================================================

  /// 🔍 Animate to frame all content in the viewport.
  ///
  /// Computes the minimum scale and offset needed to make [contentBounds]
  /// fully visible, then animates smoothly via spring physics.
  /// [padding] adds screen-space margin around the content.
  void fitContent(
    Rect contentBounds,
    Size viewportSize, {
    double padding = 40.0,
  }) {
    if (contentBounds.isEmpty || viewportSize.isEmpty) return;
    fitRect(contentBounds, viewportSize, padding: padding);
  }

  /// 🔍 Animate to frame a specific rect (e.g. lasso selection, PDF page).
  ///
  /// Calculates contain-fit scale + centered offset, then uses
  /// [animateToTransform] for smooth spring animation.
  void fitRect(Rect targetRect, Size viewportSize, {double padding = 60.0}) {
    if (targetRect.isEmpty || viewportSize.isEmpty) return;

    final availW = viewportSize.width - padding * 2;
    final availH = viewportSize.height - padding * 2;
    if (availW <= 0 || availH <= 0) return;

    // Contain fit: scale so the entire rect is visible
    final scaleX = availW / targetRect.width;
    final scaleY = availH / targetRect.height;
    final targetScale = math.min(scaleX, scaleY).clamp(_minScale, _maxScale);

    // Center the rect in the viewport
    final targetOffset = Offset(
      viewportSize.width / 2 - targetRect.center.dx * targetScale,
      viewportSize.height / 2 - targetRect.center.dy * targetScale,
    );

    animateToTransform(
      targetOffset: targetOffset,
      targetScale: targetScale,
      focalPoint: viewportSize.center(Offset.zero),
    );
  }

  // ============================================================================
  // DISPOSE
  // ============================================================================

  @override
  void dispose() {
    stopAnimation();
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }
}
