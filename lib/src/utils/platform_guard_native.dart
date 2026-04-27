// Native implementation — uses dart:io Platform
import 'dart:io';

/// Getter `isAndroid`.
bool get isAndroid => Platform.isAndroid;
/// Getter `isIOS`.
bool get isIOS => Platform.isIOS;
/// Getter `isWindows`.
bool get isWindows => Platform.isWindows;
/// Getter `isMacOS`.
bool get isMacOS => Platform.isMacOS;
/// Getter `isLinux`.
bool get isLinux => Platform.isLinux;
