import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Type of gradient fill.
enum GradientType { linear, radial, conic }

/// Abstract base for gradient fills on shapes and strokes.
///
/// Gradients use normalized coordinates (0.0–1.0) so they scale
/// automatically when the shape bounds change.
abstract class GradientFill {
  final GradientType type;
  final List<Color> colors;
  final List<double> stops;
  final ui.TileMode tileMode;

  const GradientFill({
    required this.type,
    required this.colors,
    required this.stops,
    this.tileMode = ui.TileMode.clamp,
  });

  /// Creates a Flutter [Shader] sized to [bounds].
  Shader toShader(Rect bounds);

  /// Serialize to JSON.
  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'colors': colors.map((c) => c.toARGB32()).toList(),
      'stops': stops,
      'tileMode': tileMode.name,
    };
  }

  /// Deserialize from JSON — dispatches to the correct subtype.
  static GradientFill fromJson(Map<String, dynamic> json) {
    final type = GradientType.values.firstWhere((t) => t.name == json['type']);
    switch (type) {
      case GradientType.linear:
        return LinearGradientFill.fromJson(json);
      case GradientType.radial:
        return RadialGradientFill.fromJson(json);
      case GradientType.conic:
        return ConicGradientFill.fromJson(json);
    }
  }

  /// Parse shared fields from JSON.
  static List<Color> _colorsFromJson(List<dynamic> list) =>
      list.map((v) => Color((v as int).toUnsigned(32))).toList();

  static List<double> _stopsFromJson(List<dynamic> list) =>
      list.map((v) => (v as num).toDouble()).toList();

  static ui.TileMode _tileModeFromJson(String? name) {
    if (name == null) return ui.TileMode.clamp;
    return ui.TileMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => ui.TileMode.clamp,
    );
  }
}

// ---------------------------------------------------------------------------
// Linear Gradient
// ---------------------------------------------------------------------------

/// A gradient that interpolates colors along a line.
///
/// [begin] and [end] are in normalized coordinates (0.0–1.0)
/// relative to the shape bounds. E.g. (0,0) = top-left, (1,1) = bottom-right.
class LinearGradientFill extends GradientFill {
  final Offset begin;
  final Offset end;

  const LinearGradientFill({
    required super.colors,
    required super.stops,
    super.tileMode,
    this.begin = Offset.zero,
    this.end = const Offset(1.0, 0.0),
  }) : super(type: GradientType.linear);

  @override
  Shader toShader(Rect bounds) {
    // Convert normalized coords to absolute coords within bounds.
    final from = Offset(
      bounds.left + begin.dx * bounds.width,
      bounds.top + begin.dy * bounds.height,
    );
    final to = Offset(
      bounds.left + end.dx * bounds.width,
      bounds.top + end.dy * bounds.height,
    );
    return ui.Gradient.linear(from, to, colors, stops, tileMode);
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['begin'] = [begin.dx, begin.dy];
    json['end'] = [end.dx, end.dy];
    return json;
  }

  factory LinearGradientFill.fromJson(Map<String, dynamic> json) {
    final beginList = json['begin'] as List<dynamic>;
    final endList = json['end'] as List<dynamic>;
    return LinearGradientFill(
      colors: GradientFill._colorsFromJson(json['colors'] as List),
      stops: GradientFill._stopsFromJson(json['stops'] as List),
      tileMode: GradientFill._tileModeFromJson(json['tileMode'] as String?),
      begin: Offset(
        (beginList[0] as num).toDouble(),
        (beginList[1] as num).toDouble(),
      ),
      end: Offset(
        (endList[0] as num).toDouble(),
        (endList[1] as num).toDouble(),
      ),
    );
  }

  LinearGradientFill copyWith({
    List<Color>? colors,
    List<double>? stops,
    ui.TileMode? tileMode,
    Offset? begin,
    Offset? end,
  }) {
    return LinearGradientFill(
      colors: colors ?? this.colors,
      stops: stops ?? this.stops,
      tileMode: tileMode ?? this.tileMode,
      begin: begin ?? this.begin,
      end: end ?? this.end,
    );
  }
}

