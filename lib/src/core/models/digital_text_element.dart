import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Rich Text Span — per-segment style override
// ---------------------------------------------------------------------------

/// A styled segment within a rich text element.
///
/// Each span carries its own text and optional style overrides.
/// `null` values inherit from the parent [DigitalTextElement].
class DigitalTextSpan {
  final String text;
  final Color? color;
  final FontWeight? fontWeight;
  final FontStyle? fontStyle;
  final double? fontSize;
  final TextDecoration? textDecoration;
  final double? letterSpacing;

  const DigitalTextSpan({
    required this.text,
    this.color,
    this.fontWeight,
    this.fontStyle,
    this.fontSize,
    this.textDecoration,
    this.letterSpacing,
  });

  DigitalTextSpan copyWith({
    String? text,
    Color? color,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? fontSize,
    TextDecoration? textDecoration,
    double? letterSpacing,
  }) {
    return DigitalTextSpan(
      text: text ?? this.text,
      color: color ?? this.color,
      fontWeight: fontWeight ?? this.fontWeight,
      fontStyle: fontStyle ?? this.fontStyle,
      fontSize: fontSize ?? this.fontSize,
      textDecoration: textDecoration ?? this.textDecoration,
      letterSpacing: letterSpacing ?? this.letterSpacing,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      if (color != null) 'color': color!.toARGB32(),
      if (fontWeight != null) 'fontWeight': fontWeight!.index,
      if (fontStyle != null)
        'fontStyle': fontStyle == FontStyle.italic ? 'italic' : 'normal',
      if (fontSize != null) 'fontSize': fontSize,
      if (textDecoration != null)
        'textDecoration': _serializeDecoration(textDecoration!),
      if (letterSpacing != null) 'letterSpacing': letterSpacing,
    };
  }

  factory DigitalTextSpan.fromJson(Map<String, dynamic> json) {
    return DigitalTextSpan(
      text: json['text'] as String,
      color: json['color'] != null ? Color(json['color'] as int) : null,
      fontWeight:
          json['fontWeight'] != null
              ? FontWeight.values[json['fontWeight'] as int]
              : null,
      fontStyle:
          json['fontStyle'] != null
              ? (json['fontStyle'] == 'italic'
                  ? FontStyle.italic
                  : FontStyle.normal)
              : null,
      fontSize: (json['fontSize'] as num?)?.toDouble(),
      textDecoration:
          json['textDecoration'] != null
              ? _parseDecorationStatic(json['textDecoration'] as String)
              : null,
      letterSpacing: (json['letterSpacing'] as num?)?.toDouble(),
    );
  }

  static String _serializeDecoration(TextDecoration d) {
    if (d == TextDecoration.underline) return 'underline';
    if (d == TextDecoration.lineThrough) return 'lineThrough';
    if (d == TextDecoration.overline) return 'overline';
    return 'none';
  }

  static TextDecoration _parseDecorationStatic(String value) {
    switch (value) {
      case 'underline':
        return TextDecoration.underline;
      case 'lineThrough':
        return TextDecoration.lineThrough;
      case 'overline':
        return TextDecoration.overline;
      default:
        return TextDecoration.none;
    }
  }
}

// ---------------------------------------------------------------------------
// Digital Text Element
// ---------------------------------------------------------------------------

/// Sentinel value for copyWith — distinguishes "not provided" from explicit null.
const Object _sentinel = Object();

/// 📝 Digital text element on the canvas
///
/// Represents text inserted via keyboard with support for:
/// - Free positioning on canvas (absolute coordinates)
/// - Scaling (resize via handles)
/// - Selection and dragging
/// - JSON persistence and serialization
/// - OCR mode (text recognized from handwriting)
///
/// 🚀 PERFORMANCE: Layout is cached via [layoutPainter]. The TextPainter is
/// created lazily on first access and reused for subsequent calls to
/// [getBounds], [containsPoint], and by [DigitalTextPainter.paint].
/// Since [copyWith] returns a new instance, the cache is automatically
/// invalidated (new instance = null cache fields).
class DigitalTextElement {
  final String id;
  final String text;
  final Offset position;
  final Color color;
  final double fontSize;
  final FontWeight fontWeight;
  final FontStyle fontStyle;
  final String? fontFamily;
  final TextAlign textAlign;
  final TextDecoration textDecoration;
  final double letterSpacing;
  final double opacity;
  final double rotation; // radians
  final double scale;
  final bool isOCR;
  final int? pageIndex;
  final DateTime createdAt;
  final DateTime? modifiedAt;

