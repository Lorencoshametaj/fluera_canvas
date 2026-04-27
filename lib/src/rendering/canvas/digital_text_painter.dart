import 'package:flutter/material.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

/// 🎨 Painter for rendering digital text elements directly on the Canvas.
///
/// 🚀 PERFORMANCE: Reuses [DigitalTextElement.layoutPainter] instead of
/// creating new TextPainter/TextSpan objects per element per frame.
/// Layout is done lazily in the element itself and cached across frames.
class DigitalTextPainter extends CustomPainter {
  /// Field `texts`.
  final List<DigitalTextElement> texts;
  /// Field `canvasOffset`.
  final Offset canvasOffset;
  /// Field `canvasScale`.
  final double canvasScale;
  /// Field `selectedElementId`.
  final String? selectedElementId;

  /// API element `DigitalTextPainter`.
  DigitalTextPainter({
    required this.texts,
    required this.canvasOffset,
    required this.canvasScale,
    this.selectedElementId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (texts.isEmpty) return;

    canvas.save();
    // Apply same transformation as strokes
    canvas.translate(canvasOffset.dx, canvasOffset.dy);
    canvas.scale(canvasScale);

    for (final element in texts) {
      // 🚀 Reuse cached TextPainter — no allocation in paint()
      element.layoutPainter.paint(canvas, element.position);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DigitalTextPainter oldDelegate) {
    // Fast path: viewport transform changed
    if (oldDelegate.canvasOffset != canvasOffset ||
        oldDelegate.canvasScale != canvasScale ||
        oldDelegate.selectedElementId != selectedElementId) {
      return true;
    }
    // Element list check: length + identity
    if (oldDelegate.texts.length != texts.length) return true;
    if (!identical(oldDelegate.texts, texts)) return true;
    return false;
  }
}
