import '../scene_graph/canvas_node.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

/// Mixin that adds multi-fill and multi-stroke stacking to a [CanvasNode].
///
/// Nodes that apply this mixin gain ordered lists of [FillLayer]s and
/// [StrokeLayer]s. Each layer is rendered independently with its own
/// opacity, blend mode, and visibility toggle.
///
/// Fill layers render bottom-to-top (index 0 = bottom), then stroke
/// layers render bottom-to-top on top of fills.
///
/// Usage:
/// ```dart
/// class PathNode extends CanvasNode with PaintStackMixin { ... }
/// ```
mixin PaintStackMixin on CanvasNode {
  /// Ordered fill layers (index 0 = bottom-most).
  List<FillLayer> fills = [];

  /// Ordered stroke layers (index 0 = bottom-most).
  List<StrokeLayer> strokes = [];

  // ---------------------------------------------------------------------------
  // Fill helpers
  // ---------------------------------------------------------------------------

  /// Add a fill layer at the given [index] (default: top of stack).
  void addFill(FillLayer fill, [int? index]) {
    if (index != null) {
      fills.insert(index.clamp(0, fills.length), fill);
    } else {
      fills.add(fill);
    }
  }

  /// Remove a fill layer by its [id].
  bool removeFill(String fillId) {
    final before = fills.length;
    fills.removeWhere((f) => f.id == fillId);
    return fills.length < before;
  }

  /// Move a fill layer from [oldIndex] to [newIndex].
  void reorderFill(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= fills.length) return;
    final fill = fills.removeAt(oldIndex);
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    fills.insert(target.clamp(0, fills.length), fill);
  }

  // ---------------------------------------------------------------------------
  // Stroke helpers
  // ---------------------------------------------------------------------------

  /// Add a stroke layer at the given [index] (default: top of stack).
  void addStroke(StrokeLayer stroke, [int? index]) {
    if (index != null) {
      strokes.insert(index.clamp(0, strokes.length), stroke);
    } else {
      strokes.add(stroke);
    }
  }

  /// Remove a stroke layer by its [id].
  bool removeStroke(String strokeId) {
    final before = strokes.length;
    strokes.removeWhere((s) => s.id == strokeId);
    return strokes.length < before;
  }

  /// Move a stroke layer from [oldIndex] to [newIndex].
  void reorderStroke(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= strokes.length) return;
    final stroke = strokes.removeAt(oldIndex);
    final target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    strokes.insert(target.clamp(0, strokes.length), stroke);
  }

  // ---------------------------------------------------------------------------
  // Bounds helper
  // ---------------------------------------------------------------------------

  /// Maximum bounds inflation from visible strokes.
  ///
  /// Used by subclasses to correctly inflate [localBounds].
  double get maxStrokeBoundsInflation {
    double max = 0;
    for (final s in strokes) {
      final inf = s.boundsInflation;
      if (inf > max) max = inf;
    }
    return max;
  }

  // ---------------------------------------------------------------------------
  // Lookup helpers
  // ---------------------------------------------------------------------------

  /// Find a fill layer by its [id], or null if not found.
  FillLayer? findFill(String id) {
    for (final f in fills) {
      if (f.id == id) return f;
    }
    return null;
  }

  /// Find a stroke layer by its [id], or null if not found.
  StrokeLayer? findStroke(String id) {
    for (final s in strokes) {
      if (s.id == id) return s;
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Deep clone
  // ---------------------------------------------------------------------------

  /// Deep-copy all fill and stroke layers from this node into [target].
  ///
  /// Use after cloning a node to avoid shared-mutable-list issues.
  void clonePaintStackInto(PaintStackMixin target) {
    target.fills = fills.map((f) => f.copyWith()).toList();
    target.strokes = strokes.map((s) => s.copyWith()).toList();
  }

  // ---------------------------------------------------------------------------
  // Serialization helpers
  // ---------------------------------------------------------------------------

  /// Serialize the paint stack to JSON (called by subclass [toJson]).
  Map<String, dynamic> paintStackToJson() {
    final json = <String, dynamic>{};
    if (fills.isNotEmpty) {
      json['fills'] = fills.map((f) => f.toJson()).toList();
    }
    if (strokes.isNotEmpty) {
      json['strokes'] = strokes.map((s) => s.toJson()).toList();
    }
    return json;
  }

  /// Restore the paint stack from JSON (called by subclass [fromJson]).
  static void applyPaintStackFromJson(
    PaintStackMixin node,
    Map<String, dynamic> json,
  ) {
    if (json['fills'] != null) {
      node.fills =
          (json['fills'] as List<dynamic>)
              .map((f) => FillLayer.fromJson(f as Map<String, dynamic>))
              .toList();
    }
    if (json['strokes'] != null) {
      node.strokes =
          (json['strokes'] as List<dynamic>)
              .map((s) => StrokeLayer.fromJson(s as Map<String, dynamic>))
              .toList();
    }
  }
}
