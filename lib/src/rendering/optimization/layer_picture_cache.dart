import 'dart:ui' as ui;
import 'package:fluera_canvas/fluera_canvas.dart';

/// LRU cache for per-layer `Picture` objects.
///
/// Each layer's subtree is rendered into a `PictureRecorder` once,
/// producing a `Picture` that can be replayed every frame via
/// `canvas.drawPicture()` — zero re-traversal for unchanged layers.
///
/// The cache is keyed by node ID and invalidated when a layer's
/// content version changes (tracked by `contentFingerprint` or
/// the invalidation graph's dirty flags).
///
/// ## Usage
///
/// ```dart
/// final cache = LayerPictureCache();
///
/// // During render:
/// final cached = cache.get(layer.id.value, layer.contentVersion);
/// if (cached != null) {
///   canvas.drawPicture(cached);
/// } else {
///   final recorder = ui.PictureRecorder();
///   final pbCanvas = Canvas(recorder);
///   renderSubtree(pbCanvas, layer);
///   final picture = recorder.endRecording();
///   cache.put(layer.id.value, layer.contentVersion, picture);
///   canvas.drawPicture(picture);
/// }
/// ```
class LayerPictureCache {
  /// Cached pictures keyed by node ID.
  final Map<String, _CachedPicture> _cache = {};

  /// Maximum number of cached pictures.
  ///
  /// When exceeded, the least recently used entry is evicted.
  final int maxEntries;

  /// Access order for LRU eviction. Front = LRU, back = MRU.
  final List<String> _accessOrder = [];

  /// API element `maxEntries`.
  LayerPictureCache({this.maxEntries = 32});

  /// Get a cached picture for [nodeId] if it matches [contentVersion].
  ///
  /// Returns `null` if not cached or if the version doesn't match
  /// (indicating the content changed and needs re-rendering).
  ui.Picture? get(String nodeId, int contentVersion) {
    final entry = _cache[nodeId];
    if (entry == null) return null;

    if (entry.contentVersion != contentVersion) {
      // Version mismatch — stale cache entry. Remove it.
      _remove(nodeId);
      return null;
    }

    // Move to MRU position.
    _accessOrder.remove(nodeId);
    _accessOrder.add(nodeId);

    return entry.picture;
  }

  /// Cache a rendered picture for [nodeId] at [contentVersion].
  void put(String nodeId, int contentVersion, ui.Picture picture) {
    // Remove old entry if exists.
    if (_cache.containsKey(nodeId)) {
      _remove(nodeId);
    }

    // Evict LRU if at capacity.
    while (_cache.length >= maxEntries && _accessOrder.isNotEmpty) {
      _remove(_accessOrder.first);
    }

    _cache[nodeId] = _CachedPicture(
      picture: picture,
      contentVersion: contentVersion,
    );
    _accessOrder.add(nodeId);
  }

  /// Invalidate a specific node's cached picture.
  void invalidate(String nodeId) {
    _remove(nodeId);
  }

  /// Invalidate all cached pictures.
  void invalidateAll() {
    for (final entry in _cache.values) {
      entry.picture.dispose();
    }
    _cache.clear();
    _accessOrder.clear();
  }

  /// Invalidate pictures for a set of dirty node IDs.
  ///
  /// Call this when the invalidation graph reports dirty nodes.
  void invalidateDirty(Set<String> dirtyNodeIds) {
    for (final id in dirtyNodeIds) {
      _remove(id);
    }
  }

  /// Number of cached pictures.
  int get size => _cache.length;

  /// Whether a picture is cached for [nodeId].
  bool contains(String nodeId) => _cache.containsKey(nodeId);

  /// Remove and dispose a cache entry.
  void _remove(String nodeId) {
    final entry = _cache.remove(nodeId);
    if (entry != null) {
      entry.picture.dispose();
    }
    _accessOrder.remove(nodeId);
  }

  /// Dispose all cached pictures and release resources.
  void dispose() {
    invalidateAll();
  }
}

/// Internal cache entry pairing a picture with its content version.
class _CachedPicture {
  final ui.Picture picture;
  final int contentVersion;

  _CachedPicture({required this.picture, required this.contentVersion});
}
