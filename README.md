# fluera_canvas

> **The document-grade infinite-canvas SDK for Flutter.**
>
> Built for **notes apps, whiteboards and design tools** — not signature pads.
> Multi-thousand strokes at 60 FPS, drop-in Material toolbar, persistence
> primitives, optional native GPU bridge (separate package).
>
> The only Flutter canvas SDK on pub.dev with infinite pan / zoom / **rotate**
> camera physics, RTree-backed viewport culling, and per-stroke `ui.Picture`
> cache. Pure Dart — no platform code in the free core. If you're building
> Notability / Goodnotes / Miro / Figma-class UX, start here.
>
> **Status:** `0.10.0` — additive release, zero breaking changes from
> 0.8.0. The API stabilizes at `1.0.0`. All minor versions before
> then are additive only.
> Marketing site: **[engine.fluera.dev](https://engine.fluera.dev/)**

## Positioning

| You're building… | Use |
|---|---|
| Notes app, whiteboard, sketching app, design tool, mind-map, diagram editor, infinite-canvas planner | **`fluera_canvas` ✅** |
| **Photo annotation, draw-on-image with strokes that follow when you move/rotate/scale the image** | **`fluera_canvas` ✅** (0.7.2 image annotations — see below) |
| Signature pad, e-signature flow | `signature` / `hand_signature` (more focused) |
| Custom stroke renderer, no widget | `perfect_freehand` (pure rendering primitive) |

Different tools for different jobs. `fluera_canvas` deliberately doesn't
chase the signature-pad niche — that's well served. What's missing on
pub.dev is the **document-grade** category: infinite surface, thousands
of strokes, persistence-friendly, image annotations that ride the image
as a rigid block, ready for a real note-taking or design product.
That's what this SDK is for.

## What you get

- `FlueraCanvas` — drop-in drawing widget. **Pen, stroke-mode eraser,
  pixel-mode eraser, line / rectangle / ellipse shape tools**, undo /
  redo history, pressure-aware input, infinite pan / zoom / rotation,
  PNG export. One `GlobalKey<FlueraCanvasState>` and you have a full
  canvas in your app. (Optional commercial `fluera_canvas_gpu` add-on
  drops in a native GPU live-stroke pipeline.)
- `FlueraCanvasToolbar` — drop-in Material toolbar that wires the most
  common controls (tool segmented control, color swatches, stroke-width
  slider, undo / redo / clear) into the canvas with zero glue code.
  Opt-in flags `showShapeTools`, `showPixelEraser`, `showColorPickerButton`
  expose the new 0.4.0 features. Auto-syncs to history state via
  `FlueraCanvasState.historyListenable`.
- `FlueraCanvasColorPickerDialog` + `showFlueraColorPicker(...)` —
  zero-dependency HSV / hex color picker for arbitrary color choices
  beyond the 6-swatch preset.
- `InfiniteCanvasController` — camera with pan, zoom, rotation, spring
  physics, momentum, multi-phase animation. Use it if you want to drive the
  view from outside (e.g. "reset view" button, programmatic fly-to).
- `InfiniteCanvasGestureDetector` — multi-touch, stylus, palm rejection,
  hover tracking. All policies are pluggable.
- Scene graph primitives (`StrokeNode`, `ShapeNode`, `TextNode`, `ImageNode`,
  `PathNode`, `GroupNode`, `LayerNode`) with a visitor pattern.
- Spatial index (`RTree`, `ViewportCuller`) used by default — combined
  with a per-stroke `ui.Picture` cache and a committed-strokes
  `RepaintBoundary`, the canvas scales to **5 k–10 k strokes at 60 FPS**
  on mid-tier Android devices (Adreno 660 / Impeller-Vulkan, profile mode).
- Input pipeline — One-Euro smoothing, dynamic pressure mapping, palm
  rejection, stylus prediction, 120 Hz raw processor.
- Drawing models — `ProDrawingPoint`, `PressureCurve`, `VelocityCurve`,
  `BrushPreset`, `ProBrushSettings`.
- A module system and telemetry hooks so consumers can wire their own
  storage, sync, AI, export or PDF pipelines.

## What's new in 0.9.0

- **Live stroke chunked PictureRecorder cache** — long handwriting
  strokes (5 k+ points) cache every 256-point range as a
  `ui.Picture`; the painter replays cached chunks and only
  re-tessellates the trailing tail. O(N) → O(N/256) per-frame
  work for the live stroke.
- **Multi-layer LayerPictureCache consumption** — both the fast
  single-layer path AND the multi-layer composite path now replay
  cached `ui.Picture`s instead of re-walking children. Every
  layer-state mutator (opacity / visible / locked / blend / mask)
  bumps the version.
- **Default sticker catalogue** — `kFlueraDefaultStickers` ships 8
  Material-icon stickers via the new `FlueraIconStickerProvider`
  (zero asset bundling). Override with `stickers: const []` to
  opt out.
- **Web-safe `dart:io`** — file-export service uses conditional
  import so web builds compile cleanly. Asset embedding falls
  back to path-only on web.
- **Backgrounds demo** — example gallery now showcases solid /
  grid / dotted / lined paper with live toggle.
- **LayerPictureCache active on the fast path** — single-layer
  scenes (the >99% notes-app case) now replay one cached
  `ui.Picture` per paint instead of walking every stroke.
  Pan / zoom over a static 10 k-stroke scene drops from O(N)
  per paint to O(1).
- **Web / WASM verified** — `flutter build web` compiles cleanly,
  WASM dry-run succeeds, and `test/web_compat_test.dart` exercises
  every public API surface a web consumer would touch.
- **Group / ungroup** — `state.groupSelection()` /
  `state.ungroupSelection()`. Selection scope follows the
  Figma / Sketch convention: tap on a member of a group selects
  the group as a single unit; children become addressable again
  only after ungrouping. Single undo per op.
- **Snap-to-grid + smart guides** — set
  `FlueraCanvas(snapToGrid: 16, smartGuidesEnabled: true)` and the
  body-drag move snaps the dragged selection's 9 anchors (corners +
  edges + centre) to grid lines AND to alignments with other
  visible nodes. Magenta dashed guides render while the snap is
  locked. Hold Shift to bypass.

