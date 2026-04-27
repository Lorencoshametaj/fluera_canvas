# Migrating from `fluera_canvas` 0.5.x → 0.10.0

## TL;DR

**Zero breaking changes.** Bump `fluera_canvas: ^0.5.0` to
`fluera_canvas: ^0.10.0` in your `pubspec.yaml`, run `flutter pub get`,
recompile. Existing apps keep working without code changes.

Every release in the 0.6 → 0.10.x line is **additive** — new opt-in
widget props, new `FlueraCanvasState` methods, new optional toolbar
flags. Defaults preserve 0.5.0 behaviour where it's user-visible
(except for the auto-on perf wins documented below, which have no
visual or API impact).

## What's new (additive)

### 0.6.0 — Selection + transform

- `CanvasTool.select` enters selection mode. Tap a node → bounding
  box + 8 handles. Drag body to translate, corners to scale, top
  rotate handle to rotate, mid-edge handles for 1-D scale.
- `state.selectionListenable` — observe the live selection set.
- `state.mirrorSelection(Axis)` — mirror horizontally / vertically
  around the selection centre.
- `state.deleteSelection()` — generic across stroke / image / text /
  group nodes (not just strokes).
- Toolbar opt-in: `showSelectionTools: true`.

### 0.7.x — Image annotations + persistence

- `FlueraImageTool.pickAndCommit(...)` — file picker + `ImageNode`
  insertion at viewport centre. Add `file_selector` is already a
  transitive dep of `fluera_canvas`.
- `state.addImageNode(ImageNode)` — programmatic insertion.
- **Image annotations are sticky**: stroking on top of an `ImageNode`
  reroutes the stroke onto `ImageNode.annotations` (in image-local
  coords) so it follows every move / rotate / scale / mirror as a
  rigid block. Strokes that cross the image boundary are split.
- **Selection frame follows rotation (OBB)** — rotated images show an
  oriented bounding box; handles ride the visual corners.
- **Hit-test is transform-aware** — moved nodes re-select at their new
  visual position.
- **Persistence**: `state.toBytes()` / `state.loadFromBytes(bytes)` /
  `FlueraCanvas(initialBytes: ...)` round-trip strokes + image bytes
  + image annotations through FCV0 v5.

### 0.8.0 — Live text + sticker panel

- `CanvasTool.text` opens an inline Material `TextField` overlay on
  tap. Type → commit on Done / blur. Esc cancels and rolls back a
  fresh empty node so you don't litter the layer.
- `state.addTextNode(TextNode)`, `state.updateTextElement(id,
  element)`, `state.findNode(id)`, `state.removeFreshTextNode(node)`.
- `FlueraStickerPanel` widget + `FlueraSticker.fromIcon(...)` factory
  for icon-based stickers (zero asset bundling).
- Toolbar opt-in: `showTextTool: true`, `showStickerPanel: true`.
- FCV0 v6 round-trips text nodes.

### 0.9.0 — Perf wire-up + design-tool UX

- **Auto-on perf** (no API change): `PostStrokeOptimizer`
  (`simplifyEpsilon: 0.5` default), `LayerPictureCache` (cached
  `ui.Picture` per layer, multi-layer composite path), live-stroke
  chunked `PictureRecorder`, `DirtyRegionTracker`, memory-pressure
  observer, RTree update on transform.
- **Lasso tool** — `CanvasTool.lasso`. Drag any closed path; every
  node whose centre falls inside is selected. Toolbar opt-in:
  `showLassoTool: true`.
- **Snap-to-grid + smart guides**:
  ```dart
  FlueraCanvas(snapToGrid: 16, smartGuidesEnabled: true);
  ```
  Magenta dashed guides render while the snap is locked. Hold Shift
  to bypass.
- **Group / ungroup** — `state.groupSelection()` /
  `state.ungroupSelection()`. Tap on a group member selects the
  group as a unit (Figma / Sketch convention).
- **Duplicate + Z-order** — `state.duplicateSelection({offset})`,
  `state.bringToFront(id)`, `state.sendToBack(id)`. Single undo
  per op.
- **Keyboard shortcuts overhaul** — Delete (selection-aware), Esc
  (clear selection), Ctrl/Cmd+A (select all), Ctrl/Cmd+D
  (duplicate), arrows (1-px nudge, Shift = 10 px), Ctrl/Cmd+Z/Y
  (undo / redo).
