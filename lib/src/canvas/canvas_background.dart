// ════════════════════════════════════════════════════════════════════════════
// CanvasBackground — background decoration for FlueraCanvas.
//
// Lightweight factory-style API that covers the 95 % case:
//   • solid color
//   • grid (square cells)
//   • dotted (punched dots)
//   • lined (horizontal rules — note-taking style)
//   • paperGrain (canvas_gpu 1.3.0 — Feature #4 paper texture overlay)
//
// The pattern is rendered in world space and stays anchored to the canvas
// origin, so panning/zooming feels like moving over a real sheet of paper.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../drawing/brushes/brush_texture.dart';
import '../rendering/canvas/paper_grain_painter.dart';

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

  /// Paper grain — tiles a [`PaperType`] texture (charcoal,
  /// pencil grain, watercolor cold-press, canvas weave, kraft)
  /// over a base [fill] color. Strokes draw on top of the grain
  /// without modifying it. Added in canvas_gpu 1.3.0
  /// (Feature #4 brush textures + paper grain).
  ///
  /// The actual texture image is loaded asynchronously via
  /// [`BrushTexture.load`] on first paint; subsequent paints reuse
  /// the cached image. While the image is loading the painter
  /// falls back to the [fill] color only — no flash of unstyled
  /// content.
  const CanvasBackground.paperGrain({
    required PaperType paperType,
    Color fill = const Color(0xFFFAFAFA),
    double opacity = 0.4,
    double scale = 1.5,
  }) : this._(
         type: _Type.paperGrain,
         fill: fill,
         lineColor: const Color(0x00000000),
         spacing: scale,
         lineWidth: opacity,
         dotRadius: 0,
         paperType: paperType,
       );

  const CanvasBackground._({
    required _Type type,
    required this.fill,
    required this.lineColor,
    required this.spacing,
    required this.lineWidth,
    required this.dotRadius,
    this.paperType,
  }) : _type = type;

  final _Type _type;
  /// Field `fill`.
  final Color fill;
  /// Field `lineColor`.
  final Color lineColor;
  /// Field `spacing` — also reused as `scale` for `paperGrain`.
  final double spacing;
  /// Field `lineWidth` — also reused as `opacity` for `paperGrain`.
  final double lineWidth;
  /// Field `dotRadius`.
  final double dotRadius;
  /// Paper texture type (only used when `_type == paperGrain`).
  /// canvas_gpu 1.3.0 (Feature #4).
  final PaperType? paperType;

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
    } else if (t == _Type.paperGrain) {
      _paintPaperGrain(canvas, viewport, scale);
    }
  }

  /// 1.4.0 optim #9 — memoize the `Paint` object for the paper
  /// grain so we don't reconstruct the `ImageShader` on every
  /// frame. Keyed by `(textureImage.identityHash, opacity, scale)`
  /// so opacity / scale changes (rare — only when the consumer
  /// re-applies a preset) invalidate naturally.
  static final Map<int, Paint> _paintCache = <int, Paint>{};

  /// Tile the paper-grain texture across the visible viewport.
  /// `lineWidth` slot stores opacity, `spacing` slot stores
  /// scale (chosen so the existing const constructor stays
  /// const-compatible without adding new fields).
  void _paintPaperGrain(Canvas canvas, Rect v, double scale) {
    final paper = paperType;
    if (paper == null || paper == PaperType.smooth) return;
    final textureType = PaperGrainPainter.textureTypeForPaper(paper);
    final image = BrushTexture.getCached(textureType);
    if (image == null) {
      // Texture not yet loaded — kick off async load. The next
      // repaint (after `_textureLoadKick` resolves) will draw
      // the tile pattern. Until then the base [fill] is shown.
      _textureLoadKick(textureType);
      return;
    }
    final cacheKey = Object.hash(
      identityHashCode(image),
      lineWidth, // opacity
      spacing, // scale
    );
    final paint = _paintCache.putIfAbsent(
      cacheKey,
      () => BrushTexture.createTexturePaint(
            textureImage: image,
            intensity: lineWidth,
            scale: spacing,
          ) ??
          Paint(),
    );
    canvas.drawRect(v, paint);
  }

  /// 1.4.0 optim #2 — paint() is called per-frame; without a guard
  /// we'd fire a fresh microtask + duplicate `BrushTexture.load`
  /// call every frame until the texture lands in the cache. Track
  /// in-flight loads here so each `TextureType` triggers at most
  /// one outstanding microtask.
  static final Set<TextureType> _kickInFlight = <TextureType>{};

  /// Async-fire the texture load on first paint. The image lands
  /// in `BrushTexture._cache` and the canvas picks it up on the
  /// next repaint cycle (driven by the canvas's commit ticker).
  static void _textureLoadKick(TextureType type) {
    if (_kickInFlight.contains(type)) return;
    _kickInFlight.add(type);
    // Fire-and-forget: BrushTexture.load is idempotent + cached.
    // Wrap in a microtask so we don't block the paint thread.
    Future<void>.microtask(() async {
      try {
        await BrushTexture.load(type);
      } finally {
        _kickInFlight.remove(type);
      }
    });
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
      other.dotRadius == dotRadius &&
      other.paperType == paperType;

  @override
  int get hashCode => Object.hash(
        _type,
        fill,
        lineColor,
        spacing,
        lineWidth,
        dotRadius,
        paperType,
      );
}

enum _Type { solid, grid, dotted, lined, paperGrain }
