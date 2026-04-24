import 'dart:ui';
import 'text_overlay.dart';
import 'tone_curve.dart';
import 'color_adjustments.dart';
import 'gradient_filter.dart';
import 'perspective_settings.dart';
import 'export_settings.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

/// 🖼️ MODELLO ELEMENTO IMMAGINE
/// Represents an image positioned on the canvas with all modifications
class ImageElement {
  final String id;
  final String imagePath; // Path locale of the image
  final String? storageUrl; // URL Cloud Storage (per immagini grandi)
  final String? thumbnailUrl; // URL thumbnail per preview rapida
  final Offset position; // Position on the canvas
  final double scale; // Scala (1.0 = size originale)
  final double rotation; // Rotazione in radianti
  final DateTime createdAt;
  final int pageIndex; // Page this image belongs to

  // ✨ Color filters
  final double brightness; // -0.5 to +0.5
  final double contrast; // -0.5 to +0.5
  final double saturation; // -1.0 to +1.0
  final double opacity; // 0.0 to 1.0
  final double vignette; // 0.0 (off) to 1.0 (max)
  final int vignetteColor; // Color.value, default 0xFF000000 (black)
  final double hueShift; // -1.0 to +1.0 (maps to -π to +π)
  final double temperature; // -1.0 (cool) to +1.0 (warm)
  final double highlights; // -1.0 to +1.0 (tone bright areas)
  final double shadows; // -1.0 to +1.0 (tone dark areas)
  final double fade; // 0.0 (off) to 1.0 (faded/lifted blacks)

  // 🎨 Split toning
  final int splitHighlightColor; // 0 = off, else Color.value for highlights
  final int splitShadowColor; // 0 = off, else Color.value for shadows
  final double splitBalance; // -1.0 (shadow-heavy) to +1.0 (highlight-heavy)
  final double splitIntensity; // 0.0 (off) to 1.0 (max)
  final double clarity; // -1.0 to +1.0 (local contrast / structure)
  final double texture; // -1.0 to +1.0 (fine detail enhancement)
  final double dehaze; // -1.0 to +1.0 (remove/add haze)

  // 📤 Export settings
  final String exportFormat; // 'png', 'jpeg', 'webp'
  final int exportQuality; // 0-100 (for lossy formats)

  // 📈 Tone Curve
  final ToneCurve toneCurve; // custom tone adjustment curve

  // 🎨 HSL per-channel (7 channels × 3 values = 21 doubles)
  // Channels: Red, Orange, Yellow, Green, Cyan, Blue, Purple
  // Per channel: [hue shift, saturation, luminance] each -1.0 to +1.0
  final List<double> hslAdjustments;

  // 🔇 Noise
  final double noiseReduction; // 0.0 (off) to 1.0 (max)

  // 🌈 Gradient Filter
  final double gradientAngle; // 0.0-360.0 degrees
  final double gradientPosition; // 0.0-1.0 (where filter starts)
  final double gradientStrength; // 0.0-1.0
  final int gradientColor; // Color.value, 0 = transparent

  // 📐 Perspective Correction
  final double perspectiveX; // -1.0 to +1.0 (horizontal keystone)
  final double perspectiveY; // -1.0 to +1.0 (vertical keystone)

  // 🔍 Post-processing (GPU)
  final double blurRadius; // 0.0 (off) to 50.0 (max)
  final double sharpenAmount; // 0.0 (off) to 2.0 (very strong)
  final double edgeDetectStrength; // 0.0 (off) to 1.0 (full sketch)
  final int lutIndex; // -1 (none) or index into lutPresets
  final double grainAmount; // 0.0 (off) to 1.0 (heavy grain)
  final double grainSize; // 0.5 (fine) to 3.0 (coarse)

  // 🔄 Transformations
  final bool flipHorizontal;
  final bool flipVertical;

  // ✂️ Crop (cropped area, relativa all'immagine originale 0.0-1.0)
  final Rect? cropRect; // null = nessun crop

  // 🎨 Strokes and shapes drawn on top of the image (in editing mode)
  final List<ProStroke> drawingStrokes;
  final List<GeometricShape> drawingShapes;

  // 📝 Text overlays
  final List<TextOverlay> textOverlays;

  // ── Composed Sub-Model Getters ──
  // These construct sub-model instances from the flat fields.
  // Use these in new code instead of accessing raw fields.

