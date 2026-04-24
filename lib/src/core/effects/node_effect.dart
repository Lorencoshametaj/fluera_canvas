import 'dart:ui' as ui;
import './shader_effect_wrapper.dart';

/// Base class for non-destructive effects applied to scene graph nodes.
///
/// Effects are rendered in order: **pre-effects** (shadows, glow) are
/// drawn before the node, **post-effects** (blur, color overlay) modify
/// the node's appearance after it has been drawn.
///
/// Each effect can be individually enabled/disabled without removing it
/// from the stack.
abstract class NodeEffect {
  bool isEnabled;

  NodeEffect({this.isEnabled = true});

  /// Whether this effect renders BEFORE the node (e.g. shadows).
  bool get isPre => false;

  /// Whether this effect renders AFTER the node (e.g. blur, overlay).
  bool get isPost => !isPre;

  /// The effect type identifier for serialization.
  String get effectType;

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'effectType': effectType,
    'isEnabled': isEnabled,
  };

  /// Deserialize from JSON — dispatches to the correct subtype.
  static NodeEffect fromJson(Map<String, dynamic> json) {
    switch (json['effectType'] as String) {
      case 'blur':
        return BlurEffect.fromJson(json);
      case 'dropShadow':
        return DropShadowEffect.fromJson(json);
      case 'innerShadow':
        return InnerShadowEffect.fromJson(json);
      case 'outerGlow':
        return OuterGlowEffect.fromJson(json);
      case 'colorOverlay':
        return ColorOverlayEffect.fromJson(json);
      case 'shaderEffect':
        return ShaderEffectWrapper.fromJson(json);
      default:
        throw ArgumentError('Unknown effectType: ${json['effectType']}');
    }
  }
}

// ---------------------------------------------------------------------------
// Blur Effect
// ---------------------------------------------------------------------------

/// Gaussian blur applied to the node's rendered output.
///
/// Uses `ImageFilter.blur` via `saveLayer` to blur the entire node.
class BlurEffect extends NodeEffect {
  double sigmaX;
  double sigmaY;

  BlurEffect({this.sigmaX = 4.0, this.sigmaY = 4.0, super.isEnabled});

  @override
  String get effectType => 'blur';

  @override
  bool get isPost => true;

  /// Create the Paint for saveLayer that applies the blur.
  ui.Paint createPaint() {
    return ui.Paint()
      ..imageFilter = ui.ImageFilter.blur(
        sigmaX: sigmaX,
        sigmaY: sigmaY,
        tileMode: ui.TileMode.decal,
      );
  }

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'sigmaX': sigmaX,
    'sigmaY': sigmaY,
  };

  factory BlurEffect.fromJson(Map<String, dynamic> json) {
    return BlurEffect(
      sigmaX: (json['sigmaX'] as num?)?.toDouble() ?? 4.0,
      sigmaY: (json['sigmaY'] as num?)?.toDouble() ?? 4.0,
      isEnabled: json['isEnabled'] as bool? ?? true,
    );
  }

  BlurEffect copyWith({double? sigmaX, double? sigmaY, bool? isEnabled}) =>
      BlurEffect(
        sigmaX: sigmaX ?? this.sigmaX,
        sigmaY: sigmaY ?? this.sigmaY,
        isEnabled: isEnabled ?? this.isEnabled,
      );
}

// ---------------------------------------------------------------------------
// Drop Shadow Effect
// ---------------------------------------------------------------------------

/// Classic drop shadow drawn behind the node.
///
/// The node is rendered twice: first as a shadow (offset + blur + color),
/// then the original on top.
class DropShadowEffect extends NodeEffect {
  ui.Color color;
  ui.Offset offset;
  double blurRadius;
  double spread;

  DropShadowEffect({
    this.color = const ui.Color(0x66000000),
    this.offset = const ui.Offset(4, 4),
    this.blurRadius = 8.0,
    this.spread = 0.0,
    super.isEnabled,
  });

  @override
  String get effectType => 'dropShadow';

  @override
  bool get isPre => true;

  /// Create the Paint for the shadow layer.
  ui.Paint createShadowPaint() {
    return ui.Paint()
      ..color = color
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, _sigmaFromRadius);
  }

  double get _sigmaFromRadius => blurRadius * 0.5;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'color': color.toARGB32(),
    'offsetX': offset.dx,
    'offsetY': offset.dy,
    'blurRadius': blurRadius,
    'spread': spread,
  };

  factory DropShadowEffect.fromJson(Map<String, dynamic> json) {
    return DropShadowEffect(
      color: ui.Color((json['color'] as int?)?.toUnsigned(32) ?? 0x66000000),
      offset: ui.Offset(
        (json['offsetX'] as num?)?.toDouble() ?? 4.0,
        (json['offsetY'] as num?)?.toDouble() ?? 4.0,
      ),
      blurRadius: (json['blurRadius'] as num?)?.toDouble() ?? 8.0,
      spread: (json['spread'] as num?)?.toDouble() ?? 0.0,
      isEnabled: json['isEnabled'] as bool? ?? true,
    );
  }

  DropShadowEffect copyWith({
    ui.Color? color,
    ui.Offset? offset,
    double? blurRadius,
    double? spread,
    bool? isEnabled,
  }) => DropShadowEffect(
    color: color ?? this.color,
    offset: offset ?? this.offset,
    blurRadius: blurRadius ?? this.blurRadius,
    spread: spread ?? this.spread,
    isEnabled: isEnabled ?? this.isEnabled,
  );
}

