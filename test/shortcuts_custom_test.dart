// Tests for the 0.16.0 FlueraShortcuts customizable map.
// We assert the resolution layer (overrides + defaults), not actual
// key dispatch (Flutter's `Shortcuts` widget already has its own
// integration tests for that).

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlueraShortcuts.resolve', () {
    test('default macOS undo binds Cmd+Z', () {
      const s = FlueraShortcuts();
      final activator = s.resolve(FlueraShortcutAction.undo, isMac: true)
          as SingleActivator;
      expect(activator.trigger, LogicalKeyboardKey.keyZ);
      expect(activator.meta, isTrue);
      expect(activator.control, isFalse);
    });

    test('default non-Mac undo binds Ctrl+Z', () {
      const s = FlueraShortcuts();
      final activator = s.resolve(FlueraShortcutAction.undo, isMac: false)
          as SingleActivator;
      expect(activator.trigger, LogicalKeyboardKey.keyZ);
      expect(activator.control, isTrue);
      expect(activator.meta, isFalse);
    });

    test('override wins over per-platform default', () {
      const customUndo = SingleActivator(
        LogicalKeyboardKey.keyU,
        control: true,
      );
      const s = FlueraShortcuts(
        overrides: {FlueraShortcutAction.undo: customUndo},
      );
      // Both platforms see the override.
      expect(s.resolve(FlueraShortcutAction.undo, isMac: true), customUndo);
      expect(s.resolve(FlueraShortcutAction.undo, isMac: false), customUndo);
      // Other actions still fall back to defaults.
      final redoMac = s.resolve(FlueraShortcutAction.redo, isMac: true)
          as SingleActivator;
      expect(redoMac.meta, isTrue);
      expect(redoMac.shift, isTrue);
    });

    test('all FlueraShortcutAction values have a default for both platforms', () {
      const s = FlueraShortcuts();
      for (final action in FlueraShortcutAction.values) {
        expect(s.resolve(action, isMac: true), isA<ShortcutActivator>());
        expect(s.resolve(action, isMac: false), isA<ShortcutActivator>());
      }
    });
  });
}
