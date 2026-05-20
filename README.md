# fluera_canvas

> **Pure-Dart Flutter SDK for infinite-canvas drawing widgets.**
> Pan, zoom, rotate camera. Layered scene graph. Pressure-aware input.
> Persistence + PNG export. Selection / lasso / transform / text /
> stickers / image annotations. **5 k+ strokes at 60 FPS** on a
> mid-tier Android.
>
> Status: **`0.16.2`** — pre-1.0 but additive only (zero breaking
> changes from 0.8.0). API stabilises at `1.0.0`.
> Marketing site: **[engine.fluera.dev](https://engine.fluera.dev/)**

**Jump to:** [Hello canvas](#hello-canvas) · [Zero-config](#zero-config-drop-in) · [Recipes](#common-recipes) · [Cookbook](doc/cookbook.md) · [Integrations](doc/integrations.md) · [Keyboard](#keyboard-shortcuts) · [Export](doc/export.md) · [Performance](#performance) · [FAQ](#faq--troubleshooting) · [Customization](doc/customization.md) · [Migration](doc/migration-0.5-to-0.10.0.md) · [Changelog](CHANGELOG.md)

## Install

```yaml
dependencies:
  fluera_canvas: ^0.16.2
```

```dart
import 'package:fluera_canvas/fluera_canvas.dart';
```

## Positioning

| You're building… | Use |
|---|---|
| Notes app, whiteboard, sketching app, design tool, mind-map, diagram editor, infinite-canvas planner | **`fluera_canvas`** — full scene-graph + persistence + selection / transform |
| Photo annotation, draw-on-image with strokes that follow when you move / rotate / scale the image | **`fluera_canvas`** — image annotations are first-class (sticky, split-on-boundary) |
| Signature pad, e-signature flow | `signature` / `hand_signature` (more focused on that single use case) |
| Custom stroke renderer, no widget | `perfect_freehand` (pure rendering primitive) |

`fluera_canvas` deliberately doesn't compete in the signature-pad
niche — that's well served. The gap on pub.dev was the
**document-grade** category: infinite surface, thousands of strokes,
persistence-friendly, image annotations that ride the image as a
rigid block. That's what this SDK is for.

## What you get

- **`FlueraCanvas`** — drop-in drawing widget. Pen, stroke- + pixel-mode
  eraser, line / rectangle / ellipse shape tools, undo / redo,
  pressure-aware input, infinite pan / zoom / rotation, PNG export.
  Headless: drive `tool` / `strokeColor` / `strokeWidth` from any UI.
- **`FlueraSketch` / `FlueraSketchScaffold` / `FlueraSketchApp`** — three
  zero-config widgets at increasing levels of "magic". `runApp(const FlueraSketchApp())`
  literally gives you a complete drawing app.
- **`FlueraCanvasToolbar`** — drop-in Material 3 toolbar. Pill tool
  buttons, circular color swatches, stroke-width slider with live
  preview, opacity slider, filled-tonal trailing actions
  (undo / redo / clear), optional layer panel / sticker panel / text
  tool / image tool. Brandable via `FlueraToolbarTheme`
  (`ThemeExtension`); auto-collapses to a 3-row layout below
  `compactBreakpoint` (default 600 px).
- **`FlueraCanvasColorPickerDialog`** + `showFlueraColorPicker(...)` —
  zero-dependency HSV / hex picker.
- **`InfiniteCanvasController`** — camera with pan, zoom, rotation,
  spring physics, momentum, multi-phase animation.
- **`InfiniteCanvasGestureDetector`** — multi-touch, stylus, palm
  rejection, hover tracking. All policies pluggable.
- **Scene graph** — `CanvasStrokeNode`, `ShapeNode`, `TextNode`,
  `ImageNode`, `PathNode`, `GroupNode`, `LayerNode` with visitor
  pattern.
- **Spatial index** + per-stroke `ui.Picture` cache + multi-layer
  `LayerPictureCache` + `DirtyRegionTracker` + memory-pressure
  observer — together responsible for the 5 k+ stroke / 60 FPS budget.
- **Input pipeline** — One-Euro smoothing, dynamic pressure mapping,
  palm rejection, stylus prediction, 120 Hz raw processor.
- **Persistence** — binary FCV0 v6 round-trips strokes, image bytes,
  image annotations, text, layer state.

## What's new in 0.10.x

- **`FlueraSketchApp`** zero-config drop-in: `runApp(const FlueraSketchApp())`
  is a complete drawing app. Three presets: `notes`, `whiteboard`,
  `signature`. Optional `onAutoSave` / `onAutoLoad` / `onExportPng`
  callbacks for any persistence backend.
- **Lasso UX parity** with the Fluera flagship app: tap-on-selection
  enters transform mode (drag = move, handle = scale / rotate);
  hit-test stricter (no over-selection from bbox-only).
- **Live stroke now honours active layer's blend mode + opacity** —
  toggling `multiply` / `screen` updates the in-flight preview
  immediately, no jump at pen-up.
- **Smoothing pipeline rebuilt** to match the commercial fountain-pen
  path builder: One-Euro at ingest → arc-length subdivision →
  two-pass EMA → ghost-tail anchor → Catmull-Rom → cubic bezier
  (tau = 1/6). Live and committed strokes share identical geometry.
- **Pixel eraser** is pressure-aware + velocity-aware + drops
  micro-survivor fragments < 3 px arc-length.
- **PNG export** has 4 bounds modes via `FlueraExportBounds`:
  `viewport` (legacy), `allContent`, `selection`, `custom`. Plus
  `pixelRatio`, `padding`, `transparent`.
- **SVG export (basic, 0.13.0)** via `state.toSvgBytes()` — geometry +
  layer compositing for vector workflows. High-fidelity SVG with all
  16 PS blend modes + image annotations is available in the
  commercial `fluera_canvas_gpu` (same call site, transparently
  upgraded). Full matrix in [doc/export.md](doc/export.md).
- **Clipboard (0.13.0)** — `Ctrl/Cmd + C` / `V` copy and paste the
  current selection across canvas instances via the system clipboard.
  Programmatic API: `state.copySelection()` /
  `state.pasteFromClipboard()`.
- **Minimap (0.13.0)** — drop-in `FlueraMinimap` widget shows a live
  overview of the entire canvas + viewport rectangle. Tap to recenter.
- **Camera bounds (0.13.0)** — `InfiniteCanvasController(minScale,
  maxScale, panBoundary)` to clamp the camera for single-page apps.
- **Stylus tilt + metadata (0.14.0)** — `CanvasStroke.tilts` (per-point
  pen tilt in radians) + `CanvasStroke.metadata` (consumer-defined
  JSON-encodable bag) round-trip through FCV0 v8 and the JSON serializer.
  Built-in vector renderer ignores tilt; `fluera_canvas_gpu` exploits it
  for nib-angle calligraphy.
- **Document model (0.14.0)** — `FlueraDocument` wraps a `FlueraCanvas`
  with id / title / dirty flag / autosave debounce hook. Skips the
  plumbing every notes app reinvents.
- **Published benchmarks (0.14.0)** — concrete numbers in
  [doc/performance.md](doc/performance.md). 5k+ strokes @ 60fps,
  43 ms for 10k hit-tests on a 5k-stroke scene.
- **Smart guides on-by-default (0.15.0)** — drag-to-move on a
  selection snaps the dragged frame's anchors to nearby nodes
  (Figma / TLDraw style). Magenta dashed guide lines render during
  the drag; hold Shift to bypass. Reusable as a public `SnapEngine`
  primitive for custom widgets.
- **Hit-test API public (0.15.0)** — `state.hitTest(Offset)` and
  `state.hitTestInRect(Rect)` on top of the internal RTree spatial
  index. Hover tooltips, custom select, click-through detection.
- **Programmatic drawing helpers (0.15.0)** — `state.drawLine` /
  `drawCircle` / `drawPolygon` deposit ink without going through
  pointer events. Tutorial overlays, generative art, AI-driven canvases.
- **Custom per-tool cursors (0.15.0)** — `cursorPerTool` map on
  `FlueraCanvas` overrides the desktop mouse cursor on a per-tool
  basis. Branded cursors, tutorial states, custom affordances.
- **Cookbook + integrations docs (0.16.0)** — 10 copy-paste recipes
  in [doc/cookbook.md](doc/cookbook.md) for the most common asks
  ("autosave", "export PNG transparent", "limit zoom to a single
  page"). 8 integration snippets in
  [doc/integrations.md](doc/integrations.md) for riverpod, bloc,
  drift, hive, share_plus, printing, etc.
- **Accessibility (0.16.0)** — `semanticsEnabled: true` on
  `FlueraCanvas` (default `true`) wraps the canvas in a `Semantics`
  node carrying a summary label so screen readers announce
  something meaningful when focused.
- **i18n via `FlueraStrings` (0.16.0)** — opt-in
  `ThemeExtension<FlueraStrings>` localises every visible string
  in the toolbar (24 fields). English defaults; partial overrides
  translate only what your brand needs.
- **Customizable shortcuts (0.16.0)** — `FlueraShortcuts` map on
  `FlueraCanvas` re-binds any subset of the 8 default keyboard
  actions (undo/redo/copy/paste/...). Per-platform defaults
  preserved via `FlueraShortcuts.defaults`.
- **Cupertino toolbar (0.16.1)** — `FlueraCanvasCupertinoToolbar`
  is an Apple HIG mirror of the Material drop-in: same API, same
  callbacks, same theming — built with `CupertinoButton` /
  `CupertinoSlider` / `CupertinoColors` / `CupertinoIcons`. Pick
  this when targeting iOS / macOS with pixel-perfect aesthetics.
  Zero new dependencies (Cupertino is built-in Flutter).
- **TextNode is now selectable + transformable** (drag / scale / rotate
  via the same handles as image / stroke nodes).
- Edge-case hardening: serializer bounds-checks (DoS protection),
  `renderToImage` clamps, single-tap "dot" stroke commit, text editor
  hot-restart guards.

Full per-release detail in **[CHANGELOG.md](CHANGELOG.md)**. Upgrading
from 0.5.x? See **[doc/migration-0.5-to-0.10.0.md](doc/migration-0.5-to-0.10.0.md)**
— zero breaking changes, plus a checklist of opt-in flags to surface
the new selection / lasso / text / sticker / snap-to-grid features.

## Hello canvas

The headless variant — wire `tool` / `color` / `width` from your own
UI. Use this when you want full control over the drawing chrome.

```dart
import 'package:flutter/material.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

class MyPage extends StatefulWidget {
  const MyPage({super.key});
  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  final _canvasKey = GlobalKey<FlueraCanvasState>();
  CanvasTool _tool = CanvasTool.draw;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            onPressed: () => _canvasKey.currentState?.undo(),
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            onPressed: () => _canvasKey.currentState?.redo(),
          ),
        ],
      ),
      body: FlueraCanvas(
        key: _canvasKey,
        tool: _tool,
        strokeColor: Colors.black87,
        strokeWidth: 2.5,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => setState(() => _tool =
            _tool == CanvasTool.draw ? CanvasTool.erase : CanvasTool.draw),
        child: Icon(_tool == CanvasTool.draw
            ? Icons.edit
            : Icons.cleaning_services),
      ),
    );
  }
}
```

Want pan / zoom / rotation driven from outside (a "reset view"
button, programmatic fly-to)? Pass
`controller: InfiniteCanvasController()`.

## Zero-config drop-in

Pick the level of "magic":

### Whole app, one line

```dart
void main() => runApp(const FlueraSketchApp());
```

You get a Material 3 `MaterialApp` + AppBar with undo / redo / clear /
export-PNG popup, the full toolbar with every opt-in flag wired
(pen / shapes / pixel-eraser / lasso / select / text / sticker / image /
layers / transform / color picker), dotted background. Three presets:

```dart
const FlueraSketchApp(preset: FlueraSketchPreset.notes);      // minimal
const FlueraSketchApp(preset: FlueraSketchPreset.whiteboard); // default
const FlueraSketchApp(preset: FlueraSketchPreset.signature);  // single pen, no zoom
```

### Embed a sketch page in an existing app

```dart
MaterialPageRoute(builder: (_) => FlueraSketchScaffold(
  title: 'My note',
  preset: FlueraSketchPreset.notes,
  // Optional persistence hooks — wire any backend.
  onAutoSave: (bytes) => File('$dir/note.fcv').writeAsBytes(bytes),
  onAutoLoad: () async => File('$dir/note.fcv').readAsBytes(),
));
```

The scaffold debounces autosave at 2 s (`autoSaveDebounce:`). The
export-PNG popup falls back to a clipboard data-URL if you don't pass
`onExportPng`.

### Just the canvas + toolbar (no Scaffold)

```dart
Scaffold(
  appBar: AppBar(title: Text('My drawing')),
  body: const FlueraSketch(),  // canvas + toolbar self-contained
);
```

`FlueraSketch` owns the `tool` / `color` / `strokeWidth` state
internally — no `setState` plumbing. Pass
`canvasKey: GlobalKey<FlueraCanvasState>()` if you want to drive
`save` / `load` / `undo` from outside.

The three widgets stack: `FlueraSketchApp` → wraps →
`FlueraSketchScaffold` → wraps → `FlueraSketch`. Each is usable
standalone. When you outgrow the presets, drop down to
[`FlueraCanvas`](#hello-canvas) — same scene graph, every API still
available.

## Tools

Switch via the `tool:` parameter (or via `FlueraCanvasToolbar` opt-in
flags):

| Tool | What it does |
|---|---|
| `CanvasTool.draw` | Free-form pressure-aware stroke. |
| `CanvasTool.erase` | Stroke-mode eraser — removes whole strokes the eraser circle touches. Vector-preserving (undo brings them back intact). |
| `CanvasTool.erasePixel` | Pixel-mode eraser — splits intersected strokes around the eraser circle and keeps the surviving pieces. |
| `CanvasTool.line` | Drag from A to B for a straight line. |
| `CanvasTool.rectangle` | Drag corner-to-corner for a rectangle outline. |
| `CanvasTool.ellipse` | Drag for an ellipse outline (32-segment polyline). |
| `CanvasTool.select` | Tap a node to select; drag to move; corners / edges / rotate handle for transform. |
| `CanvasTool.lasso` | Drag a closed path; nodes whose centre or corners fall inside are selected. Concave shapes work. |
| `CanvasTool.text` | Tap to drop a `TextNode`; inline Material `TextField` opens for editing. |
| `CanvasTool.image` | (via `FlueraImageTool.pickAndCommit`) — file-picker import. |

Shape tools commit as ordinary `CanvasStroke` instances, so they
participate in undo / redo, persistence, hit-test, and the per-stroke
`ui.Picture` cache for free.

## Common recipes

All snippets assume `final canvasKey = GlobalKey<FlueraCanvasState>();`
and a `CanvasTool _tool` field driven by your widget state. The canvas
is intentionally headless — wire `_tool` from a `SegmentedButton`, a
`FlueraCanvasToolbar`, your own UI, anything.

### Select + drag + delete

```dart
FlueraCanvas(
  key: canvasKey,
  tool: CanvasTool.select,        // tap to pick a node, drag to move
  snapToGrid: 16,                  // optional: snap drag to 16-px grid
  smartGuidesEnabled: true,        // optional: magenta align guides
);

// Programmatic delete (Delete key is auto-wired):
canvasKey.currentState?.deleteSelection();
```

Selection is observable via `canvasKey.currentState!.selectionListenable`.
See `state.duplicateSelection()`, `state.bringToFront(id)`,
`state.sendToBack(id)`, `state.groupSelection()`,
`state.ungroupSelection()`.

### Lasso free-form selection

```dart
FlueraCanvas(key: canvasKey, tool: CanvasTool.lasso);
// User drags any closed path; every node whose bounds the lasso
// encloses or crosses is added to the selection. Live magenta dashed
// preview during the drag. After pen-up, tapping inside the bbox
// drags the selection (no need to switch to `select` first); tapping
// outside starts a fresh lasso.
```

Use **lasso** for scattered or non-rectangular selections (strokes
around an imported image, an artistic cluster, hand-drawn diagrams).
Use **`CanvasTool.select`** marquee for grid layouts where an
axis-aligned rectangle does the job faster.

### Snap-to-grid + smart guides

```dart
FlueraCanvas(
  key: canvasKey,
  tool: CanvasTool.select,
  snapToGrid: 8,                   // 0 disables; 8 / 16 / 24 are typical
  smartGuidesEnabled: true,        // align with neighbours on drag
  smartGuidesTolerancePx: 6,       // screen-space tolerance
);
// Hold Shift while dragging to bypass both snap and guides.
```

### Live text tool

```dart
FlueraCanvas(key: canvasKey, tool: CanvasTool.text);
// Tap empty canvas: a Material TextField caret opens inline. Type;
// commit on Done / blur / Esc. Tap an existing TextNode to re-enter
// edit mode. Use CanvasTool.select afterwards to drag / scale / rotate.
```

### Sticker panel

```dart
FlueraCanvasToolbar(
  canvasKey: canvasKey,
  tool: _tool,
  onToolChanged: (t) => setState(() => _tool = t),
  showStickerPanel: true,
  // stickers: const [], // omit or set to [] to opt out of defaults
);

// Defaults: kFlueraDefaultStickers ships 8 Material-icon stickers via
// FlueraIconStickerProvider — zero asset bundling.

// Custom catalogue:
final myStickers = <FlueraSticker>[
  FlueraSticker.fromIcon(id: 'rocket', label: 'Rocket', icon: Icons.rocket_launch),
  FlueraSticker.fromIcon(id: 'bolt',   label: 'Bolt',   icon: Icons.bolt),
];
```

### Image annotations (sticky strokes)

```dart
// 1. Import an image:
await FlueraImageTool.pickAndCommit(context: context, state: canvasKey.currentState!);

// 2. Switch to a draw tool and stroke on top of the image. Strokes
//    that fall inside the image bounds are auto-attached as image
//    annotations (in image-local coords) and ride every move /
//    rotate / scale / mirror as a rigid block. Strokes that cross the
//    boundary are split: inside parts attach, outside parts stay free.
```

### Theming the drop-in toolbar

```dart
MaterialApp(
  theme: ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF6750A4),
    extensions: const [
      FlueraToolbarTheme(
        radius: 18,
        swatchSize: 36,
        selectedFill: Color(0xFF00CC88),
      ),
    ],
  ),
  // ...
);
```

Or pass `theme:` directly on a single toolbar — wins over the global
extension. See [doc/customization.md](doc/customization.md) for the full
field reference (21 fields covering geometry, motion, and 8 colour
overrides).

### Compact mode

`FlueraCanvasToolbar` switches to a vertical 3-row stack below
`compactBreakpoint` (default `600` px) — palette + size slider on
row 2, opacity slider + trailing icons on row 3. Tap targets stay
44×44 in both modes. Override:

```dart
FlueraCanvasToolbar(
  // ...
  compactBreakpoint: 720,  // switch earlier (tablet portrait)
  // compactBreakpoint: 0, // disable, always use wide layout
)
```

### Custom toolbar layout

When the built-in `FlueraCanvasToolbar` doesn't fit your design
(Cupertino, sidebar, floating, custom segmented button) — skip it and
drive the canvas directly:

```dart
class _DemoState extends State<Demo> {
  final _canvasKey = GlobalKey<FlueraCanvasState>();
  CanvasTool _tool = CanvasTool.draw;
  Color _color = Colors.black;
  double _width = 2.5;

  @override
  Widget build(BuildContext context) => Column(children: [
    Expanded(child: FlueraCanvas(
      key: _canvasKey,
      tool: _tool,
      strokeColor: _color,
      strokeWidth: _width,
    )),
    // Your own toolbar widgets here — anything that mutates
    // _tool / _color / _width via setState.
  ]);
}
```

`FlueraCanvas` is intentionally headless. The state is observable via
`historyListenable` / `selectionListenable` so a custom toolbar can
gate undo / redo / contextual buttons without polling. See the
**Custom toolbar (headless)** demo in `example/lib/main.dart` for a
runnable Photoshop-style floating-sidebar implementation.

### Save / load (mobile + desktop)

```dart
// Persist to disk:
final bytes = canvasKey.currentState!.toBytes();
await File('$dir/scene.fcv').writeAsBytes(bytes);

// Restore inside initState (the safest path — see FAQ #1):
FlueraCanvas(key: canvasKey, initialBytes: await loadBytes());

// Or reload after first frame:
canvasKey.currentState?.loadFromBytes(bytes);
```

FCV0 v6 round-trips strokes, image bytes, image annotations, text
nodes, layer state. Backward-read v1 → v5 unchanged.

### Save / load (web)

`dart:io File` doesn't exist in the browser sandbox. `state.toBytes()`
still returns a `Uint8List` — wire it to a download instead:

```dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:web/web.dart' as web;            // web only
import 'dart:js_interop';

void downloadFcv(Uint8List bytes, String filename) {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );
  final url = web.URL.createObjectURL(blob);
  web.HTMLAnchorElement()
    ..href = url
    ..download = filename
    ..click();
  web.URL.revokeObjectURL(url);
}

if (kIsWeb) {
  downloadFcv(canvasKey.currentState!.toBytes(), 'scene.fcv');
} else {
  await File('$dir/scene.fcv').writeAsBytes(canvasKey.currentState!.toBytes());
}
```

To **load** on web, use `file_selector` (already a transitive dep of
`fluera_canvas`):

```dart
import 'package:file_selector/file_selector.dart';

final file = await openFile(acceptedTypeGroups: [
  XTypeGroup(label: 'fluera', extensions: ['fcv']),
]);
if (file != null) {
  canvasKey.currentState?.loadFromBytes(await file.readAsBytes());
}
```

This snippet works on every platform — no `kIsWeb` branch needed.

## Keyboard shortcuts

`FlueraCanvas` wraps its widget tree in `Shortcuts + Actions` and
ships **15 default keybindings**. The Ctrl/Cmd modifier auto-resolves
per platform (Cmd on macOS / iOS, Ctrl elsewhere) — no `Platform`
branching required.

| Shortcut (Win / Linux / Web) | Shortcut (macOS / iOS) | Action |
|---|---|---|
| `Ctrl+Z` | `Cmd+Z` | Undo last op |
| `Ctrl+Y` *or* `Ctrl+Shift+Z` | `Cmd+Y` *or* `Cmd+Shift+Z` | Redo |
| `Ctrl+A` | `Cmd+A` | Select all selectable nodes in active layer |
| `Ctrl+D` | `Cmd+D` | Duplicate current selection (offset 20 × 20 px) |
| `Delete` *or* `Backspace` | `Delete` *or* `Backspace` | Delete selection — falls back to *clear canvas* when nothing is selected |
| `Esc` | `Esc` | Clear selection / cancel inline text editor |
| `←` `→` `↑` `↓` | same | Nudge selection 1 px (world-space) |
| `Shift + ← → ↑ ↓` | same | Nudge selection 10 px |

Hold **Shift** while body-dragging a selection to bypass `snapToGrid`
and `smartGuidesEnabled` for that single drag.

### Add your own shortcuts

Wrap `FlueraCanvas` in a `Shortcuts + Actions` of your own — the
outer wrapper is evaluated first, so your bindings win for the
activators they claim and the built-in 15 still fire for everything
else. No package change required:

```dart
class _SaveIntent extends Intent { const _SaveIntent(); }

Shortcuts(
  shortcuts: <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.keyS, control: true):
        const _SaveIntent(),
  },
  child: Actions(
    actions: <Type, Action<Intent>>{
      _SaveIntent: CallbackAction<_SaveIntent>(onInvoke: (_) {
        _persist(canvasKey.currentState!.toBytes());
        return null;
      }),
    },
    child: FlueraCanvas(key: canvasKey, /* … */),
  ),
);
```

To override one of the built-ins, declare the same activator with
your own Intent + Action; the package's binding is shadowed.

## Export

`fluera_canvas` ships **PNG raster** export with four
infinite-canvas-aware bounds modes via `FlueraExportBounds`.

### What you see (legacy / WYSIWYG)

```dart
final image = await state.renderToImage(width: 1920, height: 1080);
final png = await image.toByteData(format: ui.ImageByteFormat.png);
```

### Everything (even off-screen)

The infinite-canvas killer feature: rasterise the union of every
visible node's `worldBounds`, regardless of where the camera is
pointing. Output dimensions auto-computed.

```dart
final image = await state.renderToImage(
  bounds: FlueraExportBounds.allContent,
  pixelRatio: 2.0,    // optional — HiDPI / print export
  padding: 24,        // optional — world-px margin around the bounds
);
```

### Selection only

```dart
final image = await state.renderToImage(
  bounds: FlueraExportBounds.selection,
  pixelRatio: 2.0,
);
// Returns a 1×1 sentinel image when nothing is selected.
```

### A specific region

```dart
final image = await state.renderToImage(
  bounds: FlueraExportBounds.custom,
  region: const Rect.fromLTWH(0, 0, 800, 600),  // world coords
);
```

### Transparent background

Pair any non-viewport mode with `transparent: true` to skip the
background fill + grid / dotted / lined pattern, producing a PNG with
a real alpha channel:

```dart
final image = await state.renderToImage(
  bounds: FlueraExportBounds.allContent,
  pixelRatio: 2.0,
  transparent: true,
);
```

**Guards**: `pixelRatio` is clamped to `[0.05, 32.0]`; output size is
rejected over 16 384 px per side (GPU max texture). Helpful sibling
getters: `state.contentBoundsWorld`, `state.selectionBoundsWorld`,
`state.viewportCenterWorld`, `state.viewportSize`.

## Platforms

`fluera_canvas` is **pure Dart**. No platform-channel code, no native
plugin, no shaders — runs anywhere Flutter runs.

| Platform | Status |
| --- | --- |
| Android | ✅ |
| iOS     | ✅ |
| macOS   | ✅ |
| Linux   | ✅ |
| Windows | ✅ |
| Web (CanvasKit / WASM) | ✅ |

Only runtime deps: `meta`, `vector_math`, `file_selector` (latter only
pulled when the image / sticker tools are wired). Zero native
footprint, no AndroidManifest tweaks, no Podfile changes.

### Per-platform notes

- **Keyboard shortcuts auto-adjust**: `Ctrl+…` on Windows / Linux /
  Web; `Cmd+…` on macOS / iOS. No consumer wiring required.
- **Trackpad pinch-zoom and two-finger pan** work out of the box on
  macOS / Windows / Linux / ChromeOS via `PointerScrollEvent` and
  `PointerPanZoom*` events.
- **Stylus / Apple Pencil / S Pen / Surface Pen / Wacom** are
  detected automatically via `PointerDeviceKind.stylus`; pressure +
  tilt are forwarded to the brush pipeline.
- **Web file save**: `state.toBytes()` returns a `Uint8List` —
  trigger a download via the snippet in **Save / load (web)** above.
- **Image import** (`FlueraImageTool.pickAndCommit`) uses
  `file_selector` and works on every platform Flutter supports,
  including web (renders a hidden `<input type="file">`).
- **Right-click context menu and clipboard copy/paste** are *not*
  bundled — they're consumer-side decisions. Wire them via
  `Listener.onPointerDown` (button == 2) and
  `Clipboard.setData` / `Clipboard.getData` if your UX needs them.

## Performance

Every optimisation is wired by default. The knobs below let power
users tune for their workload.

- **Stroke smoothing pipeline** — five-stage chain mirrored from the
  commercial `fluera_engine` fountain-pen path builder: One-Euro
  filter at point ingest (`minCutoff = 1.0`, `beta = 0.007`) →
  adaptive arc-length subdivision via Catmull-Rom interpolation on
  long gaps → two-pass EMA pre-smoothing (forward + backward,
  alpha 0.3, endpoints pinned) → predicted "ghost" tail anchor
  (velocity + half-acceleration extrapolation, never drawn) →
  Catmull-Rom → cubic bezier with tau = 1/6. Live and committed
  strokes share identical geometry — what the user sees while drawing
  is exactly what gets persisted.
- **Stroke simplification** — `simplifyEpsilon: 0` default (raw
  fidelity). Set `0.5` to opt into Douglas-Peucker compression
  (~40-60 % point reduction with sub-pixel visual difference).
- **LayerPictureCache** — pan / zoom on a 10 k-stroke static scene
  paints in O(1): one cached `ui.Picture` per layer, replayed.
- **DirtyRegionTracker** — mutating one stroke in the bottom-right
  doesn't repaint the full screen.
- **MemoryPressure observer** — drops picture caches on
  `didHaveMemoryPressure()` so the OS doesn't reap your app on mobile.
- **RTree-backed hit test** — O(log n + k) on visible-stroke queries.
- **Live stroke chunked PictureRecorder** — handwriting strokes with
  5 k+ points cache every 256-point range; the painter replays cached
  chunks and only re-tessellates the trailing tail.
- **Pixel eraser polish** — pressure-aware radius (linear ramp 40-100 %),
  velocity-aware sub-stamp growth (≤ 1.4× to absorb fast-drag gaps),
  micro-survivor cleanup (drops < 3 px arc-length fragments after a cut).

Numbers + benchmark recipes: **[doc/performance.md](doc/performance.md)**.

## Beyond the free tier

Vector export (SVG / PDF), native sub-frame live-stroke latency,
advanced brush engines, real-time collaboration, PDF annotation,
LaTeX OCR, SQLCipher storage and timeline playback are intentionally
**not** in this package. They're available as optional commercial
add-ons (`fluera_canvas_gpu`, `fluera_engine_pro`) that plug into the
same scene graph via the public `GpuStrokeBackend` hook — no fork, no
rewrite. See **[doc/commercial-add-ons.md](doc/commercial-add-ons.md)**
for the full list and pricing pointer. The free `fluera_canvas`
package on its own is production-ready.

## FAQ / Troubleshooting

**My persisted canvas appears empty when I reopen it.**
Use `FlueraCanvas(initialBytes: bytesFromDisk)` to restore — it
decodes inside `initState`, before the first paint. Calling
`loadFromBytes` on the State after the first frame can leave the
`RepaintBoundary` cached layer stale on Impeller-Vulkan / Adreno (the
second paint is silently coalesced and the canvas looks empty). Full
write-up: [doc/troubleshooting-impeller.md](doc/troubleshooting-impeller.md#symptom-2).

**My live stroke is invisible until I lift my finger on Android.**
Flutter pipeline coalescing quirk on Impeller-Vulkan / Adreno in
profile mode — mid-gesture `setState` / `markNeedsPaint` calls inside
pointer-event handlers get folded together until pen-up.
`FlueraCanvas` ships a vsync `Ticker` workaround that calls
`setState({})` from a frame callback while a draw / erase / shape
gesture is active — the live stroke and eraser preview circle track
the pointer in real time. Zero idle cost. Verified on
Adreno 660 / Impeller-Vulkan, profile mode.

**What's the difference between the stroke eraser and the pixel eraser?**
The stroke eraser (`CanvasTool.erase`) removes whole strokes whose
bounds touch the eraser circle. Vector-preserving — `undo` brings
them back intact. The pixel eraser (`CanvasTool.erasePixel`) splits
each touched stroke around the circle and keeps the surviving pieces;
on `undo` the original is restored. Use stroke-mode for sketching
apps where strokes are atoms; use pixel-mode for fine corrections in
note-taking apps.

**Can I add a custom shape tool (polygon, arrow, …)?**
The built-in `line` / `rectangle` / `ellipse` cover the common cases.
For anything else, build the polyline yourself and call
`canvasState.pushStroke(CanvasStroke(points: [...], ...))`. It rides
the same undo / redo / persistence / hit-test infrastructure for free.

**How do I open the color picker without the toolbar?**

```dart
final picked = await showFlueraColorPicker(
  context: context,
  initial: currentColor,
  enableAlpha: true, // optional, default true
);
if (picked != null) setState(() => currentColor = picked);
```

Returns `null` on cancel.

**Why is the API so big? I see hundreds of exported symbols.**
Most are scene-graph primitives, brush models, filters, and input
pipeline pieces inherited from the larger commercial `fluera_engine`.
They're free to use but not required by `FlueraCanvas` itself. Stick
to the symbols documented in this README and you'll have everything
you need for typical drawing-app use cases.

**How many strokes can it handle at 60 FPS?**
~5 000–10 000 strokes in a typical viewport on a mid-tier Android
(Adreno 660) thanks to per-stroke `ui.Picture` cache + spatial-index
viewport culling + cached committed `RepaintBoundary`. Beyond that
you'll start to see frame drops during camera animation; idle and
during drawing it's still fluid. See
[doc/performance.md](doc/performance.md) for the breakdown.

**How do I build a multi-canvas / autosave app?**
That pattern is consumer-side (we don't ship `path_provider` /
`sqflite` / encrypted storage as SDK deps). The example app's
"Multi-canvas + autosave" demo shows the full pattern in ~150 lines
using `path_provider` — copy and adapt.

**Does `fluera_canvas` work on Web?**
Yes. CanvasKit and WASM compilation both work out of the box — the
package has zero web-specific code, just Dart through Flutter's
standard web toolchain.

**Can I use `fluera_canvas` without the commercial GPU plugin?**
Yes — that's the default. The package is **pure Dart**: no platform
code, no MethodChannel, no shaders. The optional native GPU plugin
(`fluera_canvas_gpu`, separate package) plugs into the public
`GpuStrokeBackend` hook to buy sub-frame latency on the live path,
but is strictly optional.

More guides: [doc/architecture.md](doc/architecture.md),
[doc/performance.md](doc/performance.md),
[doc/troubleshooting-impeller.md](doc/troubleshooting-impeller.md).

## Contributing

Issues and PRs welcome at
[github.com/Lorencoshametaj/fluera_canvas](https://github.com/Lorencoshametaj/fluera_canvas).
Please open an issue before starting a large change so we can align on
API shape — we're converging on `1.0` and want to avoid breaking
churn.

## License

MIT — see [LICENSE](LICENSE).
