import 'dart:ui' as ui;
import 'package:fluera_canvas/fluera_canvas.dart';
import 'dart:collection';

/// 🎨 Snapshot Cache Manager for Incremental Rendering
///
/// **Phase 3 Feature**: Caches rendered canvas regions to avoid redundant repaints.
///
/// **Benefits**:
/// - Reuse previously rendered regions → 10x-100x faster
/// - Only repaint dirty areas
/// - LRU eviction with memory limits
///
/// **Usage**:
/// ```dart
/// // Cache a rendered region
/// await cacheManager.cacheSnapshot(region, renderedImage);
///
/// // Retrieve cached snapshot
/// final cached = cacheManager.getSnapshot(region);
/// if (cached != null) {
///   canvas.drawImage(cached, offset, paint);
/// }
///
/// // Invalidate on modification
/// cacheManager.invalidate(dirtyRect);
/// ```
class SnapshotCacheManager {
  /// Cache storage: LinkedHashMap provides O(1) LRU eviction.
  /// Keys are inserted at the end. The first element is the least recently used.
  final LinkedHashMap<ui.Rect, _CacheEntry> _cache =
      LinkedHashMap<ui.Rect, _CacheEntry>();

  /// Maximum cache size in bytes (default: 50MB)
  int maxCacheSize = 50 * 1024 * 1024;

  /// Current cache size in bytes
  int _currentCacheSize = 0;

  /// Cache hit/miss statistics
  int _cacheHits = 0;
  int _cacheMisses = 0;

  /// Get cache statistics
  Map<String, dynamic> get stats => {
    'entries': _cache.length,
    'sizeBytes': _currentCacheSize,
    'sizeMB': (_currentCacheSize / (1024 * 1024)).toStringAsFixed(2),
    'hits': _cacheHits,
    'misses': _cacheMisses,
    'hitRate':
        _cacheHits + _cacheMisses > 0
            ? ((_cacheHits / (_cacheHits + _cacheMisses)) * 100)
                .toStringAsFixed(1)
            : '0.0',
  };

  /// Cache a rendered region
  Future<void> cacheSnapshot(ui.Rect region, ui.Image image) async {
    final imageSize = _estimateImageSize(image);

    // Check if adding this would exceed limit
    if (_currentCacheSize + imageSize > maxCacheSize) {
      _evictLRU(imageSize);
    }

    // If it already exists, remove it first to update size and push to back (MRU)
    if (_cache.containsKey(region)) {
      final oldEntry = _cache.remove(region)!;
      _currentCacheSize -= oldEntry.sizeBytes;
      oldEntry.image.dispose();
    }

    // Store in cache (implicitly at the end = MRU)
    _cache[region] = _CacheEntry(
      image: image,
      region: region,
      sizeBytes: imageSize,
    );

    _currentCacheSize += imageSize;
  }

  /// Get cached snapshot for region (exact match)
  ui.Image? getSnapshot(ui.Rect region) {
    final entry = _cache.remove(region);

    if (entry != null) {
      // Re-insert at the end to mark as MRU
      _cache[region] = entry;
      _cacheHits++;
      return entry.image;
    }

    _cacheMisses++;
    return null;
  }

  /// Find cached snapshot that contains the region
  ui.Image? findContainingSnapshot(ui.Rect region) {
    // Note: O(n) scan, but 'n' is very small due to memory limits (typically < 10 items).
    // Spatial indexing would add more overhead than it saves for this 'n'.
    ui.Rect? foundKey;
    _CacheEntry? foundEntry;

    for (final entry in _cache.entries) {
      if (_containsRegion(entry.value.region, region)) {
        foundKey = entry.key;
        foundEntry = entry.value;
        break;
      }
    }

    if (foundKey != null && foundEntry != null) {
      // Re-insert at the end to mark as MRU
      _cache.remove(foundKey);
      _cache[foundKey] = foundEntry;
      _cacheHits++;
      return foundEntry.image;
    }

    _cacheMisses++;
    return null;
  }

