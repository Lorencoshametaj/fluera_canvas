import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:fluera_canvas/fluera_canvas.dart';
import '../drawing/input/stylus_detector.dart';
import '../drawing/input/palm_rejection_policy.dart';

import './stylus_hover_tracker.dart';

bool _defaultBlockPanZoom() => false;
bool _defaultShouldRotateImage(Offset _) => false;
bool _defaultShouldTransformSelection(Offset _) => false;

/// Widget that handles all multi-touch and stylus input for an infinite canvas.
///
/// Supports:
/// - **Pinch zoom** (two-finger gesture) — delegates scale updates to
///   [InfiniteCanvasController.setScale].
/// - **Pan** (two-finger, or one-finger when `enableSingleFingerPan: true`) —
///   translates via [InfiniteCanvasController.setOffset]; momentum-based
///   deceleration is applied after lift-off.
/// - **Drawing** (single-finger or stylus) — emits [onDrawStart] /
///   [onDrawUpdate] / [onDrawEnd] callbacks with pressure and tilt values.
/// - **Stylus mode**: when a stylus is detected (Apple Pencil, S Pen), the
///   stylus draws regardless of how many fingers are touching the screen, and
///   fingers pan instead of drawing. Disable by setting
///   `enableStylusMode: false`.
/// - **Palm rejection**: large contact areas from a resting palm are filtered
///   out of the drawing stream automatically.
///
/// The widget is a thin input shell — it owns no state about what was drawn.
/// Feed the callbacks into your own scene graph, storage, or the example
/// `InfiniteCanvas` widget included with the SDK for a ready-made pipeline.
///
/// ```dart
/// InfiniteCanvasGestureDetector(
///   controller: myController,
///   onDrawStart: (pos, pressure, tiltX, tiltY) { ... },
///   onDrawUpdate: (pos, pressure, tiltX, tiltY) { ... },
///   onDrawEnd: (pos) { ... },
///   child: CustomPaint(painter: myPainter, size: Size.infinite),
/// );
/// ```
class InfiniteCanvasGestureDetector extends StatefulWidget {
  final InfiniteCanvasController controller;
  final Widget child;
  final Function(Offset, double pressure, double tiltX, double tiltY)?
  onDrawStart;
  final Function(Offset position, double pressure, double tiltX, double tiltY)?
  onDrawUpdate;

  /// 🚀 Callback ottimizzata for batch updates
  final Function(
    List<Offset> positions,
    List<double> pressures,
    List<double> tiltsX,
    List<double> tiltsY,
  )?
  onDrawBatchUpdate;
  final Function(Offset)? onDrawEnd;
  final VoidCallback?
  onDrawCancel; // 🚫 Clear stroke without saving (e.g. 2nd finger interrupts)
  final VoidCallback?
  onDoubleTapZoom; // 🎯 Called on double-tap zoom to undo the first tap's dot
  final Function(Offset)? onLongPress;

  /// 🎯 Long-press continuation: move and end events forwarded to radial menu
  final Function(Offset screenPos)? onLongPressMoveUpdate;
  final Function(Offset screenPos)? onLongPressEnd;

  // ✂️ SPACE-SPLIT: Two-finger spread gesture callbacks
  final Function(double splitLinePosition, {bool isHorizontal})?
  onSpaceSplitStart;
  final Function(double splitLinePosition, double spreadDistance)?
  onSpaceSplitUpdate;
  final VoidCallback? onSpaceSplitEnd;

  // ✌️ MULTI-FINGER TAP: Undo with 2-finger tap, Redo with 3-finger tap
  final VoidCallback? onTwoFingerTap;
  final VoidCallback? onThreeFingerTap;

  /// 🧠 SEMANTIC TAP: Called on single-finger quick taps (no movement).
  /// If returns true, tap was consumed (e.g. by semantic node flashcard).
  /// screenPoint is in screen coordinates.
  final bool Function(Offset screenPoint)? onSingleTap;

  // 🔲 GESTURAL LASSO: Tap + Drag activates lasso without switching tools
  final Function(Offset canvasPosition)? onGesturalLassoStart;
  final Function(Offset canvasPosition)? onGesturalLassoUpdate;
  final Function(Offset canvasPosition)? onGesturalLassoEnd;
  final VoidCallback? onGesturalLassoArmed; // #2: Haptic when lasso arms

  final bool Function()
  blockPanZoom; // 🔒 Block pan/zoom when true (evaluated at gesture time)
  final bool
  enableSingleFingerPan; // 🖐️ Enable pan with a finger instead of drawing
  /// 📄 Optional callback: given a canvas-space position, returns true if
  /// the single-finger pan should be intercepted and routed to draw callbacks
  /// instead (e.g. for PDF document dragging).
  final bool Function(Offset canvasPosition)? onPanInterceptTest;
  final bool isStylusModeEnabled; // 🖊️ Stylus mode: stylus draws, finger pans

  /// 🖐️ PALM REJECTION: optional exclusion zone where large-area touches
  /// (palms) are silently ignored. Stylus events are never rejected.
  final ui.Rect? palmExclusionZone;

  // 🌀 Image rotation callbacks (two-finger rotate + scale on selected image)
  final VoidCallback? onImageScaleStart;
  final Function(
    double rotationDelta,
    double scaleDelta,
    Offset focalPointDelta,
  )?
  onImageTransform;
  final VoidCallback? onImageScaleEnd;

  /// ⚡ Evaluated at GESTURE TIME (not build time) to decide whether
  /// two-finger gestures should route to image rotation.
  /// Receives the gesture focal point (screen coords) to hit-test images.
  /// Returns true when a two-finger gesture is over an image.
  final bool Function(Offset focalPoint) shouldRouteToImageRotation;

  // 🤏 SELECTION TRANSFORM: Two-finger rotate + scale on lasso selection
  final VoidCallback? onSelectionScaleStart;
  final Function(
    double rotationDelta,
    double scaleDelta,
    Offset focalPointDelta,
  )?
  onSelectionTransform;
  final VoidCallback? onSelectionScaleEnd;

  /// Evaluated at GESTURE TIME to decide whether two-finger gestures
  /// should route to selection rotation/scale.
  final bool Function(Offset focalPoint) shouldRouteToSelectionTransform;

  /// 🚫 Called when 3rd finger arrives during selection pinch → cancel transform
  final VoidCallback? onSelectionPinchCancel;

  /// 🤏 Called when 2nd finger arrives, to cancel any active lasso drag.
  /// Needed because lasso drag doesn't set _isDrawing, so _onDrawCancel
  /// doesn't fire for it.
  final VoidCallback? onCancelLassoDrag;

  // 📈 Graph viewport zoom+pan: called when blockPanZoom blocks canvas zoom.
  // Routes two-finger pinch scale and pan delta to graph viewport.
  final Function(double scale, Offset focalDelta)? onBlockedScale;

  /// 🖐️ Palm rejection / handedness policy. Defaults to a no-op: every touch
  /// is accepted and nothing is learned. Consumer packages (e.g.
  /// fluera_engine's HandednessSettings) should pass a real implementation.
  final PalmRejectionPolicy palmRejection;

  /// 🖊️ Stylus hover tracker. Defaults to a no-op. Set this to forward
  /// stylus-hover events to a cursor overlay or snap helper.
  final StylusHoverTracker stylusHoverTracker;

  const InfiniteCanvasGestureDetector({
    super.key,
    required this.controller,
    required this.child,
    this.onDrawStart,
    this.onDrawUpdate,
    this.onDrawBatchUpdate,
    this.onDrawEnd,
    this.onDrawCancel,
    this.onDoubleTapZoom,
    this.onLongPress,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
    this.onSpaceSplitStart,
    this.onSpaceSplitUpdate,
    this.onSpaceSplitEnd,
    this.onTwoFingerTap,
    this.onThreeFingerTap,
    this.onSingleTap,
    this.onGesturalLassoStart,
    this.onGesturalLassoUpdate,
    this.onGesturalLassoEnd,
    this.onGesturalLassoArmed,
    this.blockPanZoom = _defaultBlockPanZoom,
    this.enableSingleFingerPan = false,
    this.onPanInterceptTest,
    this.isStylusModeEnabled = false,
    this.palmExclusionZone,
    this.onImageScaleStart,
    this.onImageTransform,
    this.onImageScaleEnd,
    this.shouldRouteToImageRotation =
        _defaultShouldRotateImage, // default: never route
    this.onSelectionScaleStart,
    this.onSelectionTransform,
    this.onSelectionScaleEnd,
    this.shouldRouteToSelectionTransform = _defaultShouldTransformSelection,
    this.onSelectionPinchCancel,
    this.onCancelLassoDrag,
    this.onBlockedScale,
    this.palmRejection = noopPalmRejectionPolicy,
    this.stylusHoverTracker = noopStylusHoverTracker,
  });

  @override
  State<InfiniteCanvasGestureDetector> createState() =>
      _InfiniteCanvasGestureDetectorState();
}

