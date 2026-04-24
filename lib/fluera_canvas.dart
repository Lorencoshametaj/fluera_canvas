// ════════════════════════════════════════════════════════════════════════════
// 🎨 fluera_canvas — professional 2D canvas SDK for Flutter.
//
// Public barrel. Anything exported from here is part of the SDK's semver
// contract. Anything inside `src/` without a corresponding export line is
// internal and may change at any time.
//
// Version: 0.1.0 (pre-release). Until 1.0.0 the API is considered unstable.
// ════════════════════════════════════════════════════════════════════════════

// Core utilities + error model.
export 'src/utils/uid.dart';
export 'src/core/schema_version.dart';
export 'src/core/engine_error.dart';
export 'src/core/engine_telemetry.dart';

// Scene graph leaf primitives.
export 'src/core/scene_graph/content_origin.dart';
export 'src/core/scene_graph/invalidation_graph.dart';
export 'src/core/scene_graph/node_id.dart';

// Paint / gradient primitives (stack order, fill definitions).
export 'src/core/effects/gradient_fill.dart';
export 'src/core/effects/paint_stack.dart';

// Shape enum.
export 'src/core/models/shape_type.dart';

// Drawing data models — coordinates, pressure, brush presets.
export 'src/drawing/models/pro_drawing_point.dart';
export 'src/drawing/models/pressure_curve.dart';
export 'src/drawing/models/velocity_curve.dart';
export 'src/drawing/models/brush_preset.dart';
export 'src/drawing/models/pro_brush_settings.dart';

// Rendering configuration primitives.
export 'src/rendering/lod_config.dart';

// Infinite canvas camera / physics controller.
export 'src/canvas/liquid_canvas_config.dart';
export 'src/canvas/infinite_canvas_controller.dart';
export 'src/canvas/infinite_canvas_gesture_detector.dart';
export 'src/canvas/stylus_hover_tracker.dart';

// Drawing input primitives.
export 'src/drawing/input/stylus_detector.dart' show StylusDetector;
export 'src/drawing/input/palm_rejection_policy.dart';

// Platform utilities.
export 'src/utils/platform_guard.dart' show PlatformGuard;

// GPU live-stroke bridges (engine-agnostic Dart side — native platform
// code still ships via fluera_engine's plugin until Ondata 6 moves it).
export 'src/rendering/memory_pressure.dart';
export 'src/rendering/gpu/vulkan_stroke_overlay_service.dart';
export 'src/rendering/gpu/webgpu_stroke_overlay_service.dart';
export 'src/rendering/gpu/webgpu_overlay_view.dart' show WebGpuOverlayView;
export 'src/drawing/input/input_predictor.dart';
export 'src/drawing/input/raw_input_processor_120hz.dart';

// Drawing filters (pressure-aware smoothing, prediction, noise generators).
export 'src/drawing/filters/one_euro_filter.dart';
export 'src/drawing/filters/advanced_one_euro_filter.dart';
export 'src/drawing/filters/dynamic_pressure_mapper.dart';
export 'src/drawing/filters/organic_noise.dart';
export 'src/drawing/filters/physics_ink_simulator.dart';
export 'src/drawing/filters/post_stroke_optimizer.dart';
export 'src/drawing/filters/predictive_renderer.dart';

// Public SDK façade for the native live-stroke pipeline.
export 'src/rendering/native_stroke_overlay.dart'
    show NativeStrokeOverlay, NativeStrokeOverlayController;
