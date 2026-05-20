// ════════════════════════════════════════════════════════════════════════════
// ⌨️  FlueraShortcuts — keyboard shortcut customization for FlueraCanvas.
//
// Override the default desktop shortcuts (Ctrl/Cmd+Z undo, Ctrl/Cmd+C
// copy, etc.) on a per-action basis. Pass a partial map to the
// `shortcuts` prop on `FlueraCanvas`; missing entries fall back to
// the per-platform default (Cmd-bound on macOS / iOS, Ctrl-bound
// elsewhere).
//
// Pattern mirrors `FlueraToolbarTheme` and `FlueraStrings`: opt-in
// via constructor, defaults reproduce 0.15.x behaviour exactly.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Names of the built-in canvas actions that can be re-bound. Each
/// maps to one entry in [FlueraShortcuts]. Added in 0.16.0.
enum FlueraShortcutAction {
  /// Undo the last operation. Default: `Ctrl/Cmd + Z`.
  undo,

  /// Redo. Default: `Ctrl/Cmd + Shift + Z` AND `Ctrl/Cmd + Y`.
  redo,

  /// Delete the selection (or clear the canvas if nothing is selected).
  /// Default: `Delete` AND `Backspace`.
  deleteOrClear,

  /// Drop the current selection / cancel an in-flight gesture.
  /// Default: `Esc`.
  escape,

  /// Select every visible selectable node. Default: `Ctrl/Cmd + A`.
  selectAll,

  /// Duplicate the current selection. Default: `Ctrl/Cmd + D`.
  duplicate,

  /// Copy the current selection to the system clipboard.
  /// Default: `Ctrl/Cmd + C`.
  copy,

  /// Paste from the system clipboard. Default: `Ctrl/Cmd + V`.
  paste,
}

/// Customise the keyboard shortcuts attached to [FlueraCanvas] when
/// `enableKeyboardShortcuts: true` (the default). Pass a partial
/// override map; missing entries fall back to the per-platform
/// default.
///
/// ```dart
/// FlueraCanvas(
///   shortcuts: const FlueraShortcuts(
///     overrides: {
///       FlueraShortcutAction.undo: SingleActivator(LogicalKeyboardKey.keyU, control: true),
///     },
///   ),
/// );
/// ```
///
/// Added in 0.16.0.
@immutable
class FlueraShortcuts {
  /// Build a shortcut set with optional per-action overrides.
  const FlueraShortcuts({this.overrides = const {}});

  /// Per-action overrides. Missing actions use the per-platform
  /// default ([defaultsForMacOS] / [defaultsForOther]).
  final Map<FlueraShortcutAction, ShortcutActivator> overrides;

  /// Resolve the activator for [action] respecting overrides + the
  /// current platform's defaults.
  ShortcutActivator resolve(FlueraShortcutAction action, {required bool isMac}) {
    final o = overrides[action];
    if (o != null) return o;
    final defaults = isMac ? defaultsForMacOS : defaultsForOther;
    return defaults[action]!;
  }

  /// Default shortcuts when running on macOS / iOS (Cmd-bound).
  static const Map<FlueraShortcutAction, ShortcutActivator> defaultsForMacOS = {
    FlueraShortcutAction.undo:
        SingleActivator(LogicalKeyboardKey.keyZ, meta: true),
    FlueraShortcutAction.redo:
        SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true),
    FlueraShortcutAction.deleteOrClear:
        SingleActivator(LogicalKeyboardKey.delete),
    FlueraShortcutAction.escape: SingleActivator(LogicalKeyboardKey.escape),
    FlueraShortcutAction.selectAll:
        SingleActivator(LogicalKeyboardKey.keyA, meta: true),
    FlueraShortcutAction.duplicate:
        SingleActivator(LogicalKeyboardKey.keyD, meta: true),
    FlueraShortcutAction.copy:
        SingleActivator(LogicalKeyboardKey.keyC, meta: true),
    FlueraShortcutAction.paste:
        SingleActivator(LogicalKeyboardKey.keyV, meta: true),
  };

  /// Default shortcuts when running anywhere else (Ctrl-bound).
  static const Map<FlueraShortcutAction, ShortcutActivator> defaultsForOther = {
    FlueraShortcutAction.undo:
        SingleActivator(LogicalKeyboardKey.keyZ, control: true),
    FlueraShortcutAction.redo:
        SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true),
    FlueraShortcutAction.deleteOrClear:
        SingleActivator(LogicalKeyboardKey.delete),
    FlueraShortcutAction.escape: SingleActivator(LogicalKeyboardKey.escape),
    FlueraShortcutAction.selectAll:
        SingleActivator(LogicalKeyboardKey.keyA, control: true),
    FlueraShortcutAction.duplicate:
        SingleActivator(LogicalKeyboardKey.keyD, control: true),
    FlueraShortcutAction.copy:
        SingleActivator(LogicalKeyboardKey.keyC, control: true),
    FlueraShortcutAction.paste:
        SingleActivator(LogicalKeyboardKey.keyV, control: true),
  };

  /// All-defaults instance — equivalent to `FlueraShortcuts()`.
  static const FlueraShortcuts defaults = FlueraShortcuts();
}
