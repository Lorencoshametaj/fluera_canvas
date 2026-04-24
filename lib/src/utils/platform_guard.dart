// ============================================================================
// 🌐 PLATFORM GUARD — Web-safe Platform detection
//
// dart:io Platform throws on web. This utility wraps Platform checks
// behind kIsWeb guards so the engine can compile and run on all targets.
//
// USAGE:
//   Replace:  Platform.isAndroid  →  PlatformGuard.isAndroid
//   Replace:  Platform.isIOS      →  PlatformGuard.isIOS
// ============================================================================

import 'package:flutter/foundation.dart';

import 'platform_guard_native.dart'
    if (dart.library.html) 'platform_guard_web.dart'
    as impl;

/// Web-safe wrapper around `dart:io Platform`.
///
/// All getters return `false` on web, which is correct because
/// web is none of Android/iOS/Windows/macOS/Linux.
class PlatformGuard {
  PlatformGuard._();

  static bool get isAndroid => !kIsWeb && impl.isAndroid;
  static bool get isIOS => !kIsWeb && impl.isIOS;
  static bool get isWindows => !kIsWeb && impl.isWindows;
  static bool get isMacOS => !kIsWeb && impl.isMacOS;
  static bool get isLinux => !kIsWeb && impl.isLinux;

  /// Whether the platform is a mobile device (Android or iOS).
  static bool get isMobile => isAndroid || isIOS;

  /// Whether the platform is a desktop OS.
  static bool get isDesktop => isWindows || isMacOS || isLinux;

  /// Whether we are running on the web.
  static bool get isWeb => kIsWeb;
}
