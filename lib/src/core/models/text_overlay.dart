import 'dart:ui';

/// A text overlay placed on an image.
///
/// Each overlay has position (relative to image), text content, style,
/// and optional rotation. Position is in normalized coordinates (0.0-1.0).
class TextOverlay {
  final String id;
  final String text;
  final double x; // 0.0 (left) to 1.0 (right)
  final double y; // 0.0 (top) to 1.0 (bottom)
  final double fontSize; // in logical pixels
  final int color; // Color.value
  final String? fontFamily; // 'sans-serif', 'serif', 'monospace'
  final bool bold;
  final bool italic;
  final double rotation; // radians
  final double opacity; // 0.0 to 1.0
  final int shadowColor; // shadow Color.value, 0 = no shadow

  const TextOverlay({
    required this.id,
    required this.text,
    this.x = 0.5,
    this.y = 0.5,
    this.fontSize = 24,
    this.color = 0xFFFFFFFF,
    this.fontFamily = 'sans-serif',
    this.bold = false,
    this.italic = false,
    this.rotation = 0,
    this.opacity = 1.0,
    this.shadowColor = 0x80000000,
  });

  TextOverlay copyWith({
    String? text,
    double? x,
    double? y,
    double? fontSize,
    int? color,
    String? fontFamily,
    bool? bold,
    bool? italic,
    double? rotation,
    double? opacity,
    int? shadowColor,
  }) {
    return TextOverlay(
      id: id,
      text: text ?? this.text,
      x: x ?? this.x,
      y: y ?? this.y,
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      fontFamily: fontFamily ?? this.fontFamily,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      rotation: rotation ?? this.rotation,
      opacity: opacity ?? this.opacity,
      shadowColor: shadowColor ?? this.shadowColor,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'x': x,
    'y': y,
    'fontSize': fontSize,
    'color': color,
    'fontFamily': fontFamily,
    'bold': bold,
    'italic': italic,
    'rotation': rotation,
    'opacity': opacity,
    'shadowColor': shadowColor,
  };

  factory TextOverlay.fromJson(Map<String, dynamic> json) => TextOverlay(
    id: json['id'] as String? ?? '',
    text: json['text'] as String? ?? '',
    x: (json['x'] as num?)?.toDouble() ?? 0.5,
    y: (json['y'] as num?)?.toDouble() ?? 0.5,
    fontSize: (json['fontSize'] as num?)?.toDouble() ?? 24,
    color: (json['color'] as num?)?.toInt() ?? 0xFFFFFFFF,
    fontFamily: json['fontFamily'] as String? ?? 'sans-serif',
    bold: json['bold'] as bool? ?? false,
    italic: json['italic'] as bool? ?? false,
    rotation: (json['rotation'] as num?)?.toDouble() ?? 0,
    opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
    shadowColor: (json['shadowColor'] as num?)?.toInt() ?? 0x80000000,
  );
}
