import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../../core/scene_graph/node_id.dart';

/// Immutable snapshot of the current selection.
///
/// Holds a [Set<NodeId>] of selected scene-graph nodes plus the
/// axis-aligned [bounds] in **world** coordinates that contains every
/// selected node. Both fields are derivable from the canvas state but
/// kept on the snapshot so observers (UI overlays, transform handles)
/// don't have to re-walk the graph each frame.
class CanvasSelection {
  const CanvasSelection({
    required this.ids,
    required this.bounds,
  });

  /// Empty selection — used as the initial state and after a clear.
  static const CanvasSelection empty = CanvasSelection(
    ids: <NodeId>{},
    bounds: Rect.zero,
  );

  /// Identifiers of every node currently selected.
  final Set<NodeId> ids;

  /// World-space axis-aligned rect that contains every selected node's
  /// `worldBounds`. Equal to [Rect.zero] when [ids] is empty.
  final Rect bounds;

  bool get isEmpty => ids.isEmpty;
  bool get isNotEmpty => ids.isNotEmpty;
  int get length => ids.length;

  bool contains(NodeId id) => ids.contains(id);

  CanvasSelection copyWith({Set<NodeId>? ids, Rect? bounds}) {
    return CanvasSelection(
      ids: ids ?? this.ids,
      bounds: bounds ?? this.bounds,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CanvasSelection &&
        other.ids.length == ids.length &&
        other.ids.containsAll(ids) &&
        other.bounds == bounds;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(ids),
        bounds,
      );

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
