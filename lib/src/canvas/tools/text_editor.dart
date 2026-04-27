import 'dart:async' show scheduleMicrotask;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../../core/models/digital_text_element.dart';
import '../../core/nodes/text_node.dart';
import '../../core/scene_graph/node_id.dart';
import '../../utils/uid.dart' show generateUid;
import '../fluera_canvas_widget.dart' show FlueraCanvasState;

/// Imperative entry point for the live text-tool flow.
///
/// Mounts a Material `TextField` overlay above the active canvas,
/// positioned in screen coords on top of the target [TextNode].
/// Edits are committed back to the canvas as a single
/// `_UpdateTextOp` (or `_AddLayerChildOp` when a fresh node is
/// being created), so undo restores the previous text exactly.
///
/// Tap-outside, Escape, and the soft-keyboard "Done" affordance all
/// commit the in-progress edit. Empty-text commit on a fresh node
/// rolls the addition back to avoid orphan empty TextNodes.
///
/// Only one editor is active at a time process-wide; calling
/// [start] while another session is alive auto-commits the previous
/// one before starting a new one.
class FlueraTextEditor {
  FlueraTextEditor._();

  static _ActiveEditor? _active;

  /// Begin an editing session.
  ///
  /// - When [existing] is non-null, that node enters edit mode.
  /// - Otherwise a fresh empty `TextNode` is committed at
  ///   [worldPosition] and the editor opens on it.
  static void start(
    FlueraCanvasState state, {
    NodeId? existing,
    Offset? worldPosition,
    Color color = const Color(0xFF1A1A1A),
    double fontSize = 16.0,
    String? fontFamily,
  }) {
    // Auto-commit any previous session before opening a new one.
    commit(state);

    TextNode targetNode;
    bool isFresh;

    if (existing != null) {
      final found = state.findNode(existing);
      if (found is TextNode) {
        targetNode = found;
        isFresh = false;
      } else {
        // Stale id — treat as a fresh node placement instead of
        // silently no-op'ing.
        if (worldPosition == null) return;
        targetNode = _mintBlank(worldPosition, color, fontSize, fontFamily);
        state.addTextNode(targetNode);
        isFresh = true;
      }
    } else {
      if (worldPosition == null) return;
      targetNode = _mintBlank(worldPosition, color, fontSize, fontFamily);
      state.addTextNode(targetNode);
      isFresh = true;
    }

    final controller = TextEditingController(text: targetNode.textElement.text);
    final focusNode = FocusNode();
    final overlay = Overlay.of(state.context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder:
          (ctx) => _EditorChrome(
            state: state,
            node: targetNode,
            controller: controller,
            focusNode: focusNode,
            onDone: () => commit(state),
            onCancel: () => cancel(state),
          ),
    );
    overlay.insert(entry);
    focusNode.requestFocus();

    _active = _ActiveEditor(
      state: state,
      node: targetNode,
      isFresh: isFresh,
      originalElement: targetNode.textElement,
      controller: controller,
      focusNode: focusNode,
      entry: entry,
    );
  }

  /// Commit the in-progress edit (if any). Idempotent.
  ///
  /// On commit:
  /// - Empty text on a fresh node → drop the orphan via the proper
  ///   `_AddLayerChildOp.undo` path (avoids touching unrelated
  ///   history entries).
  /// - Non-empty change → push `_UpdateTextOp` via
  ///   `state.updateTextElement(...)`.
  /// - No-op when nothing changed.
  static void commit(FlueraCanvasState state) {
    final active = _active;
    if (active == null) return;
    _active = null;

    final newText = active.controller.text;
    final oldText = active.originalElement.text;

    if (newText.isEmpty && active.isFresh) {
      // Roll back the freshly-added empty node directly through the
      // active layer so we don't accidentally undo whatever the user
      // did right before opening the editor.
      state.removeFreshTextNode(active.node);
    } else if (newText != oldText) {
      final next = active.originalElement.copyWith(
        text: newText,
        modifiedAt: DateTime.now(),
      );
      active.state.updateTextElement(active.node.id, next);
    }

    _scheduleDispose(active);
  }

  /// Cancel the in-progress edit without committing changes.
  ///
  /// On cancel:
  /// - Fresh nodes are removed from the canvas (proper history op
  ///   undo, not `state.undo()`).
  /// - Existing nodes are left exactly as they were before [start].
  static void cancel(FlueraCanvasState state) {
    final active = _active;
    if (active == null) return;
    _active = null;
    if (active.isFresh) {
      state.removeFreshTextNode(active.node);
    }
    _scheduleDispose(active);
  }

