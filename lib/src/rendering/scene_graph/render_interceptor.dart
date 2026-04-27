import 'package:flutter/material.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

// =============================================================================
// RENDER INTERCEPTOR — Pluggable middleware for the render pipeline.
// =============================================================================

/// Callback that renders the node (calls the next interceptor or the real
/// renderer).
typedef RenderNext =
    void Function(Canvas canvas, CanvasNode node, Rect viewport);

/// Base class for render interceptors.
///
/// Interceptors form a chain around the scene-graph renderer's per-node
/// callback. Each interceptor can:
/// - **Inspect** the node before/after rendering
/// - **Modify** canvas state (save/restore balanced)
/// - **Skip** the node (don't call [intercept]'s `next`)
/// - **Profile** rendering cost
///
/// ```dart
/// renderer.addInterceptor(DebugBoundsInterceptor());
/// renderer.addInterceptor(NodeFilterInterceptor((n) => n.isVisible));
/// ```
abstract class RenderInterceptor {
  /// Called for each node. Must call [next] to continue the chain,
  /// or skip it to suppress rendering entirely.
  void intercept(
    Canvas canvas,
    CanvasNode node,
    Rect viewport,
    RenderNext next,
  );

  /// Called once per frame before any nodes are rendered.
  void onFrameStart() {}

  /// Called once per frame after all nodes are rendered.
  void onFrameEnd() {}
}

// =============================================================================
// BUILT-IN INTERCEPTORS
// =============================================================================

/// Draws wireframe rectangles around every node's [CanvasNode.worldBounds].
///
/// Useful for debugging layout, culling, and hit-testing issues.
/// Paint is pre-allocated to avoid GC pressure in the render loop.
class DebugBoundsInterceptor extends RenderInterceptor {
  /// Pre-allocated paint — zero alloc in paint().
  late final Paint _debugPaint;

  /// API element `DebugBoundsInterceptor`.
  DebugBoundsInterceptor({
    Color color = const Color(0xFF00FF00),
    double strokeWidth = 1.0,
  }) {
    _debugPaint =
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth;
  }

  @override
  void intercept(
    Canvas canvas,
    CanvasNode node,
    Rect viewport,
    RenderNext next,
  ) {
    next(canvas, node, viewport);

    // Draw bounds overlay AFTER the node, so it appears on top.
    final bounds = node.worldBounds;
    if (bounds.isFinite && !bounds.isEmpty) {
      canvas.drawRect(bounds, _debugPaint);
    }
  }
}

/// Skips rendering for nodes that don't pass [predicate].
///
/// ```dart
/// // Solo mode: only render nodes on a specific layer.
/// renderer.addInterceptor(NodeFilterInterceptor(
///   (node) => node.layerId == activeLayerId,
/// ));
/// ```
class NodeFilterInterceptor extends RenderInterceptor {
  /// Predicate that returns `true` for nodes that should be rendered.
  final bool Function(CanvasNode node) predicate;

  /// Method `predicate`.
  NodeFilterInterceptor(this.predicate);

  @override
  void intercept(
    Canvas canvas,
    CanvasNode node,
    Rect viewport,
    RenderNext next,
  ) {
    if (predicate(node)) {
      next(canvas, node, viewport);
    }
    // else: node is skipped entirely
  }
}
