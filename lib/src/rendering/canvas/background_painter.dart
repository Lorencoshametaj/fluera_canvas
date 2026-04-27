import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:fluera_canvas/fluera_canvas.dart';

/// 🎨 BACKGROUND PAINTER - Viewport-level rendering per canvas infinito
///
/// ARCHITETTURA:
/// - ✅ Render at viewport level (outside Transform)
/// - ✅ Covers ALL directions (including negative coordinates)
/// - ✅ Only visible tiles printed (~4-9 per frame)
///
/// PERFORMANCE:
/// - 🚀 repaint: controller → paint() called on every pan/zoom frame
/// - 🚀 Per-frame cost: ~10 draw calls (negligible)
/// - 🚀 Wrapped in RepaintBoundary → no cascade to siblings
class BackgroundPainter extends CustomPainter {
  final String paperType;
  final Color backgroundColor;
  final InfiniteCanvasController controller;

  // 🚀 TILE CACHE: a single small tile to print repeatedly
  static ui.Picture? _cachedTile;
  static String? _cachedPaperType;
  static Color? _cachedBackgroundColor;
  static double _cachedTileSize = _tileSize;
  static const double _tileSize = 1000.0;

  // 1cm = 37.8px (96 DPI standard)
  static const double _patternScale = 37.8;

  BackgroundPainter({
    required this.paperType,
    required this.backgroundColor,
    required this.controller,
  }) : super(repaint: controller);

  @override
  void paint(Canvas canvas, Size size) {
    // 1️⃣ Solid background on the entire viewport
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = backgroundColor,
    );

    // 2️⃣ Se is blank, non serve disegnare il pattern
    if (paperType == 'blank') return;

