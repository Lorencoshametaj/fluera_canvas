// ════════════════════════════════════════════════════════════════════════════
// 🎨 fluera_canvas — professional 2D canvas SDK for Flutter.
//
// Public barrel. Anything exported from here is part of the SDK's semver
// contract. Anything inside `src/` without a corresponding export line is
// internal and may change at any time.
//
// Version: 0.1.0 (pre-release). Until 1.0.0 the API is considered unstable.
// ════════════════════════════════════════════════════════════════════════════

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
