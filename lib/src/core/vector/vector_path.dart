import 'dart:ui';
import 'dart:typed_data';

/// A single segment within a [VectorPath].
///
/// Every segment ends at [endPoint]. The segment type determines
/// how the path is drawn from the previous endpoint to this one.
abstract class PathSegment {
  Offset endPoint;

  PathSegment({required this.endPoint});

  /// Create a transformed copy of this segment.
  PathSegment transformed(Float64List matrix);

  /// Serialize to JSON.
  Map<String, dynamic> toJson();

  /// Deserialize from JSON.
  static PathSegment fromJson(Map<String, dynamic> json) {
    switch (json['segmentType'] as String) {
      case 'move':
        return MoveSegment.fromJson(json);
      case 'line':
        return LineSegment.fromJson(json);
      case 'cubic':
        return CubicSegment.fromJson(json);
      case 'quad':
        return QuadSegment.fromJson(json);
      default:
        throw ArgumentError('Unknown segmentType: ${json['segmentType']}');
    }
  }
}

// ---------------------------------------------------------------------------
// Segment types
// ---------------------------------------------------------------------------

/// Moves the pen to [endPoint] without drawing.
class MoveSegment extends PathSegment {
  MoveSegment({required super.endPoint});

  @override
  MoveSegment transformed(Float64List matrix) {
    return MoveSegment(endPoint: _transformPoint(endPoint, matrix));
  }

  @override
  Map<String, dynamic> toJson() => {
    'segmentType': 'move',
    'x': endPoint.dx,
    'y': endPoint.dy,
  };

  factory MoveSegment.fromJson(Map<String, dynamic> json) {
    return MoveSegment(
      endPoint: Offset(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      ),
    );
  }
}

/// A straight line to [endPoint].
class LineSegment extends PathSegment {
  LineSegment({required super.endPoint});

  @override
  LineSegment transformed(Float64List matrix) {
    return LineSegment(endPoint: _transformPoint(endPoint, matrix));
  }

  @override
  Map<String, dynamic> toJson() => {
    'segmentType': 'line',
    'x': endPoint.dx,
    'y': endPoint.dy,
  };

  factory LineSegment.fromJson(Map<String, dynamic> json) {
    return LineSegment(
      endPoint: Offset(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      ),
    );
  }
}

/// A cubic Bézier curve to [endPoint] with two control points.
class CubicSegment extends PathSegment {
  Offset controlPoint1;
  Offset controlPoint2;

  CubicSegment({
    required this.controlPoint1,
    required this.controlPoint2,
    required super.endPoint,
  });

  @override
  CubicSegment transformed(Float64List matrix) {
    return CubicSegment(
      controlPoint1: _transformPoint(controlPoint1, matrix),
      controlPoint2: _transformPoint(controlPoint2, matrix),
      endPoint: _transformPoint(endPoint, matrix),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'segmentType': 'cubic',
    'cp1x': controlPoint1.dx,
    'cp1y': controlPoint1.dy,
    'cp2x': controlPoint2.dx,
    'cp2y': controlPoint2.dy,
    'x': endPoint.dx,
    'y': endPoint.dy,
  };

  factory CubicSegment.fromJson(Map<String, dynamic> json) {
    return CubicSegment(
      controlPoint1: Offset(
        (json['cp1x'] as num).toDouble(),
        (json['cp1y'] as num).toDouble(),
      ),
      controlPoint2: Offset(
        (json['cp2x'] as num).toDouble(),
        (json['cp2y'] as num).toDouble(),
      ),
      endPoint: Offset(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      ),
    );
  }
}

/// A quadratic Bézier curve to [endPoint] with one control point.
class QuadSegment extends PathSegment {
  Offset controlPoint;

  QuadSegment({required this.controlPoint, required super.endPoint});