- **Auto-simplified strokes** — `PostStrokeOptimizer` is now wired
  into the commit path. `simplifyEpsilon` (default `0.5`) trims
  40-60 % of redundant points without visible difference, so
  spatial-index size, paint cost, and persisted-file size all drop
  proportionally. Pressures stay aligned (kept-indices, not
  re-sampled). Set `0` to keep the raw point list.
- **Lasso tool** — free-form selection via `CanvasTool.lasso`.
  Drag any closed path; everything whose centre falls inside is
  selected. Concave shapes honoured (vs the marquee rectangle).
  Toolbar opt-in: `showLassoTool: true`.
- **Duplicate / Z-order APIs** — `state.duplicateSelection()`,
  `state.bringToFront(id)`, `state.sendToBack(id)`. Single undo
  per op.
- **Keyboard shortcuts overhaul** — Delete becomes selection-aware
  (drops selection if non-empty, else clears canvas). New: Esc
  (clear selection), Ctrl/Cmd+A (select all), Ctrl/Cmd+D
  (duplicate), arrows (nudge 1 px, Shift = 10 px).
- **Memory-pressure observer** — `WidgetsBindingObserver` wired:
  drops layer / stroke caches when the OS reports low memory so
  the host app stays alive instead of being reaped.
- **Dirty-region + layer-cache infrastructure** — tracker +
  per-layer content version + `LayerPictureCache` instance all
  live on the state. Painter consumption lands in 0.9.1 once the
  multi-layer composite path is refactored to clip safely.
- **Benchmark suite** — `test/benchmarks/perf_baseline_test.dart`
  micro-benches 5 k stroke insert, 10 k hit-test on 5 k scene,
  5 k-point stroke push. Numbers stamped to CI for regression
  tracking.
- **Pana 160/160**, **274/274 tests**, **0 analyze issues**.

## What's new in 0.8.0

- **Live text tool** — tap empty canvas with `CanvasTool.text` to drop
  a fresh `TextNode` and open a Material `TextField` overlay
  caret-positioned over it; tap an existing text node to re-enter
  editing. The overlay rides the camera (pan / zoom) while the user
  types. Commit on Done / blur; **Esc cancels** on desktop. Empty-text
  commit on a fresh node rolls back the addition via a surgical history
  pop (no risk of nuking unrelated undo state).
