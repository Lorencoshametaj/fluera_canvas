import 'package:flutter/rendering.dart';

/// 📐 Perspective Correction — composable value object.
///
/// Keystone correction using horizontal and vertical perspective transform.
class PerspectiveSettings {
  final double x; // -1.0 to +1.0 (horizontal keystone)
  final double y; // -1.0 to +1.0 (vertical keystone)

  const PerspectiveSettings({this.x = 0.0, this.y = 0.0});

  static const identity = PerspectiveSettings();

  bool get isActive => x != 0 || y != 0;

  /// Convert to a Matrix4 perspective transform.
  Matrix4 toMatrix4() {
    if (!isActive) return Matrix4.identity();
    return Matrix4.identity()
      ..setEntry(3, 0, x * 0.001)
      ..setEntry(3, 1, y * 0.001);
  }

  PerspectiveSettings copyWith({double? x, double? y}) =>
      PerspectiveSettings(x: x ?? this.x, y: y ?? this.y);

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  factory PerspectiveSettings.fromJson(Map<String, dynamic> json) =>
      PerspectiveSettings(
        x: (json['x'] as num?)?.toDouble() ?? 0.0,
        y: (json['y'] as num?)?.toDouble() ?? 0.0,
      );
}
