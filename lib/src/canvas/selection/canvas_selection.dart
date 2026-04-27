import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:vector_math/vector_math_64.dart' show Matrix4;

import '../../core/scene_graph/node_id.dart';

/// Immutable snapshot of the current selection.
///
/// Holds a [Set<NodeId>] of selected scene-graph nodes plus an
/// **oriented** bounding frame that follows any rotation/scale on the
/// underlying node:
///
/// - [bounds] — world-space *axis-aligned* rect that contains every
///   selected node's `worldBounds`. Useful for camera tracking, edge
///   panning, dirty-region queries.
/// - [frameRect] + [frameTransform] — the frame visualised by the
///   selection painter. When a single rotated node is selected,
///   [frameRect] is its `localBounds` and [frameTransform] is its
///   `localTransform`; the OBB outline is `frameTransform × frameRect`.
///   For multi-node selections (or single un-rotated nodes),
///   [frameTransform] is identity and [frameRect] equals [bounds].
///
/// Every field is derivable from the canvas state but kept on the
/// snapshot so observers (UI overlays, transform handles) don't have
/// to re-walk the graph each frame.
class CanvasSelection {
  /// API element `CanvasSelection`.
  CanvasSelection({
    required this.ids,
    required this.bounds,
    Rect? frameRect,
    Matrix4? frameTransform,
  }) : frameRect = frameRect ?? bounds,
       frameTransform = frameTransform ?? Matrix4.identity();

  /// Empty selection — used as the initial state and after a clear.
  static final CanvasSelection empty = CanvasSelection(
    ids: const <NodeId>{},
    bounds: Rect.zero,
  );

  /// Identifiers of every node currently selected.
  final Set<NodeId> ids;

  /// World-space axis-aligned rect that contains every selected node's
  /// `worldBounds`. Equal to [Rect.zero] when [ids] is empty.
  final Rect bounds;

  /// Local-space rect of the selection frame (the rotating bounding
  /// box). For single-node rotated selections this is the node's
  /// `localBounds`; otherwise equal to [bounds].
  final Rect frameRect;

  /// Transform that maps [frameRect]'s corners into world space. The
  /// painted OBB outline is `frameTransform × frameRect`. Identity
  /// when no rotation/scale is active on the selected node.
  final Matrix4 frameTransform;

  /// Getter `isEmpty`.
  bool get isEmpty => ids.isEmpty;
  /// Getter `isNotEmpty`.
  bool get isNotEmpty => ids.isNotEmpty;
  /// Getter `length`.
  int get length => ids.length;

  /// Method `contains`.
  bool contains(NodeId id) => ids.contains(id);

  /// API element `copyWith`.
  CanvasSelection copyWith({
    Set<NodeId>? ids,
    Rect? bounds,
    Rect? frameRect,
    Matrix4? frameTransform,
  }) {
    return CanvasSelection(
      ids: ids ?? this.ids,
      bounds: bounds ?? this.bounds,
      frameRect: frameRect ?? this.frameRect,
      frameTransform: frameTransform ?? this.frameTransform,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CanvasSelection &&
        other.ids.length == ids.length &&
        other.ids.containsAll(ids) &&
        other.bounds == bounds &&
        other.frameRect == frameRect &&
        other.frameTransform == frameTransform;
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(ids), bounds, frameRect, frameTransform);

  @override
  String toString() => 'CanvasSelection(${ids.length} nodes, bounds=$bounds)';
}

/// Listenable container for the active [CanvasSelection].
///
/// The widget owns one of these and exposes it as
/// `FlueraCanvasState.selectionListenable`. UI overlays (toolbar buttons
/// that activate when a selection exists, transform-handle painters,
/// custom side panels) subscribe via `addListener` or `ListenableBuilder`.
class CanvasSelectionController extends ChangeNotifier {
  CanvasSelection _value = CanvasSelection.empty;

  /// Getter `value`.
  CanvasSelection get value => _value;

  /// Replace the active selection. No-ops when [next] is structurally
  /// equal to the current value, so subscribers don't see redundant
  /// `notifyListeners` calls.
  void set(CanvasSelection next) {
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  /// Reset to [CanvasSelection.empty].
  void clear() => set(CanvasSelection.empty);
}
