import './node_effect.dart';
import './shader_effect.dart';

/// Wraps a [ShaderEffect] so it can participate in the [NodeEffect] stack.
///
/// This bridge allows shader-based effects to be used alongside
/// traditional effects (blur, shadow, glow) in a node's effect list.
///
/// ```dart
/// node.effects.add(ShaderEffectWrapper(
///   effect: ShaderEffect.noise(scale: 10),
/// ));
/// ```
class ShaderEffectWrapper extends NodeEffect {
  /// The underlying shader effect configuration.
  final ShaderEffect effect;

  ShaderEffectWrapper({required this.effect, super.isEnabled});

  @override
  String get effectType => 'shaderEffect';

  @override
  bool get isPost => true;

  @override
  Map<String, dynamic> toJson() => {
    'effectType': effectType,
    'isEnabled': isEnabled,
    'effect': effect.toJson(),
  };

  factory ShaderEffectWrapper.fromJson(Map<String, dynamic> json) =>
      ShaderEffectWrapper(
        effect: ShaderEffect.fromJson(json['effect'] as Map<String, dynamic>),
        isEnabled: json['isEnabled'] as bool? ?? true,
      );
}
