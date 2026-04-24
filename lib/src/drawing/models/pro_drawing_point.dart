import 'dart:convert' as convert;
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import './pro_brush_settings.dart';

/// Punto di disegno professionale con metadati completi
class ProDrawingPoint {
  final Offset position;
  final double pressure;
  final double tiltX;
  final double tiltY;
  final double orientation;
  final int timestamp;

  const ProDrawingPoint({
    required this.position,
    required this.pressure,
    this.tiltX = 0.0,
    this.tiltY = 0.0,
    this.orientation = 0.0,
    this.timestamp = 0,
  });

  /// Getter per compatibility con OptimizedPathBuilder
  Offset get offset => position;

  /// Serialize as compact array: [x, y, p?, tx?, ty?, o?]
  ///
  /// 🚀 OTTIMIZZAZIONE v4: Array format + 3 decimal coordinates
  /// - Array: no key overhead (saves ~40% vs object keys)
  /// - 3 decimali: 0.001px precision — visually identical, Catmull-Rom safe
  /// - Trailing optional fields omitted if zero/default
  ///
  /// Risultato: ~17 bytes/punto (era ~70 in v1) → -75% storage
  dynamic toJson() {
    // Build from the end, trimming trailing defaults
    final hasO = orientation != 0.0;
    final hasTY = tiltY != 0.0 || hasO;
    final hasTX = tiltX != 0.0 || hasTY;
    final hasP = pressure != 1.0 || hasTX;

    if (hasO) {
      return [
        _r3(position.dx),
        _r3(position.dy),
        _r2(pressure),
        _r2(tiltX),
        _r2(tiltY),
        _r2(orientation),
      ];
    } else if (hasTY) {
      return [
        _r3(position.dx),
        _r3(position.dy),
        _r2(pressure),
        _r2(tiltX),
        _r2(tiltY),
      ];
    } else if (hasTX) {
      return [_r3(position.dx), _r3(position.dy), _r2(pressure), _r2(tiltX)];
    } else if (hasP) {
      return [_r3(position.dx), _r3(position.dy), _r2(pressure)];
    }
    return [_r3(position.dx), _r3(position.dy)];
  }

  /// Round to 3 decimals (coordinates — 0.001px, smooth enough)
  static double _r3(double v) => (v * 1000).roundToDouble() / 1000;

  /// Round to 2 decimals (pressure, tilt, orientation)
  static double _r2(double v) => (v * 100).roundToDouble() / 100;

  /// Parse from array [x, y, p?, tx?, ty?, o?] or legacy object {x, y, ...}
  factory ProDrawingPoint.fromJson(dynamic json) {
    // 🚀 v4: Compact array format
    if (json is List) {
      return ProDrawingPoint(
        position: Offset(
          (json[0] as num).toDouble(),
          (json[1] as num).toDouble(),
        ),
        pressure: json.length > 2 ? (json[2] as num).toDouble() : 1.0,
        tiltX: json.length > 3 ? (json[3] as num).toDouble() : 0.0,
        tiltY: json.length > 4 ? (json[4] as num).toDouble() : 0.0,
        orientation: json.length > 5 ? (json[5] as num).toDouble() : 0.0,
      );
    }

    // Legacy: object format {x, y, pressure/p, tiltX/tx, ...}
    final map =
        json is Map<String, dynamic>
            ? json
            : Map<String, dynamic>.from(json as Map);
    return ProDrawingPoint(
      position: Offset(
        (map['x'] as num).toDouble(),
        (map['y'] as num).toDouble(),
      ),
      pressure:
          (map['p'] as num?)?.toDouble() ??
          (map['pressure'] as num?)?.toDouble() ??
          1.0,
      tiltX:
          (map['tx'] as num?)?.toDouble() ??
          (map['tiltX'] as num?)?.toDouble() ??
          0.0,
      tiltY:
          (map['ty'] as num?)?.toDouble() ??
          (map['tiltY'] as num?)?.toDouble() ??
          0.0,
      orientation:
          (map['o'] as num?)?.toDouble() ??
          (map['orientation'] as num?)?.toDouble() ??
          0.0,
      timestamp: (map['timestamp'] as int?) ?? 0,
    );
  }

