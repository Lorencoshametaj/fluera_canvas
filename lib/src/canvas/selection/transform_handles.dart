import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:vector_math/vector_math_64.dart' show Matrix4;

/// Which handle around the selection bounding box the user grabbed.
///
/// Eight standard handles (4 corners + 4 mid-edges) plus a dedicated
/// `rotate` handle drawn above the top-mid edge.
enum SelectionHandle {
  topLeft,
  topMid,
  topRight,
  midRight,
  bottomRight,
  bottomMid,
  bottomLeft,
  midLeft,
  rotate,
}

/// Active transform gesture mode driven by the handle the user grabbed
/// (or `move` when they grabbed the bounding-box body itself).
enum TransformMode { move, scaleCorner, scaleEdge, rotate }

/// Pure-math helpers for the active transform gesture. Applied on top
/// of each selected node's `localTransform` after capturing a snapshot
/// at pen-down.
///
/// All angles are in radians, clockwise positive.
class TransformMath {
  TransformMath._();

  /// Build a translation matrix that moves a node by `[dx, dy]`.
  /// `axisLock = true` snaps the translation to the dominant axis
  /// (`max(|dx|, |dy|)`) — used when the user holds shift.
  static Matrix4 translation(double dx, double dy, {bool axisLock = false}) {
    if (axisLock) {
      if (dx.abs() >= dy.abs()) {
        dy = 0;
      } else {
        dx = 0;
      }
    }
    return Matrix4.translationValues(dx, dy, 0);
  }

  /// Compute uniform / non-uniform scale factors when a corner handle
  /// is dragged.
  ///
  /// [originalBounds] — selection bounds at pen-down (world coords).
  /// [grabbed] — which corner is being dragged (must be a corner).
  /// [pointer] — current pointer position in world coords.
  /// [uniform] — when `true`, force `sx == sy` (max of the two abs
  /// values, sign preserved). The plan defines this as the default
  /// behaviour with `shift OFF`. Pass `false` when shift is held.
  ///
  /// Returns a record with `(sx, sy, anchor)`. `anchor` is the corner
  /// opposite to [grabbed] — the pin point that stays fixed while the
  /// rest of the bounds expands or contracts toward it.
  static ({double sx, double sy, Offset anchor}) cornerScale({
    required Rect originalBounds,
    required SelectionHandle grabbed,
    required Offset pointer,
    bool uniform = true,
  }) {
    assert(_isCorner(grabbed), 'cornerScale requires a corner handle');
    final anchor = _oppositeCorner(originalBounds, grabbed);
    final draggedOriginal = _cornerOf(originalBounds, grabbed);

    final originalDx = draggedOriginal.dx - anchor.dx;
    final originalDy = draggedOriginal.dy - anchor.dy;
    final newDx = pointer.dx - anchor.dx;
    final newDy = pointer.dy - anchor.dy;

    var sx = originalDx == 0 ? 1.0 : newDx / originalDx;
    var sy = originalDy == 0 ? 1.0 : newDy / originalDy;
    if (uniform) {
      // Sign-preserving uniform scale: pick the dominant magnitude,
      // re-apply the original sign of each axis (so flipping past the
      // anchor still works on both axes).
      final mag = math.max(sx.abs(), sy.abs());
      sx = sx.isNegative ? -mag : mag;
      sy = sy.isNegative ? -mag : mag;
    }
    return (sx: sx, sy: sy, anchor: anchor);
  }

  /// 1-D scale when a mid-edge handle is dragged. Only the axis normal
  /// to the grabbed edge changes; the other stays at 1.
  static ({double sx, double sy, Offset anchor}) edgeScale({
    required Rect originalBounds,
    required SelectionHandle grabbed,
    required Offset pointer,
  }) {
    assert(_isEdge(grabbed), 'edgeScale requires a mid-edge handle');
    switch (grabbed) {
      case SelectionHandle.topMid:
        final anchor = Offset(originalBounds.center.dx, originalBounds.bottom);
        final orig = originalBounds.top - anchor.dy;
        final cur = pointer.dy - anchor.dy;
        return (sx: 1.0, sy: orig == 0 ? 1.0 : cur / orig, anchor: anchor);
      case SelectionHandle.bottomMid:
        final anchor = Offset(originalBounds.center.dx, originalBounds.top);
        final orig = originalBounds.bottom - anchor.dy;
        final cur = pointer.dy - anchor.dy;
        return (sx: 1.0, sy: orig == 0 ? 1.0 : cur / orig, anchor: anchor);
      case SelectionHandle.midLeft:
        final anchor = Offset(originalBounds.right, originalBounds.center.dy);
        final orig = originalBounds.left - anchor.dx;
        final cur = pointer.dx - anchor.dx;
        return (sx: orig == 0 ? 1.0 : cur / orig, sy: 1.0, anchor: anchor);
      case SelectionHandle.midRight:
        final anchor = Offset(originalBounds.left, originalBounds.center.dy);
        final orig = originalBounds.right - anchor.dx;
        final cur = pointer.dx - anchor.dx;
        return (sx: orig == 0 ? 1.0 : cur / orig, sy: 1.0, anchor: anchor);
      default:
        // Defensive — assert above already covered this.
        return (sx: 1.0, sy: 1.0, anchor: originalBounds.center);
    }
  }

  /// Build the matrix that scales a node by `[sx, sy]` around [anchor]:
  ///   T(anchor) · S(sx, sy) · T(-anchor)
  static Matrix4 scaleAroundAnchor(double sx, double sy, Offset anchor) {
    final pre = Matrix4.translationValues(anchor.dx, anchor.dy, 0);
    final scl = Matrix4.diagonal3Values(sx, sy, 1);
    final post = Matrix4.translationValues(-anchor.dx, -anchor.dy, 0);
    return pre
      ..multiply(scl)
      ..multiply(post);
  }

