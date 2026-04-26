import 'dart:ui' as ui;
import 'dart:collection';
import 'package:flutter/material.dart';

/// 🚀 Stroke Cache Manager with Undo Snapshot Ring Buffer
///
/// RESPONSIBILITIES:
/// - ✅ Maintains vectorial cache (ui.Picture) of completed strokes
/// - ✅ Incremental updates: only re-draws new strokes
/// - ✅ Synchronous cache update (no async lag)
/// - ✅ **Undo snapshot ring buffer**: O(1) undo/redo without re-render
///
/// UNDO SNAPSHOT ARCHITECTURE:
/// Each time the cache is built or updated, a snapshot (ui.Picture clone)
/// is saved in a ring buffer keyed by stroke count. On undo (count decreases),
/// the ring buffer is checked first — if a matching snapshot exists, it's
/// replayed in O(1) instead of triggering a full re-render.
///
/// Ring buffer capacity: 20 entries by default (covers ~20 undo steps).
/// LRU eviction with proper disposal of oldest snapshots.
class StrokeCacheManager {
  /// Cache vettoriale of completed strokes
  ui.Picture? _cachedPicture;

  /// Number of strokes in the current cache
  int _cachedStrokeCount = 0;

  // ═══════════════════════════════════════════════════════════════════════════
  // 🔄 UNDO SNAPSHOT RING BUFFER
  // ═══════════════════════════════════════════════════════════════════════════

  /// Maximum number of undo snapshots to keep
  static const int maxUndoSnapshots = 10;

  /// Ring buffer: stroke count → cached Picture
  /// LinkedHashMap for insertion-order iteration (LRU eviction)
  final LinkedHashMap<int, ui.Picture> _undoSnapshots = LinkedHashMap();

  /// Get the current cache
  ui.Picture? get cachedPicture => _cachedPicture;

  /// Number of strokes in the cache
  int get cachedStrokeCount => _cachedStrokeCount;

  /// Number of undo snapshots currently stored
  int get undoSnapshotCount => _undoSnapshots.length;

  /// Checks if the cache is valid for the given number of strokes
  bool isCacheValid(int totalStrokes) {
    return _cachedPicture != null && _cachedStrokeCount == totalStrokes;
  }

  /// Checks if the cache covers at least some strokes
  bool hasCacheForStrokes(int totalStrokes) {
    return _cachedPicture != null &&
        _cachedStrokeCount > 0 &&
        _cachedStrokeCount <= totalStrokes;
  }

  /// 🔄 Try to restore cache from undo snapshot ring buffer.
  ///
  /// Called when stroke count **decreases** (undo/delete).
  /// Returns true if a matching snapshot was found and restored.
  bool tryRestoreFromUndoSnapshot(int targetStrokeCount) {
    final snapshot = _undoSnapshots[targetStrokeCount];
    if (snapshot == null) return false;

    // Dispose current cache before replacing
    _cachedPicture?.dispose();

    // Clone the snapshot (re-record from the Picture)
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawPicture(snapshot);
    _cachedPicture = recorder.endRecording();
    _cachedStrokeCount = targetStrokeCount;

    return true;
  }

  /// 📸 Save current cache as an undo snapshot.
  ///
  /// Called automatically after cache creation or update.
  /// 🚀 P99 FIX: only snapshots every 5th stroke to avoid 1-3ms drawPicture
  /// replay on every single commit. Undo still works — just may need a
  /// full rebuild for intermediate counts (rare).
  void _saveUndoSnapshot() {
    if (_cachedPicture == null || _cachedStrokeCount <= 0) return;

    // Don't duplicate: if we already have this count, skip
    if (_undoSnapshots.containsKey(_cachedStrokeCount)) return;

    // 🚀 Lazy snapshots: only every 5th stroke count (or first stroke)
    if (_cachedStrokeCount > 1 && _cachedStrokeCount % 5 != 0) return;

    // Clone the current picture for the snapshot
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawPicture(_cachedPicture!);
    final clone = recorder.endRecording();

    _undoSnapshots[_cachedStrokeCount] = clone;

    // LRU eviction: remove oldest if over capacity
    while (_undoSnapshots.length > maxUndoSnapshots) {
      final oldestKey = _undoSnapshots.keys.first;
      _undoSnapshots.remove(oldestKey)?.dispose();
    }
  }