- **Sticker panel** — `FlueraStickerPanel` widget that browses a
  `List<FlueraSticker>` thumbnail catalogue and commits the chosen
  sticker as an `ImageNode` centered on the viewport. Same sticker
  dropped twice shares the cached `ui.Image` (one decode per process).
  Wired via `FlueraCanvasToolbar.showStickerPanel: true`.
- **Canvas-level text APIs** — `state.addTextNode(node)`,
  `state.updateTextElement(id, element)`, `state.findNode(id)`,
  `state.removeFreshTextNode(node)`. Single `_UpdateTextOp` per
  editing session for clean undo.
- **FCV0 v6 binary persistence** — `nodeType=1` (text) round-trips
  through `toBytes` / `loadFromBytes`. Backward-read v1 → v5
  unchanged; new writers always emit v6.
- **Painter dispatch in chronological order** — strokes / images /
  text are walked in `layer.children` insertion order on both the
  fast and slow path, so the last node added always wins Z-order.
- **Pana 160/160**, **252/252 tests**, **0 analyze issues**.

## What's new in 0.7.2

- **Image annotations (sticky + split)** — write directly on top of an
  imported image. Strokes that fall inside the image bounds are
  rerouted onto `ImageNode.annotations` (in image-local coords) and
  ride every move / rotate / scale / mirror as a rigid block. Strokes
  that cross the boundary are split: inside parts attach to the image,
  outside parts stay on the active layer. Stroke-mode AND pixel-mode
  eraser cut both kinds of strokes through the same image-local
  projection. Single-undo per pen-up.
- **Selection frame follows rotation (OBB)** — a selected rotated
  image now shows an oriented bounding box; corner/edge handles ride
  the visual corners and scale along the image's own axes.
- **FCV0 v5 binary persistence** — image annotations round-trip
  through `toBytes` / `loadFromBytes`. Backward-read v1 → v4. Image
  asset bytes now embedded (v4+) so close-and-reopen no longer drops
  the bitmap.
- **Hit-test transform-aware** — strokes moved with the selection
  tool re-select correctly at their new visual position; the spatial
  index falls back to a `worldBounds` pass for transformed nodes.
- **Pana 160 / 160**, 249 / 249 tests, 0 analyze issues.

## Install

```yaml
dependencies:
  fluera_canvas: ^0.10.0
```

Upgrading from 0.5.x? See **[doc/migration-0.5-to-0.10.0.md](doc/migration-0.5-to-0.10.0.md)**
— zero breaking changes, plus a checklist of opt-in flags to surface
the new selection / lasso / text / sticker / snap-to-grid features.

## Zero-config drop-in (0.10.0+)

The fastest way to get a working drawing app — pick the level of
"magic" you want.

### Whole app, one line

```dart
import 'package:flutter/material.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

void main() => runApp(const FlueraSketchApp());
```

That's it. You get a Material 3 `MaterialApp` + AppBar with undo /
redo / clear / export-PNG popup, the full toolbar with every opt-in
flag wired (pen / shapes / pixel-eraser / lasso / select / text /
sticker / image / layers / transform / color picker), and a dotted
background. Three preset shapes via `FlueraSketchPreset`:

```dart
const FlueraSketchApp(preset: FlueraSketchPreset.notes);      // Notability-minimal
const FlueraSketchApp(preset: FlueraSketchPreset.whiteboard); // Default — full kit
const FlueraSketchApp(preset: FlueraSketchPreset.signature);  // signature-pad style
```

### Embed a sketch page in an existing app

```dart
MaterialPageRoute(builder: (_) => FlueraSketchScaffold(
  title: 'My note',
  preset: FlueraSketchPreset.notes,
  // Optional persistence: wire any backend (path_provider, network, …).
  onAutoSave: (bytes) => File('$dir/note.fcv').writeAsBytes(bytes),
  onAutoLoad: () async => File('$dir/note.fcv').readAsBytes(),
));
```

The scaffold debounces autosave at 2 s by default
(`autoSaveDebounce:`). The export-PNG popup falls back to copying a
data-URL to the clipboard if you don't pass `onExportPng`.

### Just the canvas + toolbar (no Scaffold)

```dart
Scaffold(
  appBar: AppBar(title: Text('My drawing')),
  body: const FlueraSketch(),  // canvas + toolbar self-contained
);
```

`FlueraSketch` owns the `tool`, `color` and `strokeWidth` state
internally — no `setState` plumbing needed. Pass
`canvasKey: GlobalKey<FlueraCanvasState>()` if you want to drive
`save` / `load` / `undo` from outside.

