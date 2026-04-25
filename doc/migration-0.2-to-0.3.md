# Migration guide: 0.2 → 0.3

`fluera_canvas` 0.3.0 is **non-breaking** for consumers of the
0.2.x public API. Existing apps recompile and run unchanged.
That said, two new opt-in APIs and one behaviour change are worth
adopting.

## TL;DR

```diff
 FlueraCanvas(
   key: canvasKey,
   tool: tool,
   strokeColor: color,
   strokeWidth: width,
+  initialBytes: bytesFromDisk,   // ← strongly recommended for restore
 )
```

```diff
+import 'package:fluera_canvas/fluera_canvas.dart';
+
+// Drop-in toolbar replaces ~80 lines of segmented + swatches + slider
+// + undo / redo / clear glue:
+FlueraCanvasToolbar(
+  canvasKey: canvasKey,
+  tool: tool,
+  onToolChanged: (t) => setState(() => tool = t),
+  color: color,
+  onColorChanged: (c) => setState(() => color = c),
+  strokeWidth: width,
+  onStrokeWidthChanged: (w) => setState(() => width = w),
+);
```

That's the entire migration if you weren't relying on the removed
overview-zoom guard.

## What's new

### 1. `FlueraCanvas(initialBytes: Uint8List?)`

Decodes persisted bytes inside `initState`, BEFORE the first build
/ paint. The first frame already shows the persisted strokes.

**Before** (0.2.x — works in debug, can fail on Impeller-Vulkan):

```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final bytes = await myStorage.read();
    if (mounted) {
      _canvasKey.currentState?.loadFromBytes(bytes);
    }
  });
}
```

**After** (0.3.0):

```dart
Uint8List? _initialBytes;

@override
void initState() {
  super.initState();
  myStorage.read().then((bytes) {
    if (mounted) setState(() => _initialBytes = bytes);
  });
}

@override
Widget build(BuildContext context) => FlueraCanvas(
  key: _canvasKey,
  initialBytes: _initialBytes,
  // …
);
```

Why bother — `loadFromBytes` after the first frame can leave the
RepaintBoundary cached layer stale on Impeller-Vulkan (the second
paint is silently coalesced and the canvas appears empty). See
[`troubleshooting-impeller.md`](troubleshooting-impeller.md).

### 2. `FlueraCanvasToolbar` widget

Drop-in Material toolbar with pen / eraser segmented control,
6-color palette, stroke-width slider, undo / redo / clear buttons,
auto-bound to the canvas's `historyListenable` so the buttons
disable / enable correctly without manual `setState` plumbing.

**Before** (0.2.x — your own UI):

```dart
Column(children: [
  Expanded(child: FlueraCanvas(key: key, tool: tool, …)),
  // 80 lines of SegmentedButton + Slider + IconButtons + onPressed
  // wiring with setState everywhere…
]);
```

**After** (0.3.0):

```dart
Column(children: [
  Expanded(child: FlueraCanvas(key: key, tool: tool, …)),
  FlueraCanvasToolbar(
    canvasKey: key,
    tool: tool,
    onToolChanged: (t) => setState(() => tool = t),
    color: color,
    onColorChanged: (c) => setState(() => color = c),
    strokeWidth: width,
    onStrokeWidthChanged: (w) => setState(() => width = w),
  ),
]);
```

Use `palette: [...]` for a custom color set, `showUndo: false`
to suppress individual buttons, `background:` to override the
fill colour. The 0.2.x manual approach still works; the toolbar is
purely additive.

### 3. `FlueraCanvasState.historyListenable`

Read-only `Listenable` that fires on every committed-strokes
mutation (commit / erase / clear / undo / redo / load /
tool change / background change). Useful if you've built a
custom toolbar and want it to track history state without
manually wiring `onStrokeCommitted` / `onStrokesErased` +
`setState`.

```dart
ListenableBuilder(
  listenable: canvasKey.currentState!.historyListenable,
  builder: (ctx, _) => Row(children: [
    IconButton(
      icon: Icon(Icons.undo),
      onPressed: canvasKey.currentState!.canUndo
          ? () => canvasKey.currentState!.undo()
          : null,
    ),
    // …
  ]),
);
```

## Behaviour change: drawing at any zoom

`InfiniteCanvasGestureDetector` no longer blocks drawing when
`controller.scale <= 0.5`. The 0.2.x guard was an app-specific
carry-over from the original Fluera codebase that gated drawing
behind a "zoomed-in enough" threshold to encourage
overview/navigation mode at low zoom.

If your app relied on this — for example, you assumed pointer
gestures at low zoom would always pan, never draw — you have
two options:

1. Switch your `tool:` value to a non-`draw` mode (a custom
   navigation tool, or just `CanvasTool.erase` if you want pan-only)
   when the camera is below your threshold. Your widget already
   has access to `controller.scale` via the `InfiniteCanvasController`
   passed to `FlueraCanvas`.
2. Accept the new behaviour — most consumer drawing apps WANT to
   draw at any zoom level.

This is a behaviour change, not a compile break. Code still
compiles; it just behaves differently below `scale = 0.5`.

## Performance: nothing to migrate, but worth knowing

0.3.0 ships per-stroke `ui.Picture` cache + committed `RepaintBoundary`
+ single-`drawPath` quadratic-bezier rendering. The result: 5k–10k
strokes at 60 FPS on mid-tier Android. No API change, no opt-in
flag — your existing scenes get faster automatically on rebuild.

If you previously held off building large scenes because 0.2.x
fell over above ~200 strokes, those workarounds (manual layer
flattening, off-screen rasterisation) can probably be removed.
See [`performance.md`](performance.md) for the new ceiling.

## Deprecated APIs

None in 0.3.0. The 0.2.0 API surface is fully preserved.

## Rollback plan

If 0.3.0 misbehaves on your target platform, pin to 0.2.0:

```yaml
dependencies:
  fluera_canvas: 0.2.0
```

Then file an issue at
https://github.com/Lorencoshametaj/fluera_canvas/issues with the
[`bug_report.md`](../.github/ISSUE_TEMPLATE/bug_report.md) template
filled in.
