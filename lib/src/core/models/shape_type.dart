import 'package:flutter/material.dart';
import '../effects/gradient_fill.dart';

/// Tipi di figure geometriche disegnabili
enum ShapeType {
  /// Method `freehand`.
  freehand, // Disegno a mano libera (default)
  /// API element `line`.
  line, // Linea retta
  /// API element `rectangle`.
  rectangle, // Rettangolo
  /// API element `circle`.
  circle, // Cerchio/Ellisse
  /// API element `triangle`.
  triangle, // Triangolo
  /// API element `arrow`.
  arrow, // Freccia
  /// API element `star`.
  star, // Stella a 5 punte
  /// API element `heart`.
  heart, // Cuore
  /// API element `diamond`.
  diamond, // Rombo
  /// API element `pentagon`.
  pentagon, // Pentagono
  /// API element `hexagon`.
  hexagon, // Esagono
}

/// Modello per a geometric shape
class GeometricShape {
  /// Field `id`.
  final String id;
  /// Field `type`.
  final ShapeType type;
  /// Field `startPoint`.
  final Offset startPoint;
  /// Field `endPoint`.
  final Offset endPoint;
  /// Field `color`.
  final Color color;
  /// Field `strokeWidth`.
  final double strokeWidth;
  /// Field `filled`.
  final bool filled;
  /// Field `createdAt`.
  final DateTime createdAt;
  /// Field `fillGradient`.
  final GradientFill? fillGradient;
  /// Field `strokeGradient`.
  final GradientFill? strokeGradient;
  /// Method `rotation`.
  final double rotation; // Rotation angle in radians (for rotated shapes)

  /// API element `GeometricShape`.
  GeometricShape({
    required this.id,
    required this.type,
    required this.startPoint,
    required this.endPoint,
    required this.color,
    required this.strokeWidth,
    this.filled = false,
    required this.createdAt,
    this.fillGradient,
    this.strokeGradient,
    this.rotation = 0.0,
  });

  /// Copia con modifiche
  GeometricShape copyWith({
    String? id,
    ShapeType? type,
    Offset? startPoint,
    Offset? endPoint,
    Color? color,
    double? strokeWidth,
    bool? filled,
    DateTime? createdAt,
    GradientFill? fillGradient,
    GradientFill? strokeGradient,
    double? rotation,
  }) {
    return GeometricShape(
      id: id ?? this.id,
      type: type ?? this.type,
      startPoint: startPoint ?? this.startPoint,
      endPoint: endPoint ?? this.endPoint,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      filled: filled ?? this.filled,
      createdAt: createdAt ?? this.createdAt,
      fillGradient: fillGradient ?? this.fillGradient,
      strokeGradient: strokeGradient ?? this.strokeGradient,
      rotation: rotation ?? this.rotation,
    );
  }

  /// Serializezione JSON
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'startPoint': {'dx': startPoint.dx, 'dy': startPoint.dy},
    'endPoint': {'dx': endPoint.dx, 'dy': endPoint.dy},
    'color': color.toARGB32(),
    'strokeWidth': strokeWidth,
    'filled': filled,
    'createdAt': createdAt.toIso8601String(),
    if (fillGradient != null) 'fillGradient': fillGradient!.toJson(),
    if (strokeGradient != null) 'strokeGradient': strokeGradient!.toJson(),
    if (rotation != 0.0) 'rotation': rotation,
  };

  /// Deserializzazione JSON
  factory GeometricShape.fromJson(Map<String, dynamic> json) {
    return GeometricShape(
      id: json['id'] as String,
      type: ShapeType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => ShapeType.freehand,
      ),
      startPoint: Offset(
        (json['startPoint']['dx'] as num).toDouble(),
        (json['startPoint']['dy'] as num).toDouble(),
      ),
      endPoint: Offset(
        (json['endPoint']['dx'] as num).toDouble(),
        (json['endPoint']['dy'] as num).toDouble(),
      ),
      color: Color(json['color'] as int),
      strokeWidth: (json['strokeWidth'] as num).toDouble(),
      filled: json['filled'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
      fillGradient:
          json['fillGradient'] != null
              ? GradientFill.fromJson(
                json['fillGradient'] as Map<String, dynamic>,
              )
              : null,
      strokeGradient:
          json['strokeGradient'] != null
              ? GradientFill.fromJson(
                json['strokeGradient'] as Map<String, dynamic>,
              )
              : null,
      rotation: (json['rotation'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