  @override
  QuadSegment transformed(Float64List matrix) {
    return QuadSegment(
      controlPoint: _transformPoint(controlPoint, matrix),
      endPoint: _transformPoint(endPoint, matrix),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'segmentType': 'quad',
    'cpx': controlPoint.dx,
    'cpy': controlPoint.dy,
    'x': endPoint.dx,
    'y': endPoint.dy,
  };

  factory QuadSegment.fromJson(Map<String, dynamic> json) {
    return QuadSegment(
      controlPoint: Offset(
        (json['cpx'] as num).toDouble(),
        (json['cpy'] as num).toDouble(),
      ),
      endPoint: Offset(
        (json['x'] as num).toDouble(),
        (json['y'] as num).toDouble(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// VectorPath
// ---------------------------------------------------------------------------

/// An ordered collection of [PathSegment]s that defines a vector shape.
///
/// The path always starts with a [MoveSegment]. It may be open or closed.
/// Use [toFlutterPath] to convert to a Flutter [Path] for rendering.
class VectorPath {
  final List<PathSegment> segments;
  bool isClosed;

  VectorPath({required this.segments, this.isClosed = false});

  /// Create an empty path starting at [start].
  factory VectorPath.moveTo(Offset start) {
    return VectorPath(segments: [MoveSegment(endPoint: start)]);
  }

  /// Convert to a Flutter [Path] for rendering/hit testing.
  Path toFlutterPath() {
    final path = Path();

    for (final seg in segments) {
      if (seg is MoveSegment) {
        path.moveTo(seg.endPoint.dx, seg.endPoint.dy);
      } else if (seg is LineSegment) {
        path.lineTo(seg.endPoint.dx, seg.endPoint.dy);
      } else if (seg is CubicSegment) {
        path.cubicTo(
          seg.controlPoint1.dx,
          seg.controlPoint1.dy,
          seg.controlPoint2.dx,
          seg.controlPoint2.dy,
          seg.endPoint.dx,
          seg.endPoint.dy,
        );
      } else if (seg is QuadSegment) {
        path.quadraticBezierTo(
          seg.controlPoint.dx,
          seg.controlPoint.dy,
          seg.endPoint.dx,
          seg.endPoint.dy,
        );
      }
    }

    if (isClosed) path.close();
    return path;
  }

  /// Compute the tight bounding box of this path.
  Rect computeBounds() {
    return toFlutterPath().getBounds();
  }

  /// Create a transformed copy of this path.
  VectorPath transformed(Float64List matrix) {
    return VectorPath(
      segments: segments.map((s) => s.transformed(matrix)).toList(),
      isClosed: isClosed,
    );
  }

  /// Serialize to JSON.
  Map<String, dynamic> toJson() => {
    'isClosed': isClosed,
    'segments': segments.map((s) => s.toJson()).toList(),
  };

  /// Deserialize from JSON.
  factory VectorPath.fromJson(Map<String, dynamic> json) {
    final segList =
        (json['segments'] as List<dynamic>)
            .map((s) => PathSegment.fromJson(s as Map<String, dynamic>))
            .toList();
    return VectorPath(
      segments: segList,
      isClosed: json['isClosed'] as bool? ?? false,
    );
  }

  // -------------------------------------------------------------------------
  // Builder helpers
  // -------------------------------------------------------------------------

  /// Append a line segment.
  void lineTo(double x, double y) {
    segments.add(LineSegment(endPoint: Offset(x, y)));
  }

  /// Append a cubic Bézier segment.
  void cubicTo(
    double cp1x,
    double cp1y,
    double cp2x,
    double cp2y,
    double x,
    double y,
  ) {
    segments.add(
      CubicSegment(
        controlPoint1: Offset(cp1x, cp1y),
        controlPoint2: Offset(cp2x, cp2y),
        endPoint: Offset(x, y),
      ),
    );
  }

  /// Append a quadratic Bézier segment.
  void quadTo(double cpx, double cpy, double x, double y) {
    segments.add(
      QuadSegment(controlPoint: Offset(cpx, cpy), endPoint: Offset(x, y)),
    );
  }

  /// Close the path.
  void close() {
    isClosed = true;
  }

  /// The starting point (from the first MoveSegment).
  Offset? get startPoint {
    if (segments.isEmpty) return null;
    return segments.first.endPoint;
  }

  /// Total number of anchor points (one per segment).
  int get anchorCount => segments.length;

  /// Convert to SVG path `d` attribute string.
  ///
  /// Generates M (move), L (line), C (cubic) commands.
  String toSvgPathData() {
    final sb = StringBuffer();
    for (final seg in segments) {
      if (seg is MoveSegment) {
        sb.write('M ${seg.endPoint.dx} ${seg.endPoint.dy} ');
      } else if (seg is LineSegment) {
        sb.write('L ${seg.endPoint.dx} ${seg.endPoint.dy} ');
      } else if (seg is CubicSegment) {
        sb.write(
          'C ${seg.controlPoint1.dx} ${seg.controlPoint1.dy} '
          '${seg.controlPoint2.dx} ${seg.controlPoint2.dy} '
          '${seg.endPoint.dx} ${seg.endPoint.dy} ',
        );
      }
    }
    if (isClosed) sb.write('Z');
    return sb.toString().trim();
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Transform a point by a 4x4 matrix (stored as Float64List).
Offset _transformPoint(Offset point, Float64List m) {
  final x = point.dx;
  final y = point.dy;
  final w = m[3] * x + m[7] * y + m[15];
  return Offset(
    (m[0] * x + m[4] * y + m[12]) / w,
    (m[1] * x + m[5] * y + m[13]) / w,
  );
}