  /// Invalidate all cached snapshots that overlap with dirty rect
  void invalidate(ui.Rect dirtyRect) {
    final keysToRemove = <ui.Rect>[];

    for (final entry in _cache.entries) {
      if (entry.value.region.overlaps(dirtyRect)) {
        keysToRemove.add(entry.key);
      }
    }

    for (final key in keysToRemove) {
      final entry = _cache.remove(key);
      if (entry != null) {
        _currentCacheSize -= entry.sizeBytes;
        entry.image.dispose();
      }
    }
  }

  /// Invalidate all cached snapshots
  void invalidateAll() {
    for (final entry in _cache.values) {
      entry.image.dispose();
    }
    _cache.clear();
    _currentCacheSize = 0;
  }

  /// Evict least recently used entries to make room
  void _evictLRU(int requiredSpace) {
    if (_cache.isEmpty) return;

    // LinkedHashMap iteration order is insertion order (which we maintain as LRU -> MRU).
    // We just remove from the front until we have enough space.
    final keysToRemove = <ui.Rect>[];

    for (final key in _cache.keys) {
      if (_currentCacheSize + requiredSpace <= maxCacheSize) {
        break;
      }
      keysToRemove.add(key);
      _currentCacheSize -= _cache[key]!.sizeBytes;
    }

    for (final key in keysToRemove) {
      _cache.remove(key)?.image.dispose();
    }
  }

  /// Check if region A contains region B
  bool _containsRegion(ui.Rect a, ui.Rect b) {
    return a.left <= b.left &&
        a.top <= b.top &&
        a.right >= b.right &&
        a.bottom >= b.bottom;
  }

  /// Estimate image size in bytes
  int _estimateImageSize(ui.Image image) {
    // RGBA = 4 bytes per pixel
    return image.width * image.height * 4;
  }

  /// Dispose all cached images
  void dispose() {
    invalidateAll();
    _nodeCache.clear();
  }

  // ---------------------------------------------------------------------------
  // Node-based cache (GAP 8)
  // ---------------------------------------------------------------------------

  /// Node-based cache keyed by node ID + content version.
  ///
  /// Unlike the Rect-based cache, this doesn't suffer from cache misses
  /// when the viewport moves. Nodes are invalidated by ID when their
  /// content changes (via [InvalidationGraph] dirty tracking).
  final Map<String, _NodeCacheEntry> _nodeCache = {};

  /// Cache a rendered snapshot for a specific node.
  void cacheNodeSnapshot(String nodeId, int version, ui.Image image) {
    // Remove old entry if exists.
    final old = _nodeCache.remove(nodeId);
    if (old != null) {
      old.image.dispose();
    }
    _nodeCache[nodeId] = _NodeCacheEntry(image: image, version: version);
  }

  /// Get a cached snapshot for a node, or null if not cached or stale.
  ui.Image? getNodeSnapshot(String nodeId, int version) {
    final entry = _nodeCache[nodeId];
    if (entry == null) return null;
    if (entry.version != version) {
      // Stale — remove and return null.
      _nodeCache.remove(nodeId);
      entry.image.dispose();
      return null;
    }
    return entry.image;
  }

  /// Invalidate a specific node's cached snapshot.
  void invalidateNode(String nodeId) {
    final entry = _nodeCache.remove(nodeId);
    if (entry != null) {
      entry.image.dispose();
    }
  }

  /// Invalidate snapshots for a set of dirty node IDs.
  ///
  /// Call this when the invalidation graph reports dirty nodes.
  void onDirtyNodes(Set<String> dirtyNodeIds) {
    for (final id in dirtyNodeIds) {
      invalidateNode(id);
    }
  }

  /// Number of node-based cache entries.
  int get nodeCacheSize => _nodeCache.length;

  /// Debug info
  void printStatus() {
    if (_cacheHits + _cacheMisses > 0) {
      final hitRate = (_cacheHits / (_cacheHits + _cacheMisses)) * 100;
      // print('Cache Hit Rate: ${hitRate.toStringAsFixed(1)}%');
    }
  }
}

/// Internal cache entry
class _CacheEntry {
  final ui.Image image;
  final ui.Rect region;
  final int sizeBytes;

  _CacheEntry({
    required this.image,
    required this.region,
    required this.sizeBytes,
  });
}

/// Internal cache entry for node-based snapshots (GAP 8).
class _NodeCacheEntry {
  final ui.Image image;
  final int version;

  _NodeCacheEntry({required this.image, required this.version});
}
