import 'dart:ui' show Offset, Size;

import 'package:flutter/scheduler.dart' show Ticker, TickerProvider;

import 'infinite_canvas_controller.dart';

/// Drives the camera to auto-pan when a drag-driven gesture (selection
/// move, image drag, lasso, future text-frame drag) approaches the
/// gesture-area edges — the canonical "edge-of-viewport scroll" UX
/// pioneered by Figma / Miro / Procreate.
///
/// **Independent module by design.** No coupling to `FlueraCanvasState`,
/// no knowledge of selection or transform internals. Any gesture that
/// owns a screen-space pointer can wire one of these in, get
/// `onTick` callbacks while at the edge, and feed the world-space
/// pointer back into its own logic. Selection drag is the first
/// consumer; image drag, lasso completion and text-frame drag will
/// share the same instance pattern.
///
/// Lifecycle:
/// 1. `update(pointerScreen, viewportSize)` on every pointer-move of
///    the host gesture. The controller decides whether to start /
///    stop / continue ticking based on proximity to the edges.
/// 2. `onTick` fires on every vsync while panning. The callback
///    receives the world-space delta the camera moved this frame —
///    use it to refresh your gesture's anchor or just to know "the
///    camera moved, recompute".
/// 3. `stop()` on gesture end / cancel. Idempotent.
/// 4. `dispose()` when the parent State disposes.
class EdgePanController {
  EdgePanController({
    required this.controller,
    required TickerProvider vsync,
    required this.onTick,
    this.edgeMargin = 60.0,
    this.maxVelocityPxPerSec = 1200.0,
  }) : _vsync = vsync;

  /// Camera the controller pans. Reads `scale` to convert pixel
  /// velocity to world-space delta, mutates `offset` to actually pan.
  final InfiniteCanvasController controller;

  /// Pixels from the gesture-area edge inside which auto-pan kicks in.
  /// Inside this band the velocity ramps from 0 (at the band's inner
  /// edge) to `maxVelocityPxPerSec` (at the very edge). 60 px is a
  /// touch-friendly default; consumers building keyboard/mouse-only
  /// flows might want 30.
  final double edgeMargin;

  /// Velocity at the very edge of the viewport (px/sec, screen
  /// space). Linear ramp inward through the edge band.
  final double maxVelocityPxPerSec;

  /// Fired on every vsync while the controller is actively panning.
  /// `worldDelta` is the world-space distance the camera moved this
  /// frame — use it to update your gesture's anchor or just as a
  /// "the camera moved" pulse.
  final void Function(Offset worldDelta) onTick;

  final TickerProvider _vsync;

  Ticker? _ticker;
  Offset? _lastScreenPos;
  Size _viewportSize = Size.zero;
  Duration? _lastElapsed;

  /// True while the controller is actively panning the camera.
  bool get isPanning => _ticker?.isActive ?? false;

  /// Notify the controller that the host gesture's pointer is at
  /// [pointerScreen] inside an area of [viewportSize]. Starts the
  /// auto-pan ticker if the pointer is in the edge band, stops it
  /// otherwise. Idempotent — safe to call on every pointer-move.
  void update({required Offset pointerScreen, required Size viewportSize}) {
    _lastScreenPos = pointerScreen;
    _viewportSize = viewportSize;
    if (_velocityFor(pointerScreen, viewportSize) != Offset.zero) {
      if (_ticker == null) {
        _ticker = _vsync.createTicker(_tick);
        _lastElapsed = null;
        _ticker!.start();
      }
    } else {
      stop();
    }
  }

  /// Stop the auto-pan ticker and release its resources. Safe to
  /// call multiple times. Does NOT call `dispose` — the controller
  /// can be reused for the next gesture.
  void stop() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    _lastScreenPos = null;
    _lastElapsed = null;
  }

  /// Permanent teardown. Stops any active ticker and forgets the
  /// pointer state. Call from your widget's `dispose`.
  void dispose() {
    stop();
  }

  Offset _velocityFor(Offset p, Size s) {
    if (s.width <= 0 || s.height <= 0 || edgeMargin <= 0) {
      return Offset.zero;
    }
    double vx = 0;
    double vy = 0;
    if (p.dx < edgeMargin) {
      vx = -((edgeMargin - p.dx) / edgeMargin) * maxVelocityPxPerSec;
    } else if (p.dx > s.width - edgeMargin) {
      vx = ((p.dx - (s.width - edgeMargin)) / edgeMargin) * maxVelocityPxPerSec;
    }
    if (p.dy < edgeMargin) {
      vy = -((edgeMargin - p.dy) / edgeMargin) * maxVelocityPxPerSec;
    } else if (p.dy > s.height - edgeMargin) {
      vy =
          ((p.dy - (s.height - edgeMargin)) / edgeMargin) * maxVelocityPxPerSec;
    }
    // Clamp velocity to the edge cap (the linear ramp can overshoot
    // when the pointer leaves the band toward the very screen border —
    // `(p.dx - inner)/edgeMargin` can be > 1 if the user drags a
    // hardware mouse outside the viewport).
    if (vx > maxVelocityPxPerSec) vx = maxVelocityPxPerSec;
    if (vx < -maxVelocityPxPerSec) vx = -maxVelocityPxPerSec;
    if (vy > maxVelocityPxPerSec) vy = maxVelocityPxPerSec;
    if (vy < -maxVelocityPxPerSec) vy = -maxVelocityPxPerSec;
    return Offset(vx, vy);
  }

  void _tick(Duration elapsed) {
    final p = _lastScreenPos;
    final s = _viewportSize;
    if (p == null) return;
    final dt = _lastElapsed == null ? Duration.zero : elapsed - _lastElapsed!;
    _lastElapsed = elapsed;
    final dtSec = dt.inMicroseconds / 1e6;
    if (dtSec <= 0) return;
    final v = _velocityFor(p, s);
    if (v == Offset.zero) {
      stop();
      return;
    }
    // Pan the camera in the OPPOSITE direction of the desired view
    // shift: `worldUnderPointer` is `(screen - offset) / scale`, so
    // shifting the world view rightward (showing more world to the
    // right) means decreasing `offset.dx`. The host gesture's
    // pointer-in-world automatically tracks the new offset because
    // the screen position stays constant; the `onTick` callback lets
    // the host re-query that world coord.
    final dxScreen = v.dx * dtSec;
    final dyScreen = v.dy * dtSec;
    controller.setOffset(
      Offset(controller.offset.dx - dxScreen, controller.offset.dy - dyScreen),
    );
    final worldDelta = Offset(
      dxScreen / controller.scale,
      dyScreen / controller.scale,
    );
    onTick(worldDelta);
  }
}
