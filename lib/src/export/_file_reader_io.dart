import 'dart:io' show File;
import 'dart:typed_data';

/// Native build — read [path] off the local filesystem when it
/// exists. Returns `null` on missing / unreadable paths so the
/// caller can fall back to path-only embedding without throwing.
Future<Uint8List?> readFileBytesIfExists(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return bytes.isEmpty ? null : bytes;
  } catch (_) {
    return null;
  }
}
