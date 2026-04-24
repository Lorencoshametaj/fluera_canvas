import 'dart:math';

/// Generates a unique identifier string (32 hex characters).
///
/// Uses [Random.secure] for cryptographically strong randomness.
/// Produces IDs equivalent to UUID v4 without the dashes, suitable for
/// canvas element identification where RFC 4122 compliance is unnecessary.
///
/// Example output: `'a3f1b2c4d5e6f7081920a1b2c3d4e5f6'`
String generateUid() {
  final r = Random.secure();
  final sb = StringBuffer();
  for (int i = 0; i < 16; i++) {
    sb.write(r.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return sb.toString();
}