  /// Compute the rotation delta (radians) for a rotate-handle drag.
  ///
  /// [center] — pivot of the rotation, typically the selection bounds
  /// center.
  /// [anchor] — pen-down world position (initial pointer).
  /// [pointer] — current pointer world position.
  /// [snap15] — when true, snap the resulting absolute angle to the
  /// nearest multiple of 15° (π/12 rad). Snapping is done on the
  /// **delta** angle so that an unsnapped initial state (the node
  /// already had some rotation when the gesture began) is preserved.
  static double rotationDelta({
    required Offset center,
    required Offset anchor,
    required Offset pointer,
    bool snap15 = false,
  }) {
    final a0 = math.atan2(anchor.dy - center.dy, anchor.dx - center.dx);
    final a1 = math.atan2(pointer.dy - center.dy, pointer.dx - center.dx);
    var delta = a1 - a0;
    if (snap15) {
      const step = math.pi / 12; // 15°
      delta = (delta / step).round() * step;
    }
    return delta;
  }

  /// Build the rotation-about-pivot matrix.
  static Matrix4 rotationAroundPivot(double radians, Offset pivot) {
    final pre = Matrix4.translationValues(pivot.dx, pivot.dy, 0);
    final rot = Matrix4.rotationZ(radians);
    final post = Matrix4.translationValues(-pivot.dx, -pivot.dy, 0);
    return pre
      ..multiply(rot)
      ..multiply(post);
  }

  /// Mirror a node around a vertical axis [x].
  static Matrix4 mirrorH(double x) => scaleAroundAnchor(-1, 1, Offset(x, 0));

  /// Mirror a node around a horizontal axis [y].
  static Matrix4 mirrorV(double y) => scaleAroundAnchor(1, -1, Offset(0, y));

  // ── Handle introspection ─────────────────────────────────────────────

  static bool _isCorner(SelectionHandle h) =>
      h == SelectionHandle.topLeft ||
      h == SelectionHandle.topRight ||
      h == SelectionHandle.bottomLeft ||
      h == SelectionHandle.bottomRight;

  static bool _isEdge(SelectionHandle h) =>
      h == SelectionHandle.topMid ||
      h == SelectionHandle.bottomMid ||
      h == SelectionHandle.midLeft ||
      h == SelectionHandle.midRight;

  static Offset _cornerOf(Rect r, SelectionHandle h) {
    switch (h) {
      case SelectionHandle.topLeft:
        return r.topLeft;
      case SelectionHandle.topRight:
        return r.topRight;
      case SelectionHandle.bottomRight:
        return r.bottomRight;
      case SelectionHandle.bottomLeft:
        return r.bottomLeft;
      default:
        throw StateError('Not a corner: $h');
    }
  }

  static Offset _oppositeCorner(Rect r, SelectionHandle h) {
    switch (h) {
      case SelectionHandle.topLeft:
        return r.bottomRight;
      case SelectionHandle.topRight:
        return r.bottomLeft;
      case SelectionHandle.bottomRight:
        return r.topLeft;
      case SelectionHandle.bottomLeft:
        return r.topRight;
      default:
        throw StateError('Not a corner: $h');
    }
  }

  /// Map every handle (corner / edge / rotate) to its anchor point
  /// in the [bounds]. Used by both the painter and the hit-tester.
  static Offset handlePosition(Rect bounds, SelectionHandle h, double scale) {
    switch (h) {
      case SelectionHandle.topLeft:
        return bounds.topLeft;
      case SelectionHandle.topMid:
        return Offset(bounds.center.dx, bounds.top);
      case SelectionHandle.topRight:
        return bounds.topRight;
      case SelectionHandle.midRight:
        return Offset(bounds.right, bounds.center.dy);
      case SelectionHandle.bottomRight:
        return bounds.bottomRight;
      case SelectionHandle.bottomMid:
        return Offset(bounds.center.dx, bounds.bottom);
      case SelectionHandle.bottomLeft:
        return bounds.bottomLeft;
      case SelectionHandle.midLeft:
        return Offset(bounds.left, bounds.center.dy);
      case SelectionHandle.rotate:
        // 24 px screen-space above the top-mid handle.
        return Offset(bounds.center.dx, bounds.top - 24.0 / scale);
    }
  }

  /// Hit-test a world-space pointer against every handle of [bounds].
  /// Handle pickup radius is `12 / scale` world units (≈ 12 px screen).
  /// Returns `null` when the pointer landed outside every handle.
  static SelectionHandle? hitTestHandle(
    Rect bounds,
    Offset worldPoint,
    double scale,
  ) {
    final r = 12.0 / scale;
    final r2 = r * r;
    for (final h in SelectionHandle.values) {
      final p = handlePosition(bounds, h, scale);
      final dx = worldPoint.dx - p.dx;
      final dy = worldPoint.dy - p.dy;
      if (dx * dx + dy * dy <= r2) return h;
    }
    return null;
  }

  /// Pick the [TransformMode] driven by a grabbed handle.
  static TransformMode modeForHandle(SelectionHandle h) {
    switch (h) {
      case SelectionHandle.rotate:
        return TransformMode.rotate;
      case SelectionHandle.topLeft:
      case SelectionHandle.topRight:
      case SelectionHandle.bottomLeft:
      case SelectionHandle.bottomRight:
        return TransformMode.scaleCorner;
      case SelectionHandle.topMid:
      case SelectionHandle.bottomMid:
      case SelectionHandle.midLeft:
      case SelectionHandle.midRight:
        return TransformMode.scaleEdge;
    }
  }
}
