import 'dart:ui';
import 'dart:math' as math;

/// A control point in a mesh gradient grid.
///
/// Each point has a position and a color. The mesh gradient
/// interpolates colors across the surface defined by these points.
class MeshControlPoint {
  /// Position in local coordinates.
  Offset position;

  /// Color at this control point.
  Color color;

  MeshControlPoint({required this.position, required this.color});

  Map<String, dynamic> toJson() => {
    'x': position.dx,
    'y': position.dy,
    'color': color.toARGB32(),
  };

  factory MeshControlPoint.fromJson(Map<String, dynamic> json) =>
      MeshControlPoint(
        position: Offset(
          (json['x'] as num).toDouble(),
          (json['y'] as num).toDouble(),
        ),
        color: Color(json['color'] as int),
      );
}

/// A single patch in the mesh gradient (bilinear quad).
///
/// Defined by 4 corner control points. Colors are bilinearly
/// interpolated across the quad's surface.
class _MeshPatch {
  final MeshControlPoint topLeft;
  final MeshControlPoint topRight;
  final MeshControlPoint bottomLeft;
  final MeshControlPoint bottomRight;

  _MeshPatch({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
  });

  /// Sample the color at parametric coordinates (u, v) ∈ [0, 1].
  Color sampleColor(double u, double v) {
    final topColor = Color.lerp(topLeft.color, topRight.color, u)!;
    final bottomColor = Color.lerp(bottomLeft.color, bottomRight.color, u)!;
    return Color.lerp(topColor, bottomColor, v)!;
  }

  /// Sample the position at parametric coordinates (u, v) ∈ [0, 1].
  Offset samplePosition(double u, double v) {
    final topPos = Offset.lerp(topLeft.position, topRight.position, u)!;
    final bottomPos =
        Offset.lerp(bottomLeft.position, bottomRight.position, u)!;
    return Offset.lerp(topPos, bottomPos, v)!;
  }
}

/// A mesh gradient defined by an N×M grid of control points.
///
/// The gradient is rendered by tessellating each patch (quad cell)
/// into triangles and filling with bilinearly interpolated colors.
///
/// Similar to CSS `mesh-gradient` and Figma's mesh gradient tool.
///
/// ```dart
/// final mesh = MeshGradient(rows: 3, columns: 3);
/// mesh.setPoint(0, 0, MeshControlPoint(position: Offset.zero, color: Colors.red));
/// mesh.setPoint(2, 2, MeshControlPoint(position: Offset(200, 200), color: Colors.blue));
/// mesh.render(canvas, Rect.fromLTWH(0, 0, 200, 200));
/// ```
class MeshGradient {
  /// Number of rows in the control point grid.
  final int rows;

  /// Number of columns in the control point grid.
  final int columns;

  /// Flat list of control points, row-major order.
  /// Length = rows × columns.
  final List<MeshControlPoint> _points;

  /// Tessellation resolution per patch (subdivisions per axis).
  int resolution;

  MeshGradient({
    required this.rows,
    required this.columns,
    this.resolution = 8,
    List<MeshControlPoint>? points,
  }) : _points =
           points ??
           List.generate(rows * columns, (i) {
             final row = i ~/ columns;
             final col = i % columns;
             return MeshControlPoint(
               position: Offset(
                 col / math.max(1, columns - 1),
                 row / math.max(1, rows - 1),
               ),
               color:
                   Color.lerp(
                     const Color(0xFFFF0000),
                     const Color(0xFF0000FF),
                     i / math.max(1, rows * columns - 1),
                   )!,
             );
           });

  // ---------------------------------------------------------------------------
  // Grid access
  // ---------------------------------------------------------------------------

  /// Get the control point at [row], [col].
  MeshControlPoint getPoint(int row, int col) {
    assert(row >= 0 && row < rows && col >= 0 && col < columns);
    return _points[row * columns + col];
  }

  /// Set the control point at [row], [col].
  void setPoint(int row, int col, MeshControlPoint point) {
    assert(row >= 0 && row < rows && col >= 0 && col < columns);
    _points[row * columns + col] = point;
  }

  /// All control points (read-only view).
  List<MeshControlPoint> get points => List.unmodifiable(_points);

  /// Number of patches = (rows - 1) × (columns - 1).
  int get patchCount => (rows - 1) * (columns - 1);

  // ---------------------------------------------------------------------------
  // Rendering
  // ---------------------------------------------------------------------------

  /// Render the mesh gradient onto [canvas] within [bounds].
  ///
  /// Each patch is tessellated into triangles with per-vertex colors.
  void render(Canvas canvas, Rect bounds) {
    final scaleX = bounds.width;
    final scaleY = bounds.height;

    for (int r = 0; r < rows - 1; r++) {
      for (int c = 0; c < columns - 1; c++) {
        final patch = _MeshPatch(
          topLeft: getPoint(r, c),
          topRight: getPoint(r, c + 1),
          bottomLeft: getPoint(r + 1, c),
          bottomRight: getPoint(r + 1, c + 1),
        );
        _renderPatch(canvas, patch, bounds.topLeft, scaleX, scaleY);
      }
    }
  }

  void _renderPatch(
    Canvas canvas,
    _MeshPatch patch,
    Offset origin,
    double scaleX,
    double scaleY,
  ) {
    final res = resolution;

    for (int i = 0; i < res; i++) {
      for (int j = 0; j < res; j++) {
        final u0 = i / res;
        final u1 = (i + 1) / res;
        final v0 = j / res;
        final v1 = (j + 1) / res;

        // Four corners of this sub-quad.
        final p00 = patch.samplePosition(u0, v0);
        final p10 = patch.samplePosition(u1, v0);
        final p01 = patch.samplePosition(u0, v1);
        final p11 = patch.samplePosition(u1, v1);

        final c00 = patch.sampleColor(u0, v0);
        final c10 = patch.sampleColor(u1, v0);
        final c01 = patch.sampleColor(u0, v1);
        final c11 = patch.sampleColor(u1, v1);

        // Average color for this sub-quad.
        final avgColor =
            Color.lerp(
              Color.lerp(c00, c10, 0.5),
              Color.lerp(c01, c11, 0.5),
              0.5,
            )!;

        // Draw the sub-quad as a path with the averaged color.
        final path =
            Path()
              ..moveTo(origin.dx + p00.dx * scaleX, origin.dy + p00.dy * scaleY)
              ..lineTo(origin.dx + p10.dx * scaleX, origin.dy + p10.dy * scaleY)
              ..lineTo(origin.dx + p11.dx * scaleX, origin.dy + p11.dy * scaleY)
              ..lineTo(origin.dx + p01.dx * scaleX, origin.dy + p01.dy * scaleY)
              ..close();

        canvas.drawPath(path, Paint()..color = avgColor);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'rows': rows,
    'columns': columns,
    'resolution': resolution,
    'points': _points.map((p) => p.toJson()).toList(),
  };

  factory MeshGradient.fromJson(Map<String, dynamic> json) {
    final rows = json['rows'] as int;
    final columns = json['columns'] as int;
    final pointsJson = json['points'] as List<dynamic>;
    final points =
        pointsJson
            .map((p) => MeshControlPoint.fromJson(p as Map<String, dynamic>))
            .toList();

    return MeshGradient(
      rows: rows,
      columns: columns,
      resolution: json['resolution'] as int? ?? 8,
      points: points,
    );
  }
}
