// ═══════════════════════════════════════════════════════════════════
// 🌐 WebGpuStrokeOverlayService — Stub for non-web platforms
//
// Provides the same API surface so conditional imports work,
// but all methods are no-ops. This file is never used at runtime
// on native platforms.
// ═══════════════════════════════════════════════════════════════════

import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';

import 'package:fluera_canvas/fluera_canvas.dart';

class WebGpuStrokeOverlayService {
  bool get isInitialized => false;
  Future<bool> get isAvailable async => false;

  Future<bool> init(int width, int height) async => false;

  void updateAndRender(
    List<ProDrawingPoint> points,
    ui.Color color,
    double strokeWidth, {
    bool force = false,
    int brushType = 0,
    double pencilBaseOpacity = 0.4,
    double pencilMaxOpacity = 0.8,
    double pencilMinPressure = 0.5,
    double pencilMaxPressure = 1.2,
    double fountainThinning = 0.5,
    double fountainNibAngleDeg = 30.0,
    double fountainNibStrength = 0.35,
    double fountainPressureRate = 0.275,
    int fountainTaperEntry = 6,
  }) {}

  void setTransform(InfiniteCanvasController controller, int width, int height,
      [double dpr = 1.0]) {}

  void clear() {}
  bool resize(int width, int height) => false;
  void dispose() {}
}
