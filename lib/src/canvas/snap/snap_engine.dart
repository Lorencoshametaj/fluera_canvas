// ════════════════════════════════════════════════════════════════════════════
// 🧲 SnapEngine — alignment / spacing snap during selection transform.
//
// Pure-geometry pass over candidate node bounds. No rendering, no
// state mutation, no canvas dependency: takes an AABB + a list of
// candidate AABBs + which axes are active, returns a snapped AABB
// plus the magenta guide lines to render this frame.
//
// Designed to be called once per pointer-move during a selection
// drag / scale. Cost is O(c × axes) where c = candidates and axes
// is at most 2 — cheap enough to run inline with the gesture
// handler. Caller is responsible for pulling the candidate list from
// the spatial index (typically `controller.viewport.inflated(snapTolerance×2)`
// minus the nodes inside the active selection).
// ════════════════════════════════════════════════════════════════════════════

import 'dart:ui';

/// Which axes the snap pass is allowed to mutate. Drag-move enables
/// both; horizontal-edge scale enables only X; rotate disables both
/// (the snap engine is no-op for pure rotation today).
enum SnapAxes {
  /// Snap freely on X and Y.
  both,

  /// Snap on X only (e.g. left/right edge handle scale).
  x,

  /// Snap on Y only (e.g. top/bottom edge handle scale).
  y,

  /// Disable snap entirely (rotate, ungroup, etc.).
  none,
}

/// One alignment / spacing guide line to render this frame. World-space
/// coordinates — the painter projects through the camera transform.
///
/// Added in 0.15.0.
class SnapGuide {
  /// Start of the guide segment (world).
  final Offset start;

  /// End of the guide segment (world).
  final Offset end;

  /// Anchor kind that triggered this guide. One of:
  /// `'edge-left'`, `'edge-right'`, `'edge-top'`, `'edge-bottom'`,
  /// `'center-x'`, `'center-y'`, `'spacing-x'`, `'spacing-y'`.
  final String kind;

  /// Build a guide segment.
  const SnapGuide({
    required this.start,
    required this.end,
    required this.kind,
  });
}

/// Result of one snap pass — the post-snap [bounds] (caller should
/// translate the dragged content by `bounds.center - originalBounds.center`)
/// plus the guides to render until the next pointer-move event.
///
/// Added in 0.15.0.
class SnapResult {
  /// Build a snap-pass result.
  const SnapResult({required this.bounds, required this.guides});

  /// Snapped AABB in world coordinates. When no snap fires, this is
  /// the original `draggedBounds` passed in.
  final Rect bounds;

  /// Guides to render this frame. Empty when no snap fires.
  final List<SnapGuide> guides;

  /// `true` when at least one anchor snapped this pass.
  bool get didSnap => guides.isNotEmpty;
}

/// Compute alignment / spacing / edge snaps. Stateless — instance
/// just holds tunable thresholds.
///
/// ```dart
/// final snap = SnapEngine();
/// final result = snap.snap(
///   draggedBounds: selection.frameRect,
///   candidates: [for (final n in nearby) n.bounds],
///   axes: SnapAxes.both,
/// );
/// if (result.didSnap) {
///   moveSelectionTo(result.bounds.center);
///   renderGuides(result.guides);
/// }
/// ```
///
/// Added in 0.15.0.
class SnapEngine {
  /// Build a snap engine with optional tunable thresholds. Defaults
  /// match Figma / TLDraw feel.
  const SnapEngine({
    this.snapTolerance = 6.0,
    this.enableEdgeSnap = true,
    this.enableCenterSnap = true,
  });

  /// World-px distance under which a candidate anchor pulls the
  /// dragged bounds onto its line. Default `6.0` matches Figma /
  /// TLDraw feel without being so large that drags feel "sticky".
  final double snapTolerance;

  /// When `true` (default), align the dragged bounds' edges to the
  /// candidates' edges (left↔left, right↔right, top↔top, bottom↔bottom).
  final bool enableEdgeSnap;

  /// When `true` (default), align centers (X-center to X-center,
  /// Y-center to Y-center). Often the "right" snap for centred
  /// design layouts.
  final bool enableCenterSnap;

