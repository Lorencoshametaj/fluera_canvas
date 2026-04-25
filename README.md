# fluera_canvas

> **The document-grade infinite-canvas SDK for Flutter.**
>
> Built for **notes apps, whiteboards and design tools** — not signature pads.
> Multi-thousand strokes at 60 FPS, drop-in Material toolbar, persistence
> primitives, optional native GPU bridge.
>
> The only Flutter canvas SDK on pub.dev with infinite pan / zoom / rotate
> physics, RTree-backed viewport culling, and per-stroke GPU `Picture` cache.
> If you're building Notability / Goodnotes / Miro / Figma-class UX, start
> here.
>
> **Status:** `0.4.0` pre-release. API unstable until `1.0.0`.
> Marketing site: **[engine.fluera.dev](https://engine.fluera.dev/)**

## Positioning

| You're building… | Use |
|---|---|
| Notes app, whiteboard, sketching app, design tool, mind-map, diagram editor, infinite-canvas planner | **`fluera_canvas` ✅** |
| Signature pad, e-signature flow | `signature` / `hand_signature` (more focused) |
| Photo annotation, draw-on-image, sticker/text overlay | `flutter_painter_v2` (raster, has text + image overlay) |
| Custom stroke renderer, no widget | `perfect_freehand` (pure rendering primitive) |

Different tools for different jobs. `fluera_canvas` deliberately doesn't
chase the signature-pad or photo-annotation niches — those are well served.
What's missing on pub.dev is the **document-grade** category: infinite
surface, thousands of strokes, persistence-friendly, ready for a real
note-taking or design product. That's what this SDK is for.

## What you get

- `FlueraCanvas` — drop-in drawing widget. **Pen, stroke-mode eraser,
  pixel-mode eraser, line / rectangle / ellipse shape tools**, undo /
  redo history, pressure-aware input, infinite pan / zoom / rotation,
  native GPU live-stroke pipeline, PNG export. One
  `GlobalKey<FlueraCanvasState>` and you have a full canvas in your app.
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

## Install

```yaml
dependencies:
  fluera_canvas: ^0.4.0
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

**My live stroke is invisible until I lift my finger.**
You're on Android profile mode with Impeller-Vulkan, and the canvas is
not running 0.3.0 yet. Update — `_liveStrokeTicker` works around the
Flutter pipeline coalescing that drops mid-gesture frames on Adreno.

**My stroke has visible "humps" or "pinches" when I zoom in.**
Update to 0.3.0+. The renderer now uses a single `drawPath` per stroke
with quadratic-bezier smoothing and average pressure — silhouette is
C¹-continuous regardless of zoom. The 0.2.x pressure-banding renderer
is gone.

**Can I use `fluera_canvas` without the commercial GPU plugin?**
Yes — that's the default. The pure-Dart fallback handles the live
stroke and committed strokes on every platform. The native GPU plugin
(`fluera_canvas_gpu`, separate package) buys sub-frame latency on the
live path but is optional.

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
Yes. CanvasKit and WASM compilation both work. WebGPU live-stroke
requires the commercial `fluera_canvas_gpu`; without it the Dart
fallback handles the live stroke (works on every browser).

**My CI fails with `OnBackInvokedCallback is not enabled`.**
That's an Android system warning unrelated to `fluera_canvas`. Add
`android:enableOnBackInvokedCallback="true"` to your
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
