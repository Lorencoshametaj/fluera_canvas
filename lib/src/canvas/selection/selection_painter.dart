import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../fluera_canvas_widget.dart' show SmartGuideLine;
import '../infinite_canvas_controller.dart';
import 'canvas_selection.dart';

/// Custom painter that overlays the selection visual on top of the
/// committed-strokes layer.
///
/// Rendered above the scene-graph painter and below the live-stroke
/// painter so handles never get covered by a stroke being drawn but
/// also never lag behind a freshly-committed one.
///
/// Two visuals share this painter:
/// - Bounding rect + 8 handles of the active [CanvasSelection]. Drawn
///   when [selection.isNotEmpty]. Handles are sized in **screen** space
///   (12 px) so they stay legible regardless of camera zoom.
/// - The in-progress **marquee** rectangle the user is dragging out
///   while `tool == CanvasTool.select`. Drawn when [marqueeRect] is
///   non-null. Dashed outline.
///
/// Stable instance: created once in the widget's [initState] and reused
/// for the lifetime of the State, with `repaint` wired to the merged
/// listenable of the selection controller, the camera and the marquee
/// notifier so paints fire only when something actually moves.
class SelectionPainter extends CustomPainter {
  SelectionPainter({
    required this.selection,
    required this.controller,
    required this.marqueeRect,
    required Listenable repaintTrigger,
    this.smartGuides,
    this.lassoPath,
  }) : super(repaint: repaintTrigger);

  /// Live ref-cell for the active selection. Read at paint time so the
  /// painter can stay stable across selection changes.
  final ValueGetter<CanvasSelection> selection;

  /// Camera state — used to map world → screen for the handles.
  final InfiniteCanvasController controller;

  /// Live ref-cell for the in-progress marquee rect, in **world**
  /// coordinates. Returns `null` when the user is not currently
  /// dragging out a marquee.
  final ValueGetter<Rect?> marqueeRect;

  /// Live ref-cell for the smart-guide lines emitted by the move
  /// snap engine. Returns an empty list when no snap is active.
  final ValueGetter<List<SmartGuideLine>>? smartGuides;

  /// Live ref-cell for the in-progress lasso path, in **world**
  /// coordinates. Returns `null` when the user is not currently
  /// dragging out a lasso. Rendered as a magenta dashed polyline
  /// with a faint translucent fill so the user sees what their
  /// drag has captured before pen-up.
  final ValueGetter<List<Offset>?>? lassoPath;

  @override
  void paint(Canvas canvas, Size size) {
    final sel = selection();
    final marquee = marqueeRect();
    final guides = smartGuides?.call() ?? const <SmartGuideLine>[];
    final lasso = lassoPath?.call();
    final hasLasso = lasso != null && lasso.length >= 2;
    if (sel.isEmpty && marquee == null && guides.isEmpty && !hasLasso) return;

    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(controller.scale);

    if (sel.isNotEmpty) {
      _paintSelectionFrame(canvas, sel, controller.scale);
    }
    if (marquee != null) {
      _paintMarquee(canvas, marquee, controller.scale);
    }
    if (hasLasso) {
      _paintLasso(canvas, lasso, controller.scale);
    }
    if (guides.isNotEmpty) {
      _paintSmartGuides(canvas, guides, controller.scale);
    }

    canvas.restore();
  }

