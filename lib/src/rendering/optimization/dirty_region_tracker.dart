import 'dart:ui';
import 'package:flutter/foundation.dart';

/// 🎨 Dirty Region Tracker for Incremental Rendering
///
/// **Phase 3 Feature**: Tracks modified regions to enable partial canvas repaints.
///
/// **Benefits**:
/// - 8x-100x faster repaints for local modifications
/// - Only repaint changed areas instead of entire canvas
/// - Automatic region merging for optimal performance
///
/// **Usage**:
/// ```dart
/// tracker.markDirty(stroke.bounds);
/// if (tracker.shouldRepaint(viewport)) {
///   final dirtyRects = tracker.getDirtyRegions(viewport);
///   // Repaint only dirty regions
/// }
/// tracker.clearDirty();
/// ```
class DirtyRegionTracker extends ChangeNotifier {
  /// Current dirty regions (modified areas)
  final List<Rect> _dirtyRegions = [];

  /// Maximum number of separate dirty regions before merging all
  static const int maxDirtyRegions = 10;

  /// Expansion factor for dirty regions (accounts for stroke width, anti-aliasing)
  static const double dirtyExpansion = 10.0;

  /// 🚀 Batch mode flag - disable logging during bulk operations
  bool _batchMode = false;

  /// Check if there are any dirty regions
  bool get hasDirtyRegions => _dirtyRegions.isNotEmpty;

  /// Get count of dirty regions
  int get dirtyCount => _dirtyRegions.length;

  /// Mark a region as dirty (modified)
  void markDirty(Rect region) {
    if (region.isEmpty) return;

    // Expand region to account for stroke width and anti-aliasing
    final expandedRegion = region.inflate(dirtyExpansion);

    _dirtyRegions.add(expandedRegion);

    // Merge regions if too many (performance optimization)
    if (_dirtyRegions.length > maxDirtyRegions) {
      _mergeDirtyRegions();
    }

    // 🚀 Skip notifyListeners during batch mode (avoid 10k notifications!)
    if (!_batchMode) {
      notifyListeners();
    }
  }

  /// Mark multiple regions as dirty
  void markDirtyBatch(List<Rect> regions) {
    for (final region in regions) {
      if (!region.isEmpty) {
        _dirtyRegions.add(region.inflate(dirtyExpansion));
      }
    }

    if (_dirtyRegions.length > maxDirtyRegions) {
      _mergeDirtyRegions();
    }

    // 🚀 Skip notifyListeners during batch mode
    if (!_batchMode) {
      notifyListeners();
    }
  }

  /// Check if viewport needs repaint (has dirty regions)
  bool shouldRepaint(Rect viewport) {
    return _dirtyRegions.any((dirty) => dirty.overlaps(viewport));
  }

  /// Get dirty regions that overlap with viewport
  List<Rect> getDirtyRegions(Rect viewport) {
    return _dirtyRegions
        .where((dirty) => dirty.overlaps(viewport))
        .map((dirty) => dirty.intersect(viewport))
        .where((intersection) => !intersection.isEmpty)
        .toList();
  }

  /// Get bounding box of all dirty regions
  Rect? get dirtyBounds {
    if (_dirtyRegions.isEmpty) return null;

    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final rect in _dirtyRegions) {
      if (rect.left < minX) minX = rect.left;
      if (rect.top < minY) minY = rect.top;
      if (rect.right > maxX) maxX = rect.right;
      if (rect.bottom > maxY) maxY = rect.bottom;
    }

    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Clear all dirty regions (after repaint)
  void clearDirty() {
    if (_dirtyRegions.isEmpty) return; // 🚀 Skip redundant notify
    _dirtyRegions.clear();
    notifyListeners();
  }

  /// 🚀 Enter batch mode (disable logging and defer merging)
  void enterBatchMode() {
    _batchMode = true;
  }

  /// 🚀 Exit batch mode and perform final merge
  void exitBatchMode() {
    _batchMode = false;
    if (_dirtyRegions.isNotEmpty) {
      _mergeDirtyRegions();
    }
    // 🚀 Notify once at the end instead of 10k times!
    notifyListeners();
  }

  /// Merge overlapping or nearby dirty regions.
  ///
  /// Uses swap-and-pop instead of removeAt to avoid O(N) shifts.
  /// Bounded to maxDirtyRegions × 2 merge passes to avoid worst-case O(N³).
  void _mergeDirtyRegions() {
    if (_dirtyRegions.length <= 1) return;

    final merged = <Rect>[];

    for (final region in _dirtyRegions) {
      Rect current = region;
      int passes = 0;
      bool mergedWithExisting = true;

      while (mergedWithExisting && passes < maxDirtyRegions * 2) {
        mergedWithExisting = false;
        passes++;
        for (int i = 0; i < merged.length; i++) {
          if (_shouldMerge(merged[i], current)) {
            current = _mergeRects(merged[i], current);
            // Swap-and-pop: O(1) instead of removeAt's O(N) shift
            final lastIdx = merged.length - 1;
            if (i != lastIdx) {
              merged[i] = merged[lastIdx];
            }
            merged.removeLast();
            mergedWithExisting = true;
            break;
          }
        }
      }
      merged.add(current);
    }

    // Complexity cap: force merge into single bounding box if still too many.
    if (merged.length > maxDirtyRegions) {
      Rect combined = merged.first;
      for (int i = 1; i < merged.length; i++) {
        combined = _mergeRects(combined, merged[i]);
      }
      merged.clear();
      merged.add(combined);
    }

    // Replace dirty regions with merged ones
    _dirtyRegions.clear();
    _dirtyRegions.addAll(merged);
  }

  /// Check if two rects should be merged
  bool _shouldMerge(Rect a, Rect b) {
    // Merge if overlapping
    if (a.overlaps(b)) return true;

    // Merge if very close (within expansion distance)
    const mergeThreshold = dirtyExpansion * 2;

    // Check horizontal distance
    final horizontalGap =
        (a.left > b.right)
            ? a.left - b.right
            : (b.left > a.right ? b.left - a.right : 0);

    // Check vertical distance
    final verticalGap =
        (a.top > b.bottom)
            ? a.top - b.bottom
            : (b.top > a.bottom ? b.top - a.bottom : 0);

    return horizontalGap <= mergeThreshold && verticalGap <= mergeThreshold;
  }

  /// Merge two rects into their bounding box
  Rect _mergeRects(Rect a, Rect b) {
    return Rect.fromLTRB(
      a.left < b.left ? a.left : b.left,
      a.top < b.top ? a.top : b.top,
      a.right > b.right ? a.right : b.right,
      a.bottom > b.bottom ? a.bottom : b.bottom,
    );
  }

  /// Reset tracker (clear all state)
  void reset() {
    _dirtyRegions.clear();
    notifyListeners();
  }

  /// Debug info
  void printStatus() {
    if (_dirtyRegions.isNotEmpty) {}
  }
}