  ColorAdjustments get colorAdjustments => ColorAdjustments(
    brightness: brightness,
    contrast: contrast,
    saturation: saturation,
    hueShift: hueShift,
    temperature: temperature,
    highlights: highlights,
    shadows: shadows,
    fade: fade,
    clarity: clarity,
    texture: texture,
    dehaze: dehaze,
    splitHighlightColor: splitHighlightColor,
    splitShadowColor: splitShadowColor,
    splitBalance: splitBalance,
    splitIntensity: splitIntensity,
  );

  GradientFilter get gradientFilter => GradientFilter(
    angle: gradientAngle,
    position: gradientPosition,
    strength: gradientStrength,
    color: gradientColor,
  );

  PerspectiveSettings get perspective =>
      PerspectiveSettings(x: perspectiveX, y: perspectiveY);

  ExportSettings get exportSettings =>
      ExportSettings(format: exportFormat, quality: exportQuality);

  const ImageElement({
    required this.id,
    required this.imagePath,
    this.storageUrl,
    this.thumbnailUrl,
    required this.position,
    this.scale = 1.0,
    this.rotation = 0.0,
    required this.createdAt,
    required this.pageIndex,
    this.brightness = 0.0,
    this.contrast = 0.0,
    this.saturation = 0.0,
    this.opacity = 1.0,
    this.vignette = 0.0,
    this.vignetteColor = 0xFF000000,
    this.hueShift = 0.0,
    this.temperature = 0.0,
    this.highlights = 0.0,
    this.shadows = 0.0,
    this.fade = 0.0,
    this.splitHighlightColor = 0,
    this.splitShadowColor = 0,
    this.splitBalance = 0.0,
    this.splitIntensity = 0.5,
    this.clarity = 0.0,
    this.texture = 0.0,
    this.dehaze = 0.0,
    this.exportFormat = 'png',
    this.exportQuality = 95,
    this.toneCurve = const ToneCurve(),
    this.hslAdjustments = const [
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ],
    this.noiseReduction = 0.0,
    this.gradientAngle = 0.0,
    this.gradientPosition = 0.5,
    this.gradientStrength = 0.0,
    this.gradientColor = 0,
    this.perspectiveX = 0.0,
    this.perspectiveY = 0.0,
    this.blurRadius = 0.0,
    this.sharpenAmount = 0.0,
    this.edgeDetectStrength = 0.0,
    this.lutIndex = -1,
    this.grainAmount = 0.0,
    this.grainSize = 1.0,
    this.flipHorizontal = false,
    this.flipVertical = false,
    this.cropRect,
    this.drawingStrokes = const [],
    this.drawingShapes = const [],
    this.textOverlays = const [],
  });

  /// Creates a copy with modifications
  ImageElement copyWith({
    String? id,
    String? imagePath,
    String? storageUrl,
    String? thumbnailUrl,
    Offset? position,
    double? scale,
    double? rotation,
    DateTime? createdAt,
    int? pageIndex,
    double? brightness,
    double? contrast,
    double? saturation,
    double? opacity,
    double? vignette,
    int? vignetteColor,
    double? hueShift,
    double? temperature,
    double? highlights,
    double? shadows,
    double? fade,
    int? splitHighlightColor,
    int? splitShadowColor,
    double? splitBalance,
    double? splitIntensity,
    double? clarity,
    double? texture,
    double? dehaze,
    String? exportFormat,
    int? exportQuality,
    ToneCurve? toneCurve,
    List<double>? hslAdjustments,
    double? noiseReduction,
    double? gradientAngle,
    double? gradientPosition,
    double? gradientStrength,
    int? gradientColor,
    double? perspectiveX,
    double? perspectiveY,
    double? blurRadius,
    double? sharpenAmount,
    double? edgeDetectStrength,
    int? lutIndex,
    double? grainAmount,
    double? grainSize,
    bool? flipHorizontal,
    bool? flipVertical,
    Rect? cropRect,
    bool clearCrop = false,
    List<ProStroke>? drawingStrokes,
    List<GeometricShape>? drawingShapes,
    List<TextOverlay>? textOverlays,
  }) {
    return ImageElement(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      storageUrl: storageUrl ?? this.storageUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      position: position ?? this.position,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      createdAt: createdAt ?? this.createdAt,
      pageIndex: pageIndex ?? this.pageIndex,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      opacity: opacity ?? this.opacity,
      vignette: vignette ?? this.vignette,
      vignetteColor: vignetteColor ?? this.vignetteColor,
      hueShift: hueShift ?? this.hueShift,
      temperature: temperature ?? this.temperature,
      highlights: highlights ?? this.highlights,
      shadows: shadows ?? this.shadows,
      fade: fade ?? this.fade,
      splitHighlightColor: splitHighlightColor ?? this.splitHighlightColor,
      splitShadowColor: splitShadowColor ?? this.splitShadowColor,
      splitBalance: splitBalance ?? this.splitBalance,
      splitIntensity: splitIntensity ?? this.splitIntensity,
      clarity: clarity ?? this.clarity,
      texture: texture ?? this.texture,
      dehaze: dehaze ?? this.dehaze,
      exportFormat: exportFormat ?? this.exportFormat,
      exportQuality: exportQuality ?? this.exportQuality,
      toneCurve: toneCurve ?? this.toneCurve,
      hslAdjustments: hslAdjustments ?? this.hslAdjustments,
      noiseReduction: noiseReduction ?? this.noiseReduction,
      gradientAngle: gradientAngle ?? this.gradientAngle,
      gradientPosition: gradientPosition ?? this.gradientPosition,
      gradientStrength: gradientStrength ?? this.gradientStrength,
      gradientColor: gradientColor ?? this.gradientColor,
      perspectiveX: perspectiveX ?? this.perspectiveX,
      perspectiveY: perspectiveY ?? this.perspectiveY,
      blurRadius: blurRadius ?? this.blurRadius,
      sharpenAmount: sharpenAmount ?? this.sharpenAmount,
      edgeDetectStrength: edgeDetectStrength ?? this.edgeDetectStrength,
      lutIndex: lutIndex ?? this.lutIndex,
      grainAmount: grainAmount ?? this.grainAmount,
      grainSize: grainSize ?? this.grainSize,
      flipHorizontal: flipHorizontal ?? this.flipHorizontal,
      flipVertical: flipVertical ?? this.flipVertical,
      cropRect: clearCrop ? null : (cropRect ?? this.cropRect),
      drawingStrokes: drawingStrokes ?? this.drawingStrokes,
      drawingShapes: drawingShapes ?? this.drawingShapes,
      textOverlays: textOverlays ?? this.textOverlays,
    );
  }