  /// Optional text shadow
  final ui.Shadow? shadow;

  /// Optional background color behind the text (pill/label style)
  final Color? backgroundColor;

  /// Text outline/stroke color (null = no outline)
  final Color? outlineColor;

  /// Text outline/stroke width
  final double outlineWidth;

  /// Gradient colors for gradient text effect (null or empty = no gradient)
  final List<Color>? gradientColors;

  /// 🎨 Rich text spans — per-segment style overrides.
  /// When non-null, [text] is ignored in layout; spans provide the content.
  final List<DigitalTextSpan>? spans;

  /// 📦 Max width for auto-fit textbox (null = infinite, no word-wrap).
  /// When set, text wraps at this width (in canvas units, before scale).
  final double? maxWidth;

  // ── Layout cache (lazily initialized) ────────────────────────────────────
  TextPainter? _cachedPainter;
  Rect? _cachedBounds;

  DigitalTextElement({
    required this.id,
    required this.text,
    required this.position,
    required this.color,
    this.fontSize = 24.0,
    this.fontWeight = FontWeight.normal,
    this.fontStyle = FontStyle.normal,
    this.fontFamily = 'Roboto',
    this.textAlign = TextAlign.left,
    this.textDecoration = TextDecoration.none,
    this.letterSpacing = 0.0,
    this.opacity = 1.0,
    this.rotation = 0.0,
    this.scale = 1.0,
    this.isOCR = false,
    this.pageIndex,
    required this.createdAt,
    this.modifiedAt,
    this.shadow,
    this.backgroundColor,
    this.outlineColor,
    this.outlineWidth = 0.0,
    this.gradientColors,
    this.spans,
    this.maxWidth,
  });

  /// 🎨 Get the plain text content (from spans or text field)
  String get plainText {
    if (spans != null && spans!.isNotEmpty) {
      return spans!.map((s) => s.text).join();
    }
    return text;
  }

  DigitalTextElement copyWith({
    String? id,
    String? text,
    Offset? position,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    String? fontFamily,
    TextAlign? textAlign,
    TextDecoration? textDecoration,
    double? letterSpacing,
    double? opacity,
    double? rotation,
    double? scale,
    bool? isOCR,
    Object? pageIndex = _sentinel,
    DateTime? createdAt,
    Object? modifiedAt = _sentinel,
    Object? shadow = _sentinel,
    Object? backgroundColor = _sentinel,
    Object? outlineColor = _sentinel,
    double? outlineWidth,
    Object? gradientColors = _sentinel,
    Object? spans = _sentinel,
    Object? maxWidth = _sentinel,
  }) {
    return DigitalTextElement(
      id: id ?? this.id,
      text: text ?? this.text,
      position: position ?? this.position,
      color: color ?? this.color,
      fontSize: fontSize ?? this.fontSize,
      fontWeight: fontWeight ?? this.fontWeight,
      fontStyle: fontStyle ?? this.fontStyle,
      fontFamily: fontFamily ?? this.fontFamily,
      textAlign: textAlign ?? this.textAlign,
      textDecoration: textDecoration ?? this.textDecoration,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      opacity: opacity ?? this.opacity,
      rotation: rotation ?? this.rotation,
      scale: scale ?? this.scale,
      isOCR: isOCR ?? this.isOCR,
      pageIndex: pageIndex == _sentinel ? this.pageIndex : pageIndex as int?,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt == _sentinel ? this.modifiedAt : modifiedAt as DateTime?,
      shadow: shadow == _sentinel ? this.shadow : shadow as ui.Shadow?,
      backgroundColor: backgroundColor == _sentinel ? this.backgroundColor : backgroundColor as Color?,
      outlineColor: outlineColor == _sentinel ? this.outlineColor : outlineColor as Color?,
      outlineWidth: outlineWidth ?? this.outlineWidth,
      gradientColors: gradientColors == _sentinel ? this.gradientColors : gradientColors as List<Color>?,
      spans: spans == _sentinel ? this.spans : spans as List<DigitalTextSpan>?,
      maxWidth: maxWidth == _sentinel ? this.maxWidth : maxWidth as double?,
    );
  }

