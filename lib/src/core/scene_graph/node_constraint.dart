import 'dart:ui';
import 'package:fluera_canvas/fluera_canvas.dart';

import 'canvas_node.dart';

/// Type of constraint between two scene graph nodes.
///
/// Unlike [GeometricConstraint] (which works within a single VectorNetwork),
/// these constraints operate at the scene graph level between any two
/// [CanvasNode] instances.
enum NodeConstraintType {
  /// Align left edges.
  alignLeft,

  /// Align horizontal centers.
  alignCenter,

  /// Align right edges.
  alignRight,

  /// Align top edges.
  alignTop,

  /// Align vertical centers.
  alignMiddle,

  /// Align bottom edges.
  alignBottom,

  /// Match widths (target adopts source width).
  matchWidth,

  /// Match heights (target adopts source height).
  matchHeight,

  /// Maintain a fixed horizontal distance between centers.
  pinDistanceX,

  /// Maintain a fixed vertical distance between centers.
  pinDistanceY,

  /// Maintain a fixed Euclidean distance between centers.
  pinDistance,
}

// ---------------------------------------------------------------------------
// NodeConstraint
// ---------------------------------------------------------------------------

/// A constraint between two scene graph nodes.
///
/// When solved, the [targetNodeId]'s position (and optionally size)
/// is adjusted to satisfy the constraint relative to [sourceNodeId].
///
/// ```dart
/// final c = NodeConstraint(
///   type: NodeConstraintType.alignCenter,
///   sourceNodeId: 'logo',
///   targetNodeId: 'title',
/// );
/// ```
class NodeConstraint {
  /// Unique ID for this constraint.
  final String id;

  /// Type of constraint.
  final NodeConstraintType type;

  /// The reference node (stays in place).
  final String sourceNodeId;

  /// The node that gets adjusted.
  final String targetNodeId;

  /// Numeric value for distance/size constraints.
  ///
  /// For [pinDistance], [pinDistanceX], [pinDistanceY]: the desired distance.
  /// For [matchWidth], [matchHeight]: an optional scale multiplier (default 1.0).
  /// For alignment types: ignored.
  final double value;

  /// Whether this constraint is currently active.
  bool isEnabled;

  NodeConstraint({
    required this.id,
    required this.type,
    required this.sourceNodeId,
    required this.targetNodeId,
    this.value = 0.0,
    this.isEnabled = true,
  });