// ---------------------------------------------------------------------------
// Radial Gradient
// ---------------------------------------------------------------------------

/// A gradient that radiates from a center point.
///
/// [center] is in normalized coordinates (0.5, 0.5 = center).
/// [radius] is normalized to the shorter dimension of the bounds.
class RadialGradientFill extends GradientFill {
  final Offset center;
  final double radius;

  const RadialGradientFill({
    required super.colors,
    required super.stops,
    super.tileMode,
    this.center = const Offset(0.5, 0.5),
    this.radius = 0.5,
  }) : super(type: GradientType.radial);

  @override
  Shader toShader(Rect bounds) {
    final c = Offset(
      bounds.left + center.dx * bounds.width,
      bounds.top + center.dy * bounds.height,
    );
    // Use the shorter dimension for a circular gradient.
    final r = radius * bounds.shortestSide;
    return ui.Gradient.radial(c, r, colors, stops, tileMode);
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['center'] = [center.dx, center.dy];
    json['radius'] = radius;
    return json;
  }

  factory RadialGradientFill.fromJson(Map<String, dynamic> json) {
    final centerList = json['center'] as List<dynamic>;
    return RadialGradientFill(
      colors: GradientFill._colorsFromJson(json['colors'] as List),
      stops: GradientFill._stopsFromJson(json['stops'] as List),
      tileMode: GradientFill._tileModeFromJson(json['tileMode'] as String?),
      center: Offset(
        (centerList[0] as num).toDouble(),
        (centerList[1] as num).toDouble(),
      ),
      radius: (json['radius'] as num).toDouble(),
    );
  }

  RadialGradientFill copyWith({
    List<Color>? colors,
    List<double>? stops,
    ui.TileMode? tileMode,
    Offset? center,
    double? radius,
  }) {
    return RadialGradientFill(
      colors: colors ?? this.colors,
      stops: stops ?? this.stops,
      tileMode: tileMode ?? this.tileMode,
      center: center ?? this.center,
      radius: radius ?? this.radius,
    );
  }
}

// ---------------------------------------------------------------------------
// Conic (Sweep) Gradient
// ---------------------------------------------------------------------------

/// A gradient that sweeps around a center point.
///
/// [center] is in normalized coordinates.
/// [startAngle] is in radians (0 = right, π/2 = down).
class ConicGradientFill extends GradientFill {
  final Offset center;
  final double startAngle;

  const ConicGradientFill({
    required super.colors,
    required super.stops,
    super.tileMode,
    this.center = const Offset(0.5, 0.5),
    this.startAngle = 0.0,
  }) : super(type: GradientType.conic);

  @override
  Shader toShader(Rect bounds) {
    final c = Offset(
      bounds.left + center.dx * bounds.width,
      bounds.top + center.dy * bounds.height,
    );
    return ui.Gradient.sweep(c, colors, stops, tileMode, startAngle);
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['center'] = [center.dx, center.dy];
    json['startAngle'] = startAngle;
    return json;
  }

  factory ConicGradientFill.fromJson(Map<String, dynamic> json) {
    final centerList = json['center'] as List<dynamic>;
    return ConicGradientFill(
      colors: GradientFill._colorsFromJson(json['colors'] as List),
      stops: GradientFill._stopsFromJson(json['stops'] as List),
      tileMode: GradientFill._tileModeFromJson(json['tileMode'] as String?),
      center: Offset(
        (centerList[0] as num).toDouble(),
        (centerList[1] as num).toDouble(),
      ),
      startAngle: (json['startAngle'] as num?)?.toDouble() ?? 0.0,
    );
  }

  ConicGradientFill copyWith({
    List<Color>? colors,
    List<double>? stops,
    ui.TileMode? tileMode,
    Offset? center,
    double? startAngle,
  }) {
    return ConicGradientFill(
      colors: colors ?? this.colors,
      stops: stops ?? this.stops,
      tileMode: tileMode ?? this.tileMode,
      center: center ?? this.center,
      startAngle: startAngle ?? this.startAngle,
    );
  }
}