    // Delegate to static method for reuse by DrawingPainter
    paintTilesStatic(canvas, size, paperType, backgroundColor, controller);
  }

  /// 🚀 LAYER MERGE: Static method for rendering background tiles.
  /// Called by both BackgroundPainter.paint() and DrawingPainter.paint().
  static void paintTilesStatic(
    Canvas canvas,
    Size size,
    String paperType,
    Color backgroundColor,
    InfiniteCanvasController controller,
  ) {
    // Genera/aggiorna tile cache
    _regenerateTileIfNeededStatic(paperType, backgroundColor);

    // Viewport-level tile rendering
    final canvasScale = controller.scale;
    final canvasOffset = controller.offset;
    final rotation = controller.rotation;
    final scaledTileSize = _cachedTileSize * canvasScale;
    final originScreenX = canvasOffset.dx;
    final originScreenY = canvasOffset.dy;

    // Compute visible tile range.
    // When the canvas is rotated, the axis-aligned viewport rectangle covers
    // a larger area in canvas space. We transform all 4 viewport corners
    // through the INVERSE canvas transform to find the AABB in canvas space,
    // then convert to tile indices.
    int firstTileX, firstTileY, lastTileX, lastTileY;

    if (rotation == 0.0) {
      // Fast path: no rotation — simple axis-aligned calculation
      firstTileX = ((0 - originScreenX) / scaledTileSize).floor();
      firstTileY = ((0 - originScreenY) / scaledTileSize).floor();
      lastTileX = ((size.width - originScreenX) / scaledTileSize).ceil();
      lastTileY = ((size.height - originScreenY) / scaledTileSize).ceil();
    } else {
      // Slow path: rotation — compute AABB of rotated viewport in canvas space.
      // Inverse transform: un-translate → un-rotate → result is in canvas space.
      final cosR = math.cos(-rotation);
      final sinR = math.sin(-rotation);

      // Viewport corners in screen space
      final corners = [
        Offset.zero,
        Offset(size.width, 0),
        Offset(size.width, size.height),
        Offset(0, size.height),
      ];

      double minCX = double.infinity, minCY = double.infinity;
      double maxCX = double.negativeInfinity, maxCY = double.negativeInfinity;

      for (final corner in corners) {
        // Un-translate (remove canvas origin offset)
        final dx = corner.dx - originScreenX;
        final dy = corner.dy - originScreenY;
        // Un-rotate
        final cx = dx * cosR - dy * sinR;
        final cy = dx * sinR + dy * cosR;

        if (cx < minCX) minCX = cx;
        if (cy < minCY) minCY = cy;
        if (cx > maxCX) maxCX = cx;
        if (cy > maxCY) maxCY = cy;
      }

      firstTileX = (minCX / scaledTileSize).floor() - 1;
      firstTileY = (minCY / scaledTileSize).floor() - 1;
      lastTileX = (maxCX / scaledTileSize).ceil() + 1;
      lastTileY = (maxCY / scaledTileSize).ceil() + 1;
    }

    // 🌀 FADE: Smooth opacity transition when zooming out.
    // Below 36 tiles: full opacity. 36→80: linear fade. Above 80: invisible.
    final tileCount =
        (lastTileX - firstTileX + 1) * (lastTileY - firstTileY + 1);
    if (tileCount > 80) return; // Hard cap — fully invisible

    const fadeStart = 36;
    const fadeEnd = 80;
    final patternOpacity =
        tileCount <= fadeStart
            ? 1.0
            : 1.0 -
                ((tileCount - fadeStart) / (fadeEnd - fadeStart)).clamp(
                  0.0,
                  1.0,
                );

    // Apply canvas transform (translate + rotate) then print tiles
    canvas.save();

    // 🌀 FADE: If fading, wrap in saveLayer with alpha modulation.
    // saveLayer composites the layer back using paint.color.alpha.
    if (patternOpacity < 1.0) {
      canvas.saveLayer(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()
          ..color = Color.fromARGB(
            (patternOpacity * 255).round(),
            255,
            255,
            255,
          ),
      );
    }

    canvas.translate(originScreenX, originScreenY);
    if (rotation != 0.0) {
      canvas.rotate(rotation);
    }

    for (int ty = firstTileY; ty <= lastTileY; ty++) {
      for (int tx = firstTileX; tx <= lastTileX; tx++) {
        final tileX = tx * scaledTileSize;
        final tileY = ty * scaledTileSize;

        canvas.save();
        canvas.translate(tileX, tileY);
        canvas.scale(canvasScale);
        canvas.drawPicture(_cachedTile!);
        canvas.restore();
      }
    }

    if (patternOpacity < 1.0) {
      canvas.restore(); // saveLayer
    }
    canvas.restore();
  }

  /// Static version of tile regeneration for use by paintTilesStatic
  static void _regenerateTileIfNeededStatic(
    String paperType,
    Color backgroundColor,
  ) {
    final needsRegeneration =
        _cachedTile == null ||
        _cachedPaperType != paperType ||
        _cachedBackgroundColor != backgroundColor;

    if (!needsRegeneration) return;

    final oldTile = _cachedTile;

    // 🔧 Calculate tile size aligned to grid to avoid
    // linee spurie ai bordi tra tile adiacenti.
    final alignedTileSize = _computeAlignedTileSize(paperType, _patternScale);

    final recorder = ui.PictureRecorder();
    final recordCanvas = Canvas(recorder);

    final tilePainter = PaperPatternPainter(
      paperType: paperType,
      backgroundColor: backgroundColor,
      scale: _patternScale,
    );

    tilePainter.paint(recordCanvas, Size(alignedTileSize, alignedTileSize));

    _cachedTile = recorder.endRecording();
    _cachedPaperType = paperType;
    _cachedBackgroundColor = backgroundColor;
    _cachedTileSize = alignedTileSize;

    if (oldTile != null) {
      Future.microtask(() => oldTile.dispose());
    }
  }

  /// Calculates la size of the tile allineata allo spacing del pattern.
  static double _computeAlignedTileSize(String paperType, double scale) {
    double? baseSpacing;
    switch (paperType) {
      case 'grid_5mm':
        baseSpacing = 5.0;
        break;
      case 'grid_1cm':
        baseSpacing = 10.0;
        break;
      case 'grid_2cm':
        baseSpacing = 20.0;
        break;
      case 'dots':
        baseSpacing = 20.0;
        break;
      case 'dots_dense':
        baseSpacing = 10.0;
        break;
      case 'graph':
        baseSpacing = 10.0;
        break;
      case 'hex':
        baseSpacing = 20.0;
        break;
      case 'isometric':
        baseSpacing = 20.0;
        break;
      default:
        return _tileSize;
    }

    final gridPitch = baseSpacing * scale;
    final tilesNeeded = (500.0 / gridPitch).ceil().clamp(1, 100);
    return gridPitch * tilesNeeded;
  }

  @override
  bool shouldRepaint(BackgroundPainter oldDelegate) {
    return oldDelegate.paperType != paperType ||
        oldDelegate.backgroundColor != backgroundColor;
  }

  /// 🗑️ Pulisce la cache statica (chiamare when chiude il canvas)
  static void clearCache() {
    _cachedTile?.dispose();
    _cachedTile = null;
    _cachedPaperType = null;
    _cachedBackgroundColor = null;
    _cachedTileSize = _tileSize;
  }
}