  /// Run one snap pass.
  ///
  /// [draggedBounds] — current AABB of the active selection.
  /// [candidates] — AABBs of nearby nodes, MUST exclude any node
  ///   that is part of the active selection (otherwise the dragged
  ///   bounds snap to themselves and the user can never move).
  /// [axes] — which axes to mutate. Use [SnapAxes.x] / [SnapAxes.y]
  ///   for edge-handle scale operations; [SnapAxes.both] for move.
  SnapResult snap({
    required Rect draggedBounds,
    required Iterable<Rect> candidates,
    SnapAxes axes = SnapAxes.both,
  }) {
    if (axes == SnapAxes.none) {
      return SnapResult(bounds: draggedBounds, guides: const []);
    }
    final wantX = axes == SnapAxes.both || axes == SnapAxes.x;
    final wantY = axes == SnapAxes.both || axes == SnapAxes.y;

    double bestDxDelta = 0;
    double bestDyDelta = 0;
    double bestDxAbs = double.infinity;
    double bestDyAbs = double.infinity;
    final guides = <SnapGuide>[];

    for (final c in candidates) {
      // X-axis pairings: try left↔left, right↔right, center-x↔center-x
      if (wantX) {
        if (enableEdgeSnap) {
          _testAndRecord(
            draggedAnchor: draggedBounds.left,
            candidateAnchor: c.left,
            kind: 'edge-left',
            candidateBounds: c,
            draggedBounds: draggedBounds,
            isHorizontal: false,
            outBestDelta: (d) => bestDxDelta = d,
            outBestAbs: (d) => bestDxAbs = d,
            currentBestAbs: bestDxAbs,
            guides: guides,
          );
          _testAndRecord(
            draggedAnchor: draggedBounds.right,
            candidateAnchor: c.right,
            kind: 'edge-right',
            candidateBounds: c,
            draggedBounds: draggedBounds,
            isHorizontal: false,
            outBestDelta: (d) => bestDxDelta = d,
            outBestAbs: (d) => bestDxAbs = d,
            currentBestAbs: bestDxAbs,
            guides: guides,
          );
        }
        if (enableCenterSnap) {
          _testAndRecord(
            draggedAnchor: draggedBounds.center.dx,
            candidateAnchor: c.center.dx,
            kind: 'center-x',
            candidateBounds: c,
            draggedBounds: draggedBounds,
            isHorizontal: false,
            outBestDelta: (d) => bestDxDelta = d,
            outBestAbs: (d) => bestDxAbs = d,
            currentBestAbs: bestDxAbs,
            guides: guides,
          );
        }
      }
      // Y-axis pairings.
      if (wantY) {
        if (enableEdgeSnap) {
          _testAndRecord(
            draggedAnchor: draggedBounds.top,
            candidateAnchor: c.top,
            kind: 'edge-top',
            candidateBounds: c,
            draggedBounds: draggedBounds,
            isHorizontal: true,
            outBestDelta: (d) => bestDyDelta = d,
            outBestAbs: (d) => bestDyAbs = d,
            currentBestAbs: bestDyAbs,
            guides: guides,
          );
          _testAndRecord(
            draggedAnchor: draggedBounds.bottom,
            candidateAnchor: c.bottom,
            kind: 'edge-bottom',
            candidateBounds: c,
            draggedBounds: draggedBounds,
            isHorizontal: true,
            outBestDelta: (d) => bestDyDelta = d,
            outBestAbs: (d) => bestDyAbs = d,
            currentBestAbs: bestDyAbs,
            guides: guides,
          );
        }
        if (enableCenterSnap) {
          _testAndRecord(
            draggedAnchor: draggedBounds.center.dy,
            candidateAnchor: c.center.dy,
            kind: 'center-y',
            candidateBounds: c,
            draggedBounds: draggedBounds,
            isHorizontal: true,
            outBestDelta: (d) => bestDyDelta = d,
            outBestAbs: (d) => bestDyAbs = d,
            currentBestAbs: bestDyAbs,
            guides: guides,
          );
        }
      }
    }

    if (bestDxAbs == double.infinity && bestDyAbs == double.infinity) {
      return SnapResult(bounds: draggedBounds, guides: const []);
    }

    final dx = bestDxAbs == double.infinity ? 0.0 : bestDxDelta;
    final dy = bestDyAbs == double.infinity ? 0.0 : bestDyDelta;
    return SnapResult(
      bounds: draggedBounds.translate(dx, dy),
      guides: List<SnapGuide>.unmodifiable(guides),
    );
  }

  /// Test a single anchor pairing. If within tolerance AND closer
  /// than the previous best for the same axis, record the delta +
  /// emit a guide segment spanning from candidate centre to dragged
  /// centre (length tells the user "this is the alignment line").
  void _testAndRecord({
    required double draggedAnchor,
    required double candidateAnchor,
    required String kind,
    required Rect candidateBounds,
    required Rect draggedBounds,
    required bool isHorizontal,
    required void Function(double) outBestDelta,
    required void Function(double) outBestAbs,
    required double currentBestAbs,
    required List<SnapGuide> guides,
  }) {
    final delta = candidateAnchor - draggedAnchor;
    final absDelta = delta.abs();
    if (absDelta > snapTolerance) return;
    if (absDelta >= currentBestAbs) return;
    outBestDelta(delta);
    outBestAbs(absDelta);
    // Build the guide line. For Y-snaps (horizontal lines), span
    // from min(candidate.left, dragged.left) to
    // max(candidate.right, dragged.right) so the segment visibly
    // connects both rectangles. Same idea mirrored for X-snaps.
    final Offset gStart;
    final Offset gEnd;
    if (isHorizontal) {
      final y = candidateAnchor;
      final left =
          candidateBounds.left < draggedBounds.left
              ? candidateBounds.left
              : draggedBounds.left;
      final right =
          candidateBounds.right > draggedBounds.right
              ? candidateBounds.right
              : draggedBounds.right;
      gStart = Offset(left, y);
      gEnd = Offset(right, y);
    } else {
      final x = candidateAnchor;
      final top =
          candidateBounds.top < draggedBounds.top
              ? candidateBounds.top
              : draggedBounds.top;
      final bottom =
          candidateBounds.bottom > draggedBounds.bottom
              ? candidateBounds.bottom
              : draggedBounds.bottom;
      gStart = Offset(x, top);
      gEnd = Offset(x, bottom);
    }
    // Replace the previously-best guide on this axis (we only show
    // one guide per axis per frame to avoid magenta-line chaos).
    final isHorizontalGuide = isHorizontal;
    guides.removeWhere(
      (g) => isHorizontalGuide
          ? g.kind.startsWith('edge-top') ||
              g.kind.startsWith('edge-bottom') ||
              g.kind == 'center-y'
          : g.kind.startsWith('edge-left') ||
              g.kind.startsWith('edge-right') ||
              g.kind == 'center-x',
    );
    guides.add(SnapGuide(start: gStart, end: gEnd, kind: kind));
  }
}
