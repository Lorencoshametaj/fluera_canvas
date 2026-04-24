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
export 'src/core/engine_event.dart';
export 'src/core/engine_event_bus.dart';

// Scene graph observer (canvas-side; works with any EngineEventBus).
export 'src/core/scene_graph/scene_graph_observer.dart';

// Scene graph core — node tree, visitor double-dispatch, mixins,
// base node types. The SceneGraph class itself still lives in engine
// until Ondata 3c finishes the EngineScope bridge refactor.
export 'src/core/scene_graph/canvas_node.dart';
export 'src/core/scene_graph/canvas_node_factory.dart';
export 'src/core/scene_graph/node_visitor.dart';
export 'src/core/scene_graph/frozen_node_view.dart';
export 'src/core/scene_graph/paint_stack_mixin.dart';
export 'src/core/scene_graph/scene_graph_interceptor.dart';
export 'src/core/scene_graph/transform_bridge.dart';
export 'src/core/scene_graph/node_constraint.dart';
export 'src/core/scene_graph/content_origin.dart';
export 'src/core/scene_graph/invalidation_graph.dart';
export 'src/core/scene_graph/node_id.dart';

// Base nodes (group / layer / shape / stroke / text / image / path).
export 'src/core/nodes/group_node.dart';
export 'src/core/nodes/layer_node.dart';
export 'src/core/nodes/shape_node.dart';
export 'src/core/nodes/stroke_node.dart';
export 'src/core/nodes/text_node.dart';
export 'src/core/nodes/image_node.dart';
export 'src/core/nodes/path_node.dart';

// Node effects + paint extensions.
export 'src/core/effects/node_effect.dart';
export 'src/core/effects/shader_effect.dart';
export 'src/core/effects/shader_effect_wrapper.dart';
export 'src/core/effects/mesh_gradient.dart';

// Core models consumed by base nodes.
export 'src/core/models/digital_text_element.dart';
export 'src/core/models/image_element.dart';
export 'src/core/models/text_overlay.dart';
export 'src/core/models/tone_curve.dart';
export 'src/core/models/color_adjustments.dart';
export 'src/core/models/gradient_filter.dart';
export 'src/core/models/perspective_settings.dart';
export 'src/core/models/export_settings.dart';

// Vector geometry shared by path / shape nodes.
export 'src/core/vector/vector_path.dart';

// Accessibility tree — consumed by CanvasNode via semantic labels.
export 'src/systems/accessibility_tree.dart';

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

// Rendering configuration + optimization primitives.
export 'src/rendering/lod_config.dart';
export 'src/rendering/optimization/spatial_index.dart';
export 'src/rendering/optimization/viewport_culler.dart';
export 'src/rendering/optimization/stroke_optimizer.dart';
export 'src/rendering/optimization/optimized_path_builder.dart';
export 'src/rendering/optimization/paint_pool.dart';
export 'src/rendering/optimization/dirty_region_tracker.dart';

// Scene graph rendering leaves.
export 'src/rendering/scene_graph/path_renderer.dart';
export 'src/rendering/scene_graph/render_batch.dart';

// Canvas painters that have no app-layer dependencies.
export 'src/rendering/canvas/shape_painter.dart';
export 'src/rendering/canvas/digital_text_painter.dart';
export 'src/rendering/canvas/origin_indicator_painter.dart';
export 'src/rendering/canvas/paper_pattern_painter.dart';
export 'src/rendering/canvas/paper_grain_painter.dart';

// Brush infrastructure (texture sampler). Concrete brush engines remain
// in fluera_engine because they depend on EngineScope / GPU shader services.
export 'src/drawing/brushes/brush_texture.dart';

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
