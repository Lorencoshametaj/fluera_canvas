import 'dart:ui' as ui;
import '../scene_graph/canvas_node.dart';
import 'package:fluera_canvas/fluera_canvas.dart';
import '../scene_graph/node_visitor.dart';

/// A uniform value that can be passed to a fragment shader.
///
/// Uniforms are the primary way to parameterize shader effects.
sealed class ShaderUniform {
  final String name;
  const ShaderUniform(this.name);

  Map<String, dynamic> toJson();

  static ShaderUniform fromJson(Map<String, dynamic> json) {
    switch (json['type'] as String) {
      case 'float':
        return FloatUniform(
          json['name'] as String,
          (json['value'] as num).toDouble(),
        );
      case 'vec2':
        return Vec2Uniform(
          json['name'] as String,
          (json['x'] as num).toDouble(),
          (json['y'] as num).toDouble(),
        );
      case 'vec4':
        return Vec4Uniform(
          json['name'] as String,
          (json['x'] as num).toDouble(),
          (json['y'] as num).toDouble(),
          (json['z'] as num).toDouble(),
          (json['w'] as num).toDouble(),
        );
      case 'color':
        return ColorUniform(
          json['name'] as String,
          ui.Color(json['value'] as int),
        );
      default:
        throw ArgumentError('Unknown uniform type: ${json['type']}');
    }
  }
}

/// A single float uniform.
class FloatUniform extends ShaderUniform {
  double value;
  FloatUniform(super.name, this.value);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'float',
    'name': name,
    'value': value,
  };
}

/// A vec2 (2D vector) uniform.
class Vec2Uniform extends ShaderUniform {
  double x;
  double y;
  Vec2Uniform(super.name, this.x, this.y);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'vec2',
    'name': name,
    'x': x,
    'y': y,
  };
}

/// A vec4 (4D vector) uniform.
class Vec4Uniform extends ShaderUniform {
  double x;
  double y;
  double z;
  double w;
  Vec4Uniform(super.name, this.x, this.y, this.z, this.w);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'vec4',
    'name': name,
    'x': x,
    'y': y,
    'z': z,
    'w': w,
  };
}

/// A color uniform (passed as vec4 r, g, b, a to shader).
class ColorUniform extends ShaderUniform {
  ui.Color value;
  ColorUniform(super.name, this.value);

  @override
  Map<String, dynamic> toJson() => {
    'type': 'color',
    'name': name,
    'value': value.toARGB32(),
  };
}

/// Preset shader effect types.
enum ShaderPreset {
  /// Perlin/simplex noise pattern.
  noise,

  /// Voronoi cell pattern.
  voronoi,

  /// RGB channel offset effect.
  chromaticAberration,

  /// Digital glitch/distortion effect.
  glitch,

  /// Map brightness to a color gradient.
  gradientMap,

  /// Pixelate/mosaic effect.
  pixelate,

  /// Vignette (darkened edges).
  vignette,

  /// Custom user-provided shader.
  custom,
}

/// A shader-based effect that uses a GPU fragment program.
///
/// Can be used as a node effect (applied to a node's output) or
/// as a standalone [ShaderNode] that fills its bounds with the shader.
///
/// ```dart
/// final effect = ShaderEffect(
///   preset: ShaderPreset.noise,
///   uniforms: [
///     FloatUniform('scale', 10.0),
///     FloatUniform('speed', 1.5),
///     ColorUniform('tint', Colors.blue),
///   ],
/// );
/// ```
class ShaderEffect {
  /// Shader preset or custom shader.
  ShaderPreset preset;

  /// Asset path for custom shader SPIR-V (when preset == custom).
  String? shaderAssetPath;

  /// User-configurable uniforms.
  final List<ShaderUniform> uniforms;

  /// Whether the shader is enabled.
  bool isEnabled;

  /// Blend mode when compositing the shader output.
  ui.BlendMode blendMode;

  /// Opacity of the shader effect.
  double opacity;

  ShaderEffect({
    this.preset = ShaderPreset.custom,
    this.shaderAssetPath,
    List<ShaderUniform>? uniforms,
    this.isEnabled = true,
    this.blendMode = ui.BlendMode.srcOver,
    this.opacity = 1.0,
  }) : uniforms = uniforms ?? [];

  /// Set a float uniform by name.
  void setFloat(String name, double value) {
    for (final u in uniforms) {
      if (u is FloatUniform && u.name == name) {
        u.value = value;
        return;
      }
    }
    uniforms.add(FloatUniform(name, value));
  }