  /// 🚀 Create cache synchronously (no async lag)
  ///
  /// [strokes] List of strokes to cache
  /// [drawStrokeCallback] Function to draw a single stroke
  /// [size] Size of the canvas
  void createCacheSynchronously(
    List<dynamic> strokes,
    void Function(Canvas, dynamic) drawStrokeCallback,
    Size size,
  ) {
    // 🗑️ Dispose old picture before replacing
    _cachedPicture?.dispose();

    if (strokes.isEmpty) {
      _cachedPicture = null;
      _cachedStrokeCount = 0;
      return;
    }

    // Create PictureRecorder to record draw commands
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Draw all strokes using the callback
    for (final stroke in strokes) {
      drawStrokeCallback(canvas, stroke);
    }

    // Finalize and save the Picture
    _cachedPicture = recorder.endRecording();
    _cachedStrokeCount = strokes.length;

    // 📸 Save undo snapshot
    _saveUndoSnapshot();
  }

  /// Updates cache by adding new strokes to the existing cache
  ///
  /// [newStrokes] New strokes to add
  /// [drawStrokeCallback] Function to draw a single stroke
  /// [size] Size of the canvas
  void updateCache(
    List<dynamic> newStrokes,
    void Function(Canvas, dynamic) drawStrokeCallback,
    Size size,
  ) {
    if (newStrokes.isEmpty) return;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Draw existing cache if available
    final oldPicture = _cachedPicture;
    if (oldPicture != null) {
      canvas.drawPicture(oldPicture);
    }

    // Add new strokes
    for (final stroke in newStrokes) {
      drawStrokeCallback(canvas, stroke);
    }

    // Update cache (dispose the old picture after recording is done)
    _cachedPicture = recorder.endRecording();
    _cachedStrokeCount += newStrokes.length;
    oldPicture?.dispose();

    // 📸 Save undo snapshot
    _saveUndoSnapshot();
  }

  /// 🚀 STEAL: extract the cached Picture WITHOUT disposing it.
  /// Transfers ownership to the caller — cache becomes empty.
  /// Used by LOD transition to avoid expensive snapshot copy.
  ui.Picture? stealPicture() {
    final pic = _cachedPicture;
    _cachedPicture = null;
    _cachedStrokeCount = 0;
    return pic;
  }

  /// Invalidate the cache completely
  void invalidateCache() {
    _cachedPicture?.dispose();
    _cachedPicture = null;
    _cachedStrokeCount = 0;
    // Note: undo snapshots are intentionally NOT cleared here.
    // They survive invalidation so undo can still find them.
  }

  /// Clear undo snapshots (e.g. on canvas reload)
  void clearUndoSnapshots() {
    for (final snapshot in _undoSnapshots.values) {
      snapshot.dispose();
    }
    _undoSnapshots.clear();
  }

  /// 🚀 Adopt an externally-recorded Picture as the cache.
  ///
  /// Used by record-once rendering: the caller records strokes into a
  /// PictureRecorder, replays the Picture onto the live canvas, and then
  /// passes the same Picture here to avoid a second render pass.
  void adoptPicture(ui.Picture picture, int strokeCount) {
    _cachedPicture?.dispose();
    _cachedPicture = picture;
    _cachedStrokeCount = strokeCount;
    _saveUndoSnapshot();
  }

  /// 🚀 Draw cached picture onto the given canvas
  /// Returns true if cache was drawn, false if no cache available
  bool drawCached(Canvas canvas) {
    if (_cachedPicture == null) return false;
    canvas.drawPicture(_cachedPicture!);
    return true;
  }

  /// Dispose all resources
  void dispose() {
    _cachedPicture?.dispose();
    _cachedPicture = null;
    _cachedStrokeCount = 0;
    clearUndoSnapshots();
  }
}
