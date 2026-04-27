import 'dart:ui';

/// 🎨 Color grading adjustments — composable value object.
///
/// Groups all color-related adjustments that were previously flat fields
/// on ImageElement. This is a pure value object with JSON serialization.
class ColorAdjustments {
  /// Field `brightness`.
  final double brightness; // -1.0 to +1.0
  /// Field `contrast`.
  final double contrast; // -1.0 to +1.0
  /// Field `saturation`.
  final double saturation; // -1.0 to +1.0
  /// Field `hueShift`.
  final double hueShift; // -1.0 to +1.0
  /// Method `temperature`.
  final double temperature; // -1.0 to +1.0 (warm/cool)
  /// Field `highlights`.
  final double highlights; // -1.0 to +1.0
  /// Field `shadows`.
  final double shadows; // -1.0 to +1.0
  /// Method `fade`.
  final double fade; // 0.0 to 1.0 (cinematic faded blacks)
  /// Method `clarity`.
  final double clarity; // -1.0 to +1.0 (midtone contrast)
  /// Method `texture`.
  final double texture; // -1.0 to +1.0 (fine detail)
  /// Method `dehaze`.
  final double dehaze; // -1.0 to +1.0 (remove/add haze)
  /// Method `splitHighlightColor`.
  final int splitHighlightColor; // Color.value or 0 (off)
  /// Method `splitShadowColor`.
  final int splitShadowColor; // Color.value or 0 (off)
  /// Method `splitBalance`.
  final double splitBalance; // -1.0 to +1.0 (shadow/highlight bias)
  /// Field `splitIntensity`.
  final double splitIntensity; // 0.0 to 1.0

  /// API element `ColorAdjustments`.
  const ColorAdjustments({
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.saturation = 0.0,
    this.hueShift = 0.0,
    this.temperature = 0.0,
    this.highlights = 0.0,
    this.shadows = 0.0,
    this.fade = 0.0,
    this.clarity = 0.0,
    this.texture = 0.0,
    this.dehaze = 0.0,
    this.splitHighlightColor = 0,
    this.splitShadowColor = 0,
    this.splitBalance = 0.0,
    this.splitIntensity = 0.5,
  });

  /// Method `identity`.
  static const identity = ColorAdjustments();

  /// Whether all values are at defaults (no adjustment needed)
  bool get isDefault =>
      brightness == 0 &&
      contrast == 0 &&
      saturation == 0 &&
      hueShift == 0 &&
      temperature == 0 &&
      highlights == 0 &&
      shadows == 0 &&
      fade == 0 &&
      clarity == 0 &&
      texture == 0 &&
      dehaze == 0 &&
      splitHighlightColor == 0 &&
      splitShadowColor == 0 &&
      splitBalance == 0 &&
      splitIntensity == 0.5;

  /// API element `copyWith`.
  ColorAdjustments copyWith({
    double? brightness,
    double? contrast,
    double? saturation,
    double? hueShift,
    double? temperature,
    double? highlights,
    double? shadows,
    double? fade,
    double? clarity,
    double? texture,
    double? dehaze,
    int? splitHighlightColor,
    int? splitShadowColor,
    double? splitBalance,
    double? splitIntensity,
  }) => ColorAdjustments(
    brightness: brightness ?? this.brightness,
    contrast: contrast ?? this.contrast,
    saturation: saturation ?? this.saturation,
    hueShift: hueShift ?? this.hueShift,
    temperature: temperature ?? this.temperature,
    highlights: highlights ?? this.highlights,
    shadows: shadows ?? this.shadows,
    fade: fade ?? this.fade,
    clarity: clarity ?? this.clarity,
    texture: texture ?? this.texture,
    dehaze: dehaze ?? this.dehaze,
    splitHighlightColor: splitHighlightColor ?? this.splitHighlightColor,
    splitShadowColor: splitShadowColor ?? this.splitShadowColor,
    splitBalance: splitBalance ?? this.splitBalance,
    splitIntensity: splitIntensity ?? this.splitIntensity,
  );

  /// Method `toJson`.
  Map<String, dynamic> toJson() => {
    'brightness': brightness,
    'contrast': contrast,
    'saturation': saturation,
    'hueShift': hueShift,
    'temperature': temperature,
    'highlights': highlights,
    'shadows': shadows,
    'fade': fade,
    'clarity': clarity,
    'texture': texture,
    'dehaze': dehaze,
    'splitHighlightColor': splitHighlightColor,
    'splitShadowColor': splitShadowColor,
    'splitBalance': splitBalance,
    'splitIntensity': splitIntensity,
  };

  /// Method `fromJson`.
  factory ColorAdjustments.fromJson(Map<String, dynamic> json) =>
      ColorAdjustments(
        brightness: (json['brightness'] as num?)?.toDouble() ?? 0.0,
        contrast: (json['contrast'] as num?)?.toDouble() ?? 0.0,
        saturation: (json['saturation'] as num?)?.toDouble() ?? 0.0,
        hueShift: (json['hueShift'] as num?)?.toDouble() ?? 0.0,
        temperature: (json['temperature'] as num?)?.toDouble() ?? 0.0,
        highlights: (json['highlights'] as num?)?.toDouble() ?? 0.0,
        shadows: (json['shadows'] as num?)?.toDouble() ?? 0.0,
        fade: (json['fade'] as num?)?.toDouble() ?? 0.0,
        clarity: (json['clarity'] as num?)?.toDouble() ?? 0.0,
        texture: (json['texture'] as num?)?.toDouble() ?? 0.0,
        dehaze: (json['dehaze'] as num?)?.toDouble() ?? 0.0,
        splitHighlightColor:
            (json['splitHighlightColor'] as num?)?.toInt() ?? 0,
        splitShadowColor: (json['splitShadowColor'] as num?)?.toInt() ?? 0,
        splitBalance: (json['splitBalance'] as num?)?.toDouble() ?? 0.0,
        splitIntensity: (json['splitIntensity'] as num?)?.toDouble() ?? 0.5,
      );
}
