# Architecture

How `fluera_canvas` is organised internally and why. This is for
contributors and consumers debugging non-trivial issues — most users
won't need any of it.

## High-level

```
                ┌─────────────────────────────┐
   user ─────►  │ InfiniteCanvasGestureDetector│
                │  (hit-test, tool routing)    │
                └────────────┬─────────────────┘
                             │
                             ▼
                ┌─────────────────────────────┐
                │       FlueraCanvasState      │
                │  • _strokes (committed)      │
                │  • _spatialIndex (RTree)     │
                │  • _liveStroke notifier      │
                │  • _commitTick notifier      │
                │  • undo/redo history         │
                └────────────┬─────────────────┘
                             │
        ┌────────────────────┼────────────────────┐
        ▼                    ▼                    ▼
┌──────────────────┐ ┌──────────────────┐ ┌─────────────────┐
│ _CommittedPainter │ │  _LivePainter   │ │ NativeStroke    │
│ • Picture cache  │ │  • Path-smooth  │ │ Overlay (opt.)  │
│ • RepaintBoundary │ │  • super(repaint)│ │ • Vulkan/Metal/ │
│ • super(repaint:) │ │                 │ │   GL/D3D11/WebGPU│
└──────────────────┘ └──────────────────┘ └─────────────────┘
```

## Render layers

There are two stable painters in the widget tree, plus an optional
native overlay.

### `_CommittedStrokesPainter`

- One stable instance per `FlueraCanvasState`, created in `initState`,
  reused for the lifetime of the widget.
- `super(repaint: Listenable.merge([_commitTick, _controller]))` — the
  painter repaints when committed strokes change OR when the camera
  moves.
- Wrapped in a `RepaintBoundary` so its compositing layer is cached
  on the GPU. While the live stroke is animating, the rasterizer
  blits the cached committed layer instead of re-executing every
  `drawPicture` per frame.
- Per-stroke `ui.Picture` cache: each `CanvasStroke` lazily builds a
  picture of its segments, then `paint()` is one `drawPicture` per
  stroke. Combined with the spatial-index viewport cull, this scales
  to 5k–10k strokes at 60 FPS on mid-tier Android.

### `_LiveStrokePainter`

- One stable instance per State, also created in `initState`.
- `super(repaint: Listenable.merge([_liveStroke, _controller]))`.
- Renders the in-progress stroke with a single `Path` per stroke,
  smoothed with quadratic-bezier curves through midpoints. Stroke
  width is the average pressure across the path — sacrifices
  per-segment pressure variation but eliminates the "pinch" artefacts
  you'd otherwise see at high zoom.

### `NativeStrokeOverlay` (optional, conditional)

- Only mounted when `enableNativeLiveStroke: true` (default) AND the
  current platform has a native backend AND `FlueraCanvasGpu.backend`
  is non-null (i.e. the consumer added the commercial
  `fluera_canvas_gpu` package and registered its backend at boot).
- Hosts a Texture widget driven by the platform's GPU pipeline.
- When all three conditions aren't met, this overlay never mounts —
  the Dart `_LiveStrokePainter` handles the live stroke and the user
  still sees ink.

## Tools

`CanvasTool` enum dispatches gesture handling inside the State:

| Tool | Gesture flow |
|---|---|
| `draw` | Free-form: `_livePoints` accumulates pointer samples; pen-up commits a `CanvasStroke`. |
| `erase` | Stroke-mode: `_eraseAt(world)` queries the spatial index for strokes intersecting the eraser circle, removes whole hits, accumulates them in `_erasedThisGesture`. Pen-up pushes one `_EraseOp` for the entire swipe. |
| `erasePixel` | Pixel-mode: `_eraseAtPixel(world)` calls `CanvasStroke.splitAroundCircle` for each touched stroke, replaces the original with the survivors at the same Z-order, accumulates in `_pixelEraseOriginals` / `_pixelEraseReplacements`. Pen-up pushes a `_PixelEraseOp`. |
| `line` / `rectangle` / `ellipse` | Shape: `_shapeAnchor` captures pen-down position; on every pen-move `_buildShapePoints(tool, anchor, current)` recomputes the live polyline (2 / 5 / 33 points respectively); pen-up commits as a `CanvasStroke` with uniform pressure 1.0. |

Shape strokes are NOT a separate model — they're regular
`CanvasStroke`s with pre-built point lists, so they participate in
undo / redo, persistence, hit-test, spatial-index, eraser (both
modes), and the per-stroke `ui.Picture` cache for free.

`CanvasStroke.splitAroundCircle(stroke, center, r²)` is exposed
publicly so consumers can build custom pixel-mode UX (lasso-to-cut,
polygon-erase, magnetic-erase) without re-implementing the splitting
geometry. Pure function — no canvas state, no widgets, easy to
unit-test.

## State flow

### Pen-down → pen-move → pen-up (draw tool)

