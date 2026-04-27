import 'dart:typed_data';

/// Web stub — no `dart:io`, so `File()` doesn't exist. Hosts that
/// reach this branch live in browsers; we silently return `null`
/// (asset embedding falls back to path-only). The IO build of this
/// file lives next door in `_file_reader_io.dart` and pulls bytes
/// from the local filesystem.
Future<Uint8List?> readFileBytesIfExists(String path) async => null;
