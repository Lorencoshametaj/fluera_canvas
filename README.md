# fluera_canvas

> Professional 2D canvas SDK for Flutter. Pressure-sensitive infinite canvas
> with a native GPU live-stroke pipeline, a scene graph, and pluggable brush
> engines.
>
> **Status:** `0.1.0` pre-release. API unstable until `1.0.0`.
> Marketing site: **[engine.fluera.dev](https://engine.fluera.dev/)**

## What you get

- `InfiniteCanvasController` — camera with pan, zoom, rotation, spring
  physics, momentum, multi-phase animation.
- `InfiniteCanvasGestureDetector` — multi-touch, stylus, palm rejection,
  hover tracking. All policies are pluggable.
- Scene graph primitives (`StrokeNode`, `ShapeNode`, `TextNode`, `ImageNode`,
  `PathNode`, `GroupNode`, `LayerNode`) with a visitor pattern.
- Input pipeline — One-Euro smoothing, dynamic pressure mapping, palm
  rejection, stylus prediction, 120 Hz raw processor.
- Drawing models — `ProDrawingPoint`, `PressureCurve`, `VelocityCurve`,
  `BrushPreset`, `ProBrushSettings`.
- A module system and telemetry hooks so consumers can wire their own
  storage, sync, AI, export or PDF pipelines.

## Install

```yaml
dependencies:
  fluera_canvas: ^0.1.0
```

## Hello canvas

```dart
import 'package:flutter/material.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

class MyCanvas extends StatefulWidget {
  const MyCanvas({super.key});
  @override
  State<MyCanvas> createState() => _MyCanvasState();
}

class _MyCanvasState extends State<MyCanvas> {
  final controller = InfiniteCanvasController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InfiniteCanvasGestureDetector(
      controller: controller,
      onDrawStart: (p, pressure, tiltX, tiltY) { /* push stroke */ },
      onDrawUpdate: (p, pressure, tiltX, tiltY) { /* extend stroke */ },
      onDrawEnd: (p) { /* commit stroke */ },
      child: CustomPaint(
        painter: MyScenePainter(controller),
        size: Size.infinite,
      ),
    );
  }
}
```

A runnable demo lives in [`example/`](example/). Full quickstart with
persistence and camera animation: **[engine.fluera.dev/quickstart](https://engine.fluera.dev/quickstart)**.

## Platforms

| Platform | Live-stroke backend | Status |
| --- | --- | --- |
| Android | Vulkan              | ✅ Native path ships with this package |
| iOS     | Metal               | Native path via `fluera_engine` plugin (migration pending) |
| macOS   | Metal               | Native path via `fluera_engine` plugin (migration pending) |
| Linux   | OpenGL              | Dart fallback |
| Windows | Direct3D 11         | Dart fallback |
| Web     | WebGPU              | Dart fallback (WebGPU path experimental) |

Dart-only consumers can depend on `fluera_canvas` alone — the fallback Dart
painter inside `NativeStrokeOverlay` takes over automatically.

## Native live-stroke plugin

**Android**: Vulkan renderer ships in this package — no extra dependency.
APK footprint on `arm64-v8a + armv7 + x86_64`: ~5 MB multi-arch.

**iOS / macOS**: Metal renderer will move in here in the next release.
For now the native path still registers via the companion `fluera_engine`
package if you have it in your workspace.

**Linux / Windows**: Dart fallback painter runs automatically — the OpenGL
and Direct3D 11 renderers use a different tessellator that produces
slightly different visuals, so we keep them out of the native path for
cross-platform consistency.

`MethodChannel` name: `fluera_canvas/native_stroke`.

## What's *not* in here

- Advanced brush engines (watercolor, charcoal, fountain pen, oil, neon,
  ink wash, marker)
- Real-time collaboration (CRDT, vector clocks)
- PDF annotation + multi-page export
- LaTeX OCR and AI-assisted tools
- SQLCipher encrypted storage
- Timeline branching and time-travel playback

All of the above ship in the commercial `fluera_engine_pro` package. See
[engine.fluera.dev/pricing](https://engine.fluera.dev/pricing) for details.

## Contributing

Issues and PRs welcome at
[github.com/Lorencoshametaj/fluera_canvas](https://github.com/Lorencoshametaj/fluera_canvas).
Please open an issue before starting a large change so we can align on API
shape — we're converging on `1.0` and want to avoid breaking churn.

## License

MIT — see [LICENSE](LICENSE).