The three widgets stack: `FlueraSketchApp` → wraps →
`FlueraSketchScaffold` → wraps → `FlueraSketch`. Each is usable
standalone. When you outgrow the presets, drop down to
[`FlueraCanvas`](#hello-canvas) directly — same scene-graph, every
API still available.

## Hello canvas

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

Advanced camera control: pass a `controller: InfiniteCanvasController()`
if you want to drive pan / zoom / rotation from outside.

## Tools

`FlueraCanvas` ships **6 input tools** out of the box, switched via the
`tool:` parameter:

| Tool | What it does |
|---|---|
| `CanvasTool.draw` | Free-form pressure-aware stroke. |
| `CanvasTool.erase` | Stroke-mode eraser — removes whole strokes the eraser circle touches. Vector-preserving (undo brings them back intact). |
| `CanvasTool.erasePixel` | Pixel-mode eraser — splits intersected strokes around the eraser circle and keeps the surviving pieces. |
| `CanvasTool.line` | Drag from A to B for a straight line. |
| `CanvasTool.rectangle` | Drag corner-to-corner for a rectangle outline. |
| `CanvasTool.ellipse` | Drag for an ellipse outline (32-segment polyline). |

Shape tools commit as ordinary `CanvasStroke` instances, so they
participate in undo / redo, persistence (`toBytes` / `loadFromBytes`),
spatial-index hit-test, and the per-stroke `ui.Picture` cache for free.

`CanvasTool.select`, `CanvasTool.lasso`, `CanvasTool.text`, and the
sticker panel are wired through the same `tool:` parameter (or via
`FlueraCanvasToolbar` opt-in flags). See **Common recipes** below.

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

// Programmatic delete of the current selection (e.g. on Delete key —
// the canvas wires this up by default, but you can also call it):
canvasKey.currentState?.deleteSelection();
```

Selection is observable: `canvasKey.currentState!.selectionListenable`.
See `state.duplicateSelection()`, `state.bringToFront(id)`,
`state.sendToBack(id)`, `state.groupSelection()`,
`state.ungroupSelection()`.

### Lasso free-form selection

```dart
FlueraCanvas(key: canvasKey, tool: CanvasTool.lasso);
// User drags any closed path; every node whose bounds the lasso
// encloses or crosses is added to the selection. Concave shapes
// work (vs the marquee rect). Live magenta dashed preview while
// the user is dragging.
// Toolbar opt-in: FlueraCanvasToolbar(showLassoTool: true, ...).
```

Use **lasso** when the strokes you want to select are scattered or
arranged non-rectangularly (e.g. all strokes around an imported
image, an artistic cluster, hand-drawn diagrams). Use **`CanvasTool.select`**
(marquee) for grid layouts and structured content where an
axis-aligned rectangle does the job faster.

### Snap-to-grid + smart guides

```dart
FlueraCanvas(
  key: canvasKey,
  tool: CanvasTool.select,
  snapToGrid: 8,                   // 0 disables; 8/16/24 are typical
  smartGuidesEnabled: true,        // align with neighbours on drag
  smartGuidesTolerancePx: 6,       // screen-space tolerance
);
// Hold Shift while dragging to bypass both snap and guides.
```

### Live text tool

```dart
FlueraCanvas(key: canvasKey, tool: CanvasTool.text);
// Tap empty canvas: a Material TextField caret opens inline. Type;
// commit on Done / blur. Esc cancels (and rolls back a fresh empty
// node so you don't litter the layer with phantoms).
// Tap an existing TextNode to re-enter edit mode.
//
// Toolbar opt-in: FlueraCanvasToolbar(showTextTool: true, ...).
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
// Defaults: kFlueraDefaultStickers ships 8 Material-icon stickers
// via FlueraIconStickerProvider — zero asset bundling.

// Custom catalogue:
final myStickers = <FlueraSticker>[
  FlueraSticker.fromIcon(id: 'rocket', label: 'Rocket', icon: Icons.rocket_launch),
  FlueraSticker.fromIcon(id: 'bolt',   label: 'Bolt',   icon: Icons.bolt),
];
```

### Image annotations (sticky strokes)

```dart
// 1. Import an image (toolbar opt-in shows a button; or call directly):
await FlueraImageTool.pickAndCommit(context: context, state: canvasKey.currentState!);

// 2. Switch to a draw tool and stroke on top of the image. Strokes
//    that fall inside the image bounds are auto-attached as image
//    annotations (in image-local coords) and ride every move /
//    rotate / scale / mirror as a rigid block. Strokes that cross the
//    boundary are split: inside parts attach, outside parts stay free.
```

### Save / load (mobile + desktop)

```dart
// Persist to disk:
final bytes = canvasKey.currentState!.toBytes();
await File('$dir/scene.fcv').writeAsBytes(bytes);

// Restore inside initState (the safest path — see FAQ #2):
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
// On web only — keep behind `if (kIsWeb)` to keep mobile/desktop builds clean:
import 'package:web/web.dart' as web;
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

// Usage:
final bytes = canvasKey.currentState!.toBytes();
if (kIsWeb) {
  downloadFcv(bytes, 'scene.fcv');
} else {
  await File('$dir/scene.fcv').writeAsBytes(bytes);
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
  final bytes = await file.readAsBytes();
  canvasKey.currentState?.loadFromBytes(bytes);
}
```

This snippet works on every platform — no `kIsWeb` branch needed.

## Keyboard shortcuts

`FlueraCanvas` wraps its widget tree in `Shortcuts + Actions` and ships
**15 default keybindings**. The Ctrl/Cmd modifier auto-resolves per
platform (Cmd on macOS / iOS, Ctrl elsewhere) — you don't have to
branch on `Platform` in your app.

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
and `smartGuidesEnabled` for that single drag — useful for nudging a
node off-grid without reconfiguring the widget.

### Add your own shortcuts

Wrap `FlueraCanvas` in a `Shortcuts + Actions` of your own — the
outer wrapper is evaluated first, so your bindings win for the
activators they claim and the built-in 15 still fire for everything
else. No package change required:

```dart
class _SaveIntent extends Intent { const _SaveIntent(); }
class _GroupIntent extends Intent { const _GroupIntent(); }

Shortcuts(
  shortcuts: <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.keyS, control: true):
        const _SaveIntent(),
    const SingleActivator(LogicalKeyboardKey.keyG, control: true):
        const _GroupIntent(),
  },
  child: Actions(
    actions: <Type, Action<Intent>>{
      _SaveIntent: CallbackAction<_SaveIntent>(onInvoke: (_) {
        _persist(canvasKey.currentState!.toBytes());
        return null;
      }),
      _GroupIntent: CallbackAction<_GroupIntent>(onInvoke: (_) {
        canvasKey.currentState?.groupSelection();
        return null;
      }),
    },
    child: FlueraCanvas(key: canvasKey, /* … */),
  ),
);
```

Override one of the built-ins the same way — declare the same
activator (e.g. `Ctrl+D`) in your wrapper with your own Intent +
Action and the package's duplicate binding is shadowed.

## Performance

`fluera_canvas` ships every perf optimization wired by default — no
configuration needed for typical apps. The knobs below let power users
tune for their workload.

- **Stroke smoothing pipeline (0.9.3)** — five-stage chain mirrored
  from the commercial `fluera_engine` fountain-pen path builder:
  OneEuroFilter at point ingest (`minCutoff = 1.0`, `beta = 0.007`)
  → adaptive arc-length subdivision via Catmull-Rom interpolation
  on long gaps → two-pass EMA pre-smoothing (forward + backward,
  alpha 0.3, endpoints pinned) → predicted "ghost" tail anchor
  (velocity + half-acceleration extrapolation, never drawn) →
  Catmull-Rom → cubic bezier with tau = 1/6. Live and committed
  strokes share identical geometry, so what the user sees while
  drawing is exactly what gets persisted.
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
- **Pixel eraser polish (0.9.3)** — pressure-aware radius (linear
  ramp 40-100 %), velocity-aware sub-stamp growth (≤ 1.4× to absorb
  fast-drag gaps), micro-survivor cleanup (drops < 3 px arc-length
  fragments after a cut).

Numbers + benchmark recipes: **[doc/performance.md](doc/performance.md)**.

## Drop-in toolbar

Don't want to wire your own pen / eraser / color / undo UI?
`FlueraCanvasToolbar` does it for you:

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
    FlueraCanvasToolbar(
      canvasKey: _canvasKey,
      tool: _tool,
      onToolChanged: (t) => setState(() => _tool = t),
      color: _color,
      onColorChanged: (c) => setState(() => _color = c),
      strokeWidth: _width,
      onStrokeWidthChanged: (w) => setState(() => _width = w),
      // Optional 0.4.0 opt-in flags:
      showShapeTools: true,        // adds Line / Rect / Oval segments
      showPixelEraser: true,       // adds Pixel eraser segment
      showColorPickerButton: true, // adds a "+ more colors" gradient button
    ),
  ]);
}
```

