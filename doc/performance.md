# Performance tuning

The defaults in `fluera_canvas` 0.10.x are calibrated to keep mid-tier
Android (Adreno 660 / Impeller-Vulkan, profile mode) at 60 FPS up to
~5 k–10 k strokes in the viewport. This guide explains the knobs and
when to reach for them.

## Profiling baseline

Reference device: Xiaomi 2107113SG, Adreno 660, Flutter 3.27 stable,
Impeller-Vulkan, profile build.

| Workload | UI thread | Raster thread | FPS |
|---|---|---|---|
| Idle, 0 committed strokes | < 1 ms | < 2 ms | 60 |
| Drawing, 0 committed strokes | ~3 ms | ~4 ms | 60 |
| 100 strokes in viewport, drawing | ~3 ms | ~6 ms | 60 |
| 1 000 strokes in viewport, idle | < 2 ms | < 3 ms | 60 (cached) |
| 5 000 strokes in viewport, idle | < 2 ms | < 3 ms | 60 (cached) |
| 10 000 strokes total, ~500 visible | ~3 ms | ~5 ms | 60 |

The cached-layer wins are real but conditional: see "When the cache
gets invalidated" below.

## Where the time goes

Per-frame cost breakdown when drawing with N committed strokes
visible:

```
total ≈ live_paint + (cached_blit if no commit) + tessellation_tail
```

- **`live_paint`** ≈ 0.5–1.5 ms — one `Path` + one `drawPath` per
  stroke, smoothed via the five-stage pipeline (One-Euro at ingest →
  arc-length subdivision → two-pass EMA → predicted ghost tail
  anchor → Catmull-Rom → cubic bezier with tau = 1/6). Cost depends
  on the number of points in the in-progress stroke; for ≥ 5 k-point
  strokes the chunked PictureRecorder cache caps per-frame work at
  O(N/256).
- **`cached_blit`** ≈ 0.5 ms — RepaintBoundary blit of the committed
  layer. Constant; doesn't scale with `N` while the cache is valid.
- **`tessellation_tail`** ≈ 0 ms when nothing changed; ~5 ms per
  100 newly-committed strokes the first time the cache is rebuilt.

When the cache is invalidated (a new commit, an erase, a clear, a
camera change), the rasterizer re-executes every visible stroke's
`drawPicture`. This is roughly:

```
cache_rebuild ≈ ~0.05 ms × visible_strokes_count
```

So a viewport with 1 000 visible strokes costs ~50 ms to rebuild the
cache, and you'll see one dropped frame at the moment of commit.
On idle thereafter the layer is reused for free.

## Tuning knobs

### `historyCapacity` (`FlueraCanvas` parameter)

Default: `100`. Each entry is small (a few stroke references), so
RAM cost is negligible. Set to `0` to disable history entirely if
you don't need undo/redo (saves a few KB and a couple of branches
in the commit path).

### `enableNativeLiveStroke`

Default: `true`. When the commercial `fluera_canvas_gpu` backend is
registered, the live stroke is rendered by the platform's native GPU
pipeline (sub-frame latency). When the backend is null this flag is
a no-op and the Dart fallback kicks in automatically. Setting it to
`false` forces the Dart path even with the backend present —
useful for A/B testing performance.

### Spatial index threshold

`_CommittedStrokesPainter` calls
`_spatialIndex.queryVisible(viewport, margin: 200)`. The 200-unit
margin is generous to avoid pop-in at viewport edges. If you have
small strokes and very high zoom, you can reduce it (cull more
aggressively); if you have very large strokes, increase it (don't
miss strokes whose centroid is off-screen but bounds reach in).
This is internal — open an issue if you need it tunable.

### Stroke smoothing pipeline

`_paintStrokeSegments` (in `fluera_canvas_widget.dart`) runs a
five-stage chain mirrored from the commercial `fluera_engine`
fountain-pen path builder: One-Euro at point ingest, adaptive
arc-length subdivision via Catmull-Rom interpolation on long gaps,
two-pass EMA pre-smoothing, predicted ghost tail anchor (velocity +
half-acceleration extrapolation, never drawn), then a Catmull-Rom →
cubic bezier with tau = 1/6.

If your stroke still looks visibly polygonal, the input rate is most
likely the bottleneck — Flutter coalesces pointer events into the
vsync window (typically 60–120 Hz), and the platform pipeline can
silently merge sub-frame samples on slow devices. See
[troubleshooting-impeller.md](troubleshooting-impeller.md) for the
Adreno-specific quirks.

## When the cache gets invalidated

The committed `RepaintBoundary` layer survives until one of:

- A new stroke is committed (`_commitTick.notify()`)
- An eraser swipe ends with non-zero erased count
- `clear()` / `pushStroke` / `pushStrokes` / `undo` / `redo` /
  `loadFromBytes` / `loadFromJson` is called
- `widget.background` changes via `didUpdateWidget`
- The camera moves (zoom, pan, rotate) — `_controller` notifies

The first four are unavoidable; the last is the expensive one. If
your app does continuous camera animation (e.g. fly-to), every frame
re-rasterises the visible strokes. With 1 000 visible at ~0.05 ms
each that's 50 ms / frame — frame drops guaranteed.

**Mitigation:** keep camera animation duration short (≤ 200 ms);
the user perceives the motion blur, not the dropped frames.

## Benchmarking your scene

```dart
// Quick instrumentation: log raster duration for one frame.
SchedulerBinding.instance.addPostFrameCallback((Duration elapsed) {
  print('Frame: $elapsed');
});
```

For a real measurement use Flutter DevTools' Performance tab
(`flutter run --profile` then open DevTools): the raster track
will show your `_CommittedStrokesPainter.paint` calls explicitly.

## When 5 k–10 k isn't enough

The free SDK is built around viewport culling + Picture cache. If
you need 50 k+ strokes per layer, near-zero camera-animation cost,
or shader-based variable-width brushes, that's the territory of the
commercial add-ons. See
[doc/commercial-add-ons.md](commercial-add-ons.md) for the full
list.