// ---------------------------------------------------------------------------
// Inner Shadow Effect
// ---------------------------------------------------------------------------

/// Shadow rendered inside the node's shape.
///
/// Implementation: draws the node, then uses `BlendMode.dstOut` with
/// a blurred inset to create the inner shadow illusion.
class InnerShadowEffect extends NodeEffect {
  ui.Color color;
  ui.Offset offset;
  double blurRadius;

  InnerShadowEffect({
    this.color = const ui.Color(0x44000000),
    this.offset = const ui.Offset(2, 2),
    this.blurRadius = 6.0,
    super.isEnabled,
  });

  @override
  String get effectType => 'innerShadow';

  @override
  bool get isPost => true;

  double get sigma => blurRadius * 0.5;

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'color': color.toARGB32(),
    'offsetX': offset.dx,
    'offsetY': offset.dy,
    'blurRadius': blurRadius,
  };

  factory InnerShadowEffect.fromJson(Map<String, dynamic> json) {
    return InnerShadowEffect(
      color: ui.Color((json['color'] as int?)?.toUnsigned(32) ?? 0x44000000),
      offset: ui.Offset(
        (json['offsetX'] as num?)?.toDouble() ?? 2.0,
        (json['offsetY'] as num?)?.toDouble() ?? 2.0,
      ),
      blurRadius: (json['blurRadius'] as num?)?.toDouble() ?? 6.0,
      isEnabled: json['isEnabled'] as bool? ?? true,
    );
  }

  InnerShadowEffect copyWith({
    ui.Color? color,
    ui.Offset? offset,
    double? blurRadius,
    bool? isEnabled,
  }) => InnerShadowEffect(
    color: color ?? this.color,
    offset: offset ?? this.offset,
    blurRadius: blurRadius ?? this.blurRadius,
    isEnabled: isEnabled ?? this.isEnabled,
  );
}

// ---------------------------------------------------------------------------
// Outer Glow Effect
// ---------------------------------------------------------------------------

/// Glow effect rendered behind the node using additive blending.
///
/// Visually similar to a drop shadow but with `BlendMode.plus` for
/// a light emission effect.
class OuterGlowEffect extends NodeEffect {
  ui.Color color;
  double blurRadius;
  double spread;

  OuterGlowEffect({
    this.color = const ui.Color(0x88FFAA00),
    this.blurRadius = 12.0,
    this.spread = 0.0,
    super.isEnabled,
  });

  @override
  String get effectType => 'outerGlow';

  @override
  bool get isPre => true;

  /// Create the Paint for the glow layer.
  ui.Paint createGlowPaint() {
    return ui.Paint()
      ..color = color
      ..blendMode = ui.BlendMode.plus
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, blurRadius * 0.5);
  }

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'color': color.toARGB32(),
    'blurRadius': blurRadius,
    'spread': spread,
  };

  factory OuterGlowEffect.fromJson(Map<String, dynamic> json) {
    return OuterGlowEffect(
      color: ui.Color((json['color'] as int?)?.toUnsigned(32) ?? 0x88FFAA00),
      blurRadius: (json['blurRadius'] as num?)?.toDouble() ?? 12.0,
      spread: (json['spread'] as num?)?.toDouble() ?? 0.0,
      isEnabled: json['isEnabled'] as bool? ?? true,
    );
  }

  OuterGlowEffect copyWith({
    ui.Color? color,
    double? blurRadius,
    double? spread,
    bool? isEnabled,
  }) => OuterGlowEffect(
    color: color ?? this.color,
    blurRadius: blurRadius ?? this.blurRadius,
    spread: spread ?? this.spread,
    isEnabled: isEnabled ?? this.isEnabled,
  );
}

// ---------------------------------------------------------------------------
// Color Overlay Effect
// ---------------------------------------------------------------------------

/// Applies a solid color tint over the node using a [ColorFilter].
class ColorOverlayEffect extends NodeEffect {
  ui.Color color;
  ui.BlendMode blendMode;

  ColorOverlayEffect({
    this.color = const ui.Color(0x44FF0000),
    this.blendMode = ui.BlendMode.srcATop,
    super.isEnabled,
  });

  @override
  String get effectType => 'colorOverlay';

  @override
  bool get isPost => true;

  /// Create the Paint for saveLayer that applies the color overlay.
  ui.Paint createPaint() {
    return ui.Paint()..colorFilter = ui.ColorFilter.mode(color, blendMode);
  }

  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'color': color.toARGB32(),
    'blendMode': blendMode.name,
  };

  factory ColorOverlayEffect.fromJson(Map<String, dynamic> json) {
    return ColorOverlayEffect(
      color: ui.Color((json['color'] as int?)?.toUnsigned(32) ?? 0x44FF0000),
      blendMode: ui.BlendMode.values.firstWhere(
        (m) => m.name == json['blendMode'],
        orElse: () => ui.BlendMode.srcATop,
      ),
      isEnabled: json['isEnabled'] as bool? ?? true,
    );
  }

  ColorOverlayEffect copyWith({
    ui.Color? color,
    ui.BlendMode? blendMode,
    bool? isEnabled,
  }) => ColorOverlayEffect(
    color: color ?? this.color,
    blendMode: blendMode ?? this.blendMode,
    isEnabled: isEnabled ?? this.isEnabled,
  );
}
