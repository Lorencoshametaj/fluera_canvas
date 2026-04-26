import 'package:flutter/material.dart';
import 'dart:ui' as ui;

/// 🖼️ Painter per disegnare l'background image
class BackgroundImagePainter extends CustomPainter {
  final ui.Image image;
  final bool isImageEditMode;
  final Size?
  viewportSize; // Viewport dimensions for scaling in image edit mode

  BackgroundImagePainter({
    required this.image,
    this.isImageEditMode = false,
    this.viewportSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Dimensioni of the image
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();


    final srcRect = Rect.fromLTWH(0, 0, imageWidth, imageHeight);

    // In image edit mode from infinite canvas, the canvas is already the image size
    // Quindi disegna l'immagine a size piena
    final dstRect = Rect.fromLTWH(0, 0, imageWidth, imageHeight);

    canvas.drawImageRect(image, srcRect, dstRect, Paint());
  }

  @override
  bool shouldRepaint(BackgroundImagePainter oldDelegate) {
    return image != oldDelegate.image ||
        isImageEditMode != oldDelegate.isImageEditMode ||
        viewportSize != oldDelegate.viewportSize;
  }
}

/// Painter for full-screen dark overlay with holes for pages
class FullScreenDarkOverlayPainter extends CustomPainter {
  final List<Rect> pageBounds;
  final double canvasScale;
  final Offset canvasOffset;

  FullScreenDarkOverlayPainter({
    required this.pageBounds,
    required this.canvasScale,
    required this.canvasOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = Colors.black.withValues(alpha:  0.6)
          ..style = PaintingStyle.fill;

    // Create path per l'intero overlay
    final overlayPath =
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Create path per i buchi (aree of pages)
    final holePath = Path();
    for (final bounds in pageBounds) {
      final screenBounds = Rect.fromLTWH(
        bounds.left * canvasScale + canvasOffset.dx,
        bounds.top * canvasScale + canvasOffset.dy,
        bounds.width * canvasScale,
        bounds.height * canvasScale,
      );
      holePath.addRect(screenBounds);
    }

    // Combine i path usando differenza
    final combinedPath = Path.combine(
      PathOperation.difference,
      overlayPath,
      holePath,
    );

    canvas.drawPath(combinedPath, paint);
  }

  @override
  bool shouldRepaint(covariant FullScreenDarkOverlayPainter oldDelegate) {
    return pageBounds != oldDelegate.pageBounds ||
        canvasScale != oldDelegate.canvasScale ||
        canvasOffset != oldDelegate.canvasOffset;
  }
}