  /// Tear down the overlay + dispose the focus node and the text
  /// controller — but defer the dispose to the next microtask so we
  /// never call [FocusNode.dispose] from inside its own
  /// `notifyListeners()` walk (which is exactly what happens when
  /// the focus-loss callback triggers commit / cancel). Disposing
  /// during the notifier walk corrupts the listener set and throws
  /// `Concurrent modification during iteration`.
  ///
  /// Wrapped in try/catch so a stale [_active] surviving a hot
  /// restart (when the OverlayEntry's mount point has been replaced)
  /// doesn't crash the next [start] call. `OverlayEntry.remove` and
  /// `FocusNode.dispose` both throw on a disposed parent — we
  /// swallow those silently because the goal is best-effort cleanup.
  static void _scheduleDispose(_ActiveEditor active) {
    try {
      active.entry.remove();
    } catch (_) {
      // Stale overlay entry from a previous hot-restart — already
      // detached. Nothing to do.
    }
    scheduleMicrotask(() {
      try {
        active.focusNode.dispose();
      } catch (_) {/* already disposed */}
      try {
        active.controller.dispose();
      } catch (_) {/* already disposed */}
    });
  }

  /// True while an editing session is open.
  static bool get isEditing => _active != null;

  static TextNode _mintBlank(
    Offset worldPosition,
    Color color,
    double fontSize,
    String? fontFamily,
  ) {
    final id = generateUid();
    final element = DigitalTextElement(
      id: id,
      text: '',
      position: worldPosition,
      color: color,
      fontSize: fontSize,
      fontFamily: fontFamily,
      createdAt: DateTime.now(),
    );
    return TextNode(id: NodeId(id), textElement: element);
  }
}

class _ActiveEditor {
  _ActiveEditor({
    required this.state,
    required this.node,
    required this.isFresh,
    required this.originalElement,
    required this.controller,
    required this.focusNode,
    required this.entry,
  });
  final FlueraCanvasState state;
  final TextNode node;
  final bool isFresh;
  final DigitalTextElement originalElement;
  final TextEditingController controller;
  final FocusNode focusNode;
  final OverlayEntry entry;
}

/// Material chrome around the live `TextField`. Tracks the camera so
/// the input box rides every pan / zoom while the user is typing.
///
/// The heavy widget tree (`Material` + `TextField`) is built ONCE
/// per session — only the `Positioned` wrapper rebuilds on camera
/// change, so a 60 FPS pan during editing doesn't re-instantiate
/// the input subtree every frame.
class _EditorChrome extends StatefulWidget {
  const _EditorChrome({
    required this.state,
    required this.node,
    required this.controller,
    required this.focusNode,
    required this.onDone,
    required this.onCancel,
  });

  final FlueraCanvasState state;
  final TextNode node;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onDone;
  final VoidCallback onCancel;

  @override
  State<_EditorChrome> createState() => _EditorChromeState();
}

class _EditorChromeState extends State<_EditorChrome> {
  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_onFocusChange);
    super.dispose();
  }

  void _onFocusChange() {
    // Lost focus → tap-outside / IME dismiss → commit.
    if (!widget.focusNode.hasFocus) {
      widget.onDone();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.state.controller;
    final element = widget.node.textElement;

    // Hoisted heavy subtree — built once, rebuilt only when this
    // widget itself rebuilds (not on every camera tick).
    final inputChild = Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 80, maxWidth: 480),
        child: IntrinsicWidth(
          child: Shortcuts(
            shortcuts: const {
              SingleActivator(LogicalKeyboardKey.escape): _CancelIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                _CancelIntent: CallbackAction<_CancelIntent>(
                  onInvoke: (_) {
                    widget.onCancel();
                    return null;
                  },
                ),
              },
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                autofocus: true,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                // No onEditingComplete: Enter must insert a newline,
                // not commit. Commit happens via focus-out (tap
                // outside / IME dismiss → `_onFocusChange`) or via
                // Esc (Shortcuts above → `widget.onCancel`).
                style: TextStyle(
                  color: element.color,
                  fontSize: element.fontSize * ctrl.scale,
                  fontFamily: element.fontFamily,
                  fontWeight: element.fontWeight,
                  fontStyle: element.fontStyle,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(4),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 1.5,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return AnimatedBuilder(
      animation: ctrl,
      builder: (ctx, child) {
        // Anchor the input at the node's world position transformed
        // into screen coords. We don't apply the per-text rotation
        // here — for the MVP the input box stays axis-aligned even
        // when the underlying TextNode is rotated; the rotated
        // output is re-rendered on commit.
        final screen = ctrl.canvasToScreen(element.position);
        return Stack(
          children: [
            // Tap-outside catcher. Opaque so the tap is fully
            // consumed: it commits the current edit and closes the
            // overlay, but does NOT propagate down to FlueraCanvas
            // (which would interpret the same tap as "open a new
            // TextNode at the tap position" and create a fresh
            // editor on top of the just-committed one).
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onDone,
              ),
            ),
            Positioned(left: screen.dx, top: screen.dy, child: child!),
          ],
        );
      },
      child: inputChild,
    );
  }
}

class _CancelIntent extends Intent {
  const _CancelIntent();
}