  /// 🎨 Apply a style override to a character range within spans.
  /// If no spans exist yet, creates initial spans from the text.
  DigitalTextElement applyStyleToRange({
    required int start,
    required int end,
    Color? color,
    FontWeight? fontWeight,
    FontStyle? fontStyle,
    double? fontSize,
    TextDecoration? textDecoration,
    double? letterSpacing,
  }) {
    // Build current spans from existing or from single text
    final currentSpans = spans ?? [DigitalTextSpan(text: text)];

    // Flatten to character list with per-char style
    final chars = <_StyledChar>[];
    for (final span in currentSpans) {
      for (int i = 0; i < span.text.length; i++) {
        chars.add(
          _StyledChar(
            char: span.text[i],
            color: span.color,
            fontWeight: span.fontWeight,
            fontStyle: span.fontStyle,
            fontSize: span.fontSize,
            textDecoration: span.textDecoration,
            letterSpacing: span.letterSpacing,
          ),
        );
      }
    }

    // Apply new style to the range
    for (int i = start; i < end && i < chars.length; i++) {
      chars[i] = _StyledChar(
        char: chars[i].char,
        color: color ?? chars[i].color,
        fontWeight: fontWeight ?? chars[i].fontWeight,
        fontStyle: fontStyle ?? chars[i].fontStyle,
        fontSize: fontSize ?? chars[i].fontSize,
        textDecoration: textDecoration ?? chars[i].textDecoration,
        letterSpacing: letterSpacing ?? chars[i].letterSpacing,
      );
    }

    // Merge consecutive chars with same style back into spans
    final newSpans = <DigitalTextSpan>[];
    if (chars.isEmpty) return this;

    var current = chars[0];
    var buffer = StringBuffer(current.char);
    for (int i = 1; i < chars.length; i++) {
      if (chars[i].sameStyle(current)) {
        buffer.write(chars[i].char);
      } else {
        newSpans.add(
          DigitalTextSpan(
            text: buffer.toString(),
            color: current.color,
            fontWeight: current.fontWeight,
            fontStyle: current.fontStyle,
            fontSize: current.fontSize,
            textDecoration: current.textDecoration,
            letterSpacing: current.letterSpacing,
          ),
        );
        current = chars[i];
        buffer = StringBuffer(current.char);
      }
    }
    newSpans.add(
      DigitalTextSpan(
        text: buffer.toString(),
        color: current.color,
        fontWeight: current.fontWeight,
        fontStyle: current.fontStyle,
        fontSize: current.fontSize,
        textDecoration: current.textDecoration,
        letterSpacing: current.letterSpacing,
      ),
    );

    return copyWith(
      text: chars.map((c) => c.char).join(),
      spans: newSpans,
      modifiedAt: DateTime.now(),
    );
  }

  // ── Layout caching ───────────────────────────────────────────────────────

