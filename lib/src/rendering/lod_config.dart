/// ═══════════════════════════════════════════════════════════════════════════
/// 🎯 LOD (Level of Detail) threshold constants and tier computation.
///
/// SINGLE SOURCE OF TRUTH for all zoom-based LOD decisions across the engine.
/// Used by DrawingPainter, InfiniteCanvasController, and the UI canvas layer.
///
/// TIER OVERVIEW:
///   0 = Full quality   (scale ≥ 0.50)
///   1 = Simplified     (0.25 ≤ scale < 0.50)
///   2 = Thumbnails     (scale < 0.25)
/// ═══════════════════════════════════════════════════════════════════════════

/// Tier 0→1 / 1→2 boundary when zooming OUT: strokes become thumbnails.
const double kLodTier2Threshold = 0.25;

/// Tier 0→1 boundary when zooming OUT: full quality → simplified.
const double kLodTier1Threshold = 0.45;

/// Tier 1→0 boundary when zooming IN (hysteresis): back to full quality.
const double kLodTier0UpThreshold = 0.55;

/// Tier 2→1 boundary when zooming IN (hysteresis): thumbnails → simplified.
const double kLodTier1UpThreshold = 0.30;

/// Standard tier 1 upper boundary (no hysteresis context).
const double kLodTier1Standard = 0.50;

/// Budget threshold for low-zoom rendering (PDF inflation, tile budget).
const double kLodLowZoomThreshold = 0.30;

/// Compute LOD tier from [scale], with optional hysteresis based on [currentTier].
///
/// Without [currentTier]: simple non-hysteretic check.
/// With [currentTier]: uses asymmetric boundaries to prevent oscillation.
int computeLodTier(double scale, [int? currentTier]) {
  if (currentTier == null) {
    return scale < kLodTier2Threshold ? 2 : (scale < kLodTier1Standard ? 1 : 0);
  }
  if (currentTier == 0) {
    return scale < kLodTier2Threshold ? 2 : (scale < kLodTier1Threshold ? 1 : 0);
  } else if (currentTier == 1) {
    return scale < kLodTier2Threshold ? 2 : (scale >= kLodTier0UpThreshold ? 0 : 1);
  } else {
    return scale >= kLodTier0UpThreshold ? 0 : (scale >= kLodTier1UpThreshold ? 1 : 2);
  }
}