- **HiDPI / DPR-correct stroke widths** on selection outlines and
  eraser preview.
- **Default sticker catalogue** — `kFlueraDefaultStickers` ships 8
  Material-icon stickers via `FlueraIconStickerProvider`. Override
  with `stickers: const []` to opt out.

### 0.9.1 → 0.9.3 — Smoothing pipeline + eraser polish + PNG overhaul + edge-case hardening

Three patch releases stacked together. All additive.

**Smoothing pipeline rebuilt** (matches `fluera_engine`):
five-stage chain at `_paintStrokeSegments` — OneEuroFilter at
ingest → Catmull-Rom spline subdivision on long gaps → two-pass
EMA → predicted ghost tail anchor → Catmull-Rom → cubic bezier
(tau = 1/6). Live and committed strokes share identical geometry.
**Default `simplifyEpsilon` changed from `0.5` to `0`** — opt back
into compression with `FlueraCanvas(simplifyEpsilon: 0.5)`.

**Pixel eraser polish**:
- pressure-aware radius (40-100 % of nominal),
- velocity-aware sub-stamp growth (≤ 1.4×),
- micro-survivor cleanup (drops < 3 px arc-length post-cut fragments).

**PNG export overhauled — infinite-canvas-aware**:
- new `FlueraExportBounds` enum: `viewport` (legacy default),
  `allContent`, `selection`, `custom`,
- new params: `pixelRatio`, `padding`, `transparent`, `region`,
- legacy `renderToImage(width: w, height: h)` continues to work
  unchanged,
- **bug fix**: the legacy implementation iterated `_strokes` only
  and silently dropped image / text / shape / group nodes — the
  new polymorphic walker honours every node type. Apps that
  exported a sticker-heavy or text-heavy canvas to PNG were
  shipping incomplete bitmaps; this is fixed.

**TextNode is now selectable + transformable**: tap with the
`select` tool to drag / scale / rotate text. The painter now
honours `node.localTransform` (it didn't pre-0.9.2, so transforms
applied through the selection pipeline were invisible).

**New `FlueraCanvasState` getters**:
- `viewportSize` — canvas's current laid-out size,
- `viewportCenterWorld` — centre of the visible viewport in
  world coords,
- `contentBoundsWorld` — union of every visible node's world
  bounds,
- `selectionBoundsWorld` — union of selected nodes' world bounds.

**Edge-case hardening (0.9.3)**:
- FCV0 reader now bounds-checks every length field (`pointCount`,
  `layerCount`, image `blobLen`, layer `idLen` / `nameLen`) —
  malformed files throw `FormatException` instead of allocating
  gigabytes,
- `renderToImage` clamps `pixelRatio` to `[0.05, 32.0]` and
  rejects output dimensions over 16 384 px per side,
- single-point pen-down + pen-up now commits a visible "dot"
  stroke (was silently dropped),
- text editor `OverlayEntry` / `FocusNode` disposal is now
  microtask-deferred and try/catch-guarded so a stale `_active`
  surviving a hot-restart can't crash the next editor open.

### 0.10.0 — Zero-config drop-in widgets + lasso UX parity

Three new public widgets at increasing levels of "magic", all
sharing the [`FlueraSketchPreset`] enum:

```dart
const FlueraSketch();                            // canvas + toolbar
const FlueraSketchScaffold(title: 'Note');       // + AppBar (undo / export)
void main() => runApp(const FlueraSketchApp());  // + MaterialApp
```

Three preset shapes:
- `FlueraSketchPreset.notes` — Notability-style minimal,
- `FlueraSketchPreset.whiteboard` (default) — full kit with
  snap-to-grid + smart guides,
- `FlueraSketchPreset.signature` — single pen, no zoom-out, no
  text / shapes / stickers — drop-in replacement for the
  `signature` package.

`FlueraSketchScaffold` accepts optional `onAutoSave` /
`onAutoLoad` / `onExportPng` callbacks for any persistence backend
(`path_provider`, network, secure storage). Debounced autosave at 2 s
default. Export-PNG popup falls back to a clipboard data-URL if
`onExportPng` isn't wired.

Zero new dependencies — the package stays pure Dart. Persistence
remains consumer-side via callbacks.

