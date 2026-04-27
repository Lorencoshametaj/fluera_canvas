import 'dart:ui';

/// 🌈 Gradient Filter — composable value object.
///
/// Represents a linear gradient overlay applied to the image,
/// useful for ND graduated filter effects.
class GradientFilter {
  /// Field `angle`.
  final double angle; // 0.0-360.0 degrees
  /// Method `position`.
  final double position; // 0.0-1.0 (where filter starts)
  /// Field `strength`.
  final double strength; // 0.0-1.0
  /// Field `color`.
  final int color; // Color.value, 0 = off

  /// API element `GradientFilter`.
  const GradientFilter({
    this.angle = 0.0,
    this.position = 0.5,
    this.strength = 0.0,
    this.color = 0,
  });

  /// Method `off`.
  static const off = GradientFilter();

  /// Getter `isActive`.
  bool get isActive => strength > 0 && color != 0;

  /// API element `copyWith`.
  GradientFilter copyWith({
    double? angle,
    double? position,
    double? strength,
    int? color,
  }) => GradientFilter(
    angle: angle ?? this.angle,
    position: position ?? this.position,
    strength: strength ?? this.strength,
    color: color ?? this.color,
  );

  /// Method `toJson`.
  Map<String, dynamic> toJson() => {
    'angle': angle,
    'position': position,
    'strength': strength,
    'color': color,
  };

  /// Method `fromJson`.
  factory GradientFilter.fromJson(Map<String, dynamic> json) => GradientFilter(
    angle: (json['angle'] as num?)?.toDouble() ?? 0.0,
    position: (json['position'] as num?)?.toDouble() ?? 0.5,
    strength: (json['strength'] as num?)?.toDouble() ?? 0.0,
    color: (json['color'] as num?)?.toInt() ?? 0,
  );
}
