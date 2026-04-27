// ════════════════════════════════════════════════════════════════════════════
// CanvasBackground — background decoration for FlueraCanvas.
//
// Lightweight factory-style API that covers the 95 % case:
//   • solid color
//   • grid (square cells)
//   • dotted (punched dots)
//   • lined (horizontal rules — note-taking style)
//
// The pattern is rendered in world space and stays anchored to the canvas
// origin, so panning/zooming feels like moving over a real sheet of paper.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

/// Background decoration for [FlueraCanvas]. Use one of the factory
/// constructors — [solid], [grid], [dotted], [lined] — to pick a style.
///
/// All numeric parameters are expressed in **world units** (the same units
/// stroke points live in); they stay proportional to the content during
/// zoom.
class CanvasBackground {
  /// Plain fill, no pattern.
  const CanvasBackground.solid(Color color)
    : this._(
        type: _Type.solid,
        fill: color,
        lineColor: color,
        spacing: 0,
        lineWidth: 0,
        dotRadius: 0,
      );

  /// Square grid overlay.
  const CanvasBackground.grid({
    Color fill = const Color(0xFFFAFAFA),
    Color lineColor = const Color(0x11000000),
    double spacing = 32,
    double lineWidth = 1,
  }) : this._(
         type: _Type.grid,
         fill: fill,
         lineColor: lineColor,
         spacing: spacing,
         lineWidth: lineWidth,
         dotRadius: 0,
       );

  /// Dotted pattern (dot at each grid node).
  const CanvasBackground.dotted({
    Color fill = const Color(0xFFFAFAFA),
    Color dotColor = const Color(0x22000000),
    double spacing = 28,
    double dotRadius = 1.2,
  }) : this._(
         type: _Type.dotted,
         fill: fill,
         lineColor: dotColor,
         spacing: spacing,
         lineWidth: 0,
         dotRadius: dotRadius,
       );

  /// Horizontal ruled lines (note-taking style).
  const CanvasBackground.lined({
    Color fill = const Color(0xFFFAFAFA),
    Color lineColor = const Color(0x14000000),
    double spacing = 36,
    double lineWidth = 1,
  }) : this._(
         type: _Type.lined,
         fill: fill,
         lineColor: lineColor,
         spacing: spacing,
         lineWidth: lineWidth,
         dotRadius: 0,
       );

  const CanvasBackground._({
    required _Type type,
    required this.fill,
    required this.lineColor,
    required this.spacing,
    required this.lineWidth,
    required this.dotRadius,
  }) : _type = type;

  final _Type _type;
  /// Field `fill`.
  final Color fill;
  /// Field `lineColor`.
  final Color lineColor;
  /// Field `spacing`.
  final double spacing;
  /// Field `lineWidth`.
  final double lineWidth;
  /// Field `dotRadius`.
  final double dotRadius;

  /// Paint the background. [viewport] is the visible rect in world space;
  /// implementations draw the pattern only where it's actually visible so
  /// the cost scales with screen area, not world area.
  void paint(Canvas canvas, Rect viewport, double scale) {
    canvas.drawRect(viewport, Paint()..color = fill);
    final t = _type;
    if (t == _Type.grid) {
      _paintGrid(canvas, viewport, scale);
    } else if (t == _Type.dotted) {
      _paintDotted(canvas, viewport, scale);
    } else if (t == _Type.lined) {
      _paintLined(canvas, viewport, scale);
    }
  }

  void _paintGrid(Canvas canvas, Rect v, double scale) {
    if (spacing <= 0) return;
    final paint =
        Paint()
          ..color = lineColor
          ..strokeWidth = lineWidth / scale;
    // Align to world origin (0,0) so the grid feels anchored.
    final startX = (v.left / spacing).floor() * spacing;
    final startY = (v.top / spacing).floor() * spacing;
    for (double x = startX; x <= v.right; x += spacing) {
      canvas.drawLine(Offset(x, v.top), Offset(x, v.bottom), paint);
    }
    for (double y = startY; y <= v.bottom; y += spacing) {
      canvas.drawLine(Offset(v.left, y), Offset(v.right, y), paint);
    }
  }

  void _paintDotted(Canvas canvas, Rect v, double scale) {
    if (spacing <= 0) return;
    final paint = Paint()..color = lineColor;
    final r = dotRadius / scale;
    final startX = (v.left / spacing).floor() * spacing;
    final startY = (v.top / spacing).floor() * spacing;
    for (double y = startY; y <= v.bottom; y += spacing) {
      for (double x = startX; x <= v.right; x += spacing) {
        canvas.drawCircle(Offset(x, y), r, paint);
      }
    }
  }

  void _paintLined(Canvas canvas, Rect v, double scale) {
    if (spacing <= 0) return;
    final paint =
        Paint()
          ..color = lineColor
          ..strokeWidth = lineWidth / scale;
    final startY = (v.top / spacing).floor() * spacing;
    for (double y = startY; y <= v.bottom; y += spacing) {
      canvas.drawLine(Offset(v.left, y), Offset(v.right, y), paint);
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CanvasBackground &&
      other._type == _type &&
      other.fill == fill &&
      other.lineColor == lineColor &&
      other.spacing == spacing &&
      other.lineWidth == lineWidth &&
      other.dotRadius == dotRadius;

  @override
  int get hashCode =>
      Object.hash(_type, fill, lineColor, spacing, lineWidth, dotRadius);
}

enum _Type { solid, grid, dotted, lined }
