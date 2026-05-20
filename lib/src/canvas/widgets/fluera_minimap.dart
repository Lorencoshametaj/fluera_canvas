// ════════════════════════════════════════════════════════════════════════════
// 🗺️ FlueraMinimap — opt-in overview widget for an infinite canvas.
//
// Renders a compact, scaled-down view of every committed stroke + a
// rectangle indicating the current viewport. Tap to recenter the
// camera at that point; drag the viewport rectangle (or anywhere in
// the minimap) to pan smoothly.
//
// Pure Dart `CustomPainter` — no GPU, no native code, no dependencies
// beyond Flutter framework. Subscribes to the canvas's
// `historyListenable` (so the overview updates when strokes are
// added / removed) and to the camera controller (so the viewport
// rectangle moves with pan / zoom). Listening only — never mutates
// the canvas state directly except through the public `setOffset`
// API on the controller.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show Listenable;
import 'package:flutter/material.dart';

import '../fluera_canvas_widget.dart';

/// Compact overview of the entire canvas content with a viewport
/// indicator. Drop into a `Stack` overlay (typically top-right) so
/// the user always knows where they are inside an infinite canvas.
///
/// ```dart
/// Stack(
///   children: [
///     FlueraCanvas(key: canvasKey, ...),
///     Positioned(
///       top: 16, right: 16,
///       child: FlueraMinimap(canvasKey: canvasKey),
///     ),
///   ],
/// );
/// ```
///
/// Added in 0.13.0.
class FlueraMinimap extends StatefulWidget {
  /// Build a minimap bound to the [FlueraCanvas] with [canvasKey].
  const FlueraMinimap({
    super.key,
    required this.canvasKey,
    this.size = const Size(180, 120),
    this.background,
    this.viewportColor,
    this.contentColor,
    this.borderRadius = 12.0,
  });

  /// Key of the [FlueraCanvas] this minimap mirrors. Same key passed
  /// to the toolbar / sketch / scaffold widgets.
  final GlobalKey<FlueraCanvasState> canvasKey;

  /// Pixel size of the minimap surface. Default `180×120`.
  final Size size;

  /// Background fill behind the content. `null` → semi-transparent
  /// `colorScheme.surfaceContainerHighest`.
  final Color? background;

  /// Stroke colour of the viewport-indicator rectangle. `null` →
  /// `colorScheme.primary`.
  final Color? viewportColor;

  /// Stroke colour for committed-content polylines. `null` →
  /// `colorScheme.onSurface` at 70% alpha.
  final Color? contentColor;

  /// Corner radius of the minimap surface. Default `12`.
  final double borderRadius;

  @override
  State<FlueraMinimap> createState() => _FlueraMinimapState();
}

class _FlueraMinimapState extends State<FlueraMinimap> {
  // A single Listenable that fires when EITHER the camera moves OR
  // the stroke list changes — drives a single CustomPainter repaint.
  // The CustomPainter's super(repaint:) wiring handles add/remove of
  // listeners on mount/unmount; we just hold the reference here so a
  // single merged instance is reused across rebuilds.
  Listenable? _repaint;
  FlueraCanvasState? _wired;

  @override
  void didUpdateWidget(covariant FlueraMinimap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Consumer swapped the canvasKey → drop the stale wiring so the
    // next build rebinds against the new canvas.
    if (widget.canvasKey != oldWidget.canvasKey) {
      _wired = null;
      _repaint = null;
    }
  }

