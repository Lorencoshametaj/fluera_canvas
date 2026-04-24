# fluera_canvas example

Minimal demo app for the [`fluera_canvas`](../) SDK.

## What it shows

- `InfiniteCanvasController` — camera (pan, zoom, rotation, momentum).
- `InfiniteCanvasGestureDetector` — multi-touch + stylus + palm rejection wiring.
- Drawing callbacks (`onDrawStart`, `onDrawUpdate`, `onDrawEnd`) feeding a
  simple `CustomPainter` — stroke coordinates arrive in canvas space, so the
  strokes move with the camera.

Roughly 100 lines of Dart in [`lib/main.dart`](lib/main.dart).

## Run

```bash
flutter pub get
flutter run
```

Pinch to zoom, two-finger drag to pan, three-finger rotate, single finger or
stylus to draw. Tap **Clear** (the floating button) to reset.

## What's *not* in the demo

This is deliberately the smallest useful sample — it shows the input + camera
layer of `fluera_canvas`, not the full engine. For brushes with real pressure
and texture, the scene graph, layers, export, collaboration, AI, or PDF
annotation, add `fluera_engine_pro` on top. See
[engine.fluera.dev](https://engine.fluera.dev/).
