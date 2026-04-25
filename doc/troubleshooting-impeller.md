# Troubleshooting Impeller-Vulkan / Adreno

This document collects the platform-specific quirks we hit while
building `fluera_canvas` 0.3.0 on Android profile mode with the
Impeller-Vulkan backend (the default on Adreno GPUs since Flutter
3.27). If your symptoms match, the SDK already has the workaround;
this is here so you understand what you're seeing.

## Symptom 1: live stroke invisible mid-gesture, "snaps" at pen-up

You draw a line. While your finger is down, nothing visible changes
on the canvas. The moment you lift, the entire stroke appears in
one frame.

### Diagnosis

Add diagnostic prints to `_LiveStrokeNotifier.forceRepaint` and
`_LiveStrokePainter.paint`. You'll see `notifyListeners` fire
hundreds of times per stroke, while `paint()` runs only at pen-down
and pen-up.

```
[LiveNotifier] forceRepaint#10 pts=10 hasListeners=true
[LiveNotifier] forceRepaint#20 pts=20 hasListeners=true
…
[LiveNotifier] forceRepaint#90 pts=90 hasListeners=true
[LivePainter] paint#4 pts=0 size=… scale=1.0   ← clear, pen-up
```

### Cause

On Impeller-Vulkan profile builds, Flutter coalesces every
`setState` and `markNeedsPaint` call that happens INSIDE a
pointer-event handler. They only flush when the gesture ends.
Mid-gesture frames are silently dropped.

This is NOT a bug in your code. It reproduces with stable painters,
fresh listener subscriptions, `RepaintBoundary` on or off,
`Listenable.merge` or single notifier, `SchedulerBinding.scheduleFrame()`
called or not. We tried.

### Workaround (already applied in the SDK)

A vsync `Ticker` that calls `setState({})` every frame while a
gesture is active. The Ticker callback runs in the framework's
post-frame phase, NOT inside a pointer event, so the dirty mark is
honoured normally and `build` / `layout` / `paint` proceed as
expected.

Implementation: `_liveStrokeTicker` in
`fluera_canvas/lib/src/canvas/fluera_canvas_widget.dart`. Started
in `_onDrawStart` (draw OR erase tool, when not using the native
overlay), stopped in `_onDrawEnd` / `_onDrawCancel`. Zero idle cost
because it runs only during a gesture.

### Doesn't reproduce on:

- Android debug mode (different scheduler heuristics)
- Skia backend (`--enable-software-rendering` or
  `EnableImpeller=false`)
- iOS / macOS Metal
- Linux / Windows
- Web

## Symptom 2: persisted canvas appears empty after restore

User saves a canvas, closes the app, reopens it: the saved strokes
are visible for a fraction of a second then disappear, OR they
never appear at all. The Dart-level state is correct
(`strokeCount` is the right number) but the screen is blank.

### Diagnosis

In your restore code, you're calling
`_canvasKey.currentState?.loadFromBytes(bytes)` after the first
build / paint. The State accepts the strokes, the spatial index is
populated, but the `_CommittedStrokesPainter`'s `RepaintBoundary`
cached layer was already rasterised with 0 strokes. The
`_commitTick.notify()` call inside `loadFromBytes` should mark the
layer dirty, but on Impeller-Vulkan that mark is also silently
coalesced if the canvas hasn't received any pointer input yet.

### Fix (use the SDK's `initialBytes` parameter)

```dart
FlueraCanvas(
  key: canvasKey,
  initialBytes: bytesYouLoadedFromDisk,  // ← decoded inside initState
  // …
);
```

The bytes are decoded synchronously in `initState`, BEFORE the
first build / paint. The first frame already contains the strokes
in the spatial index, so the initial rasterisation of the cached
layer includes them. No race, no second-paint coalescing.

`loadFromBytes` is still available on the State for runtime
swaps (e.g. document-switch UX), but for first-mount restore
always prefer `initialBytes`.

## Symptom 3: eraser preview circle frozen until pen-up

Same root cause as Symptom 1. Fixed by the same `_liveStrokeTicker`
— which now starts on the erase tool too. If you've subclassed the
gesture detector or built your own preview, make sure your repaint
trigger isn't gated on a pointer-event-time `setState`.

## Symptom 4: AndroidManifest "OnBackInvokedCallback" warnings

Harmless Android system warnings. Fix by adding the attribute to
your `<application>` tag:

```xml
<application
    …
    android:enableOnBackInvokedCallback="true">
```

Doesn't affect canvas behaviour at all — the SDK doesn't rely on
`PopScope` for any of its internal state; it's a generic
Android 13+ recommendation.

## Symptom 5: GPU compositing errors in logcat

```
E/qdgralloc: GetGpuPixelFormat: No map for format: 0x38
E/AdrenoUtils: …Memory Layout input parameter validation failed!
E/Gralloc4: isSupported(1, 1, 56, 1, ...) failed with 1
```

These come from the Adreno GLES driver during Flutter's surface
allocation. They're harmless on Xiaomi/Qualcomm devices and don't
correlate with any visible defect. They're not caused by
`fluera_canvas` — strip them out of your bug-report logs to keep
focus on actual issues.

## Symptom 6: visible "humps" or "pinch" on strokes at zoom-in

You zoom in to ~5–10× and notice the stroke width has small
discontinuities, almost like the stroke is made of overlapping
pieces of slightly different thickness.

### Cause

You're running an older `fluera_canvas` (≤ 0.2.x) that uses
pressure banding — N drawPath calls per stroke, each with a
slightly different `strokeWidth`, with rounded joins to hide the
seams. At 1× zoom the seams are sub-pixel; at 5×+ they show.

### Fix

Update to 0.3.0+. The renderer now uses a single `drawPath` per
stroke with average pressure, and `quadraticBezierTo` smoothing.
Silhouette is C¹-continuous regardless of zoom.

## Reporting a new platform quirk

If you hit something not listed here, file an issue with:

- Device + GPU + Android version
- Flutter version (`flutter --version`)
- `fluera_canvas` version
- Build mode (debug / profile / release)
- Logcat extract showing the symptom (filtered to your app)
- Whether it reproduces on Skia (`flutter run --enable-software-rendering`)

The Skia comparison is the single most useful data point — if it
reproduces there too, it's framework-level; if Skia is fine, it's
an Impeller-side regression.