  ProDrawingPoint copyWith({
    Offset? position,
    double? pressure,
    double? tiltX,
    double? tiltY,
    double? orientation,
    int? timestamp,
  }) {
    return ProDrawingPoint(
      position: position ?? this.position,
      pressure: pressure ?? this.pressure,
      tiltX: tiltX ?? this.tiltX,
      tiltY: tiltY ?? this.tiltY,
      orientation: orientation ?? this.orientation,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// Complete professional stroke
class ProStroke {
  final String id;
  final List<ProDrawingPoint> points;
  final Color color;
  final double baseWidth;
  final ProPenType penType;
  final DateTime createdAt;
  final ProBrushSettings settings; // 🎛️ Parametri pennello personalizzati

  /// 🛡️ Engine version that produced this stroke.
  /// Permette migration/fallback se l'algoritmo di un brush cambia.
  /// - v1: strokes without tag (pre-versioning, backward compatible)
  /// - v2: first tagged version (current)
  /// Incrementare when modifica il comportamento di un brush.
  final int engineVersion;

  /// 🖼️ Image scale at the time this stroke was drawn.
  /// Used to proportionally scale strokes when the image is resized.
  /// Defaults to 1.0 for canvas strokes or legacy image strokes.
  final double referenceScale;

  /// Current rendering engine version
  static const int currentEngineVersion = 2;

  /// 🪣 Fill overlay — transient raster image (not serialized)
  /// Stored in canvas-space coordinates; rendered at fillBounds position
  ui.Image? fillOverlay;
  Rect? fillBounds;

  /// True if this stroke is a fill operation (has raster overlay)
  bool get isFill => fillOverlay != null && fillBounds != null;

  /// Dispose fill overlay image to free GPU memory
  void disposeFillOverlay() {
    fillOverlay?.dispose();
    fillOverlay = null;
    fillBounds = null;
  }

  /// 🚀 CACHED BOUNDS - Calculateto una sola volta for performance O(1)
  /// Avoids O(n) recalculation at every frame during viewport culling
  Rect? _cachedBounds;

  /// 🚀 CACHED PATH - Catmull-Rom path computed once, reused every frame.
  /// Strokes are immutable after commit → path never changes.
  /// Stored in an Expando (not an instance field) because ui.Path is a
  /// native object that CANNOT cross isolate boundaries. Storing it as
  /// a field on ProStroke would crash the save isolate.
  /// Expando: auto-cleaned when ProStroke is GC'd, O(1) lookup.
  static final Expando<ui.Path> _pathCache = Expando<ui.Path>('strokePath');

  /// Get or compute the cached Catmull-Rom path for this stroke.
  ui.Path get cachedPath {
    var path = _pathCache[this];
    if (path == null) {
      path = _buildCatmullRomPathImpl();
      _pathCache[this] = path;
    }
    return path;
  }


  ui.Path _buildCatmullRomPathImpl() {
    final path = ui.Path();
    if (points.isEmpty) return path;
    final first = points.first.position;
    path.moveTo(first.dx, first.dy);
    if (points.length == 1) return path;
    if (points.length == 2) {
      final p = points[1].position;
      path.lineTo(p.dx, p.dy);
      return path;
    }
    if (points.length == 3) {
      final p1 = points[1].position;
      final p2 = points[2].position;
      path.quadraticBezierTo(p1.dx, p1.dy, p2.dx, p2.dy);
      return path;
    }
    // Catmull-Rom spline (same algorithm as OptimizedPathBuilder)
    for (int i = 0; i < points.length - 1; i++) {
      final p0 = i > 0 ? points[i - 1].position : points[i].position;
      final p1 = points[i].position;
      final p2 = points[i + 1].position;
      final p3 =
          i < points.length - 2
              ? points[i + 2].position
              : points[i + 1].position;
      path.cubicTo(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
        p2.dx,
        p2.dy,
      );
    }
    return path;
  }

  /// 🗂️ STUB SUPPORT: forced bounds for paged-out strokes.
  /// When a stroke is paged out, its points are dropped but bounds are kept.
  final Rect? _forcedBounds;

  /// Whether this stroke is a stub (paged out to disk, points empty).
  bool get isStub => _forcedBounds != null && points.isEmpty;

  ProStroke({
    required this.id,
    required List<ProDrawingPoint> points,
    required this.color,
    required this.baseWidth,
    required this.penType,
    required this.createdAt,
    ProBrushSettings? settings,
    int? engineVersion,
    this.referenceScale = 1.0,
    this.fillOverlay,
    this.fillBounds,
    Rect? forcedBounds,
  }) : points = List.unmodifiable(points),
       settings = settings ?? const ProBrushSettings(),
       engineVersion = engineVersion ?? currentEngineVersion,
       _forcedBounds = forcedBounds;

  /// 🗂️ Create a lightweight stub copy (bounds only, no points).
  /// Used by StrokePagingManager to free memory while keeping R-Tree working.
  ProStroke toStub() {
    final b = bounds; // Force calculation before dropping points
    return ProStroke(
      id: id,
      points: const [],
      color: color,
      baseWidth: baseWidth,
      penType: penType,
      createdAt: createdAt,
      settings: settings,
      engineVersion: engineVersion,
      referenceScale: referenceScale,
      forcedBounds: b,
    );
  }

  /// 🗂️ Create a stub from bounds only (for lazy-load index).
  /// Minimal allocation: only id + bounds are meaningful.
  factory ProStroke.stubFromBounds({required String id, required Rect bounds}) {
    return ProStroke(
      id: id,
      points: const [],
      color: const Color(0xFF000000),
      baseWidth: 2.0,
      penType: ProPenType.ballpoint,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      forcedBounds: bounds,
    );
  }

  /// 🚀 Bounds cachato - calcola una volta e riusa
  /// Performance: from O(n) every frame to O(1) after first calculation
  Rect get bounds {
    if (_forcedBounds != null) return _forcedBounds;
    _cachedBounds ??= _calculateBounds();
    return _cachedBounds!;
  }

  /// Calculates bounds of the stroke (chiamato una sola volta)
  Rect _calculateBounds() {
    if (points.isEmpty) {
      return Rect.zero;
    }

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final point in points) {
      if (point.position.dx < minX) minX = point.position.dx;
      if (point.position.dy < minY) minY = point.position.dy;
      if (point.position.dx > maxX) maxX = point.position.dx;
      if (point.position.dy > maxY) maxY = point.position.dy;
    }

    // Add padding for the stroke width
    final padding = baseWidth * 2;

    return Rect.fromLTRB(
      minX - padding,
      minY - padding,
      maxX + padding,
      maxY + padding,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'ev': engineVersion, // 🛡️ Engine version tag
    'points': points.map((p) => p.toJson()).toList(),
    'color': color.toARGB32(),
    'baseWidth': baseWidth,
    'penType': penType.toString(),
    'createdAt': createdAt.toIso8601String(),
    // 🎛️ Save settings only thef not sono i default (ottimizza storage)
    if (!settings.isDefault) 'settings': settings.toJson(),
    if (referenceScale != 1.0) 'rs': referenceScale,
  };

  factory ProStroke.fromJson(Map<String, dynamic> json) => ProStroke(
    id: json['id'] as String,
    // 🛡️ Old strokes without 'ev' are version 1 (pre-versioning)
    engineVersion: (json['ev'] as int?) ?? 1,
    points: () {
      final raw = json['points'];
      List pointsList;
      if (raw is List) {
        pointsList = raw;
      } else if (raw is String) {
        // Firestore may serialize List as JSON string
        try {
          pointsList = convert.jsonDecode(raw) as List;
        } catch (_) {
          pointsList = [];
        }
      } else {
        pointsList = [];
      }
      return pointsList.map((p) => ProDrawingPoint.fromJson(p)).toList();
    }(),
    color: Color(json['color'] as int),
    baseWidth: (json['baseWidth'] as num).toDouble(),
    penType: ProPenType.values.firstWhere(
      (e) => e.toString() == json['penType'],
      orElse: () => ProPenType.ballpoint,
    ),
    createdAt: DateTime.parse(json['createdAt'] as String),
    settings: ProBrushSettings.fromJson(
      json['settings'] is Map
          ? Map<String, dynamic>.from(json['settings'] as Map)
          : null,
    ),
    referenceScale: (json['rs'] as num?)?.toDouble() ?? 1.0,
  );

  ProStroke copyWith({
    String? id,
    List<ProDrawingPoint>? points,
    Color? color,
    double? baseWidth,
    ProPenType? penType,
    DateTime? createdAt,
    ProBrushSettings? settings,
    int? engineVersion,
    double? referenceScale,
  }) {
    return ProStroke(
      id: id ?? this.id,
      points: points ?? this.points,
      color: color ?? this.color,
      baseWidth: baseWidth ?? this.baseWidth,
      penType: penType ?? this.penType,
      createdAt: createdAt ?? this.createdAt,
      settings: settings ?? this.settings,
      engineVersion: engineVersion ?? this.engineVersion,
      referenceScale: referenceScale ?? this.referenceScale,
    );
  }
}

/// Professional pen types
enum ProPenType {
  ballpoint, // Ball-point pen
  fountain, // Fountain pen
  pencil, // Pencil
  highlighter, // Highlighter
  watercolor, // Watercolor brush (wet-on-wet diffusion)
  marker, // Flat marker (saturated alpha accumulation)
  charcoal, // Charcoal stick (grain erosion + noise)
  oilPaint, // Oil paint (GPU impasto texture + directional smear)
  sprayPaint, // Spray paint (GPU stochastic dots + gaussian falloff)
  neonGlow, // Neon glow (GPU multi-layer bloom + bright core)
  inkWash, // Ink wash (GPU wet-ink diffusion + bleed edges)
  technicalPen, // Technical pen (constant width, no taper, hard edges)
}