  /// Serialize to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imagePath': imagePath,
      if (storageUrl != null) 'storageUrl': storageUrl,
      if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      'position': {'dx': position.dx, 'dy': position.dy},
      'scale': scale,
      'rotation': rotation,
      'createdAt': createdAt.toIso8601String(),
      'pageIndex': pageIndex,
      'brightness': brightness,
      'contrast': contrast,
      'saturation': saturation,
      'opacity': opacity,
      'vignette': vignette,
      'vignetteColor': vignetteColor,
      'hueShift': hueShift,
      'temperature': temperature,
      'highlights': highlights,
      'shadows': shadows,
      'fade': fade,
      'splitHighlightColor': splitHighlightColor,
      'splitShadowColor': splitShadowColor,
      'splitBalance': splitBalance,
      'splitIntensity': splitIntensity,
      'clarity': clarity,
      'texture': texture,
      'dehaze': dehaze,
      'exportFormat': exportFormat,
      'exportQuality': exportQuality,
      if (!toneCurve.isIdentity) 'toneCurve': toneCurve.toJson(),
      'hslAdjustments': hslAdjustments,
      'noiseReduction': noiseReduction,
      'gradientAngle': gradientAngle,
      'gradientPosition': gradientPosition,
      'gradientStrength': gradientStrength,
      'gradientColor': gradientColor,
      'perspectiveX': perspectiveX,
      'perspectiveY': perspectiveY,
      'blurRadius': blurRadius,
      'sharpenAmount': sharpenAmount,
      'edgeDetectStrength': edgeDetectStrength,
      'lutIndex': lutIndex,
      'grainAmount': grainAmount,
      'grainSize': grainSize,
      'flipHorizontal': flipHorizontal,
      'flipVertical': flipVertical,
      'cropRect':
          cropRect != null
              ? {
                'left': cropRect!.left,
                'top': cropRect!.top,
                'right': cropRect!.right,
                'bottom': cropRect!.bottom,
              }
              : null,
      'drawingStrokes': drawingStrokes.map((s) => s.toJson()).toList(),
      'drawingShapes': drawingShapes.map((s) => s.toJson()).toList(),
      'textOverlays': textOverlays.map((t) => t.toJson()).toList(),
    };
  }

  /// Deserialize from JSON
  factory ImageElement.fromJson(Map<String, dynamic> json) {
    Rect? cropRect;
    if (json['cropRect'] != null) {
      final crop = json['cropRect'] as Map<String, dynamic>;
      cropRect = Rect.fromLTRB(
        (crop['left'] as num).toDouble(),
        (crop['top'] as num).toDouble(),
        (crop['right'] as num).toDouble(),
        (crop['bottom'] as num).toDouble(),
      );
    }

    final strokesJson = json['drawingStrokes'] as List<dynamic>? ?? [];
    final strokes = strokesJson.map((s) => ProStroke.fromJson(s)).toList();

    final shapesJson = json['drawingShapes'] as List<dynamic>? ?? [];
    final shapes = shapesJson.map((s) => GeometricShape.fromJson(s)).toList();

    return ImageElement(
      id: json['id'] as String,
      imagePath: json['imagePath'] as String,
      storageUrl: json['storageUrl'] as String?,
      thumbnailUrl: json['thumbnailUrl'] as String?,
      position: Offset(
        (json['position']['dx'] as num).toDouble(),
        (json['position']['dy'] as num).toDouble(),
      ),
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      pageIndex: (json['pageIndex'] as num?)?.toInt() ?? 0,
      brightness: (json['brightness'] as num?)?.toDouble() ?? 0.0,
      contrast: (json['contrast'] as num?)?.toDouble() ?? 0.0,
      saturation: (json['saturation'] as num?)?.toDouble() ?? 0.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      vignette: (json['vignette'] as num?)?.toDouble() ?? 0.0,
      vignetteColor: (json['vignetteColor'] as num?)?.toInt() ?? 0xFF000000,
      hueShift: (json['hueShift'] as num?)?.toDouble() ?? 0.0,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.0,
      highlights: (json['highlights'] as num?)?.toDouble() ?? 0.0,
      shadows: (json['shadows'] as num?)?.toDouble() ?? 0.0,
      fade: (json['fade'] as num?)?.toDouble() ?? 0.0,
      splitHighlightColor: (json['splitHighlightColor'] as num?)?.toInt() ?? 0,
      splitShadowColor: (json['splitShadowColor'] as num?)?.toInt() ?? 0,
      splitBalance: (json['splitBalance'] as num?)?.toDouble() ?? 0.0,
      splitIntensity: (json['splitIntensity'] as num?)?.toDouble() ?? 0.5,
      clarity: (json['clarity'] as num?)?.toDouble() ?? 0.0,
      texture: (json['texture'] as num?)?.toDouble() ?? 0.0,
      dehaze: (json['dehaze'] as num?)?.toDouble() ?? 0.0,
      exportFormat: json['exportFormat'] as String? ?? 'png',
      exportQuality: (json['exportQuality'] as num?)?.toInt() ?? 95,
      toneCurve:
          json['toneCurve'] != null
              ? ToneCurve.fromJson(json['toneCurve'] as Map<String, dynamic>)
              : const ToneCurve(),
      hslAdjustments:
          (json['hslAdjustments'] as List<dynamic>?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
      noiseReduction: (json['noiseReduction'] as num?)?.toDouble() ?? 0.0,
      gradientAngle: (json['gradientAngle'] as num?)?.toDouble() ?? 0.0,
      gradientPosition: (json['gradientPosition'] as num?)?.toDouble() ?? 0.5,
      gradientStrength: (json['gradientStrength'] as num?)?.toDouble() ?? 0.0,
      gradientColor: (json['gradientColor'] as num?)?.toInt() ?? 0,
      perspectiveX: (json['perspectiveX'] as num?)?.toDouble() ?? 0.0,
      perspectiveY: (json['perspectiveY'] as num?)?.toDouble() ?? 0.0,
      blurRadius: (json['blurRadius'] as num?)?.toDouble() ?? 0.0,
      sharpenAmount: (json['sharpenAmount'] as num?)?.toDouble() ?? 0.0,
      edgeDetectStrength:
          (json['edgeDetectStrength'] as num?)?.toDouble() ?? 0.0,
      lutIndex: (json['lutIndex'] as num?)?.toInt() ?? -1,
      grainAmount: (json['grainAmount'] as num?)?.toDouble() ?? 0.0,
      grainSize: (json['grainSize'] as num?)?.toDouble() ?? 1.0,
      flipHorizontal: json['flipHorizontal'] as bool? ?? false,
      flipVertical: json['flipVertical'] as bool? ?? false,
      cropRect: cropRect,
      drawingStrokes: strokes,
      drawingShapes: shapes,
      textOverlays:
          (json['textOverlays'] as List<dynamic>?)
              ?.map((t) => TextOverlay.fromJson(t as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  @override
  String toString() =>
      'ImageElement(id: $id, path: $imagePath, pos: $position, scale: $scale)';
}