class _InfiniteCanvasGestureDetectorState
    extends State<InfiniteCanvasGestureDetector> {
  // State per gesture recognition
  double _initialScale = 1.0;
  Offset _initialFocalPoint = Offset.zero;
  Offset _initialOffset = Offset.zero;
  int _pointerCount = 0;
  bool _isDrawing = false;
  bool _wasDrawingGesture =
      false; // 🎯 FIX: Prevents _onScaleEnd from launching viewport animations after drawing
  Offset? _firstPointerPosition;
  bool _hasMoved = false;
  bool _wasMultiTouch = false; // Flag to track se c'era multi-touch recente
  int _lastPointerChangeTime = 0; // Timestamp ultimo cambio pointer count

  // State per pan with a dito
  bool _isSingleFingerPanning = false;
  Offset _lastPanPosition = Offset.zero;
  bool _panIntercepted =
      false; // 📄 True when pan was intercepted for document drag

  // 🚀 State for interpolation of missing points
  Offset? _lastDrawPosition;
  Offset?
  _lastCanvasPosition; // 🚀 FIX #5: cache canvas position for interpolation
  double _lastPressure = 1.0;
  // 🔴 CRITICAL: Reduced threshold to capture more points during fast writing
  static const double _interpolationThreshold =
      4.0; // px minimum between points (reduced from 8 for more precision)
  // 🔴 CRITICAL: Increased limit to avoid discontinuities in fast writing
  static const int _maxInterpolatedPoints =
      25; // max punti interpolati per evento (aumentato da 5)

  // 🖊️ State for tilt calculation
  double _lastTiltX = 0.0;
  double _lastTiltY = 0.0;

  // 🖊️ Stylus input manager for stylus mode handling
  final StylusInputManager _stylusManager = StylusInputManager();

  // 🖊️ Flag to enable/disable drawing in stylus mode
  bool _shouldEnableDrawing = true;

  // 🌊 LIQUID: Velocity tracking for pan momentum
  Offset _lastScaleFocalPoint = Offset.zero;
  int _lastScaleUpdateTime = 0;
  Offset _panVelocity = Offset.zero;
  // 🌊 LIQUID: Track if we were zooming (2+ fingers) vs panning
  bool _wasZooming = false;
  Offset _lastScaleEndFocalPoint = Offset.zero;
  // 🌊 LIQUID: Zoom velocity tracking for zoom momentum (Gap 4)
  double _zoomVelocity = 0.0;
  double _lastGestureScale = 1.0;

  // 🔄 GESTURE CONTINUITY: Smooth transition when pointer count changes
  bool _gestureTransitioning = false;
  int _previousPointerCount = 0;
  bool _semanticTapConsumed =
      false; // 🧠 Set when semantic node consumed the tap

  // 🌀 ROTATION: State tracking
  double _initialRotation = 0.0;
  double _lastGestureRotation = 0.0;
  double _rotationVelocity = 0.0;
  double? _lastSnappedAngle; // Track snap detent to avoid repeated haptics
  bool _rotationUnlocked = false; // Requires intentional rotation to activate
  bool _gestureClassified = false; // True once we've decided zoom vs rotate
  bool _zoomDominant = false; // True = zoom-only gesture, rotation suppressed

  // 🌀 ROTATION: Deadzone to prevent accidental rotation during zoom/pan.
  // The user must rotate at least ~3° before rotation activates.
  static const double _rotationDeadzone = 0.05; // ~3° in radians
  static const double _rotationDeadzoneZoomDominant =
      0.20; // ~11° when zoom dominates
  static const double _maxAngularVelocity = 3.0; // Cap spin speed (rad/s)

  // ✂️ SPACE-SPLIT: Two-finger spread tracking
  bool _isSpaceSplitting = false;
  bool _splitIsHorizontal =
      false; // true = horizontal split (↔), false = vertical (↕)
  final Map<int, Offset> _pointerPositions = {}; // pointerId → screen position
  double _splitInitialVerticalDistance = 0.0;
  double _splitInitialHorizontalDistance = 0.0;
  double _splitInitialHorizontalCenter = 0.0;
  double _splitInitialVerticalCenter = 0.0;
  static const double _splitActivationThreshold = 30.0; // px spread to activate
  static const double _splitDirectionalityRatio =
      3.0; // primary axis must be 3× secondary
  // ✂️ LONG-PRESS: Hold 2 fingers still for 400ms to arm space-split
  Timer? _splitLongPressTimer;
  bool _splitLongPressReady = false;

  // ✌️ MULTI-FINGER TAP: Track max pointer count and start time for quick-tap detection
  int _maxPointerCountInGesture = 0;
  int _multiTouchDownTime = 0;
  bool _multiTouchMoved = false;

  // 🌀 IMAGE ROTATION: State tracking for image-specific rotation
  bool _imageRotationUnlocked = false;
  double _imageRotationAccum = 0.0; // Accumulated rotation for image
  bool _imageScaleStarted = false; // Whether we fired onImageScaleStart

  double _imageInitialScale = 1.0; // Scale at gesture start
  Offset _imagePreviousFocalPoint =
      Offset.zero; // Previous focal point for drag delta

  // 🤏 SELECTION TRANSFORM: State tracking for selection pinch rotate+scale
  bool _selectionScaleStarted = false;
  bool _selectionRotationUnlocked = false;
  double _selectionInitialScale = 1.0;
  Offset _selectionPreviousFocalPoint = Offset.zero;

  // 🎯 DOUBLE-TAP ZOOM: State tracking
  int _lastSingleTapTime = 0;
  Offset _lastSingleTapPosition = Offset.zero;
  bool _pendingFirstTap =
      false; // True while waiting to see if second tap comes

  // 🔲 GESTURAL LASSO: Tap + Drag state
  bool _isGesturalLassoArmed =
      false; // True when 2nd tap detected, awaiting movement
  bool _isGesturalLassoing = false; // True when actively drawing gestural lasso
  Offset _gesturalLassoStartPos = Offset.zero; // Screen position at arm time

  // ─── 🚀 GESTURE COALESCING ──────────────────────────────────────
  // Batch all draw updates within a single frame into one callback.
  // This reduces repaint count from O(N) to O(1) per frame.
  final List<Offset> _batchPositions = [];
  final List<double> _batchPressures = [];
  final List<double> _batchTiltsX = [];
  final List<double> _batchTiltsY = [];
  bool _batchFlushScheduled = false;

  /// 🎯 REALISM FIX: Simula pressione realistica per dito from the speed
  /// - Stylus: uses real pressure (0.0-1.0 con variazione)
  /// - Finger: simulates pressure from movement speed
  ///   • Slow = more pressure (like pressing hard with real pen)
  ///   • Fast = less pressure (light and fast stroke)
  double _normalizePressure(PointerEvent event) {
    final rawPressure = event.pressure;

    // If is uno stylus, usa la pressure reale
    if (StylusDetector.isStylus(event)) {
      // Stylus ha valori graduali realistici
      return rawPressure.clamp(0.1, 1.0);
    }

    // For finger/touch: simula pressione from the speed
    // This creates a realistic effect dove:
    // - Slow movement → more ink deposited → high pressure
    // - Fast movement → less ink → low pressure

    if (_lastDrawPosition != null) {
      final distance = (event.localPosition - _lastDrawPosition!).distance;

      // Speed normalizzata: 0-30px = lento, 30+ = veloce
      // Invertiamo: distanza piccola = pressione alta
      // Range: 0.3 (veloce) a 0.9 (lento)
      const double maxDistance = 30.0; // Soglia "veloce"
      const double minPressure = 0.3; // Pressione minima (tratto veloce)
      const double maxPressure = 0.9; // Pressione massima (tratto lento)

      // Calculate pressione: more vicino = more pressione
      final normalizedDistance = (distance / maxDistance).clamp(0.0, 1.0);
      final simulatedPressure =
          maxPressure - (normalizedDistance * (maxPressure - minPressure));

      return simulatedPressure;
    }

    // Primo punto: usa pressione media
    return 0.6;
  }

  @override
  void didUpdateWidget(InfiniteCanvasGestureDetector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 🖊️ Update stylus mode if changed
    if (oldWidget.isStylusModeEnabled != widget.isStylusModeEnabled) {
      _stylusManager.setStylusMode(widget.isStylusModeEnabled);
    }
  }

  @override
  void initState() {
    super.initState();
    // 🖊️ Initialize stylus manager
    _stylusManager.setStylusMode(widget.isStylusModeEnabled);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      // 🖊️ FEATURE 7: Track stylus hover for aggressive palm rejection
      onPointerHover: _onPointerHover,
      onPointerPanZoomStart: _onPointerPanZoomStart,
      onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
      onPointerPanZoomEnd: _onPointerPanZoomEnd,
      onPointerSignal: _onPointerSignal,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        onScaleEnd: _onScaleEnd,
        onLongPressStart: (details) {
          // Long press rilevato - converti coordinata schermo → canvas
          if (widget.onLongPress != null && _pointerCount == 1) {
            final canvasPoint = widget.controller.screenToCanvas(
              details.localPosition,
            );
            widget.onLongPress!(canvasPoint);
          }
        },
        onLongPressMoveUpdate: (details) {
          // 🎯 RADIAL MENU: Forward local position (matches canvasToScreen coords)
          if (_pointerCount == 1 && widget.onLongPressMoveUpdate != null) {
            widget.onLongPressMoveUpdate!(details.localPosition);
          }

          // 🧠 KNOWLEDGE FLOW: Route long-press movement to draw update
          // ONLY at LOD 1/2 (scale < 0.5) for connection drag.
          if (_pointerCount == 1 &&
              widget.controller.scale < 0.5 &&
              widget.onDrawUpdate != null) {
            final canvasPoint = widget.controller.screenToCanvas(
              details.localPosition,
            );
            widget.onDrawUpdate!(canvasPoint, 0.5, 0.0, 0.0);
          }
        },
        onLongPressEnd: (details) {
          // 🎯 RADIAL MENU: Forward local position release
          if (_pointerCount <= 1 && widget.onLongPressEnd != null) {
            widget.onLongPressEnd!(details.localPosition);
          }

          // 🧠 KNOWLEDGE FLOW: Route long-press end to draw end
          // ONLY at LOD 1/2 for connection drag finalization.
          if (_pointerCount <= 1 &&
              widget.controller.scale < 0.5 &&
              widget.onDrawEnd != null) {
            final canvasPoint = widget.controller.screenToCanvas(
              details.localPosition,
            );
            widget.onDrawEnd!(canvasPoint);
          }
        },
        child: widget.child,
      ),
    );
  }

  // 🖊️ AUTO-DETECT: Track first draw position for stroke direction
  Offset? _strokeStartPosition;

  // 🖊️ Stylus hover detection + cursor preview
  void _onPointerHover(PointerHoverEvent event) {
    if (StylusDetector.isStylus(event)) {
      widget.palmRejection.onStylusHover(event.localPosition);
      // 🖊️ Feed hover state for cursor preview overlay
      widget.stylusHoverTracker.updateHover(
        event.localPosition,
        distance: event.distance,
      );
    } else {
      widget.palmRejection.onStylusHoverExit();
      widget.stylusHoverTracker.endHover();
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    // 🛡️ SAFETY: If _pointerCount somehow went negative (e.g. PointerCancel
    // for a pointer we never saw the Down for), reset to 0 now.
    if (_pointerCount < 0) _pointerCount = 0;
    final isStylus = StylusDetector.isStylus(event);

    // 🖊️ STYLUS TRACKING: Inform HandednessSettings for temporal rejection
    if (isStylus) {
      widget.palmRejection.onStylusDown(event.localPosition);
      widget.stylusHoverTracker.endHover(); // Hide cursor on touch-down
    }

    // 🖐️ COMPREHENSIVE PALM REJECTION:
    // UI bypass + temporal + cooldown + hover + multi-point + velocity + area + wrist + zone
    // 🔧 FIX: Skip palm rejection when a pointer is already down — the incoming
    // touch is likely the 2nd finger for pinch-zoom/pan, NOT a palm. Rejecting
    // it would prevent _pointerCount from reaching 2, breaking zoom/pan.
    if (!isStylus && _pointerCount == 0) {
      final speed = event.delta.distance.clamp(0.0, 100.0);
      final screenSize = MediaQuery.sizeOf(context);

      // 🛡️ UI safe zone: top 60px (toolbar) + bottom 44px (nav bar)
      final uiSafeZone = Rect.fromLTRB(0, 0, screenSize.width, 60);

      if (widget.palmRejection.shouldRejectTouch(
        position: event.localPosition,
        radiusMajor: event.radiusMajor,
        radiusMinor: event.radiusMinor,
        screenSize: screenSize,
        speed: speed,
        uiSafeZone: uiSafeZone,
      )) {
        // Trigger auto-calibration periodically
        widget.palmRejection.triggerAutoCalibration(screenSize);
        return; // Palm touch — rejected
      }

      // 🐌 Begin drift tracking for deferred rejection
      widget.palmRejection.beginDriftTracking(
        event.pointer,
        event.localPosition,
      );
    }

    // ✂️ SPACE-SPLIT: Track individual pointer positions
    _pointerPositions[event.pointer] = event.localPosition;

    _pointerCount++;
    _lastPointerChangeTime = DateTime.now().millisecondsSinceEpoch;

    // 🌊 LIQUID: Stop any running physics animation on new touch
    widget.controller.stopAnimation();

    // 🖊️ Register the pointer for stylus manager
    _stylusManager.addPointer(event);

    // 🖊️ Determines if drawing should be enabled based on stylus mode
    if (widget.isStylusModeEnabled) {
      // In stylus mode, abilita drawing SOLO con stylus
      _shouldEnableDrawing = StylusDetector.isStylus(event);
    } else {
      // In mode normale, abilita drawing with a dito
      _shouldEnableDrawing = _pointerCount == 1;
    }

    // Traccia se c'was multi-touch
    if (_pointerCount >= 2) {
      _wasMultiTouch = true;

      // ✌️ MULTI-FINGER TAP: Track max pointer count
      if (_pointerCount > _maxPointerCountInGesture) {
        _maxPointerCountInGesture = _pointerCount;
      }
      if (_pointerCount == 2 && _maxPointerCountInGesture <= 2) {
        _multiTouchDownTime = DateTime.now().millisecondsSinceEpoch;
        _multiTouchMoved = false;
      } else if (_pointerCount == 3) {
        _multiTouchDownTime = DateTime.now().millisecondsSinceEpoch;
        _multiTouchMoved = false;
      }

      // ✂️ SPACE-SPLIT: Start long-press timer when 2nd finger arrives
      if (_pointerCount == 2 && _pointerPositions.length >= 2) {
        final positions = _pointerPositions.values.toList();
        _splitInitialVerticalDistance =
            (positions[0].dy - positions[1].dy).abs();
        _splitInitialHorizontalDistance =
            (positions[0].dx - positions[1].dx).abs();
        _splitInitialHorizontalCenter = (positions[0].dx + positions[1].dx) / 2;
        _splitInitialVerticalCenter = (positions[0].dy + positions[1].dy) / 2;
        // Start 400ms long-press timer
        _splitLongPressReady = false;
        _splitLongPressTimer?.cancel();
        _splitLongPressTimer = Timer(const Duration(milliseconds: 400), () {
          _splitLongPressReady = true;
          // 🔑 Re-record finger distances NOW (not from 400ms ago)
          // so spread is measured from the moment split mode arms.
          if (_pointerPositions.length >= 2) {
            final pos = _pointerPositions.values.toList();
            _splitInitialVerticalDistance = (pos[0].dy - pos[1].dy).abs();
            _splitInitialHorizontalDistance = (pos[0].dx - pos[1].dx).abs();
            _splitInitialHorizontalCenter = (pos[0].dx + pos[1].dx) / 2;
            _splitInitialVerticalCenter = (pos[0].dy + pos[1].dy) / 2;
          }
          HapticFeedback.lightImpact(); // Confirm: split mode armed
        });
      }

      // 🚫 3RD FINGER CANCEL: If selection pinch is active and 3rd finger arrives, cancel
      if (_pointerCount >= 3 && _selectionScaleStarted) {
        _selectionScaleStarted = false;
        _selectionRotationUnlocked = false;
        widget.onSelectionPinchCancel?.call();
      }
    }

    // Save la position del primo dito
    if (_pointerCount == 1) {
      _firstPointerPosition = event.localPosition;
      _hasMoved = false;
      _maxPointerCountInGesture = 1; // ✌️ Reset for new gesture
      _multiTouchMoved = false;
      _semanticTapConsumed = false; // Reset semantic tap flag

      // 🧠 SEMANTIC TAP: Intercept BEFORE any drawing/gesture logic.
      // When the semantic view is active, taps on nodes should show flashcard
      // or trigger zoom-in. This must happen here because _onPointerUp's
      // single-tap branch is unreliable (gestural lasso arms, double-tap,
      // micro-movement sets _hasMoved, etc.).
      if (widget.onSingleTap != null &&
          widget.onSingleTap!(event.localPosition)) {
        _semanticTapConsumed = true;
        // Don't start any drawing or gesture — tap was consumed
        return;
      }
    } else if (_pointerCount > 1) {
      // If arriva un secondo dito, invalida il tap
      _firstPointerPosition = null;
    }

    // If c'è more di un dito, CANCELLA il drawing (non salvare il puntino)
    if (_pointerCount > 1 && _isDrawing) {
      _isDrawing = false;
      // 🚫 Use onDrawCancel to discard in-progress stroke
      // invece di onDrawEnd che lo salverebbe come puntino
      if (widget.onDrawCancel != null) {
        widget.onDrawCancel!();
      }
    }

    // 🤏 LASSO DRAG CANCEL: When 2nd finger arrives, cancel any active
    // lasso drag so pinch-to-transform can take over. Lasso drag doesn't
    // set _isDrawing, so _onDrawCancel above doesn't handle it.
    if (_pointerCount == 2) {
      widget.onCancelLassoDrag?.call();
    }

    // 🚀 FIX: Start drawing IMMEDIATELY on pointer down
    // This captures the first point without waiting for onPointerMove
    // Solves the problem of losing the first points during writing
    //
    // 📄 PAN INTERCEPT: When pan mode is active BUT touch hits a PDF page,
    // route to draw callbacks instead of canvas pan.
    bool shouldDraw = !widget.enableSingleFingerPan;
    if (widget.enableSingleFingerPan && widget.onPanInterceptTest != null) {
      final canvasPoint = widget.controller.screenToCanvas(event.localPosition);
      if (widget.onPanInterceptTest!(canvasPoint)) {
        shouldDraw = true;
        _panIntercepted = true; // Flag to route moves to draw, not pan
      }
    }
    if (_pointerCount == 1 && _shouldEnableDrawing && shouldDraw) {
      // 🎯 DOUBLE-TAP CHECK: If this could be the second tap of a double-tap,
      // suppress drawing to avoid the temporary dot flash.
      final now = DateTime.now().millisecondsSinceEpoch;
      final isLikelySecondTap =
          _pendingFirstTap &&
          (now - _lastSingleTapTime) < 300 &&
          (event.localPosition - _lastSingleTapPosition).distance < 40;

      _isDrawing = true;
      _lastDrawPosition = event.localPosition;
      final normalizedPressure = _normalizePressure(event);
      _lastPressure = normalizedPressure;

      // 🖊️ Calculate tiltX and tiltY from tilt and orientation
      final tiltMagnitude = event.tilt;
      final orientation = event.orientation;
      _lastTiltX = (tiltMagnitude * math.cos(orientation)).clamp(-1.0, 1.0);
      _lastTiltY = (tiltMagnitude * math.sin(orientation)).clamp(-1.0, 1.0);

      // 🔲 GESTURAL LASSO: If this is the second tap of a potential double-tap,
      // arm gestural lasso instead of starting draw. Movement will decide
      // whether it becomes a lasso (drag) or a double-tap zoom (no drag).
      if (isLikelySecondTap && widget.onGesturalLassoStart != null) {
        _isGesturalLassoArmed = true;
        _isDrawing = false; // Don't draw — we're waiting to disambiguate
        _gesturalLassoStartPos = event.localPosition;
        // #2: Haptic feedback when lasso is armed
        widget.onGesturalLassoArmed?.call();
      } else if (!isLikelySecondTap && widget.onDrawStart != null) {
        final canvasPoint = widget.controller.screenToCanvas(
          event.localPosition,
        );
        _lastCanvasPosition = canvasPoint;
        _strokeStartPosition =
            canvasPoint; // 📊 AUTO-DETECT: record stroke start
        widget.onDrawStart!(
          canvasPoint,
          normalizedPressure,
          _lastTiltX,
          _lastTiltY,
        );
      }
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    // ✂️ SPACE-SPLIT: Update tracked pointer position
    if (_pointerPositions.containsKey(event.pointer)) {
      _pointerPositions[event.pointer] = event.localPosition;
    }

    // ✂️ SPACE-SPLIT: Detect spread (only after long-press armed it)
    // Cancel long-press timer if zooming (scale change before 400ms timer fires)
    if (_pointerCount == 2 &&
        !_splitLongPressReady &&
        !_isSpaceSplitting &&
        _splitLongPressTimer != null) {
      // Check if fingers moved significantly (= zoom, not hold-still)
      if (_pointerPositions.length >= 2) {
        final positions = _pointerPositions.values.toList();
        final currentDist = (positions[0] - positions[1]).distance;
        final initialDist =
            Offset(
              _splitInitialHorizontalDistance,
              _splitInitialVerticalDistance,
            ).distance;
        if (initialDist > 0 && (currentDist / initialDist - 1.0).abs() > 0.15) {
          // Scale changed > 15% before timer fired → this is zoom, not hold
          _splitLongPressTimer?.cancel();
          _splitLongPressTimer = null;
        }
      }
    }
    if (_pointerCount == 2 &&
        _pointerPositions.length >= 2 &&
        !_isDrawing &&
        (_splitLongPressReady || _isSpaceSplitting)) {
      final positions = _pointerPositions.values.toList();
      final currentVerticalDist = (positions[0].dy - positions[1].dy).abs();
      final currentHorizontalDist = (positions[0].dx - positions[1].dx).abs();
      final verticalSpread =
          currentVerticalDist - _splitInitialVerticalDistance;
      final horizontalSpread =
          currentHorizontalDist - _splitInitialHorizontalDistance;

      if (_isSpaceSplitting) {
        // Already splitting — update along the locked axis
        final spread = _splitIsHorizontal ? horizontalSpread : verticalSpread;
        final canvasSpread = spread / widget.controller.scale;
        final canvasCenter = widget.controller.screenToCanvas(
          Offset(_splitInitialHorizontalCenter, _splitInitialVerticalCenter),
        );
        final pos = _splitIsHorizontal ? canvasCenter.dx : canvasCenter.dy;
        widget.onSpaceSplitUpdate?.call(pos, canvasSpread);
        return;
      }

      // Detect which axis dominates
      final absV = verticalSpread.abs();
      final absH = horizontalSpread.abs();

      if (absV > _splitActivationThreshold &&
          absV > absH * _splitDirectionalityRatio &&
          widget.onSpaceSplitStart != null) {
        // Vertical split (horizontal line)
        _isSpaceSplitting = true;
        _splitIsHorizontal = false;
        final splitLineY =
            widget.controller
                .screenToCanvas(
                  Offset(
                    _splitInitialHorizontalCenter,
                    _splitInitialVerticalCenter,
                  ),
                )
                .dy;
        widget.onSpaceSplitStart?.call(splitLineY, isHorizontal: false);
        HapticFeedback.lightImpact();
        return;
      } else if (absH > _splitActivationThreshold &&
          absH > absV * _splitDirectionalityRatio &&
          widget.onSpaceSplitStart != null) {
        // Horizontal split (vertical line)
        _isSpaceSplitting = true;
        _splitIsHorizontal = true;
        final splitLineX =
            widget.controller
                .screenToCanvas(
                  Offset(
                    _splitInitialHorizontalCenter,
                    _splitInitialVerticalCenter,
                  ),
                )
                .dx;
        widget.onSpaceSplitStart?.call(splitLineX, isHorizontal: true);
        HapticFeedback.lightImpact();
        return;
      }
    }
    // 🖊️ Update pointer for stylus manager
    _stylusManager.updatePointer(event);

    // 🖊️ STYLUS TRACKING: Update pen position for wrist guard
    if (StylusDetector.isStylus(event)) {
      widget.palmRejection.onStylusMove(event.localPosition);
    } else {
      // 📊 DEFERRED REJECTION: Pressure curve + drift analysis for non-stylus
      // These catch palms that passed the initial shouldRejectTouch check.
      final settings = widget.palmRejection;
      if (settings.recordPressureSample(event.pointer, event.pressure)) {
        // Flat pressure curve detected — cancel this touch
        settings.recordDeferredRejection(
          event.localPosition,
          PalmRejectionReason.pressureCurve,
          event.radiusMajor,
        );
        return; // Swallow further move events for this palm
      }
      if (settings.checkDrift(
        event.pointer,
        event.localPosition,
        event.radiusMajor,
      )) {
        settings.recordDeferredRejection(
          event.localPosition,
          PalmRejectionReason.drift,
          event.radiusMajor,
        );
        return; // Near-zero movement — likely palm resting
      }
    }

    // Ignora se ci sono 2+ dita (zoom/pan)
    if (_pointerCount >= 2) {
      // ✌️ MULTI-FINGER TAP: Track if fingers moved significantly
      if (!_multiTouchMoved && event.delta.distance > 8) {
        _multiTouchMoved = true;
      }
      return;
    }

    // 🔄 GESTURE CONTINUITY: Don't draw/pan right after multi-touch
    // Extended cooldown prevents accidental strokes when lifting fingers.
    final timeSinceLastChange =
        DateTime.now().millisecondsSinceEpoch - _lastPointerChangeTime;
    if (_wasMultiTouch && timeSinceLastChange < 60) {
      // Re-anchor positions so first move after cooldown doesn't jump
      _lastPanPosition = event.localPosition;
      _lastDrawPosition = event.localPosition;
      return; // Ignore movement during cooldown
    }

    // 🖐️ If finger pan mode is active, pan instead of drawing
    // 📄 But NOT if pan was intercepted (e.g. PDF document drag)
    // 🧠 KNOWLEDGE FLOW: If blockPanZoom is active (connection drag started
    // via long-press), forward to draw callbacks instead of panning.
    if (_pointerCount == 1 &&
        widget.enableSingleFingerPan &&
        !_panIntercepted) {
      if (widget.blockPanZoom()) {
        final canvasPoint = widget.controller.screenToCanvas(
          event.localPosition,
        );
        widget.onDrawUpdate?.call(canvasPoint, 1.0, 0.0, 0.0);
        return;
      }
      if (!_isSingleFingerPanning) {
        _isSingleFingerPanning = true;
        widget.controller.isPanning = true; // 🚀 SCROLL OPT
        _lastPanPosition = event.localPosition;
        // 🌊 LIQUID: Reset velocity tracking for single-finger pan
        _lastScaleUpdateTime = DateTime.now().microsecondsSinceEpoch;
        _panVelocity = Offset.zero;
      } else {
        // Calculate il delta di movimento
        final delta = event.localPosition - _lastPanPosition;

        // 🌊 LIQUID: Track velocity
        final now = DateTime.now().microsecondsSinceEpoch;
        final dt = (now - _lastScaleUpdateTime) / 1000000.0;
        if (dt > 0.001) {
          final instantV = delta / dt;
          _panVelocity = Offset(
            _panVelocity.dx * 0.7 + instantV.dx * 0.3,
            _panVelocity.dy * 0.7 + instantV.dy * 0.3,
          );
        }
        _lastScaleUpdateTime = now;
        _lastPanPosition = event.localPosition;

        // Applica il pan
        final newOffset = widget.controller.offset + delta;
        widget.controller.updateTransform(
          offset: newOffset,
          scale: widget.controller.scale,
        );
      }
      return;
    }

    // 🖊️ STYLUS MODE: in stylus mode, finger pans instead of drawing
    if (widget.isStylusModeEnabled &&
        _pointerCount == 1 &&
        !_shouldEnableDrawing) {
      // 🧠 KNOWLEDGE FLOW: If blockPanZoom is active (connection drag started
      // via long-press), forward to draw callbacks instead of panning.
      if (widget.blockPanZoom()) {
        final canvasPoint = widget.controller.screenToCanvas(
          event.localPosition,
        );
        widget.onDrawUpdate?.call(canvasPoint, 1.0, 0.0, 0.0);
        return;
      }
      // È un dito in stylus mode → fai pan
      if (!_isSingleFingerPanning) {
        _isSingleFingerPanning = true;
        widget.controller.isPanning = true; // 🚀 SCROLL OPT
        _lastPanPosition = event.localPosition;
        // 🌊 LIQUID: Reset velocity tracking
        _lastScaleUpdateTime = DateTime.now().microsecondsSinceEpoch;
        _panVelocity = Offset.zero;
      } else {
        final delta = event.localPosition - _lastPanPosition;

        // 🌊 LIQUID: Track velocity
        final now = DateTime.now().microsecondsSinceEpoch;
        final dt = (now - _lastScaleUpdateTime) / 1000000.0;
        if (dt > 0.001) {
          final instantV = delta / dt;
          _panVelocity = Offset(
            _panVelocity.dx * 0.7 + instantV.dx * 0.3,
            _panVelocity.dy * 0.7 + instantV.dy * 0.3,
          );
        }
        _lastScaleUpdateTime = now;
        _lastPanPosition = event.localPosition;

        final newOffset = widget.controller.offset + delta;
        widget.controller.updateTransform(
          offset: newOffset,
          scale: widget.controller.scale,
        );
      }
      return;
    }

    // 🔲 GESTURAL LASSO: Handle armed/active state BEFORE normal drawing.
    // When armed, movement > 8px activates lasso. When active, route to lasso update.
    if (_pointerCount == 1 && _isGesturalLassoArmed && !_isGesturalLassoing) {
      final dist = (event.localPosition - _gesturalLassoStartPos).distance;
      // #5: Adaptive threshold — scale by inverse of zoom so it feels
      // consistent at any zoom level (8px at 1x, 4px at 2x, 16px at 0.5x)
      final adaptiveThreshold = 8.0 / widget.controller.scale.clamp(0.25, 4.0);
      if (dist > adaptiveThreshold) {
        // Movement detected → activate gestural lasso
        _isGesturalLassoArmed = false;
        _isGesturalLassoing = true;
        _pendingFirstTap = false;
        _lastSingleTapTime = 0;
        final canvasPoint = widget.controller.screenToCanvas(
          _gesturalLassoStartPos,
        );
        widget.onGesturalLassoStart!(canvasPoint);
        // Also send the current point as first update
        final currentCanvas = widget.controller.screenToCanvas(
          event.localPosition,
        );
        widget.onGesturalLassoUpdate?.call(currentCanvas);
        _hasMoved = true;
      }
      return;
    }
    if (_pointerCount == 1 && _isGesturalLassoing) {
      final canvasPoint = widget.controller.screenToCanvas(event.localPosition);
      widget.onGesturalLassoUpdate?.call(canvasPoint);
      _hasMoved = true;
      return;
    }

    // Drawing only with 1 finger (when pan mode is not active AND stylus mode allows)
    if (_pointerCount == 1 && _shouldEnableDrawing) {
      _hasMoved = true;

      // 🖊️ In stylus mode, verify we are still drawing with the stylus
      if (widget.isStylusModeEnabled &&
          !_stylusManager.canDrawWithCurrentPointer()) {
        // If is not more una stylus, termina il disegno
        if (_isDrawing && widget.onDrawEnd != null) {
          final canvasPoint = widget.controller.screenToCanvas(
            event.localPosition,
          );
          widget.onDrawEnd!(canvasPoint);
          _isDrawing = false;
        }
        return;
      }

      // 🚀 FIX: Removed block "if (!_isDrawing)" which called onDrawStart
      // onDrawStart ora is called in onPointerDown per catturare il primo punto
      // Qui gestiamo SOLO gli update of the drawing already iniziato
      if (_isDrawing) {
        final canvasPoint = widget.controller.screenToCanvas(
          event.localPosition,
        );

        final normalizedPressure = _normalizePressure(event); // 🎯 FIX 3

        // 🖊️ FIX: Calculate current tiltX and tiltY
        final tiltMagnitude = event.tilt;
        final orientation = event.orientation;
        final currentTiltX = (tiltMagnitude * math.cos(orientation)).clamp(
          -1.0,
          1.0,
        );
        final currentTiltY = (tiltMagnitude * math.sin(orientation)).clamp(
          -1.0,
          1.0,
        );

        // 🚀 FIX #5: INTERPOLATION IN CANVAS SPACE
        // Instead of converting each interpolated point with screenToCanvas(),
        // we interpolate directly between cached canvas positions.
        if (_lastCanvasPosition != null) {
          final distance = (event.localPosition - _lastDrawPosition!).distance;
          if (distance > _interpolationThreshold) {
            final rawSteps = (distance / _interpolationThreshold).ceil();
            final steps = rawSteps.clamp(
              1,
              _maxInterpolatedPoints + 1,
            ); // Limit points

            for (int i = 1; i < steps; i++) {
              final t = i / steps;
              // 🚀 Direct interpolation in canvas space (zero screenToCanvas!)
              final interpolatedCanvas =
                  Offset.lerp(_lastCanvasPosition!, canvasPoint, t)!;
              final interpolatedPressure =
                  _lastPressure + (normalizedPressure - _lastPressure) * t;
              final interpolatedTiltX =
                  _lastTiltX + (currentTiltX - _lastTiltX) * t;
              final interpolatedTiltY =
                  _lastTiltY + (currentTiltY - _lastTiltY) * t;

              // 🚀 COALESCED: Buffer point instead of dispatching immediately
              _addToBatch(
                interpolatedCanvas,
                interpolatedPressure,
                interpolatedTiltX,
                interpolatedTiltY,
              );
            }
          }
        }

        _lastDrawPosition = event.localPosition;
        _lastCanvasPosition =
            canvasPoint; // 🚀 FIX #5: cache for next interpolation
        _lastPressure = normalizedPressure;
        _lastTiltX = currentTiltX;
        _lastTiltY = currentTiltY;

        // 🚀 COALESCED: Buffer the real point and schedule batch flush
        _addToBatch(
          canvasPoint,
          normalizedPressure,
          currentTiltX,
          currentTiltY,
        );
        _scheduleBatchFlush();
      }
    }
  }

  // ─── 🚀 GESTURE COALESCING HELPERS ─────────────────────────────────

  /// Add a draw point to the intra-frame batch buffer.
  void _addToBatch(
    Offset position,
    double pressure,
    double tiltX,
    double tiltY,
  ) {
    _batchPositions.add(position);
    _batchPressures.add(pressure);
    _batchTiltsX.add(tiltX);
    _batchTiltsY.add(tiltY);
  }

  /// Schedule a single post-frame callback to flush all buffered points.
  /// Idempotent — only schedules once per frame.
  void _scheduleBatchFlush() {
    if (_batchFlushScheduled) return;
    _batchFlushScheduled = true;

    SchedulerBinding.instance.addPostFrameCallback((_) {
      _flushBatch();
    });
  }

  /// Flush the batch: dispatch all buffered points in one call.
  void _flushBatch() {
    _batchFlushScheduled = false;
    if (_batchPositions.isEmpty) return;

    if (_batchPositions.length == 1) {
      // Single point — use the standard callback
      widget.onDrawUpdate?.call(
        _batchPositions[0],
        _batchPressures[0],
        _batchTiltsX[0],
        _batchTiltsY[0],
      );
    } else if (widget.onDrawBatchUpdate != null) {
      // 🚀 Batch callback (N points → 1 repaint)
      widget.onDrawBatchUpdate!(
        List<Offset>.from(_batchPositions),
        List<double>.from(_batchPressures),
        List<double>.from(_batchTiltsX),
        List<double>.from(_batchTiltsY),
      );
    } else {
      // Fallback: dispatch individually (last point only triggers repaint)
      for (int i = 0; i < _batchPositions.length; i++) {
        widget.onDrawUpdate?.call(
          _batchPositions[i],
          _batchPressures[i],
          _batchTiltsX[i],
          _batchTiltsY[i],
        );
      }
    }

    _batchPositions.clear();
    _batchPressures.clear();
    _batchTiltsX.clear();
    _batchTiltsY.clear();
  }

  void _onPointerUp(PointerUpEvent event) {
    // 🚀 COALESCING: Flush any pending batch before finalizing the stroke.
    // This ensures that all buffered points are dispatched before onDrawEnd.
    _flushBatch();

    // 🖊️ STYLUS TRACKING: Inform HandednessSettings stylus is up
    if (StylusDetector.isStylus(event)) {
      widget.palmRejection.onStylusUp();
    } else {
      // 🧹 Clean up pressure/drift tracking for this pointer
      widget.palmRejection.clearPointerTracking(event.pointer);
    }

    // ✂️ SPACE-SPLIT: Remove tracked pointer
    _pointerPositions.remove(event.pointer);

    _previousPointerCount = _pointerCount;
    _pointerCount--;
    if (_pointerCount < 0) _pointerCount = 0; // 🛡️ SAFETY: Never go negative

    // ✂️ SPACE-SPLIT: End split gesture when pointer lifts
    if (_isSpaceSplitting && _pointerCount < 2) {
      _isSpaceSplitting = false;
      _splitLongPressReady = false;
      _splitLongPressTimer?.cancel();
      _splitLongPressTimer = null;
      widget.onSpaceSplitEnd?.call();
      HapticFeedback.mediumImpact();
      // Skip normal pointer-up processing
      _wasMultiTouch = false;
      _firstPointerPosition = null;
      _hasMoved = false;
      _lastDrawPosition = null;
      _lastCanvasPosition = null;
      _lastPressure = 1.0;
      _isSingleFingerPanning = false;
      widget.controller.isPanning = false;
      _panIntercepted = false;
      _shouldEnableDrawing = true;
      return;
    }
    _lastPointerChangeTime = DateTime.now().millisecondsSinceEpoch;

    // 🔄 GESTURE CONTINUITY: When transitioning between pointer counts
    // (e.g., 2→1 fingers), re-anchor to current state to prevent jumps.
    if (_previousPointerCount >= 2 && _pointerCount >= 1) {
      _gestureTransitioning = true;
    }

    // 🖊️ Remove the pointer from stylus manager
    _stylusManager.removePointer(event.pointer);

    // Only se siamo all'ultimo dito e stiamo disegnando
    if (_pointerCount == 0) {
      // 🛡️ Clear stale multi-point timestamps so they don't
      // contaminate the next gesture's palm rejection check.
      widget.palmRejection.clearRecentFingerDownTimestamps();
      // 🧠 SEMANTIC TAP: If the tap was consumed at pointer-down, skip all cleanup
      if (_semanticTapConsumed) {
        _semanticTapConsumed = false;
        _wasMultiTouch = false;
        _firstPointerPosition = null;
        _hasMoved = false;
        _lastDrawPosition = null;
        _lastCanvasPosition = null;
        _lastPressure = 1.0;
        _isSingleFingerPanning = false;
        widget.controller.isPanning = false;
        _panIntercepted = false;
        _shouldEnableDrawing = true;
        // Don't arm double-tap detection for semantic taps
        _pendingFirstTap = false;
        _lastSingleTapTime = 0;
        return;
      }

      // 🐛 FIX: Do NOT reset _wasMultiTouch here — the conditional checks
      // below depend on it to distinguish single-tap from multi-touch cleanup.
      // Resetting it before the checks caused multi-touch gestures (pan) to
      // fall into the single-tap path, arming double-tap detection and
      // blocking the next stroke within 300ms.
      _gestureTransitioning = false; // Reset stale transition flag

      // 🌊 LIQUID: Launch momentum from single-finger pan
      // 🧠 KNOWLEDGE FLOW: If blockPanZoom is active (connection drag started
      // from long-press), call onDrawEnd to finalize — even if the gesture
      // wasn't a traditional pan (_isSingleFingerPanning may be false because
      // connection drag starts from _onLongPress, not from pan gesture).
      if (widget.blockPanZoom()) {
        _isSingleFingerPanning = false;
        widget.controller.isPanning = false;
        if (widget.onDrawEnd != null) {
          final canvasPoint = widget.controller.screenToCanvas(
            event.localPosition,
          );
          widget.onDrawEnd!(canvasPoint);
        }
        _panVelocity = Offset.zero;
        // 🧠 Skip ALL remaining cleanup — connection drag finalized above.
        // Without this, code falls into tap/draw branches that call onDrawEnd
        // a second time, triggering unwanted keyboard popup.
        _panIntercepted = false;
        _shouldEnableDrawing = true;
        _wasMultiTouch = false;
        _firstPointerPosition = null;
        _hasMoved = false;
        _lastDrawPosition = null;
        _lastCanvasPosition = null;
        _lastPressure = 1.0;
        // Don't execute any other pointer-up logic
      } else if (_isSingleFingerPanning && _panVelocity.distance > 0) {
        widget.controller.startMomentum(_panVelocity);
        _panVelocity = Offset.zero;
      }

      _isSingleFingerPanning = false; // 🖐️ Reset pan with a finger
      widget.controller.isPanning = false; // 🚀 SCROLL OPT
      _panIntercepted = false; // 📄 Reset pan intercept
      _shouldEnableDrawing = true; // 🖊️ Reset stylus drawing flag

      // 🔲 GESTURAL LASSO: End active gestural lasso
      if (_isGesturalLassoing) {
        _isGesturalLassoing = false;
        _isGesturalLassoArmed = false;
        final canvasPoint = widget.controller.screenToCanvas(
          event.localPosition,
        );
        widget.onGesturalLassoEnd?.call(canvasPoint);
        // Reset state — skip all other pointer-up logic
        _wasMultiTouch = false;
        _firstPointerPosition = null;
        _hasMoved = false;
        _lastDrawPosition = null;
        _lastCanvasPosition = null;
        _lastPressure = 1.0;
        _isSingleFingerPanning = false;
        widget.controller.isPanning = false;
        _panIntercepted = false;
        _shouldEnableDrawing = true;
        _pendingFirstTap = false;
        _lastSingleTapTime = 0;
      } else if (_isDrawing && _hasMoved) {
        // Drawing with movement — finalize stroke
        _isDrawing = false;
        _wasDrawingGesture = true; // 🎯 FIX: Flag for _onScaleEnd
        if (widget.onDrawEnd != null) {
          final canvasPoint = widget.controller.screenToCanvas(
            event.localPosition,
          );
          widget.onDrawEnd!(canvasPoint);

          // 📊 AUTO-DETECT: Record stroke direction for handedness inference
          if (_strokeStartPosition != null) {
            final deltaX = canvasPoint.dx - _strokeStartPosition!.dx;
            widget.palmRejection.recordStrokeDirection(deltaX);
            _strokeStartPosition = null;
          }
        }
        // Drawing stroke resets double-tap state
        _pendingFirstTap = false;
        _lastSingleTapTime = 0;
      } else if (!_hasMoved && !_wasMultiTouch) {
        // 🔲 GESTURAL LASSO: If armed but no movement → this is a double-tap
        if (_isGesturalLassoArmed) {
          _isGesturalLassoArmed = false;
          // Fall through to regular double-tap zoom handling below
        }

        // 🎯 Quick tap (no movement, single finger) — double-tap zoom check
        final wasDrawing = _isDrawing;
        _isDrawing = false;

        final now = DateTime.now().millisecondsSinceEpoch;
        final timeSinceLastTap = now - _lastSingleTapTime;
        final distFromLastTap =
            (event.localPosition - _lastSingleTapPosition).distance;

        if (timeSinceLastTap < 300 &&
            distFromLastTap < 40 &&
            _pendingFirstTap) {
          // 🎯 DOUBLE-TAP DETECTED!
          _pendingFirstTap = false;
          _lastSingleTapTime = 0;

          // Cancel any in-progress stroke from this (second) tap
          if (wasDrawing) {
            widget.onDrawCancel?.call();
          }

          // 🏎️ SMART ZOOM CYCLE: 1x → 2x → 4x → 1x
          // Each step doubles the scale (feels natural and proportional).
          // If already past 2x, jump straight back to 1x (no confusion).
          final currentScale = widget.controller.scale;
          double targetScale;
          if (currentScale < 1.5) {
            targetScale = 2.0;
          } else if (currentScale < 3.0) {
            targetScale = 4.0;
          } else {
            targetScale = 1.0;
          }

          // 📳 Graduated haptic: zoom-in = medium, zoom-out (reset) = light
          if (targetScale > currentScale) {
            HapticFeedback.mediumImpact(); // Zooming in — decisive
          } else {
            HapticFeedback.lightImpact(); // Zooming out — gentle
          }

          widget.controller.animateZoomTo(targetScale, event.localPosition);

          // Discard the first tap's dot silently (if drawing mode created one)
          widget.onDoubleTapZoom?.call();
        } else {
          // 🧠 SEMANTIC TAP: Check if semantic node consumed this tap.
          // SKIP if _semanticTapConsumed: the PointerDown already handled it
          // (e.g. opened flashcard or triggered zoom-in). Re-calling here would
          // immediately zoom on the same finger-up that opened the card.
          if (!_semanticTapConsumed &&
              widget.onSingleTap != null &&
              widget.onSingleTap!(event.localPosition)) {
            // Tap was consumed (e.g. flashcard preview) — cancel any dot
            if (wasDrawing) {
              widget.onDrawCancel?.call();
            }
            _pendingFirstTap = false;
            _lastSingleTapTime = 0;
          } else {
            // First tap — record timing for double-tap detection
            _pendingFirstTap = true;
            _lastSingleTapTime = now;
            _lastSingleTapPosition = event.localPosition;

            // In drawing mode, finalize the dot
            if (wasDrawing) {
              _wasDrawingGesture = true; // 🎯 FIX: Flag for _onScaleEnd
              if (widget.onDrawEnd != null) {
                final canvasPoint = widget.controller.screenToCanvas(
                  event.localPosition,
                );
                widget.onDrawEnd!(canvasPoint);
              }
            }
          }
        }
      } else {
        // Multi-touch or other — just clean up
        _isDrawing = false;
        _pendingFirstTap = false;
        _lastSingleTapTime = 0;

        // ✌️ MULTI-FINGER TAP: Check if this was a quick tap (not a zoom/pan)
        if (_wasMultiTouch && !_multiTouchMoved && _multiTouchDownTime > 0) {
          final tapDuration =
              DateTime.now().millisecondsSinceEpoch - _multiTouchDownTime;
          if (tapDuration < 300) {
            if (_maxPointerCountInGesture == 2 &&
                widget.onTwoFingerTap != null) {
              widget.onTwoFingerTap!();
              // Skip the normal cleanup path for onDrawEnd to avoid side effects
              _wasMultiTouch = false;
              _firstPointerPosition = null;
              _hasMoved = false;
              _lastDrawPosition = null;
              _lastCanvasPosition = null;
              _lastPressure = 1.0;
              return; // Done
            } else if (_maxPointerCountInGesture == 3 &&
                widget.onThreeFingerTap != null) {
              widget.onThreeFingerTap!();
              _wasMultiTouch = false;
              _firstPointerPosition = null;
              _hasMoved = false;
              _lastDrawPosition = null;
              _lastCanvasPosition = null;
              _lastPressure = 1.0;
              return; // Done
            }
          }
        }

        // 📈 Call onDrawEnd to clean up any active drag state (graph, latex, etc.)
        // that was cancelled by multi-touch but never finalized.
        if (widget.onDrawEnd != null) {
          final canvasPoint = widget.controller.screenToCanvas(
            event.localPosition,
          );
          widget.onDrawEnd!(canvasPoint);
        }
      }

      // 🐛 FIX: Reset multi-touch flag AFTER the checks that depend on it
      _wasMultiTouch = false;

      // Reset state
      _firstPointerPosition = null;
      _hasMoved = false;
      _lastDrawPosition = null; // 🚀 Reset interpolation
      _lastCanvasPosition = null; // 🚀 FIX #5: Reset canvas cache
      _lastPressure = 1.0;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _flushBatch(); // 🚀 COALESCING: Flush pending points

    // ✂️ SPACE-SPLIT: Remove tracked pointer and cancel split
    _pointerPositions.remove(event.pointer);
    if (_isSpaceSplitting) {
      _isSpaceSplitting = false;
      // Cancel — don't apply split
    }

    _pointerCount--;
    if (_pointerCount < 0) _pointerCount = 0; // 🛡️ SAFETY: Never go negative
    _lastPointerChangeTime = DateTime.now().millisecondsSinceEpoch;

    // 🖊️ Remove the pointer from stylus manager
    _stylusManager.removePointer(event.pointer);

    if (_isDrawing) {
      _isDrawing = false;
      if (widget.onDrawEnd != null) {
        final canvasPoint = widget.controller.screenToCanvas(
          event.localPosition,
        );
        widget.onDrawEnd!(canvasPoint);
      }
    }

    // Reset state
    if (_pointerCount == 0) {
      _wasMultiTouch = false;
      _isSingleFingerPanning = false; // 🖐️ Reset pan with a finger
      _panIntercepted = false; // 📄 Reset pan intercept
      _shouldEnableDrawing = true; // 🖊️ Reset stylus drawing flag
      _firstPointerPosition = null;
      _hasMoved = false;
    }
  }

  // ─── 🖱️ DESKTOP SCROLL/TRACKPAD ZOOM ────────────────────────────────

  // Trackpad pinch-to-zoom state
  double _trackpadInitialScale = 1.0;
  Offset _trackpadInitialOffset = Offset.zero;

  /// 🖱️ Mouse scroll wheel zoom: Ctrl+scroll = zoom, plain scroll = pan.
  /// On Linux/macOS, trackpad pinch also fires PointerScrollEvent.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      // Check if Ctrl is held (zoom) or plain scroll (pan)
      final isCtrlHeld = HardwareKeyboard.instance.logicalKeysPressed.any(
        (key) =>
            key == LogicalKeyboardKey.controlLeft ||
            key == LogicalKeyboardKey.controlRight ||
            key == LogicalKeyboardKey.metaLeft ||
            key == LogicalKeyboardKey.metaRight,
      );

      if (isCtrlHeld) {
        // 🔍 Ctrl+Scroll = Zoom
        _handleScrollZoom(event);
      } else {
        // 🖐️ Plain scroll = Pan
        _handleScrollPan(event);
      }
    }
  }

  /// Handle scroll-to-zoom (Ctrl+scroll wheel or trackpad).
  void _handleScrollZoom(PointerScrollEvent event) {
    if (widget.blockPanZoom()) return;

    final controller = widget.controller;
    final focalPoint = event.localPosition;

    // Scroll up = zoom in, scroll down = zoom out
    // scrollDelta.dy is positive for scroll down
    final zoomDelta = -event.scrollDelta.dy;
    const double sensitivity = 0.002; // Adjust for feel
    final scaleFactor = math.exp(zoomDelta * sensitivity);

    // Clamp to prevent drift when at scale limits (0.1 - 5.0)
    final newScale = (controller.scale * scaleFactor).clamp(0.1, 5.0);
    if ((newScale - controller.scale).abs() < 0.0001) return; // No change

    // Zoom centered on cursor position
    final focalCanvas = controller.screenToCanvas(focalPoint);
    final newOffset = focalPoint - focalCanvas * newScale;

    controller.updateTransform(offset: newOffset, scale: newScale);
  }

  /// Handle plain scroll = pan (two-finger swipe on trackpad).
  void _handleScrollPan(PointerScrollEvent event) {
    if (widget.blockPanZoom()) return;

    final controller = widget.controller;
    final delta = Offset(-event.scrollDelta.dx, -event.scrollDelta.dy);

    controller.updateTransform(
      offset: controller.offset + delta,
      scale: controller.scale,
    );
  }

  /// 🖱️ Trackpad pinch-to-zoom start (PointerPanZoomStartEvent).
  void _onPointerPanZoomStart(PointerPanZoomStartEvent event) {
    if (widget.blockPanZoom()) return;
    _trackpadInitialScale = widget.controller.scale;
    _trackpadInitialOffset = widget.controller.offset;
    widget.controller.stopAnimation();
  }

  /// 🖱️ Trackpad pinch-to-zoom update (PointerPanZoomUpdateEvent).
  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (widget.blockPanZoom()) return;

    final controller = widget.controller;
    final focalPoint = event.localPosition;

    // Apply scale from trackpad pinch, clamp to prevent drift at limits
    final newScale = (_trackpadInitialScale * event.scale).clamp(0.1, 5.0);
    if ((newScale - controller.scale).abs() < 0.0001 &&
        event.panDelta == Offset.zero) {
      return; // No change
    }

    // Zoom centered on trackpad focal point
    final focalCanvas = controller.screenToCanvas(focalPoint);
    final newOffset =
        focalPoint -
        focalCanvas * newScale +
        event.panDelta; // Include pan delta from trackpad

    controller.updateTransform(offset: newOffset, scale: newScale);
  }

  /// 🖱️ Trackpad pinch-to-zoom end (PointerPanZoomEndEvent).
  void _onPointerPanZoomEnd(PointerPanZoomEndEvent event) {
    // Nothing to clean up — state is handled per-event
  }

  // 🌀 Two-finger double-tap detection (reset view)
  int _lastTwoFingerTapTime = 0;
  Offset _lastTwoFingerTapPosition = Offset.zero;

  void _onScaleStart(ScaleStartDetails details) {
    // 🔒 Block pan/zoom when an interactive element is being manipulated
    // ⚡ BUT allow through when image rotation is active (evaluated at gesture time) —
    // blockPanZoom includes _imageTool.isRotating, which creates a deadlock.
    final _blockPZ = widget.blockPanZoom();
    final _routeImg = widget.shouldRouteToImageRotation(
      details.localFocalPoint,
    );
    final _routeSel = widget.shouldRouteToSelectionTransform(
      details.localFocalPoint,
    );

    if (_blockPZ && !_routeImg && !_routeSel) return;
    // 🔄 GESTURE CONTINUITY: When transitioning between pointer counts
    // (e.g., 2→1 fingers), re-anchor to current state to prevent jumps.
    if (_gestureTransitioning) {
      _gestureTransitioning = false;
      _initialScale = widget.controller.scale;
      _initialFocalPoint = details.localFocalPoint;
      _initialOffset = widget.controller.offset;
      _initialRotation = widget.controller.rotation;
      _lastGestureRotation = 0.0;
      _lastScaleFocalPoint = details.localFocalPoint;
      _lastScaleUpdateTime = DateTime.now().microsecondsSinceEpoch;
      // Keep existing velocity for smooth momentum handoff
      _wasZooming = false;
      return; // Skip all other initialization — seamless transition
    }

    _initialScale = widget.controller.scale;
    _initialFocalPoint = details.localFocalPoint;
    _initialOffset = widget.controller.offset;
    _initialRotation = widget.controller.rotation;
    _lastGestureRotation = 0.0;
    _rotationUnlocked = false; // Reset deadzone for new gesture
    _gestureClassified = false; // Reset dominant gesture classifier
    _zoomDominant = false;

    // 🌀 TWO-FINGER DOUBLE-TAP: Detect rapid 2-finger taps to reset view
    if (_pointerCount >= 2) {
      final now = DateTime.now().millisecondsSinceEpoch;
      final timeSinceLastTap = now - _lastTwoFingerTapTime;
      final distFromLastTap =
          (details.localFocalPoint - _lastTwoFingerTapPosition).distance;

      if (timeSinceLastTap < 400 && distFromLastTap < 80) {
        // Double-tap detected! Reset rotation + zoom
        HapticFeedback.mediumImpact();
        widget.controller.resetRotation();
        widget.controller.startZoomSpringBack(details.localFocalPoint);
        _lastTwoFingerTapTime = 0; // Reset to avoid triple-tap
        return;
      }

      _lastTwoFingerTapTime = now;
      _lastTwoFingerTapPosition = details.localFocalPoint;
    }

    // 🌊 LIQUID: Initialize velocity tracking
    _lastScaleFocalPoint = details.localFocalPoint;
    _lastScaleUpdateTime = DateTime.now().microsecondsSinceEpoch;
    _panVelocity = Offset.zero;
    _rotationVelocity = 0.0;
    _wasZooming = false;
    _zoomVelocity = 0.0;
    _lastGestureScale = widget.controller.scale;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    // Only process with 2+ fingers
    if (_pointerCount < 2) return;

    // ✌️ MULTI-FINGER TAP: Any pan or zoom movement disqualifies as tap.
    // _onPointerMove only tracks per-frame delta (which can be tiny on
    // high-refresh devices). The real movement happens here in _onScaleUpdate.
    if (!_multiTouchMoved) {
      final panned =
          (details.localFocalPoint - _initialFocalPoint).distance > 8;
      final scaled = (details.scale - 1.0).abs() > 0.02;
      if (panned || scaled) _multiTouchMoved = true;
    }

    // ✂️ SPACE-SPLIT: Skip normal zoom/pan/rotate when splitting or armed
    if (_isSpaceSplitting || _splitLongPressReady) return;

    // 🤏 SELECTION TRANSFORM: Route pinch to selection rotate+scale
    final shouldTransformSelection = widget.shouldRouteToSelectionTransform(
      details.localFocalPoint,
    );

    if (shouldTransformSelection && widget.onSelectionScaleStart != null) {
      if (!_selectionScaleStarted) {
        _selectionScaleStarted = true;
        _selectionRotationUnlocked = false;
        _selectionInitialScale = details.scale;
        _selectionPreviousFocalPoint = details.localFocalPoint;
        widget.onSelectionScaleStart?.call();
      }

      double rotation = 0.0;
      if (_selectionRotationUnlocked ||
          details.rotation.abs() > _rotationDeadzone) {
        _selectionRotationUnlocked = true;
        rotation = details.rotation;
      }

      final scaleRatio = details.scale / _selectionInitialScale;
      final focalDelta = details.localFocalPoint - _selectionPreviousFocalPoint;
      _selectionPreviousFocalPoint = details.localFocalPoint;

      widget.onSelectionTransform?.call(rotation, scaleRatio, focalDelta);
      return;
    }

    // 🌀 IMAGE ROTATION: When image rotation is active (evaluated at gesture time),
    // route rotation + scale to the image instead of the canvas.
    // ⚡ Uses shouldRouteToImageRotation() instead of checking callbacks at build time
    // because the gesture detector widget may not rebuild when state changes.
    final shouldRotateImage = widget.shouldRouteToImageRotation(
      details.localFocalPoint,
    );
    if (shouldRotateImage && widget.onImageScaleStart != null) {
      // Fire start callback once
      if (!_imageScaleStarted) {
        _imageScaleStarted = true;
        _imageRotationAccum = 0.0;
        _imageRotationUnlocked = false;

        _imageInitialScale = details.scale;
        _imagePreviousFocalPoint = details.localFocalPoint;
        widget.onImageScaleStart?.call();
      }

      // 🌀 Rotation deadzone: ignore small rotation until threshold exceeded
      double rotation = 0.0;
      if (_imageRotationUnlocked ||
          details.rotation.abs() > _rotationDeadzone) {
        _imageRotationUnlocked = true;
        rotation = details.rotation;
      }

      // 🤏 Simultaneous scale: ratio relative to gesture start
      final scaleRatio = details.scale / _imageInitialScale;

      // 🖐️ Simultaneous drag: focal point delta (screen space)
      final focalDelta = details.localFocalPoint - _imagePreviousFocalPoint;
      _imagePreviousFocalPoint = details.localFocalPoint;

      widget.onImageTransform?.call(rotation, scaleRatio, focalDelta);
      return;
    }

    // 🔒 Block canvas pan/zoom; route scale+pan to graph viewport instead
    if (widget.blockPanZoom()) {
      if (_pointerCount >= 2) {
        final delta = details.localFocalPoint - _lastScaleFocalPoint;
        widget.onBlockedScale?.call(details.scale, delta);
        _lastScaleFocalPoint = details.localFocalPoint;
      }
      return;
    }
    widget.controller.isPanning = true; // 🚀 SCROLL OPT

    // 🌊 LIQUID: Track velocity for momentum
    final now = DateTime.now().microsecondsSinceEpoch;
    final dt = (now - _lastScaleUpdateTime) / 1000000.0; // seconds
    if (dt > 0.001) {
      final delta = details.localFocalPoint - _lastScaleFocalPoint;
      final instantVelocity = delta / dt;
      // Exponential smoothing (α = 0.3) for stable velocity
      _panVelocity = Offset(
        _panVelocity.dx * 0.7 + instantVelocity.dx * 0.3,
        _panVelocity.dy * 0.7 + instantVelocity.dy * 0.3,
      );
    }
    _lastScaleFocalPoint = details.localFocalPoint;
    _lastScaleUpdateTime = now;

    // Detect if user is zooming (scale significantly changed)
    // 🎯 FIX: Raised threshold from 0.02 to 0.10 to prevent 2-finger pan
    // from being misidentified as zoom (finger spread fluctuates ~2-5%).
    if ((details.scale - 1.0).abs() > 0.10) {
      _wasZooming = true;
    }

    // 🌊 LIQUID: Track zoom velocity (Gap 4)
    // Scale velocity = Δscale / Δtime (in scale-units per second)
    if (dt > 0.001) {
      final currentScale = _initialScale * details.scale;
      final scaleDelta = currentScale - _lastGestureScale;
      final instantZoomV = scaleDelta / dt;
      _zoomVelocity = _zoomVelocity * 0.6 + instantZoomV * 0.4;
      _lastGestureScale = currentScale;
    }

    // 🌊 LIQUID: Allow elastic overshoot for zoom (raw, unclamped scale)
    final rawScale = _initialScale * details.scale;

    // 🎯 DOMINANT GESTURE CLASSIFIER: Decide zoom vs rotate early.
    // Once classified, the gesture stays locked to prevent mixing.
    // Like Apple Maps: the system decides what you meant and commits.
    if (!_gestureClassified) {
      final scaleChange = (details.scale - 1.0).abs();
      final rotChange = details.rotation.abs();

      // Classify when either signal is strong enough
      if (scaleChange > 0.08 || rotChange > _rotationDeadzone) {
        _gestureClassified = true;
        // If scale moved significantly MORE than rotation → zoom-only
        // Ratio: scale must be 2.5x stronger than rotation to suppress
        if (scaleChange > 0.08 && scaleChange > rotChange * 2.5) {
          _zoomDominant = true;
        }
      }
    }

    // 🌀 ROTATION: Track rotation from gesture with adaptive deadzone.
    // When zoom-dominant, rotation requires a much larger intentional twist
    // (~11° instead of ~3°) to activate — prevents accidental rotation.
    final effectiveDeadzone =
        _zoomDominant ? _rotationDeadzoneZoomDominant : _rotationDeadzone;
    double newRotation;
    if (_rotationUnlocked || details.rotation.abs() > effectiveDeadzone) {
      _rotationUnlocked = true;
      newRotation = _initialRotation + details.rotation;
    } else {
      newRotation = _initialRotation; // Keep locked until deadzone exceeded
    }

    // 🌀 MAGNETIC SNAP: Add resistance near snap angles (like Procreate)
    // When close to a snap angle, dampen the rotation delta to create
    // a "sticky" feel. The user must push harder to break free.
    // 🏠 GRAVITY WELL: 0° has a wider, stronger zone — the "home" position.
    final snapAngle = widget.controller.checkSnapAngle(newRotation);
    if (snapAngle != null && !widget.controller.rotationLocked) {
      final distFromSnap = (newRotation - snapAngle).abs();
      final isHomeAngle = snapAngle == 0.0 || snapAngle.abs() < 0.001;
      // 🏠 0° gets a wider zone (15° vs 10°) and quadratic dampening (harder)
      final snapThreshold = isHomeAngle ? 0.26 : 0.18; // ~15° vs ~10°
      final t = (distFromSnap / snapThreshold).clamp(0.0, 1.0);
      // 🏠 Quadratic for 0° (harder to escape), cubic for others (softer)
      final dampening = isHomeAngle ? t * t : t * t * t;
      newRotation = snapAngle + (newRotation - snapAngle) * dampening;
    }

    // 🌀 ROTATION: Track angular velocity
    final rotationDelta = details.rotation - _lastGestureRotation;
    _lastGestureRotation = details.rotation;
    if (dt > 0.001) {
      final instantAngularV = (rotationDelta / dt).clamp(
        -_maxAngularVelocity,
        _maxAngularVelocity,
      );
      _rotationVelocity = _rotationVelocity * 0.7 + instantAngularV * 0.3;
    }

    // Calculate il delta di pan dat the point iniziale
    final panDelta = details.localFocalPoint - _initialFocalPoint;

    // 🎯 FIX: Use the ACTUAL rotation/scale that will be applied, not raw values.
    // When rotation is locked, the controller ignores newRotation.
    // When elastic clamping is active, the applied scale differs from rawScale.
    final effectiveRotation =
        widget.controller.rotationLocked ? _initialRotation : newRotation;

    // Calculate offset considering zoom + pan + rotation
    // Convert focal point from screen → canvas using initial transform
    // (undo translate → undo rotate → undo scale)
    final translated = _initialFocalPoint - _initialOffset;
    final cosR0 = math.cos(-_initialRotation);
    final sinR0 = math.sin(-_initialRotation);
    final unrotated = Offset(
      translated.dx * cosR0 - translated.dy * sinR0,
      translated.dx * sinR0 + translated.dy * cosR0,
    );
    final focalPointCanvas = unrotated / _initialScale;

    // Apply new transform: scale → rotate → translate
    // Use getEffectiveScale (elastic) so offset and _scale stay consistent.
    // The elastic cap in _applyElasticClamp ensures the overshoot is tiny,
    // preventing noticeable viewport drift at large canvas positions.
    final effectiveScale = widget.controller.getEffectiveScale(rawScale);
    final cosR = math.cos(effectiveRotation);
    final sinR = math.sin(effectiveRotation);
    final scaledFocal = Offset(
      focalPointCanvas.dx * effectiveScale,
      focalPointCanvas.dy * effectiveScale,
    );
    final rotatedFocal = Offset(
      scaledFocal.dx * cosR - scaledFocal.dy * sinR,
      scaledFocal.dx * sinR + scaledFocal.dy * cosR,
    );
    final newOffset = _initialFocalPoint - rotatedFocal + panDelta;

    // 🌊 LIQUID: Apply transform with elastic bounds + rotation
    widget.controller.updateTransform(
      offset: newOffset,
      scale: rawScale,
      rotation: newRotation,
      elastic: true,
    );

    // 🌀 SNAP HAPTIC: Two-tier feedback system.
    // Cardinal angles (0°, 90°, 180°, 270°) = always strong (mechanical detent)
    // Intermediate angles (45°, 135°, etc.) = velocity-proportional
    if (!widget.controller.rotationLocked) {
      final snapAngle = widget.controller.checkSnapAngle(newRotation);
      if (snapAngle != null && snapAngle != _lastSnappedAngle) {
        // 📐 Cardinal angle check: 0°, ±90°, ±180°
        final isCardinal =
            snapAngle.abs() < 0.001 ||
            (snapAngle.abs() - math.pi / 2).abs() < 0.001 ||
            (snapAngle.abs() - math.pi).abs() < 0.001;

        if (isCardinal) {
          HapticFeedback.mediumImpact(); // Cardinal — always strong
        } else if (_rotationVelocity.abs() > 1.5) {
          HapticFeedback.lightImpact(); // Fast intermediate — standard
        } else {
          HapticFeedback.selectionClick(); // Slow intermediate — subtle
        }
        _lastSnappedAngle = snapAngle;
      } else if (snapAngle == null) {
        _lastSnappedAngle = null;
      }
    }

    _lastScaleEndFocalPoint = details.localFocalPoint;
  }

  void _onScaleEnd(ScaleEndDetails details) {
    // 🤏 SELECTION TRANSFORM: End selection transform FIRST
    final wasSelectionScaling = _selectionScaleStarted;
    if (_selectionScaleStarted) {
      _selectionScaleStarted = false;
      _selectionRotationUnlocked = false;
      widget.onSelectionScaleEnd?.call();
    }
    if (wasSelectionScaling) return;

    // 🌀 IMAGE ROTATION: End image rotation FIRST (before blockPanZoom check,
    // because blockPanZoom includes isRotating → deadlock)
    final wasImageScaling = _imageScaleStarted;
    if (_imageScaleStarted) {
      _imageScaleStarted = false;
      _imageRotationUnlocked = false;
      _imageRotationAccum = 0.0;

      widget.onImageScaleEnd?.call();
    }
    if (wasImageScaling) return; // Don't launch viewport animations

    // 🔒 Block momentum/spring-back when an interactive element is being manipulated
    if (widget.blockPanZoom()) return;
    // 🎯 FIX: If this scale-end follows a drawing gesture, skip ALL viewport
    // animations (spring-back, momentum, rotation). The GestureDetector fires
    // onScaleEnd after every gesture — including single-finger drawing.
    // Without this guard, startZoomSpringBack shifts the viewport on finger-up
    // when zoom is beyond elastic limits, causing the committed stroke to jump.
    final wasDrawing = _wasDrawingGesture;
    _wasDrawingGesture = false;
    if (wasDrawing) {
      _panVelocity = Offset.zero;
      _rotationVelocity = 0.0;
      _wasZooming = false;
      _lastGestureScale = 1.0;
      widget.controller.isPanning = false;
      widget.controller.markNeedsPaint();
      return;
    }

    // 🌊 LIQUID: Launch zoom spring-back if scale is beyond limits
    widget.controller.startZoomSpringBack(_lastScaleEndFocalPoint);

    // 🌊 LIQUID: Launch zoom momentum if user was actively zooming (Gap 4)
    // 🎯 FIX: Raised velocity threshold and made mutually exclusive with
    // pan momentum — both write to _offset in the ticker and conflict.
    bool zoomMomentumLaunched = false;
    if (_wasZooming && _zoomVelocity.abs() > 0.5) {
      widget.controller.startZoomMomentum(
        _zoomVelocity,
        _lastScaleEndFocalPoint,
      );
      zoomMomentumLaunched = true;
    }

    // 🌊 LIQUID: Launch pan momentum from terminal velocity
    // 🎯 FIX: Skip if ANY zoom animation is active (spring-back or momentum).
    // Pan velocity from a zoom gesture is the centroid of diverging fingers,
    // not a meaningful pan direction — applying it causes viewport to fly off.
    if (!widget.controller.isAnimating && _panVelocity.distance > 0) {
      widget.controller.startMomentum(_panVelocity);
    }

    // 🌀 ROTATION: Launch rotation momentum
    widget.controller.startRotationMomentum(_rotationVelocity);

    _panVelocity = Offset.zero;
    _rotationVelocity = 0.0;
    _wasZooming = false;
    _lastGestureScale = 1.0;
    // 🚀 SCROLL OPT: Clear flag (momentum getter handles _isMomentumActive)
    widget.controller.isPanning = false;
    widget.controller
        .markNeedsPaint(); // 🚀 Final repaint with isPanning=false → annotations reappear
  }
}
