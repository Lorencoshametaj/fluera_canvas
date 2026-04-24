import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import './gradient_fill.dart';
import '../../utils/uid.dart';

/// Sentinel for [copyWith] methods to distinguish "not provided" from "null".
const _absent = _Absent();

class _Absent {
  const _Absent();
}

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// Type of fill in a paint stack layer.
enum FillType { solid, gradient, image }

/// Stroke alignment relative to the path boundary.
///
/// - [center]: stroke straddles the path (default, standard Canvas behavior).
/// - [inside]: stroke is inset so it stays within the shape bounds.
/// - [outside]: stroke extends outward from the shape bounds.
enum StrokePosition { center, inside, outside }

/// How an image fill is scaled within the shape bounds.
enum ImageFillMode { fill, fit, crop, tile }

// ---------------------------------------------------------------------------
// FillLayer
// ---------------------------------------------------------------------------

/// A single fill layer in a paint stack.
///
/// Fill layers are rendered bottom-to-top (index 0 = bottom-most).
/// Each fill can independently be a solid color, gradient, or image,
/// with its own opacity and blend mode.
///
/// ```dart
/// FillLayer.solid(color: Colors.blue);
/// FillLayer.fromGradient(gradient: myLinearGradient, opacity: 0.6);
/// ```
class FillLayer {
  /// Unique identifier for this fill layer.
  final String id;

  /// What kind of fill this layer uses.
  FillType type;

  /// Solid fill color (used when [type] == [FillType.solid]).
  Color? color;

  /// Gradient fill (used when [type] == [FillType.gradient]).
  GradientFill? gradient;

  /// Asset ID for an image fill (used when [type] == [FillType.image]).
  ///
  /// The actual image rendering is resolved by the asset pipeline at
  /// render time. This field only stores the reference.
  String? imageAssetId;

  /// How the image should be scaled within the shape bounds.
  ImageFillMode imageFillMode;

  /// Independent opacity for this fill layer (0.0–1.0).
  double _opacity;
  double get opacity => _opacity;
  set opacity(double value) => _opacity = value.clamp(0.0, 1.0);

  /// Blend mode for compositing this fill onto the layers below.
  ui.BlendMode blendMode;

  /// Whether this fill layer is currently visible.
  bool isVisible;

  FillLayer({
    String? id,
    this.type = FillType.solid,
    this.color,
    this.gradient,
    this.imageAssetId,
    this.imageFillMode = ImageFillMode.fill,
    double opacity = 1.0,
    this.blendMode = ui.BlendMode.srcOver,
    this.isVisible = true,
  }) : id = id ?? generateUid(),
       _opacity = opacity.clamp(0.0, 1.0);

  // -- Named constructors ---------------------------------------------------

  /// Create a solid color fill layer.
  factory FillLayer.solid({
    Color color = const Color(0xFF000000),
    double opacity = 1.0,
    ui.BlendMode blendMode = ui.BlendMode.srcOver,
    bool isVisible = true,
  }) => FillLayer(
    type: FillType.solid,
    color: color,
    opacity: opacity,
    blendMode: blendMode,
    isVisible: isVisible,
  );

  /// Create a gradient fill layer.
  factory FillLayer.fromGradient({
    required GradientFill gradient,
    double opacity = 1.0,
    ui.BlendMode blendMode = ui.BlendMode.srcOver,
    bool isVisible = true,
  }) => FillLayer(
    type: FillType.gradient,
    gradient: gradient,
    opacity: opacity,
    blendMode: blendMode,
    isVisible: isVisible,
  );

  // -- Paint creation -------------------------------------------------------

  /// Create a [Paint] for rendering this fill within the given [bounds].
  ///
  /// Returns null if this layer is not visible or has no paintable content.
  Paint? toPaint(Rect bounds) {
    if (!isVisible) return null;

    final paint =
        Paint()
          ..style = PaintingStyle.fill
          ..isAntiAlias = true;

    switch (type) {
      case FillType.solid:
        if (color == null) return null;
        paint.color = color!.withValues(alpha: color!.a * _opacity);
        break;

      case FillType.gradient:
        if (gradient == null || bounds.isEmpty) return null;
        paint.shader = gradient!.toShader(bounds);
        // NOTE: gradient + opacity < 1.0 is handled by the renderer via
        // saveLayer compositing. Setting paint.color.alpha does not reliably
        // affect shader-painted draws in Skia/Impeller.
        break;

      case FillType.image:
        // Image fill rendering is deferred to a future implementation.
        // The paint will be created by the asset pipeline at render time.
        return null;
    }

    paint.blendMode = blendMode;
    return paint;
  }

  // -- copyWith -------------------------------------------------------------