The toolbar subscribes to `FlueraCanvasState.historyListenable` so
`Undo` / `Redo` automatically reflect the live history state — no
`onStrokeCommitted` plumbing required. Use `palette: [...]` for a
custom color set, or pass `showUndo: false` etc. to suppress
individual buttons. Want a different layout (Cupertino, sidebar,
floating)? Skip the toolbar and drive `tool` / `strokeColor` /
`strokeWidth` from your own UI — `FlueraCanvas` is intentionally
headless.

A runnable demo lives in [`example/`](example/). Full quickstart with
persistence and camera animation: **[engine.fluera.dev/quickstart](https://engine.fluera.dev/quickstart)**.

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

Only runtime deps: `meta` and `vector_math`. Zero native footprint, no
AndroidManifest tweaks, no Podfile changes.

### Per-platform notes

- **Keyboard shortcuts auto-adjust**: `Ctrl+…` on Windows / Linux /
  Web; `Cmd+…` on macOS / iOS. No consumer wiring required. Full
  table in **Keyboard shortcuts** below.
- **Trackpad pinch-zoom and two-finger pan** work out of the box on
  macOS / Windows / Linux / ChromeOS via `PointerScrollEvent` and
  `PointerPanZoom*` events.
- **Stylus / Apple Pencil / S Pen / Surface Pen / Wacom** are
  detected automatically via `PointerDeviceKind.stylus`; pressure +
  tilt are forwarded to the brush pipeline.
- **Web file save**: `state.toBytes()` returns a `Uint8List` —
  trigger a download via the snippet in the **Save / load (web)**
  recipe above. Loading via `file_selector.openFile()` is identical
  on every platform.
- **Image import** (`FlueraImageTool.pickAndCommit`) uses
  `file_selector` and works on every platform Flutter supports,
  including web (renders a hidden `<input type="file">`).
- **Right-click context menu and clipboard copy/paste** are *not*
  bundled — they're consumer-side decisions. Wire them via
  `Listener.onPointerDown` (button == 2) and
  `Clipboard.setData` / `Clipboard.getData` if your UX needs them.

## Optional native GPU live-stroke (commercial add-on)

The free `fluera_canvas` widget renders the live stroke through a Dart
`CustomPainter`. Latency is ~12–16 ms, which is fine for note-taking and
whiteboards on a flagship device.

If you need sub-frame latency on a wide range of hardware (Procreate /
Goodnotes-class UX), the commercial **`fluera_canvas_gpu`** package
plugs a native renderer into the same widget tree via the public
`GpuStrokeBackend` interface that ships in this core. Backends:
Android Vulkan, iOS / macOS Metal, Linux OpenGL, Windows Direct3D 11,
Web WebGPU. Wire it once at `main()`:

```dart
import 'package:fluera_canvas_gpu/fluera_canvas_gpu.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlueraCanvasGpu.setBackend(FlueraCanvasGpuBackend());
  runApp(const MyApp());
}
```

With no backend registered the canvas falls back to the Dart painter
silently — your app keeps working everywhere `fluera_canvas` works.
See [engine.fluera.dev/pricing](https://engine.fluera.dev/pricing) for
the licensing tiers.

## Export

`fluera_canvas` free ships **PNG raster** export with four
infinite-canvas-aware bounds modes via `FlueraExportBounds`.

### What you see (legacy / WYSIWYG)

```dart
final image = await state.renderToImage(width: 1920, height: 1080);
final png = await image.toByteData(format: ui.ImageByteFormat.png);
```

### Everything (even off-screen)

The infinite-canvas killer feature: rasterize the union of every
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

**Guards**: `pixelRatio` is clamped to `[0.05, 32.0]`; output size
is rejected over 16 384 px per side (GPU max texture). Helpful
sibling getters: `state.contentBoundsWorld`, `state.selectionBoundsWorld`,
`state.viewportCenterWorld`, `state.viewportSize`.

**Vector formats** — SVG 1.1, PDF 1.5 with multi-page picker, OCG
toggleable layers, blend modes via `/ExtGState /BM`, watermarks,
PDF/A-1b conformance, drop-in `FlueraPdfExportButton` widget — ship
in the commercial **`fluera_canvas_gpu`** package. They serve the
design-tool / pre-print / plotter customer segments and live behind
the Indie €399 / Team €1499 license tier. See
[engine.fluera.dev/pricing](https://engine.fluera.dev/pricing).

## What's *not* in here

- Advanced brush engines (watercolor, charcoal, fountain pen, oil, neon,
  ink wash, marker)
- Real-time collaboration (CRDT, vector clocks)
- PDF annotation editing
- LaTeX OCR and AI-assisted tools
- SQLCipher encrypted storage
- Timeline branching and time-travel playback

All of the above ship in the commercial `fluera_engine_pro` package. See
[engine.fluera.dev/pricing](https://engine.fluera.dev/pricing) for details.

## FAQ / Troubleshooting

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

**My persisted canvas appears empty when I reopen it.**
Use `FlueraCanvas(initialBytes: bytesFromDisk)` to restore — it decodes
the bytes inside `initState`, before the first paint. Calling
`loadFromBytes` on the State after the first frame can leave the
`RepaintBoundary` cached layer stale on Impeller-Vulkan / Adreno (the
second paint is silently coalesced and the canvas looks empty).
Full write-up: [doc/troubleshooting-impeller.md](doc/troubleshooting-impeller.md#symptom-2).

**My live stroke is invisible until I lift my finger on Android.**
This is a Flutter pipeline coalescing quirk on Impeller-Vulkan / Adreno
in profile mode (mid-gesture `setState` / `markNeedsPaint` calls inside
pointer-event handlers get folded together until pen-up). `FlueraCanvas`
ships a vsync `Ticker` workaround that calls `setState({})` from a
frame callback while a draw / erase / shape gesture is active — the
live stroke and eraser preview circle track the pointer in real time.
Zero idle cost. Verified on Xiaomi 2107113SG (Adreno 660).

**My stroke has visible "humps" or "pinches" when I zoom in.**
Update to 0.3.0+. The renderer now uses a single `drawPath` per stroke
with quadratic-bezier smoothing and average pressure — silhouette is
C¹-continuous regardless of zoom. The 0.2.x pressure-banding renderer
is gone.

**Can I use `fluera_canvas` without the commercial GPU plugin?**
Yes — that's the default. The free package is **pure Dart**: no
platform code ships in it, no MethodChannel, no shaders. The pure-Dart
pipeline handles the live stroke and committed strokes on every
platform Flutter supports. The native GPU plugin (`fluera_canvas_gpu`,
separate commercial package) plugs into the public `GpuStrokeBackend`
hook to buy sub-frame latency on the live path, but is strictly
optional.

**Why is the API so big? I see hundreds of exported symbols.**
Most of them are scene-graph primitives, brush models, filters, and
input pipeline pieces inherited from the larger commercial
`fluera_engine`. They're free to use but not required by `FlueraCanvas`
itself. Stick to the symbols documented in the README and you'll have
everything you need for typical drawing-app use cases.

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
free package has zero web-specific code, just Dart through Flutter's
standard web toolchain. The commercial `fluera_canvas_gpu` adds a
WebGPU live-stroke path for browsers that ship `navigator.gpu`
(Chrome 113+, Edge 113+, Safari 18+).

**My CI logs an `OnBackInvokedCallback is not enabled` warning.**
That's a generic Android system warning unrelated to `fluera_canvas`.
Add `android:enableOnBackInvokedCallback="true"` to your
`<application>` tag in `AndroidManifest.xml`.

More guides: [doc/architecture.md](doc/architecture.md),
[doc/performance.md](doc/performance.md),
[doc/troubleshooting-impeller.md](doc/troubleshooting-impeller.md),
[doc/migration-0.2-to-0.3.md](doc/migration-0.2-to-0.3.md),
[doc/migration-0.3-to-0.4.md](doc/migration-0.3-to-0.4.md).

## Contributing

Issues and PRs welcome at
[github.com/Lorencoshametaj/fluera_canvas](https://github.com/Lorencoshametaj/fluera_canvas).
Please open an issue before starting a large change so we can align on API
shape — we're converging on `1.0` and want to avoid breaking churn.

## License

MIT — see [LICENSE](LICENSE).
