import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../infinite_canvas_controller.dart';
import 'canvas_selection.dart';
import 'transform_handles.dart';

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

  @override
  void paint(Canvas canvas, Size size) {
    final sel = selection();
    final marquee = marqueeRect();
    if (sel.isEmpty && marquee == null) return;

    canvas.save();
    canvas.translate(controller.offset.dx, controller.offset.dy);
    canvas.scale(controller.scale);

    if (sel.isNotEmpty) {
      _paintSelectionFrame(canvas, sel.bounds, controller.scale);
    }
    if (marquee != null) {
      _paintMarquee(canvas, marquee, controller.scale);
    }

    canvas.restore();
  }

  void _paintSelectionFrame(Canvas canvas, Rect bounds, double scale) {
    // Stroke widths in world-space inversely scaled so the visual
    // stays at constant screen-space thickness.
    final outline = Paint()
      ..color = const Color(0xFF1565C0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / scale;
    final outlineBg = Paint()
      ..color = const Color(0x66FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 / scale;
    canvas.drawRect(bounds, outlineBg);
    canvas.drawRect(bounds, outline);

    // 8 handles: 4 corners + 4 mid-edges. Render at constant 12 px
    // screen-space size by undoing the world scale.
    const handlePxSize = 12.0;
    final hs = handlePxSize / scale;
    final handleFill = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;
    final handleStroke = Paint()
      ..color = const Color(0xFF1565C0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / scale;

    final positions = <Offset>[
      bounds.topLeft,
      Offset(bounds.center.dx, bounds.top),
      bounds.topRight,
      Offset(bounds.right, bounds.center.dy),
      bounds.bottomRight,
      Offset(bounds.center.dx, bounds.bottom),
      bounds.bottomLeft,
      Offset(bounds.left, bounds.center.dy),
    ];
    for (final p in positions) {
      final r = Rect.fromCenter(center: p, width: hs, height: hs);
      canvas.drawRect(r, handleFill);
      canvas.drawRect(r, handleStroke);
    }

    // Rotate handle: a small circle 24 px above the top-mid edge with
    // a 1-px tether so users see what it controls. Drawn as the last
    // overlay so the tether sits under the handle's white fill.
    final rotatePos =
        TransformMath.handlePosition(bounds, SelectionHandle.rotate, scale);
    final tether = Paint()
      ..color = const Color(0xFF1565C0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0 / scale;
    canvas.drawLine(
      Offset(bounds.center.dx, bounds.top),
      rotatePos,
      tether,
    );
    final rotateRadius = (handlePxSize * 0.65) / scale;
    canvas.drawCircle(rotatePos, rotateRadius, handleFill);
    canvas.drawCircle(rotatePos, rotateRadius, handleStroke);
  }

  void _paintMarquee(Canvas canvas, Rect rect, double scale) {
    final fill = Paint()
      ..color = const Color(0x141565C0)
      ..style = PaintingStyle.fill;
    canvas.drawRect(rect, fill);

    // Dashed outline. Implemented as a path effect-free segment loop —
    // dart:ui has no native PathDashEffect.
    final paint = Paint()
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
      final length = ui.Size(dx, dy).shortestSide == 0
          ? (dx.abs() + dy.abs())
          : 0.0;
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
