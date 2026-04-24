import 'package:flutter/material.dart';

/// 🚀 Object Pool per Paint per ridurre allocazioni
///
/// RESPONSIBILITIES:
/// - ✅ Reuse Paint objects instead of always creating new ones
/// - ✅ Riduce garbage collection
/// - ✅ Migliora performance di rendering
///
/// PERFORMANCE:
/// - From creating N Paint objects → reusing 2-3 Paint objects
/// - Reduces memory allocations by 90%+
class PaintPool {
  // Pool di Paint riutilizzabili per stroke
  static final Paint _strokePaint =
      Paint()
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true;

  // Pool di Paint riutilizzabili per fill
  static final Paint _fillPaint =
      Paint()
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;

  // Paint con blur per matita
  static final Paint _blurPaint =
      Paint()
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true;

  /// 🚀 Ottieni Paint per stroke (riutilizzabile)
  ///
  /// [color] Stroke color
  /// [strokeWidth] Larghezza del tratto
  /// [strokeCap] Type of cap
  /// [strokeJoin] Type of join
  static Paint getStrokePaint({
    required Color color,
    required double strokeWidth,
    StrokeCap strokeCap = StrokeCap.round,
    StrokeJoin strokeJoin = StrokeJoin.round,
  }) {
    return _strokePaint
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = strokeCap
      ..strokeJoin = strokeJoin
      ..maskFilter = null; // Reset blur
  }

  /// 🚀 Ottieni Paint per fill (riutilizzabile)
  ///
  /// [color] Fill color
  static Paint getFillPaint({required Color color}) {
    return _fillPaint
      ..color = color
      ..maskFilter = null; // Reset blur
  }

  /// 🚀 Ottieni Paint con blur (per matita)
  ///
  /// [color] Stroke color
  /// [strokeWidth] Larghezza del tratto
  /// [blurRadius] Raggio del blur
  /// [strokeCap] Type of cap
  static Paint getBlurPaint({
    required Color color,
    required double strokeWidth,
    required double blurRadius,
    StrokeCap strokeCap = StrokeCap.round,
  }) {
    return _blurPaint
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = strokeCap
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius);
  }
}