  @override
  void dispose() {
    // Drop references so neither the previous canvas state nor the
    // merged listenable can be reached through this State after
    // unmount. The CustomPainter detaches its own listener via the
    // framework's element unmount.
    _wired = null;
    _repaint = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _ensureWired();
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Material(
        color: widget.background ??
            scheme.surfaceContainerHighest.withValues(alpha: 0.92),
        elevation: 4,
        child: SizedBox(
          width: widget.size.width,
          height: widget.size.height,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: _handleTap,
            onPanUpdate: _handlePanUpdate,
            child: CustomPaint(
              painter: _MinimapPainter(
                canvasKey: widget.canvasKey,
                viewportColor: widget.viewportColor ?? scheme.primary,
                contentColor: widget.contentColor ??
                    scheme.onSurface.withValues(alpha: 0.7),
                outlineColor: scheme.outlineVariant,
                repaint: _repaint ?? const AlwaysStoppedAnimation(0),
              ),
              size: widget.size,
            ),
          ),
        ),
      ),
    );
  }

  void _ensureWired() {
    final state = widget.canvasKey.currentState;
    if (state == null) {
      // Canvas not yet mounted — schedule a rebuild on the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    if (identical(_wired, state)) return;
    _wired = state;
    _repaint = Listenable.merge([state.historyListenable, state.controller]);
  }

  void _handleTap(TapDownDetails details) {
    final state = widget.canvasKey.currentState;
    if (state == null) return;
    final mapping = _MinimapPainter._computeMapping(state, widget.size);
    if (mapping == null) return;
    // Tap point in minimap space → world space → centre the camera there.
    final world = mapping.minimapToWorld(details.localPosition);
    _centerCameraOn(state, world);
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    final state = widget.canvasKey.currentState;
    if (state == null) return;
    final mapping = _MinimapPainter._computeMapping(state, widget.size);
    if (mapping == null) return;
    // Translate the camera by the inverse of the drag delta.
    final controller = state.controller;
    final worldDelta = details.delta / mapping.scale;
    controller.setOffset(controller.offset - worldDelta);
  }

  void _centerCameraOn(FlueraCanvasState state, Offset worldPoint) {
    // Move camera so that `worldPoint` is at the centre of the
    // viewport. `_offset` semantics: world point at (offset / scale)
    // sits at screen origin; to centre worldPoint, screenSize/2 must
    // map to it → offset = worldPoint * scale - screenSize/2.
    final controller = state.controller;
    final scale = controller.scale;
    final viewport = state.viewportSize;
    final newOffset = Offset(
      worldPoint.dx * scale - viewport.width / 2,
      worldPoint.dy * scale - viewport.height / 2,
    );
    controller.setOffset(newOffset);
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({
    required this.canvasKey,
    required this.viewportColor,
    required this.contentColor,
    required this.outlineColor,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final GlobalKey<FlueraCanvasState> canvasKey;
  final Color viewportColor;
  final Color contentColor;
  final Color outlineColor;

  @override
  void paint(Canvas canvas, Size size) {
    final state = canvasKey.currentState;
    if (state == null) return;
    final mapping = _computeMapping(state, size);
    if (mapping == null) {
      _paintPlaceholder(canvas, size);
      return;
    }

    // Per-stroke polylines.
    final strokes = state.strokes;
    if (strokes.isNotEmpty) {
      final paint = Paint()
        ..color = contentColor
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 1.0;
      for (final s in strokes) {
        if (s.points.isEmpty) continue;
        final path = Path();
        final first = mapping.worldToMinimap(s.points.first);
        path.moveTo(first.dx, first.dy);
        for (int i = 1; i < s.points.length; i++) {
          final p = mapping.worldToMinimap(s.points[i]);
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path, paint);
      }
    }

    // Viewport indicator.
    final viewport = state.viewportSize;
    final scale = state.controller.scale;
    final offset = state.controller.offset;
    final worldVisible = Rect.fromLTWH(
      offset.dx / scale,
      offset.dy / scale,
      viewport.width / scale,
      viewport.height / scale,
    );
    final tl = mapping.worldToMinimap(worldVisible.topLeft);
    final br = mapping.worldToMinimap(worldVisible.bottomRight);
    final r = Rect.fromPoints(tl, br);
    final viewportPaint = Paint()
      ..color = viewportColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(r.intersect(Offset.zero & size), viewportPaint);

    // 1-px hairline border for visual grounding.
    final border = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      border,
    );
  }

  void _paintPlaceholder(Canvas canvas, Size size) {
    // Empty canvas — show a faint outline + centred dot to indicate
    // "nothing to navigate yet".
    final outline = Paint()
      ..color = outlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      outline,
    );
    final dot = Paint()..color = outlineColor;
    canvas.drawCircle(size.center(Offset.zero), 2, dot);
  }

  /// Compute the world-space content bounds + the linear mapping
  /// onto the minimap surface. Returns `null` if there's nothing to
  /// map (no strokes AND no viewport size).
  static _MinimapMapping? _computeMapping(
    FlueraCanvasState state,
    Size minimapSize,
  ) {
    final strokes = state.strokes;
    Rect? content;
    for (final s in strokes) {
      content = content == null ? s.bounds : content.expandToInclude(s.bounds);
    }
    // Always include the viewport in the mapping so the viewport
    // indicator stays inside the minimap even when the user pans
    // outside any committed content.
    final viewport = state.viewportSize;
    final controller = state.controller;
    final worldVisible = Rect.fromLTWH(
      controller.offset.dx / controller.scale,
      controller.offset.dy / controller.scale,
      viewport.width / controller.scale,
      viewport.height / controller.scale,
    );
    content = content == null
        ? worldVisible
        : content.expandToInclude(worldVisible);
    if (content.isEmpty) return null;
    // Pad by 5% so polylines don't touch the edges.
    final padded = content.inflate(math.max(content.width, content.height) * 0.05);
    final scaleX = minimapSize.width / padded.width;
    final scaleY = minimapSize.height / padded.height;
    final scale = math.min(scaleX, scaleY);
    // Centre the (uniformly-scaled) content in the minimap.
    final tx = (minimapSize.width - padded.width * scale) / 2 - padded.left * scale;
    final ty = (minimapSize.height - padded.height * scale) / 2 - padded.top * scale;
    return _MinimapMapping(scale: scale, tx: tx, ty: ty);
  }

  @override
  bool shouldRepaint(covariant _MinimapPainter old) =>
      old.canvasKey != canvasKey ||
      old.viewportColor != viewportColor ||
      old.contentColor != contentColor ||
      old.outlineColor != outlineColor;
}

/// Affine mapping: world × scale + (tx, ty) = minimap.
class _MinimapMapping {
  const _MinimapMapping({
    required this.scale,
    required this.tx,
    required this.ty,
  });
  final double scale;
  final double tx;
  final double ty;

  Offset worldToMinimap(Offset world) =>
      Offset(world.dx * scale + tx, world.dy * scale + ty);

  Offset minimapToWorld(Offset minimap) =>
      Offset((minimap.dx - tx) / scale, (minimap.dy - ty) / scale);
}