```
gesture detector → _onDrawStart
  ├─ _liveStroke.beginStroke(color, width)
  ├─ _livePoints = [pt0]
  ├─ _liveStroke.setStroke(_livePoints, _livePressures)
  │    └─ notifyListeners → _LiveStrokePainter.markNeedsPaint
  ├─ _liveStrokeTicker.start()  ← Impeller-Vulkan workaround
  └─ (optional) _nativeOverlay.beginStroke / appendPoint

gesture detector → _onDrawUpdate (× many)
  ├─ _livePoints.add(pt)        ← in-place mutation
  ├─ _liveStroke.forceRepaint()
  └─ (optional) _nativeOverlay.appendPoint

gesture detector → _onDrawEnd
  ├─ _liveStrokeTicker.stop()
  ├─ _strokes.add(stroke)        ← commit to scene
  ├─ _spatialIndex.insert(stroke)
  ├─ _commitTick.notify()        ← committed painter repaints
  ├─ _liveStroke.clear()         ← live painter short-circuits
  ├─ _history?.push(_AddOp(...))
  └─ widget.onStrokeCommitted?.call(stroke)
```

### Eraser swipe

Same shape, but `_onDrawStart`/`Update` go through the eraser path:
the spatial index is queried for strokes whose bounds overlap the
eraser circle, hits are removed from `_strokes` + `_spatialIndex`
and accumulated in `_erasedThisGesture`. On pen-up the entire swipe
becomes a single `_EraseOp` in the undo history (one undo restores
all erased strokes).

The eraser preview circle tracks the pointer in real time thanks to
the same `_liveStrokeTicker` workaround.

### Persistence

- `toBytes` / `loadFromBytes` — compact little-endian binary
  (`FCV0` magic, version 1). ~14 bytes per point.
- `toJson` / `loadFromJson` — diff-friendly JSON, ~10× larger.
- `FlueraCanvas(initialBytes:)` — bytes are decoded inside
  `initState`, BEFORE the first build/paint. The first frame already
  shows the persisted strokes. This is the only safe way to restore
  on Impeller-Vulkan; calling `loadFromBytes` after the first frame
  can leave the `RepaintBoundary` cached layer stale.

## Spatial index

`RTree<CanvasStroke>` (in `lib/src/rendering/optimization/spatial_index.dart`):

- O(log n) hit-test for the eraser tool.
- O(log n + k) viewport query for the committed painter cull —
  `paint()` only iterates strokes whose bounds intersect the
  viewport (with a small margin).
- Lazy deletion (tombstones) + auto-compaction. `remove()` is O(1);
  the tree is rebuilt in batch when tombstones exceed 25 % of live
  count or mutations exceed 30 %.

## Notifier graph

Three custom notifiers drive the render pipeline:

| Notifier | Type | Fires on | Listened by |
|---|---|---|---|
| `_liveStroke` | `ChangeNotifier` (mutable point lists + color/width) | every `forceRepaint()` after a pointer move | `_LiveStrokePainter` via `super(repaint:)` |
| `_commitTick` | `ChangeNotifier` (tick-only, no payload) | every `_strokes` mutation | `_CommittedStrokesPainter` via `super(repaint:)` |
| `_controller` | `InfiniteCanvasController` (`ChangeNotifier`) | camera change | both painters via `super(repaint:)` |

The State exposes `_commitTick` read-only as
`FlueraCanvasState.historyListenable` so a toolbar UI can rebuild
its buttons without wiring `onStrokeCommitted` + `setState`.

## Workaround for Impeller-Vulkan profile mode

Verified empirically: on Android profile builds running Impeller-Vulkan
(common on Adreno GPUs), Flutter coalesces every `setState` /
`markNeedsPaint` call that happens INSIDE a pointer-event handler.
They only flush at pen-up. Mid-gesture frames are silently dropped.

The fix is `_liveStrokeTicker`: a vsync `Ticker` that calls
`setState({})` from inside its frame callback (which is itself a
frame callback — bypasses the coalescing). The ticker only runs
while a gesture is active; idle cost is zero.

See [`doc/troubleshooting-impeller.md`](troubleshooting-impeller.md)
for the deep dive.

## Open-core boundary

The split between this free package and the commercial
`fluera_canvas_gpu` is enforced by an interface, not by stub code:

- `fluera_canvas` exports `GpuStrokeBackend` (abstract) and the
  `FlueraCanvasGpu.setBackend(...)` static.
- `fluera_canvas_gpu` (separate repo) provides
  `FlueraCanvasGpuBackend` that implements the interface and routes
  to per-platform native plugins.

Without `fluera_canvas_gpu` the backend is null, the
`NativeStrokeOverlay` widget never mounts, and the Dart
`_LiveStrokePainter` handles the live stroke. Same `FlueraCanvas`
widget code path for both consumer types.
