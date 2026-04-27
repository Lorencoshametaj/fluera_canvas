# `fluera_canvas` and the commercial add-ons

`fluera_canvas` is **fully open-source under MIT** and meant to stand on its
own. You don't need anything else to ship a real drawing app — the free core
covers infinite canvas, scene graph, selection / transform, lasso, text,
stickers, image annotations, layers, snap-to-grid, smart guides, PNG export
and persistence.

That said, the `fluera_canvas` widget exposes a couple of small, optional
extension hooks. If you choose to consume them, you can plug in commercial
packages from the same author for use cases the free tier deliberately
doesn't address.

## `fluera_canvas_gpu` — native live-stroke + vector export

The free core renders the live stroke through a Dart `CustomPainter`. Latency
is ~12–16 ms — fine for note-taking and whiteboards on a flagship device.

If you need sub-frame latency on a wide range of hardware (Procreate /
Goodnotes-class UX), the commercial **`fluera_canvas_gpu`** package plugs a
native renderer into the same widget tree via the public `GpuStrokeBackend`
interface that ships in this core. Backends: Android Vulkan, iOS / macOS
Metal, Linux OpenGL, Windows Direct3D 11, Web WebGPU. Wire it once at
`main()`:

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

The same package adds vector export: SVG 1.1, PDF 1.5 with multi-page
picker, OCG toggleable layers, blend modes via `/ExtGState /BM`,
watermarks, PDF/A-1b conformance, and a drop-in `FlueraPdfExportButton`
widget. They serve the design-tool / pre-print / plotter segments.

## `fluera_engine_pro` — full Notability-class engine

For very specialized note-taking apps the commercial **`fluera_engine_pro`**
package adds:

- 13+ advanced brush engines (watercolor, charcoal, fountain pen, oil, neon,
  ink wash, marker, …),
- real-time multi-user collaboration (CRDT + vector clocks),
- in-document PDF annotation editing,
- LaTeX OCR + AI-assisted tools,
- SQLCipher encrypted storage,
- timeline branching and time-travel playback.

## Licensing & pricing

Both add-ons live behind a license tier (Indie / Team). See
**[engine.fluera.dev/pricing](https://engine.fluera.dev/pricing)** for the
current rates and tier details. The free `fluera_canvas` package on this
page never expires, never throws "license required" prompts, and never
phones home — the commercial extensions are entirely additive.
