# fluera_canvas

> Professional 2D canvas SDK for Flutter. Pressure-sensitive infinite canvas
> with a native GPU live-stroke pipeline, a scene graph, and pluggable brush
> engines.
>
> **Status:** `0.3.0` pre-release. API unstable until `1.0.0`.
> Marketing site: **[engine.fluera.dev](https://engine.fluera.dev/)**

## What you get

- `FlueraCanvas` — drop-in drawing widget. Pen / eraser tools, undo / redo
  history, pressure-aware input, infinite pan / zoom / rotation, native
  GPU live-stroke pipeline, PNG export. One `GlobalKey<FlueraCanvasState>`
  and you have a full canvas in your app.
- `FlueraCanvasToolbar` — drop-in Material toolbar that wires the most
  common controls (pen / eraser, color swatches, stroke-width slider,
  undo / redo / clear) into the canvas with zero glue code. Auto-syncs
  to history state via `FlueraCanvasState.historyListenable`.
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

## Install

```yaml
dependencies:
  fluera_canvas: ^0.3.0
```

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

| Platform | Live-stroke backend | Status |
| --- | --- | --- |
| Android | Vulkan              | ✅ Native path ships with this package |
| iOS     | Metal               | ✅ Native path ships with this package |
| macOS   | Metal               | ✅ Native path ships with this package |
| Linux   | OpenGL              | ✅ Native path ships with this package |
| Windows | Direct3D 11         | ✅ Native path ships with this package |
| Web     | WebGPU              | ✅ Native path (Chrome 113+, Edge 113+, Safari 18+) |

Consumers can depend on `fluera_canvas` alone — every platform's native
live-stroke plugin ships with this package. If a specific GPU isn't
available at runtime (e.g. WebGPU disabled in the browser), the Dart
fallback inside `NativeStrokeOverlay` takes over automatically.

## Native live-stroke plugin

**Android**: Vulkan renderer ships in this package — no extra dependency.
APK footprint on `arm64-v8a + armv7 + x86_64`: ~5 MB multi-arch.

> **Required** on Android: your host app must run Flutter itself on the
> Vulkan backend so it can composite the plugin's Vulkan SurfaceProducer.
> Add the following inside `<application>` in
> `android/app/src/main/AndroidManifest.xml`:
>
> ```xml
> <meta-data
>     android:name="io.flutter.embedding.android.EnableImpeller"
>     android:value="true" />
> <meta-data
>     android:name="io.flutter.embedding.android.ImpellerBackend"
>     android:value="vulkan" />
> ```
>
> Without this, the Texture widget renders an empty surface — the
> strokes are drawn on a Vulkan image Flutter's compositor never reads.

**iOS / macOS**: Metal renderer ships in this package — no extra
dependency. CADisplayLink 120 Hz ProMotion sync (iOS) is also bundled.

**Linux**: OpenGL/GTK plugin. Requires `libgtk-3-dev`, `libegl1-mesa-dev`,
`libgl1-mesa-dev` at build time.

**Windows**: Direct3D 11 plugin. Links against `d3d11`, `dxgi`,
`d3dcompiler` (all shipped with the Windows 10 SDK).

**Web**: WebGPU plugin. Lives alongside the other platforms but is
gated on `navigator.gpu` availability — falls back to Dart on browsers
without WebGPU (Firefox stable, Safari < 18).

`MethodChannel` name: `fluera_canvas/native_stroke` on all native
platforms. Web uses a direct JS interop bridge (no MethodChannel).

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
