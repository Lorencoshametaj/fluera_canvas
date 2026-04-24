// ════════════════════════════════════════════════════════════════════════════
// 🎨 fluera_canvas — professional 2D canvas SDK for Flutter.
//
// Public barrel. Anything exported from here is part of the SDK's semver
// contract. Anything inside `src/` without a corresponding export line is
// internal and may change at any time.
//
// Version: 0.1.0 (pre-release). Until 1.0.0 the API is considered unstable.
// ════════════════════════════════════════════════════════════════════════════

// ─── CORE UTILITIES ────────────────────────────────────────────────────────

export 'src/utils/uid.dart';
export 'src/utils/platform_guard.dart' show PlatformGuard;
export 'src/core/schema_version.dart';
export 'src/core/engine_error.dart';
export 'src/core/engine_telemetry.dart';
export 'src/core/engine_event.dart';
export 'src/core/engine_event_bus.dart';

// ─── CANVAS + CAMERA ───────────────────────────────────────────────────────

export 'src/canvas/infinite_canvas_controller.dart';
export 'src/canvas/infinite_canvas_gesture_detector.dart';
export 'src/canvas/liquid_canvas_config.dart';
export 'src/canvas/stylus_hover_tracker.dart';

// ─── DRAWING INPUT + FILTERS ───────────────────────────────────────────────

export 'src/drawing/input/stylus_detector.dart' show StylusDetector;
export 'src/drawing/input/palm_rejection_policy.dart';
export 'src/drawing/input/input_predictor.dart';
export 'src/drawing/input/raw_input_processor_120hz.dart';

export 'src/drawing/filters/one_euro_filter.dart';
export 'src/drawing/filters/advanced_one_euro_filter.dart';
export 'src/drawing/filters/dynamic_pressure_mapper.dart';
export 'src/drawing/filters/organic_noise.dart';
export 'src/drawing/filters/physics_ink_simulator.dart';
export 'src/drawing/filters/post_stroke_optimizer.dart';
export 'src/drawing/filters/predictive_renderer.dart';

// ─── DRAWING MODELS ────────────────────────────────────────────────────────

export 'src/drawing/models/pro_drawing_point.dart';
export 'src/drawing/models/pressure_curve.dart';
export 'src/drawing/models/velocity_curve.dart';
export 'src/drawing/models/brush_preset.dart';
export 'src/drawing/models/pro_brush_settings.dart';
export 'src/drawing/brushes/brush_texture.dart';

// ─── SCENE GRAPH CORE ──────────────────────────────────────────────────────
//
// The `SceneGraph` class itself still lives in fluera_engine (it depends on
// EngineScope + design variables). Base nodes, visitor, factory, and the
// immutable helpers are all exported here.

export 'src/core/scene_graph/canvas_node.dart';
export 'src/core/scene_graph/canvas_node_factory.dart';
export 'src/core/scene_graph/node_visitor.dart';
export 'src/core/scene_graph/frozen_node_view.dart';
export 'src/core/scene_graph/paint_stack_mixin.dart';
export 'src/core/scene_graph/scene_graph_interceptor.dart';
export 'src/core/scene_graph/scene_graph_observer.dart';
export 'src/core/scene_graph/transform_bridge.dart';
export 'src/core/scene_graph/node_constraint.dart';
export 'src/core/scene_graph/content_origin.dart';
export 'src/core/scene_graph/invalidation_graph.dart';
export 'src/core/scene_graph/node_id.dart';

// ─── BASE NODES ────────────────────────────────────────────────────────────

export 'src/core/nodes/group_node.dart';
export 'src/core/nodes/layer_node.dart';
export 'src/core/nodes/shape_node.dart';
export 'src/core/nodes/stroke_node.dart';
export 'src/core/nodes/text_node.dart';
export 'src/core/nodes/image_node.dart';
export 'src/core/nodes/path_node.dart';

// ─── EFFECTS + PAINT STACK ─────────────────────────────────────────────────

export 'src/core/effects/node_effect.dart';
export 'src/core/effects/shader_effect.dart';
export 'src/core/effects/shader_effect_wrapper.dart';
export 'src/core/effects/mesh_gradient.dart';
export 'src/core/effects/gradient_fill.dart';
export 'src/core/effects/paint_stack.dart';

// ─── CORE MODELS ───────────────────────────────────────────────────────────

export 'src/core/models/shape_type.dart';
export 'src/core/models/canvas_layer.dart';
export 'src/core/models/digital_text_element.dart';
export 'src/core/models/image_element.dart';
export 'src/core/models/export_settings.dart';
export 'src/core/models/text_overlay.dart';
export 'src/core/models/tone_curve.dart';
export 'src/core/models/color_adjustments.dart';
export 'src/core/models/gradient_filter.dart';
export 'src/core/models/perspective_settings.dart';
export 'src/core/vector/vector_path.dart';

// ─── ACCESSIBILITY ─────────────────────────────────────────────────────────

export 'src/systems/accessibility_tree.dart';

// ─── RENDERING ─────────────────────────────────────────────────────────────

export 'src/rendering/lod_config.dart';
export 'src/rendering/memory_pressure.dart';

// Optimization primitives.
export 'src/rendering/optimization/spatial_index.dart';
export 'src/rendering/optimization/viewport_culler.dart';
export 'src/rendering/optimization/stroke_optimizer.dart';
export 'src/rendering/optimization/optimized_path_builder.dart';
export 'src/rendering/optimization/paint_pool.dart';
export 'src/rendering/optimization/dirty_region_tracker.dart';

// Scene graph renderers.
export 'src/rendering/scene_graph/path_renderer.dart';
export 'src/rendering/scene_graph/render_batch.dart';

// Leaf painters (no engine-layer dependencies).
export 'src/rendering/canvas/shape_painter.dart';
export 'src/rendering/canvas/digital_text_painter.dart';
export 'src/rendering/canvas/origin_indicator_painter.dart';
export 'src/rendering/canvas/paper_pattern_painter.dart';
export 'src/rendering/canvas/paper_grain_painter.dart';

// ─── GPU LIVE-STROKE BRIDGE ────────────────────────────────────────────────
//
// Dart-side bridge to the native platform renderers (Vulkan / Metal / GL /
// D3D11 / WebGPU). The native plugin code still ships via fluera_engine
// until Ondata 6 moves it into this package.

export 'src/rendering/gpu/vulkan_stroke_overlay_service.dart';
// WebGPU service unconditionally imports dart:js_interop + package:web —
// which doesn't type-check on non-web. Fall back to the stub everywhere
// except web so native builds compile.
export 'src/rendering/gpu/webgpu_stroke_overlay_service_stub.dart'
    if (dart.library.js_interop) 'src/rendering/gpu/webgpu_stroke_overlay_service.dart';
export 'src/rendering/gpu/webgpu_overlay_view.dart' show WebGpuOverlayView;
export 'src/rendering/native_stroke_overlay.dart'
    show NativeStrokeOverlay, NativeStrokeOverlayController;

// ─── EXPORT + IMPORT ───────────────────────────────────────────────────────

export 'src/export/binary_canvas_format.dart';
export 'src/export/raster_image_encoder.dart';
export 'src/export/raster_encoder_channel.dart';
export 'src/export/export_preset.dart';
export 'src/export/fluera_file_format.dart';
export 'src/export/fluera_file_export_service.dart';
export 'src/export/pdf_export_models.dart';
export 'src/export/svg_importer.dart';
export 'src/export/timelapse_export_config.dart';
