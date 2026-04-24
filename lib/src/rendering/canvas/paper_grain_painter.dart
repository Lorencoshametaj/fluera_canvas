import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../drawing/brushes/brush_texture.dart';

/// 🎨 Paper type for the canvas background
enum PaperType {
  smooth, // Carta liscia (nessuna grana)
  coldPress, // Carta pressata a freddo (grana media)
  hotPress, // Carta pressata a caldo (grana fine)
  canvas, // Tela pittura (grana regolare)
  kraft, // Carta kraft (grana con fibre)
}

/// 🎨 Paper Grain Painter
///
/// Render una texture di carta tiled dietro gli strokes on the canvas.
/// The texture is applied as a semi-transparent overlay.
///
/// Usage: add as CustomPaint layer below DrawingPainter.
class PaperGrainPainter extends CustomPainter {
  /// Paper type
  final PaperType paperType;

  /// Grain opacity (0.0 = invisible, 1.0 = full)
  final double opacity;

  /// Scala of the texture (adattata allo zoom)
  final double scale;

  /// If true, la texture is stata caricata ed is pronta
  final ui.Image? textureImage;

  const PaperGrainPainter({
    required this.paperType,
    this.opacity = 0.15,
    this.scale = 1.0,
    this.textureImage,
  });

  /// Mappa PaperType → TextureType for the caricamento
  static TextureType textureTypeForPaper(PaperType paper) {
    switch (paper) {
      case PaperType.smooth:
        return TextureType.none;
      case PaperType.coldPress:
        return TextureType.pencilGrain;
      case PaperType.hotPress:
        return TextureType.watercolor;
      case PaperType.canvas:
        return TextureType.canvas;
      case PaperType.kraft:
        return TextureType.kraft;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (paperType == PaperType.smooth || textureImage == null || opacity <= 0) {
      return;
    }

    final texturePaint = BrushTexture.createTexturePaint(
      textureImage: textureImage!,
      intensity: opacity,
      scale: scale,
    );
    if (texturePaint == null) return;

    // Draw the texture over the entire visible area
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), texturePaint);
  }

  @override
  bool shouldRepaint(PaperGrainPainter oldDelegate) {
    return oldDelegate.paperType != paperType ||
        oldDelegate.opacity != opacity ||
        oldDelegate.scale != scale ||
        oldDelegate.textureImage != textureImage;
  }
}