  /// Get a float uniform value by name.
  double? getFloat(String name) {
    for (final u in uniforms) {
      if (u is FloatUniform && u.name == name) return u.value;
    }
    return null;
  }

  /// Set a color uniform by name.
  void setColor(String name, ui.Color color) {
    for (final u in uniforms) {
      if (u is ColorUniform && u.name == name) {
        u.value = color;
        return;
      }
    }
    uniforms.add(ColorUniform(name, color));
  }

  Map<String, dynamic> toJson() => {
    'preset': preset.name,
    if (shaderAssetPath != null) 'shaderAssetPath': shaderAssetPath,
    'uniforms': uniforms.map((u) => u.toJson()).toList(),
    'isEnabled': isEnabled,
    'blendMode': blendMode.name,
    'opacity': opacity,
  };

  factory ShaderEffect.fromJson(Map<String, dynamic> json) => ShaderEffect(
    preset: ShaderPreset.values.byName(json['preset'] as String? ?? 'custom'),
    shaderAssetPath: json['shaderAssetPath'] as String?,
    uniforms:
        (json['uniforms'] as List<dynamic>?)
            ?.map((u) => ShaderUniform.fromJson(u as Map<String, dynamic>))
            .toList() ??
        [],
    isEnabled: json['isEnabled'] as bool? ?? true,
    blendMode: ui.BlendMode.values.firstWhere(
      (m) => m.name == (json['blendMode'] as String? ?? 'srcOver'),
      orElse: () => ui.BlendMode.srcOver,
    ),
    opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
  );

  /// Create preset shader effects with sensible defaults.
  factory ShaderEffect.noise({double scale = 10.0, double speed = 1.0}) =>
      ShaderEffect(
        preset: ShaderPreset.noise,
        uniforms: [FloatUniform('scale', scale), FloatUniform('speed', speed)],
      );

  factory ShaderEffect.voronoi({double scale = 5.0}) => ShaderEffect(
    preset: ShaderPreset.voronoi,
    uniforms: [FloatUniform('scale', scale)],
  );

  factory ShaderEffect.chromaticAberration({double intensity = 3.0}) =>
      ShaderEffect(
        preset: ShaderPreset.chromaticAberration,
        uniforms: [FloatUniform('intensity', intensity)],
      );

  factory ShaderEffect.glitch({double intensity = 0.5, double speed = 2.0}) =>
      ShaderEffect(
        preset: ShaderPreset.glitch,
        uniforms: [
          FloatUniform('intensity', intensity),
          FloatUniform('speed', speed),
        ],
      );

  factory ShaderEffect.pixelate({double pixelSize = 8.0}) => ShaderEffect(
    preset: ShaderPreset.pixelate,
    uniforms: [FloatUniform('pixelSize', pixelSize)],
  );
}

/// A scene graph node that renders entirely via a fragment shader.
///
/// Unlike [ShaderEffect] which modifies an existing node's appearance,
/// [ShaderNode] fills its local bounds with the shader output.
class ShaderNode extends CanvasNode {
  /// The shader effect configuration.
  ShaderEffect effect;

  /// Width of the shader quad.
  double width;

  /// Height of the shader quad.
  double height;

  ShaderNode({
    required super.id,
    super.name = 'Shader',
    super.localTransform,
    super.opacity,
    super.blendMode,
    super.isVisible,
    super.isLocked,
    required this.effect,
    this.width = 100,
    this.height = 100,
  });

  @override
  ui.Rect get localBounds => ui.Rect.fromLTWH(0, 0, width, height);

  bool hitTestLocal(ui.Offset localPoint) {
    return localBounds.contains(localPoint);
  }

  @override
  Map<String, dynamic> toJson() {
    final json = baseToJson();
    json['nodeType'] = 'shader';
    json['effect'] = effect.toJson();
    json['width'] = width;
    json['height'] = height;
    return json;
  }

  factory ShaderNode.fromJson(Map<String, dynamic> json) {
    final node = ShaderNode(
      id: NodeId(json['id'] as String),
      name: json['name'] as String? ?? 'Shader',
      effect: ShaderEffect.fromJson(json['effect'] as Map<String, dynamic>),
      width: (json['width'] as num?)?.toDouble() ?? 100,
      height: (json['height'] as num?)?.toDouble() ?? 100,
    );
    CanvasNode.applyBaseFromJson(node, json);
    return node;
  }

  @override
  R accept<R>(NodeVisitor<R> visitor) => visitor.visitOther(this);
}