  /// Create a copy with overridden fields.
  ///
  /// Pass `null` explicitly to clear optional fields:
  /// ```dart
  /// fill.copyWith(color: null)  // clears color
  /// ```
  FillLayer copyWith({
    FillType? type,
    Object? color = _absent,
    Object? gradient = _absent,
    Object? imageAssetId = _absent,
    ImageFillMode? imageFillMode,
    double? opacity,
    ui.BlendMode? blendMode,
    bool? isVisible,
  }) => FillLayer(
    id: id,
    type: type ?? this.type,
    color: identical(color, _absent) ? this.color : color as Color?,
    gradient:
        identical(gradient, _absent)
            ? this.gradient
            : gradient as GradientFill?,
    imageAssetId:
        identical(imageAssetId, _absent)
            ? this.imageAssetId
            : imageAssetId as String?,
    imageFillMode: imageFillMode ?? this.imageFillMode,
    opacity: opacity ?? _opacity,
    blendMode: blendMode ?? this.blendMode,
    isVisible: isVisible ?? this.isVisible,
  );

  // -- Serialization --------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    if (color != null) 'color': color!.toARGB32(),
    if (gradient != null) 'gradient': gradient!.toJson(),
    if (imageAssetId != null) 'imageAssetId': imageAssetId,
    if (imageFillMode != ImageFillMode.fill)
      'imageFillMode': imageFillMode.name,
    if (_opacity != 1.0) 'opacity': _opacity,
    if (blendMode != ui.BlendMode.srcOver) 'blendMode': blendMode.name,
    if (!isVisible) 'isVisible': false,
  };

  factory FillLayer.fromJson(Map<String, dynamic> json) {
    return FillLayer(
      id: json['id'] as String? ?? generateUid(),
      type: FillType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => FillType.solid,
      ),
      color:
          json['color'] != null
              ? Color((json['color'] as int).toUnsigned(32))
              : null,
      gradient:
          json['gradient'] != null
              ? GradientFill.fromJson(json['gradient'] as Map<String, dynamic>)
              : null,
      imageAssetId: json['imageAssetId'] as String?,
      imageFillMode:
          json['imageFillMode'] != null
              ? ImageFillMode.values.firstWhere(
                (m) => m.name == json['imageFillMode'],
                orElse: () => ImageFillMode.fill,
              )
              : ImageFillMode.fill,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      blendMode:
          json['blendMode'] != null
              ? ui.BlendMode.values.firstWhere(
                (m) => m.name == json['blendMode'],
                orElse: () => ui.BlendMode.srcOver,
              )
              : ui.BlendMode.srcOver,
      isVisible: json['isVisible'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FillLayer && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'FillLayer(id: $id, type: $type)';
}

// ---------------------------------------------------------------------------
// StrokeLayer
// ---------------------------------------------------------------------------

/// A single stroke layer in a paint stack.
///
/// Stroke layers are rendered after fills, bottom-to-top (index 0 = bottom-most).
/// Each stroke has its own width, color/gradient, cap/join style,
/// position (center/inside/outside), and optional dash pattern.
///
/// ```dart
/// StrokeLayer(color: Colors.black, width: 2.0);
/// StrokeLayer(
///   color: Colors.red,
///   width: 1.0,
///   position: StrokePosition.outside,
///   dashPattern: [6.0, 3.0],
/// );
/// ```
class StrokeLayer {
  /// Unique identifier for this stroke layer.
  final String id;

  /// Stroke color (null = use gradient).
  Color? color;

  /// Stroke gradient (null = use color).
  GradientFill? gradient;

  /// Stroke width in logical pixels.
  double width;

  /// Stroke cap style.
  ui.StrokeCap cap;

  /// Stroke join style.
  ui.StrokeJoin join;

  /// Where the stroke sits relative to the path boundary.
  StrokePosition position;

  /// Independent opacity for this stroke layer (0.0–1.0).
  double _opacity;
  double get opacity => _opacity;
  set opacity(double value) => _opacity = value.clamp(0.0, 1.0);

  /// Blend mode for compositing this stroke onto the layers below.
  ui.BlendMode blendMode;

  /// Whether this stroke layer is currently visible.
  bool isVisible;

  /// Optional dash pattern: alternating dash/gap lengths.
  ///
  /// Null means a solid (continuous) stroke.
  /// Example: `[6.0, 3.0]` = 6px dash, 3px gap, repeating.
  List<double>? dashPattern;

  StrokeLayer({
    String? id,
    this.color,
    this.gradient,
    this.width = 1.0,
    this.cap = ui.StrokeCap.round,
    this.join = ui.StrokeJoin.round,
    this.position = StrokePosition.center,
    double opacity = 1.0,
    this.blendMode = ui.BlendMode.srcOver,
    this.isVisible = true,
    this.dashPattern,
  }) : id = id ?? generateUid(),
       _opacity = opacity.clamp(0.0, 1.0);

  // -- Paint creation -------------------------------------------------------

  /// Create a [Paint] for rendering this stroke within the given [bounds].
  ///
  /// Returns null if this layer is not visible or has no paintable content.
  Paint? toPaint(Rect bounds) {
    if (!isVisible) return null;
    if (color == null && gradient == null) return null;

    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = cap
          ..strokeJoin = join
          ..strokeMiterLimit = 4.0
          ..isAntiAlias = true;

    if (gradient != null && bounds.isFinite && !bounds.isEmpty) {
      paint.shader = gradient!.toShader(bounds);
      // NOTE: gradient + opacity < 1.0 is handled by the renderer via
      // saveLayer compositing, not via paint.color.alpha.
    } else if (color != null) {
      paint.color = color!.withValues(alpha: color!.a * _opacity);
    } else {
      return null;
    }

    paint.blendMode = blendMode;
    return paint;
  }

  /// Effective stroke width contribution to bounds.
  ///
  /// For [StrokePosition.center], half the width extends outside.
  /// For [StrokePosition.outside], the full width extends outside.
  /// For [StrokePosition.inside], nothing extends outside.
  double get boundsInflation {
    if (!isVisible) return 0;
    switch (position) {
      case StrokePosition.center:
        return width / 2;
      case StrokePosition.outside:
        return width;
      case StrokePosition.inside:
        return 0;
    }
  }

  // -- copyWith -------------------------------------------------------------

  /// Create a copy with overridden fields.
  ///
  /// Pass `null` explicitly to clear optional fields:
  /// ```dart
  /// stroke.copyWith(color: null, gradient: myGradient)  // switch to gradient
  /// ```
  StrokeLayer copyWith({
    Object? color = _absent,
    Object? gradient = _absent,
    double? width,
    ui.StrokeCap? cap,
    ui.StrokeJoin? join,
    StrokePosition? position,
    double? opacity,
    ui.BlendMode? blendMode,
    bool? isVisible,
    Object? dashPattern = _absent,
  }) => StrokeLayer(
    id: id,
    color: identical(color, _absent) ? this.color : color as Color?,
    gradient:
        identical(gradient, _absent)
            ? this.gradient
            : gradient as GradientFill?,
    width: width ?? this.width,
    cap: cap ?? this.cap,
    join: join ?? this.join,
    position: position ?? this.position,
    opacity: opacity ?? _opacity,
    blendMode: blendMode ?? this.blendMode,
    isVisible: isVisible ?? this.isVisible,
    dashPattern:
        identical(dashPattern, _absent)
            ? this.dashPattern
            : dashPattern as List<double>?,
  );

  // -- Serialization --------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'id': id,
    if (color != null) 'color': color!.toARGB32(),
    if (gradient != null) 'gradient': gradient!.toJson(),
    'width': width,
    if (cap != ui.StrokeCap.round) 'cap': cap.index,
    if (join != ui.StrokeJoin.round) 'join': join.index,
    if (position != StrokePosition.center) 'position': position.name,
    if (_opacity != 1.0) 'opacity': _opacity,
    if (blendMode != ui.BlendMode.srcOver) 'blendMode': blendMode.name,
    if (!isVisible) 'isVisible': false,
    if (dashPattern != null) 'dashPattern': dashPattern,
  };

  factory StrokeLayer.fromJson(Map<String, dynamic> json) {
    return StrokeLayer(
      id: json['id'] as String? ?? generateUid(),
      color:
          json['color'] != null
              ? Color((json['color'] as int).toUnsigned(32))
              : null,
      gradient:
          json['gradient'] != null
              ? GradientFill.fromJson(json['gradient'] as Map<String, dynamic>)
              : null,
      width: (json['width'] as num?)?.toDouble() ?? 1.0,
      cap:
          json['cap'] != null
              ? ui.StrokeCap.values[json['cap'] as int]
              : ui.StrokeCap.round,
      join:
          json['join'] != null
              ? ui.StrokeJoin.values[json['join'] as int]
              : ui.StrokeJoin.round,
      position:
          json['position'] != null
              ? StrokePosition.values.firstWhere(
                (p) => p.name == json['position'],
                orElse: () => StrokePosition.center,
              )
              : StrokePosition.center,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      blendMode:
          json['blendMode'] != null
              ? ui.BlendMode.values.firstWhere(
                (m) => m.name == json['blendMode'],
                orElse: () => ui.BlendMode.srcOver,
              )
              : ui.BlendMode.srcOver,
      isVisible: json['isVisible'] as bool? ?? true,
      dashPattern:
          json['dashPattern'] != null
              ? (json['dashPattern'] as List)
                  .map((v) => (v as num).toDouble())
                  .toList()
              : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StrokeLayer &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'StrokeLayer(id: $id, width: $width)';
}
