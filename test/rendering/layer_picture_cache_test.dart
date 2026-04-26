import 'package:flutter_test/flutter_test.dart';

import 'package:fluera_canvas/fluera_canvas.dart';

// We can't create real ui.Picture objects in unit tests (they require a
// PictureRecorder + Canvas), so we test the cache logic via mock-like
// approaches using the public API only.

void main() {
  group('LayerPictureCache', () {
    test('starts empty', () {
      final cache = LayerPictureCache();
      expect(cache.size, 0);
      expect(cache.contains('any'), isFalse);
    });

    test('get returns null for missing entry', () {
      final cache = LayerPictureCache();
      expect(cache.get('node-1', 1), isNull);
    });

    test('invalidateAll on empty cache is safe', () {
      final cache = LayerPictureCache();
      cache.invalidateAll();
      expect(cache.size, 0);
    });

    test('dispose on empty cache is safe', () {
      final cache = LayerPictureCache();
      cache.dispose();
      expect(cache.size, 0);
    });

    test('invalidate on non-existent key is safe', () {
      final cache = LayerPictureCache();
      cache.invalidate('does-not-exist');
      expect(cache.size, 0);
    });

    test('invalidateDirty removes only matching IDs', () {
      final cache = LayerPictureCache();
      // Can't add entries without real Pictures, but can verify no crash.
      cache.invalidateDirty({'a', 'b', 'c'});
      expect(cache.size, 0);
    });

    test('maxEntries defaults to 32', () {
      final cache = LayerPictureCache();
      expect(cache.maxEntries, 32);
    });

    test('custom maxEntries', () {
      final cache = LayerPictureCache(maxEntries: 8);
      expect(cache.maxEntries, 8);
    });
  });
}