  /// Paint the in-progress lasso path as a magenta dashed polyline
  /// with a faint translucent fill. The fill makes the captured
  /// region visible at a glance while the user is still drawing
  /// the loop.
  void _paintLasso(Canvas canvas, List<Offset> points, double scale) {
    final closedPath = ui.Path()..addPolygon(points, true);
    final fill =
        Paint()
          ..color = const Color(0x14FF2D8E)
          ..style = PaintingStyle.fill;
    canvas.drawPath(closedPath, fill);

    final paint =
        Paint()
          ..color = const Color(0xFFFF2D8E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 / scale;
    final dash = 6.0 / scale;
    final gap = 4.0 / scale;
    for (var i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      _dashedSegment(canvas, a, b, paint, dash, gap);
    }
  }

  void _dashedSegment(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint,
    double dash,
    double gap,
  ) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist <= 0) return;
    double covered = 0;
    while (covered < dist) {
      final segEnd = math.min(covered + dash, dist);
      final t1 = covered / dist;
      final t2 = segEnd / dist;
      canvas.drawLine(
        Offset(a.dx + dx * t1, a.dy + dy * t1),
        Offset(a.dx + dx * t2, a.dy + dy * t2),
        paint,
      );
      covered = segEnd + gap;
    }
  }

  /// Paint the live snap / smart-guide lines as thin dashed strokes
  /// in a vivid magenta — the standard design-tool convention so
  /// users immediately recognise the alignment overlay vs the blue
  /// selection chrome.
  void _paintSmartGuides(
    Canvas canvas,
    List<SmartGuideLine> guides,
    double scale,
  ) {
    final paint =
        Paint()
          ..color = const Color(0xFFFF2D8E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 / scale;
    final dash = 6.0 / scale;
    final gap = 4.0 / scale;
    for (final g in guides) {
      if (g.axis == Axis.vertical) {
        _drawDashedLine(
          canvas,
          Offset(g.position, g.rangeStart),
          Offset(g.position, g.rangeEnd),
          paint,
          dash,
          gap,
        );
      } else {
        _drawDashedLine(
          canvas,
          Offset(g.rangeStart, g.position),
          Offset(g.rangeEnd, g.position),
          paint,
          dash,
          gap,
        );
      }
    }
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint,
    double dash,
    double gap,
  ) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final dist =
        dx == 0 ? dy.abs() : (dy == 0 ? dx.abs() : (dx * dx + dy * dy));
    final length =
        (dx == 0 || dy == 0)
            ? dist
            : ui.Size(dx, dy).shortestSide; // not used for axis-aligned
    final total = (dx == 0 || dy == 0) ? dist : length;
    if (total <= 0) return;
    double covered = 0;
    while (covered < total) {
      final segEnd = (covered + dash).clamp(0.0, total);
      final t1 = covered / total;
      final t2 = segEnd / total;
      final p1 = Offset(a.dx + dx * t1, a.dy + dy * t1);
      final p2 = Offset(a.dx + dx * t2, a.dy + dy * t2);
      canvas.drawLine(p1, p2, paint);
      covered = segEnd + gap;
    }
  }

  void _paintSelectionFrame(Canvas canvas, CanvasSelection sel, double scale) {
    // Stroke widths in world-space inversely scaled so the visual
    // stays at constant screen-space thickness.
    final outline =
        Paint()
          ..color = const Color(0xFF1565C0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / scale;
    final outlineBg =
        Paint()
          ..color = const Color(0x66FFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0 / scale;

    // Outline: drawn under the frame transform so the rectangle
    // rotates / scales with the underlying node.
    canvas.save();
    canvas.transform(sel.frameTransform.storage);
    canvas.drawRect(sel.frameRect, outlineBg);
    canvas.drawRect(sel.frameRect, outline);
    canvas.restore();

    // Handles: drawn axis-aligned (constant 12 px screen-space size),
    // but POSITIONED at the world-space transformed corners of the
    // local frame rect — so the user sees handles riding the rotated
    // OBB without their own visual being skewed by the frame's
    // rotation/scale.
    const handlePxSize = 12.0;
    final hs = handlePxSize / scale;
    final handleFill =
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..style = PaintingStyle.fill;
    final handleStroke =
        Paint()
          ..color = const Color(0xFF1565C0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 / scale;

    Offset toWorld(Offset local) =>
        MatrixUtils.transformPoint(sel.frameTransform, local);

    final localPositions = <Offset>[
      sel.frameRect.topLeft,
      Offset(sel.frameRect.center.dx, sel.frameRect.top),
      sel.frameRect.topRight,
      Offset(sel.frameRect.right, sel.frameRect.center.dy),
      sel.frameRect.bottomRight,
      Offset(sel.frameRect.center.dx, sel.frameRect.bottom),
      sel.frameRect.bottomLeft,
      Offset(sel.frameRect.left, sel.frameRect.center.dy),
    ];
    for (final p in localPositions) {
      final w = toWorld(p);
      final r = Rect.fromCenter(center: w, width: hs, height: hs);
      canvas.drawRect(r, handleFill);
      canvas.drawRect(r, handleStroke);
    }

    // Rotate handle: a small circle 24 px above the top-mid edge with
    // a 1-px tether so users see what it controls. Drawn as the last
    // overlay so the tether sits under the handle's white fill. The
    // tether direction follows the frame's rotation by lifting the
    // handle along the *world* up-axis emitted by the frame's local
    // -y direction.
    final topMidLocal = Offset(sel.frameRect.center.dx, sel.frameRect.top);
    final topMidWorld = toWorld(topMidLocal);
    // Map local up (-y) into world to figure out which way "above the
    // top edge" actually points after the frame is rotated.
    final originWorld = toWorld(Offset.zero);
    final upWorld = toWorld(const Offset(0, -1)) - originWorld;
    final upLen = upWorld.distance;
    final upUnit = upLen == 0 ? const Offset(0, -1) : upWorld / upLen;
    final rotatePos = topMidWorld + upUnit * (24.0 / scale);

    final tether =
        Paint()
          ..color = const Color(0xFF1565C0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 / scale;
    canvas.drawLine(topMidWorld, rotatePos, tether);
    final rotateRadius = (handlePxSize * 0.65) / scale;
    canvas.drawCircle(rotatePos, rotateRadius, handleFill);
    canvas.drawCircle(rotatePos, rotateRadius, handleStroke);
  }

  void _paintMarquee(Canvas canvas, Rect rect, double scale) {
    final fill =
        Paint()
          ..color = const Color(0x141565C0)
          ..style = PaintingStyle.fill;
    canvas.drawRect(rect, fill);

    // Dashed outline. Implemented as a path effect-free segment loop —
    // dart:ui has no native PathDashEffect.
    final paint =
        Paint()
          ..color = const Color(0xFF1565C0)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0 / scale;
    final dash = 6.0 / scale;
    final gap = 4.0 / scale;
    _drawDashedRect(canvas, rect, paint, dash, gap);
  }

  void _drawDashedRect(
    Canvas canvas,
    Rect rect,
    Paint paint,
    double dash,
    double gap,
  ) {
    void dashedLine(Offset a, Offset b) {
      final dx = b.dx - a.dx;
      final dy = b.dy - a.dy;
      final len = (dx * dx + dy * dy);
      if (len <= 0) return;
      final length =
          ui.Size(dx, dy).shortestSide == 0 ? (dx.abs() + dy.abs()) : 0.0;
      // Use Manhattan length for axis-aligned segments (it equals the
      // Euclidean length when one component is zero).
      final dist = length;
      double covered = 0;
      while (covered < dist) {
        final segEnd = (covered + dash).clamp(0.0, dist);
        final t1 = covered / dist;
        final t2 = segEnd / dist;
        final p1 = Offset(a.dx + dx * t1, a.dy + dy * t1);
        final p2 = Offset(a.dx + dx * t2, a.dy + dy * t2);
        canvas.drawLine(p1, p2, paint);
        covered = segEnd + gap;
      }
    }

    dashedLine(rect.topLeft, rect.topRight);
    dashedLine(rect.topRight, rect.bottomRight);
    dashedLine(rect.bottomRight, rect.bottomLeft);
    dashedLine(rect.bottomLeft, rect.topLeft);
  }

  @override
  bool shouldRepaint(covariant SelectionPainter oldDelegate) => false;
}