  // -- Serialization --------------------------------------------------------

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'sourceNodeId': sourceNodeId,
    'targetNodeId': targetNodeId,
    if (value != 0.0) 'value': value,
    if (!isEnabled) 'isEnabled': false,
  };

  factory NodeConstraint.fromJson(Map<String, dynamic> json) {
    return NodeConstraint(
      id: json['id'] as String,
      type: NodeConstraintType.values.firstWhere((t) => t.name == json['type']),
      sourceNodeId: json['sourceNodeId'] as String,
      targetNodeId: json['targetNodeId'] as String,
      value: (json['value'] as num?)?.toDouble() ?? 0.0,
      isEnabled: json['isEnabled'] as bool? ?? true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NodeConstraint &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'NodeConstraint($type: $sourceNodeId → $targetNodeId, value: $value)';
}

// ---------------------------------------------------------------------------
// NodeConstraintSolver
// ---------------------------------------------------------------------------

/// Iterative solver for scene-graph level [NodeConstraint]s.
///
/// Uses Gauss-Seidel relaxation: each constraint projects the
/// target node's position to satisfy the constraint. Multiple
/// iterations smooth out mutual dependencies.
///
/// ```dart
/// final solver = NodeConstraintSolver(
///   constraints: sceneGraph.nodeConstraints,
///   nodeResolver: sceneGraph.findNodeById,
/// );
/// solver.solve();
/// ```
class NodeConstraintSolver {
  /// The constraints to solve.
  final List<NodeConstraint> constraints;

  /// Function to resolve a node ID to its [CanvasNode].
  final CanvasNode? Function(String id) nodeResolver;

  NodeConstraintSolver({required this.constraints, required this.nodeResolver});

  /// Solve all constraints iteratively.
  ///
  /// Uses adaptive iteration count: simple layouts (≤3 constraints) use
  /// fewer iterations. Returns `true` if all constraints converged
  /// within [tolerance].
  bool solve({int maxIterations = 20, double tolerance = 0.5}) {
    final active = constraints.where((c) => c.isEnabled).length;
    if (active == 0) return true;

    // Adaptive: cap iterations to constraint count * 3, clamped to maxIterations.
    final effectiveMax = (active * 3).clamp(1, maxIterations);

    for (int iter = 0; iter < effectiveMax; iter++) {
      double maxError = 0;
      for (final constraint in constraints) {
        if (!constraint.isEnabled) continue;
        final error = _applyConstraint(constraint);
        if (error > maxError) maxError = error;
      }
      if (maxError <= tolerance) return true;
    }
    return false;
  }

  /// Apply a single constraint. Returns the error (distance from satisfied).
  double _applyConstraint(NodeConstraint c) {
    final source = nodeResolver(c.sourceNodeId);
    final target = nodeResolver(c.targetNodeId);
    if (source == null || target == null) return 0;

    final sb = source.worldBounds;
    final tb = target.worldBounds;
    if (sb.isEmpty || tb.isEmpty) return 0;

    switch (c.type) {
      case NodeConstraintType.alignLeft:
        return _alignEdge(target, tb.left - sb.left, horizontal: true);

      case NodeConstraintType.alignCenter:
        return _alignEdge(
          target,
          tb.center.dx - sb.center.dx,
          horizontal: true,
        );

      case NodeConstraintType.alignRight:
        return _alignEdge(target, tb.right - sb.right, horizontal: true);

      case NodeConstraintType.alignTop:
        return _alignEdge(target, tb.top - sb.top, horizontal: false);

      case NodeConstraintType.alignMiddle:
        return _alignEdge(
          target,
          tb.center.dy - sb.center.dy,
          horizontal: false,
        );

      case NodeConstraintType.alignBottom:
        return _alignEdge(target, tb.bottom - sb.bottom, horizontal: false);

      case NodeConstraintType.matchWidth:
        return _matchDimension(
          target,
          sb.width,
          tb.width,
          multiplier: c.value != 0 ? c.value : 1.0,
          horizontal: true,
        );

      case NodeConstraintType.matchHeight:
        return _matchDimension(
          target,
          sb.height,
          tb.height,
          multiplier: c.value != 0 ? c.value : 1.0,
          horizontal: false,
        );

      case NodeConstraintType.pinDistanceX:
        final curr = tb.center.dx - sb.center.dx;
        final error = curr - c.value;
        if (error.abs() <= 0.5) return 0;
        target.translate(-error, 0);
        target.invalidateTransformCache();
        return error.abs();

      case NodeConstraintType.pinDistanceY:
        final curr = tb.center.dy - sb.center.dy;
        final error = curr - c.value;
        if (error.abs() <= 0.5) return 0;
        target.translate(0, -error);
        target.invalidateTransformCache();
        return error.abs();

      case NodeConstraintType.pinDistance:
        final currDist = (tb.center - sb.center).distance;
        final error = currDist - c.value;
        if (error.abs() <= 0.5 || currDist < 0.001) return 0;
        // Move target along the line connecting centers.
        final dir = (tb.center - sb.center) / currDist;
        final correction = dir * -error;
        target.translate(correction.dx, correction.dy);
        target.invalidateTransformCache();
        return error.abs();
    }
  }

  double _alignEdge(
    CanvasNode target,
    double error, {
    required bool horizontal,
  }) {
    if (error.abs() <= 0.5) return 0;
    if (horizontal) {
      target.translate(-error, 0);
    } else {
      target.translate(0, -error);
    }
    target.invalidateTransformCache();
    return error.abs();
  }

  double _matchDimension(
    CanvasNode target,
    double sourceSize,
    double targetSize, {
    required double multiplier,
    required bool horizontal,
  }) {
    final desired = sourceSize * multiplier;
    if (targetSize <= 0 || desired <= 0) return 0;
    final ratio = desired / targetSize;
    final error = (ratio - 1.0).abs();
    if (error <= 0.01) return 0;
    final center = target.worldBounds.center;
    if (horizontal) {
      target.scaleFrom(ratio, 1.0, center);
    } else {
      target.scaleFrom(1.0, ratio, center);
    }
    target.invalidateTransformCache();
    return (targetSize - desired).abs();
  }
}
