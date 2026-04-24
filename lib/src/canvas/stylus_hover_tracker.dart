// ════════════════════════════════════════════════════════════════════════════
// 🖊️ StylusHoverTracker — injectable hook for stylus hover state.
//
// The gesture detector feeds stylus-hover events into this hook so consumer
// packages can render a hover cursor overlay, snap targets to the nib, etc.
// Canvas core ships a no-op so the SDK stays lean.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:ui' show Offset;

/// Hook receiving stylus hover lifecycle events from
/// [InfiniteCanvasGestureDetector].
class StylusHoverTracker {
  const StylusHoverTracker();

  /// The stylus is hovering above the screen at [position] with physical
  /// [distance] (in pixels, when reported by the platform; 0 otherwise).
  void updateHover(Offset position, {double distance = 0.0}) {}

  /// The stylus has left the hover range or touched down.
  void endHover() {}
}

const StylusHoverTracker noopStylusHoverTracker = StylusHoverTracker();