  /// 🚀 Ensure [_cachedPainter] is valid. Creates a TextPainter on first call,
  /// reuses it on subsequent calls for the same instance.
  void _ensureLayout() {
    if (_cachedPainter != null) return;

    // Base style (used as default for all spans)
    final baseStyle = TextStyle(
      color: color.withValues(alpha: opacity),
      fontSize: fontSize * scale,
      fontWeight: fontWeight,
      fontStyle: fontStyle,
      fontFamily: fontFamily,
      decoration: textDecoration,
      letterSpacing: letterSpacing != 0.0 ? letterSpacing : null,
      shadows: shadow != null ? [shadow!] : null,
    );

    // 🎨 Rich text: build TextSpan with children from spans
    final TextSpan textSpan;
    if (spans != null && spans!.isNotEmpty) {
      textSpan = TextSpan(
        style: baseStyle,
        children:
            spans!.map((s) {
              return TextSpan(
                text: s.text,
                style: TextStyle(
                  color: s.color?.withValues(alpha: opacity),
                  fontSize: s.fontSize != null ? s.fontSize! * scale : null,
                  fontWeight: s.fontWeight,
                  fontStyle: s.fontStyle,
                  decoration: s.textDecoration,
                  letterSpacing: s.letterSpacing,
                ),
              );
            }).toList(),
      );
    } else {
      textSpan = TextSpan(text: text, style: baseStyle);
    }

    _cachedPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
    )..layout(maxWidth: maxWidth != null ? maxWidth! * scale : double.infinity);
  }

  /// 🧹 Clears the cached [TextPainter] so this element can safely cross
  /// an isolate boundary (TextPainter contains unsendable native objects).
  /// The cache will be lazily recreated on next access.
  void clearLayoutCache() {
    _cachedPainter?.dispose();
    _cachedPainter = null;
    _cachedBounds = null;
  }

  /// 🚀 Cached TextPainter — reused by [DigitalTextPainter.paint] to avoid
  /// per-frame allocation. Lazily created on first access.
  TextPainter get layoutPainter {
    _ensureLayout();
    return _cachedPainter!;
  }

  /// Calculates bounds of the text element (for hit testing and rendering).
  /// Result is cached per instance.
  Rect getBounds() {
    if (_cachedBounds != null) return _cachedBounds!;

    _ensureLayout();
    _cachedBounds = Rect.fromLTWH(
      position.dx,
      position.dy,
      _cachedPainter!.width,
      _cachedPainter!.height,
    );
    return _cachedBounds!;
  }

  /// Checks if a point touches this text element (rotation-aware).
  bool containsPoint(Offset point) {
    final bounds = getBounds();
    if (rotation == 0.0) return bounds.contains(point);

    // Un-rotate the test point around the element's position (top-left pivot,
    // matching drawing_painter_helpers.dart which rotates around position).
    final cosR = math.cos(-rotation);
    final sinR = math.sin(-rotation);
    final dx = point.dx - position.dx;
    final dy = point.dy - position.dy;
    final unrotated = Offset(
      position.dx + dx * cosR - dy * sinR,
      position.dy + dx * sinR + dy * cosR,
    );
    return bounds.contains(unrotated);
  }

  // ── Serialization ────────────────────────────────────────────────────────

  /// JSON serialization
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'position': {'x': position.dx, 'y': position.dy},
      'color': color.toARGB32(),
      'fontSize': fontSize,
      'fontWeight': fontWeight.index,
      'fontStyle': fontStyle == FontStyle.italic ? 'italic' : 'normal',
      'fontFamily': fontFamily,
      'textAlign': textAlign.name,
      'textDecoration': _serializeDecoration(textDecoration),
      if (letterSpacing != 0.0) 'letterSpacing': letterSpacing,
      if (opacity != 1.0) 'opacity': opacity,
      if (rotation != 0.0) 'rotation': rotation,
      'scale': scale,
      'isOCR': isOCR,
      'pageIndex': pageIndex,
      'createdAt': createdAt.toIso8601String(),
      'modifiedAt': modifiedAt?.toIso8601String(),
      if (shadow != null)
        'shadow': {
          'color': shadow!.color.toARGB32(),
          'blurRadius': shadow!.blurRadius,
          'dx': shadow!.offset.dx,
          'dy': shadow!.offset.dy,
        },
      if (backgroundColor != null)
        'backgroundColor': backgroundColor!.toARGB32(),
      if (outlineColor != null) 'outlineColor': outlineColor!.toARGB32(),
      if (outlineWidth > 0) 'outlineWidth': outlineWidth,
      if (gradientColors != null && gradientColors!.isNotEmpty)
        'gradientColors': gradientColors!.map((c) => c.toARGB32()).toList(),
      if (spans != null && spans!.isNotEmpty)
        'spans': spans!.map((s) => s.toJson()).toList(),
      if (maxWidth != null) 'maxWidth': maxWidth,
    };
  }

  static String _serializeDecoration(TextDecoration d) {
    if (d == TextDecoration.underline) return 'underline';
    if (d == TextDecoration.lineThrough) return 'lineThrough';
    if (d == TextDecoration.overline) return 'overline';
    return 'none';
  }

  static TextDecoration _parseDecoration(String? value) {
    switch (value) {
      case 'underline':
        return TextDecoration.underline;
      case 'lineThrough':
        return TextDecoration.lineThrough;
      case 'overline':
        return TextDecoration.overline;
      default:
        return TextDecoration.none;
    }
  }

  /// JSON deserialization
  factory DigitalTextElement.fromJson(Map<String, dynamic> json) {
    // Parse shadow if present
    ui.Shadow? shadow;
    if (json['shadow'] != null) {
      final s = json['shadow'] as Map<String, dynamic>;
      shadow = ui.Shadow(
        color: Color(s['color'] as int),
        blurRadius: (s['blurRadius'] as num).toDouble(),
        offset: Offset(
          (s['dx'] as num).toDouble(),
          (s['dy'] as num).toDouble(),
        ),
      );
    }

    return DigitalTextElement(
      id: json['id'] as String,
      text: json['text'] as String,
      position: Offset(
        (json['position']['x'] as num).toDouble(),
        (json['position']['y'] as num).toDouble(),
      ),
      color: Color(json['color'] as int),
      fontSize: (json['fontSize'] as num).toDouble(),
      fontWeight: FontWeight.values[json['fontWeight'] as int],
      fontStyle:
          json['fontStyle'] == 'italic' ? FontStyle.italic : FontStyle.normal,
      fontFamily: json['fontFamily'] as String,
      textAlign: _parseTextAlign(json['textAlign'] as String?),
      textDecoration: _parseDecoration(json['textDecoration'] as String?),
      letterSpacing: (json['letterSpacing'] as num?)?.toDouble() ?? 0.0,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
      scale: (json['scale'] as num).toDouble(),
      isOCR: json['isOCR'] as bool? ?? false,
      pageIndex: json['pageIndex'] as int?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      modifiedAt:
          json['modifiedAt'] != null
              ? DateTime.parse(json['modifiedAt'] as String)
              : null,
      shadow: shadow,
      backgroundColor:
          json['backgroundColor'] != null
              ? Color(json['backgroundColor'] as int)
              : null,
      outlineColor:
          json['outlineColor'] != null
              ? Color(json['outlineColor'] as int)
              : null,
      outlineWidth: (json['outlineWidth'] as num?)?.toDouble() ?? 0.0,
      gradientColors:
          json['gradientColors'] != null
              ? (json['gradientColors'] as List)
                  .map((c) => Color(c as int))
                  .toList()
              : null,
      spans:
          json['spans'] != null
              ? (json['spans'] as List)
                  .map(
                    (s) => DigitalTextSpan.fromJson(s as Map<String, dynamic>),
                  )
                  .toList()
              : null,
      maxWidth: (json['maxWidth'] as num?)?.toDouble(),
    );
  }

  static TextAlign _parseTextAlign(String? value) {
    switch (value) {
      case 'center':
        return TextAlign.center;
      case 'right':
        return TextAlign.right;
      case 'justify':
        return TextAlign.justify;
      default:
        return TextAlign.left;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DigitalTextElement &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'DigitalTextElement(id: $id, text: "$text", pos: $position, scale: $scale)';
}

// ---------------------------------------------------------------------------
// Private helper for per-character style tracking in applyStyleToRange
// ---------------------------------------------------------------------------

class _StyledChar {
  final String char;
  final Color? color;
  final FontWeight? fontWeight;
  final FontStyle? fontStyle;
  final double? fontSize;
  final TextDecoration? textDecoration;
  final double? letterSpacing;

  const _StyledChar({
    required this.char,
    this.color,
    this.fontWeight,
    this.fontStyle,
    this.fontSize,
    this.textDecoration,
    this.letterSpacing,
  });

  bool sameStyle(_StyledChar other) =>
      color == other.color &&
      fontWeight == other.fontWeight &&
      fontStyle == other.fontStyle &&
      fontSize == other.fontSize &&
      textDecoration == other.textDecoration &&
      letterSpacing == other.letterSpacing;
}