Plus the new `FlueraExportBounds` enum used by the
infinite-canvas-aware `renderToImage(bounds: ...)` API (already
shipped in 0.9.3, now properly documented):
- `FlueraExportBounds.viewport` (legacy default — WYSIWYG),
- `FlueraExportBounds.allContent` — auto-bounds union of every
  visible node (perfect for "export the whole canvas" flows),
- `FlueraExportBounds.selection` — only what's selected,
- `FlueraExportBounds.custom` — explicit world-space `Rect`.

**Lasso UX parity with the Fluera flagship app**:
- A pen-down inside the bounding rect of an existing lasso
  selection now enters transform mode (drag = move, handle =
  scale / rotate) instead of starting a fresh lasso. Tap OUTSIDE
  the bbox keeps the previous behaviour — clear + new lasso.
- Lasso hit-test is stricter — dropped the
  `lassoBounds.overlaps(nodeBounds)` catch-all that caused
  over-selection on "C"-shaped lassos. Now matches Photoshop /
  Procreate / Figma containment semantics.

**Live stroke now honours the active layer's blend mode + opacity**:
toggling a `multiply` / `screen` / etc. layer no longer leaves the
in-flight preview as `srcOver` until pen-up.

## Persistence forward-incompat

Files written by 0.9.0 use **FCV0 v6**. They include nodeType bytes
for image (v4+), image annotations (v5+), and text (v6).

- **0.5.x reading 0.9.0 files**: ⚠️ NOT supported — the v6 magic
  byte triggers `FormatException("file version > supported")`. This
  is forward-incompat by design.
- **0.9.0 reading 0.5.x files** (FCV0 v3): ✅ supported. Strokes are
  preserved verbatim; layer state defaults are applied; no images /
  annotations / text exist (those nodeTypes don't appear in v3).

If your app autosaves and your users have older clients in the
field, plan a phased rollout: ship 0.9.0 widely first, then start
emitting v6 files only after a confidence window.

## Opt-in flags to enable for the full UX

The toolbar starts with the same defaults as 0.5.0, so adoption is
non-disruptive. To surface every new 0.6–0.9 feature:

```dart
FlueraCanvasToolbar(
  canvasKey: canvasKey,
  // … existing props …
  showSelectionTools: true,    // 0.6.0 — select tool segment
  showLassoTool: true,         // 0.9.0 — lasso tool segment
  showTextTool: true,          // 0.8.0 — text tool segment
  showImageTool: true,         // 0.7.0 — file-picker button
  showStickerPanel: true,      // 0.8.0 — sticker bottom-sheet button
  showLayers: true,            // 0.6.0 — layer panel button
);
```

And on the canvas:

```dart
FlueraCanvas(
  key: canvasKey,
  snapToGrid: 16,              // 0.9.0 — design-tool snap
  smartGuidesEnabled: true,    // 0.9.0 — magenta align guides
  // simplifyEpsilon: 0.5,     // default — leave alone in 99% of cases
);
```

## New `FlueraCanvasState` methods

All additive (no signature changes to existing methods):

| API | Since | Purpose |
|---|---|---|
| `addTextNode(node)` | 0.8.0 | Programmatic text insertion |
| `updateTextElement(id, element)` | 0.8.0 | Update text content |
| `addImageNode(node)` | 0.7.0 | Programmatic image insertion |
| `findNode(id)` | 0.8.0 | Lookup by `NodeId` |
| `removeFreshTextNode(node)` | 0.8.0 | Surgical history pop on cancel |
| `mirrorSelection(Axis)` | 0.6.0 | Mirror around selection centre |
| `deleteSelection()` | 0.6.0 | Generic delete (any node type) |
| `duplicateSelection({offset})` | 0.9.0 | Clone with translation |
| `groupSelection()` | 0.9.0 | Wrap selection into a `GroupNode` |
| `ungroupSelection()` | 0.9.0 | Unwrap, restore Z-order |
| `bringToFront(id)` | 0.9.0 | Top of parent layer's children |
| `sendToBack(id)` | 0.9.0 | Bottom of parent layer's children |

## Where to go next

- **Common recipes** — see the [README](../README.md#common-recipes).
- **Performance tuning** — see [doc/performance.md](performance.md).
- **Architecture deep-dive** — see [doc/architecture.md](architecture.md).
- **Impeller / Vulkan quirks** — see
  [doc/troubleshooting-impeller.md](troubleshooting-impeller.md).
