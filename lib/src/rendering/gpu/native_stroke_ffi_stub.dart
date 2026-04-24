// ═══════════════════════════════════════════════════════════════════
// 🌐 NativeStrokeFfi STUB — No-op for web platform
//
// Web uses WebGPU via js_interop, not dart:ffi.
// This stub ensures vulkan_stroke_overlay_service.dart compiles on web.
// ═══════════════════════════════════════════════════════════════════

import 'dart:ui' as ui;
import 'package:fluera_canvas/fluera_canvas.dart';

class NativeStrokeFfi {
  bool get isInitialized => false;

  bool init() => false;

  void updateAndRender(
    List<ProDrawingPoint> points,
    int startIndex,
    ui.Color color,
    double strokeWidth,
    int totalPoints, {
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
    double zoomScale = 1.0,
  }) {}

  void setTransform(
    InfiniteCanvasController controller,
    int width,
    int height, [
    double dpr = 1.0,
    ui.Offset canvasOrigin = ui.Offset.zero,
  ]) {}

  void clear() {}

  void dispose() {}

  // 🚀 Ring buffer stubs (no-op on web)
  bool updateAndRenderIncremental(
    List<ProDrawingPoint> points,
    ui.Color color,
    double strokeWidth,
    int totalPoints, {
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
    double zoomScale = 1.0,
  }) => false;

  void resetRing() {}
}
