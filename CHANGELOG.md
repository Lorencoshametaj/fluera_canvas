# Changelog

## 0.3.0

**Drop-in toolbar, 5k–10k stroke perf, Impeller-Vulkan profile-mode fix.**

This release adds a ready-to-use Material toolbar widget, an order-of-magnitude
faster committed-stroke renderer (per-stroke `ui.Picture` cache + offscreen
compositing layer + smoothed quadratic-bezier paths), and a ticker-driven
workaround for a Flutter pipeline coalescing bug we hit on Android profile
mode (Impeller-Vulkan / Adreno) where mid-gesture frames were dropped.

**New: drop-in toolbar**
- `FlueraCanvasToolbar` — Material widget that renders pen / eraser
  segmented control, color swatches, stroke-width slider, and undo /
  redo / clear buttons. Auto-subscribes to the canvas history listenable
  so the buttons reflect live state without `setState` plumbing.
- `kFlueraDefaultPalette` — exported 6-color preset.
- `FlueraCanvasState.historyListenable` — read-only `Listenable` that
  fires on every committed-strokes mutation (commit, erase, clear,
  undo, redo, load, tool switch, background change).
- New example demo: **Built-in toolbar** — drop-in usage in <30 lines.

**Renderer: 5k–10k strokes at 60 FPS**
- Each `CanvasStroke` now lazily builds and caches a `ui.Picture` of its
  rasterised path. Repainting a committed stroke is one `drawPicture`
  call, not N `drawLine` calls.
- Committed strokes drawn through a `RepaintBoundary` so the rasterizer
  blits the cached compositing layer instead of re-executing every
  picture per frame.
- Stable painter instances (`_LiveStrokePainter`, `_CommittedStrokesPainter`)
  created once in `initState` — no `super(repaint:)` listener swap on
  every parent rebuild, which on Impeller-Vulkan was silently dropping
  notifications.
- Strokes now drawn as a single `Path` per stroke with quadratic-bezier
  smoothing (each interior point is a control, the curve passes through
  midpoints) — eliminates polyline-kink "humps" on diagonal strokes
  visible at zoom-in. Stroke width is the average pressure (continuous
  silhouette, no pressure-band step artefacts).
- `_CommitNotifier` (internal) drives committed repaints. Consumers
  expose this read-only as `FlueraCanvasState.historyListenable`.

**Persistence-friendly initial state**
- New `FlueraCanvas(initialBytes: Uint8List?)` parameter. The bytes
  (produced by `FlueraCanvasState.toBytes()`) are decoded and inserted
  into the spatial index inside `initState`, BEFORE the first build /
  paint, so the first frame already shows the persisted strokes. This
  is the right way to restore a saved canvas — calling `loadFromBytes`
  on the State after the first frame can leave the [RepaintBoundary]
  cached layer stale on Impeller-Vulkan / Adreno (the second paint is
  silently coalesced and the canvas appears empty).
- Removed the `controller.scale <= 0.5` "overview guard" from
  [InfiniteCanvasGestureDetector] — it was an app-specific carry-over
  from the original Fluera codebase that prevented drawing at low
  zoom. The SDK now lets the consumer draw at any zoom; an overview
  mode can still be implemented app-side by switching `tool` to a
  non-draw value.

**Pipeline workaround (Impeller-Vulkan / Adreno profile mode)**
- During an active gesture, a vsync `Ticker` calls `setState({})` every
  frame so the rendering pipeline keeps producing frames. Without it,
  Flutter coalesces all `setState` / `markNeedsPaint` calls inside
  pointer events and only repaints at pen-up — making the live stroke
  and eraser preview circle invisible mid-gesture. The ticker runs
  only while a gesture is active (zero idle cost) and is enabled for
  both `draw` and `erase` tools, so the eraser preview tracks the
  pointer in real time.

**Eraser preview**
- Preview circle now tracks the pointer in real time during the erase
  gesture on touch (previously frozen until pen-up on Impeller-Vulkan).

**Internal**
- `setState` calls inside mutators of `_strokes` (commit, erase, clear,
  push, undo, redo, replace) replaced with explicit `_commitTick.notify()`.
- `widget.background` change in `didUpdateWidget` now triggers a
  committed repaint via the same notifier.
- `dispose` releases all per-stroke `ui.Picture` resources.

**Breaking** — none. All public APIs are backward compatible with 0.2.0.

## 0.2.0 — Unreleased

**Production-ready UX set.** Tool mode, undo/redo with shortcuts, spatial
index, background patterns, persistence, eraser preview, platform cursor.

- `CanvasTool` enum (`draw`, `erase`) passed via `FlueraCanvas(tool: …)`.
- Stroke-mode eraser: pointer removes strokes it touches (O(log n) hit-test
  via an `RTree<CanvasStroke>`); a whole swipe becomes one undo step.
  Vector-preserving — erased strokes are restored intact by `undo()`.
- `eraserRadius` param (default 24 px screen space).
- Undo / redo stack with configurable `historyCapacity` (default 100).
  - `FlueraCanvasState.undo() / redo() / canUndo / canRedo /
    historyLength / clearHistory()`
  - Covers: committed draw, erase swipe, `clear()`, `pushStroke`, `pushStrokes`.
- Spatial index wired into the default painter: `_InfiniteCanvasPainter`
  iterates only strokes returned by a viewport-culled RTree query.
  Per-frame cost scales with on-screen content, not scene total.
  Holds 60 FPS up to **~10 000 strokes** on a mid-tier Android device.
- `strokeAt(Offset worldPoint, {tolerance})` — front-most hit test.
- `strokesInRect(Rect worldRect)` — bulk query.
- `onStrokesErased` callback for eraser-tool observers.
- Example app expanded to a 4-demo gallery: drawing tools, stress test
  (10 k procedural strokes), programmatic push, PNG export.

**Persistence**
- `FlueraCanvasState.toBytes()` / `loadFromBytes(Uint8List)` — compact
  little-endian binary format (magic `FCV0`, version 1).
- `FlueraCanvasState.toJson()` / `loadFromJson(String)` — human-readable,
  diff-friendly. ~10× larger than the binary form.
- Loading replaces the scene and clears the undo history.

**Background patterns**
- New `CanvasBackground` with factory constructors `solid`, `grid`,
  `dotted`, `lined`. Pattern rendered in world space and anchored to the
  canvas origin (pan/zoom behaves like moving over real paper).
- Breaking: `FlueraCanvas(background:)` now takes `CanvasBackground`
  instead of `Color`. Migrate with `background: CanvasBackground.solid(myColor)`.

**Eraser preview + desktop cursor**
- `showEraserPreview: true` (default) draws a translucent circle under
  the pointer when [CanvasTool.erase] is active. Radius matches the
  live hit-test exactly.
- Desktop cursor follows the active tool: `SystemMouseCursors.precise`
  for `draw`, hidden (replaced by the preview circle) for `erase`.

**Keyboard shortcuts**
- `enableKeyboardShortcuts: true` (default) binds:
  - Ctrl/Cmd + Z → undo
  - Ctrl/Cmd + Shift + Z → redo
  - Ctrl/Cmd + Y → redo
  - Delete / Backspace → clear

**Breaking**
- `undoLastStroke()` removed — replaced by `undo()` which is history-aware
  (also covers erase and clear operations).
- `FlueraCanvas(background:)` type changed from `Color` to
  `CanvasBackground`.

## 0.1.0 — Unreleased

First public snapshot of the Fluera Engine SDK split. The following SDK
primitives are now shipped from `fluera_canvas`:

**Canvas + gesture**
- `InfiniteCanvasController` (camera physics, dive/flight, rotation lock
  via injectable `RotationLockPersistence` hook)
- `LiquidCanvasConfig` (opaque `reflow` slot for consumer add-ons)
- `InfiniteCanvasGestureDetector` with injectable `PalmRejectionPolicy`
  + `StylusHoverTracker` hooks (no-op defaults)
- `StylusDetector`, `PlatformGuard`, `InputPredictor`,
  `RawInputProcessor120Hz`

**Drawing models + filters**
- `ProDrawingPoint`, `PressureCurve`, `VelocityCurve`, `BrushPreset`,
  `ProBrushSettings`
- `OneEuroFilter`, `AdvancedOneEuroFilter`, `DynamicPressureMapper`,
  `OrganicNoise`, `PhysicsInkSimulator`, `PostStrokeOptimizer`,
  `PredictiveRenderer`

**Scene graph**
- `CanvasNode`, `CanvasNodeFactory` (with `externalFactory` hook for
  consumer-registered node types), `NodeVisitor` (7 base visit methods +
  `visitOther` fallback for engine-only types), `DefaultNodeVisitor`
- 7 base node classes: `GroupNode`, `LayerNode`, `ShapeNode`, `StrokeNode`,
  `TextNode`, `ImageNode`, `PathNode`
- `FrozenNodeView`, `PaintStackMixin`, `SceneGraphInterceptor`,
  `TransformBridge`, `NodeConstraint`, `ContentOrigin`, `NodeId`,
  `InvalidationGraph`
- Event infrastructure: `EngineEvent` + `EngineEventBus`,
  `SceneGraphEvent` + `SceneGraphObserver`

**Effects + models**
- `NodeEffect`, `ShaderEffect`, `ShaderEffectWrapper`, `MeshGradient`,
  `GradientFill`, `PaintStack`, `FillLayer`, `StrokeLayer`
- `DigitalTextElement`, `ImageElement`, `ExportSettings`, `CanvasLayer`,
  `TextOverlay`, `ToneCurve`, `ColorAdjustments`, `GradientFilter`,
  `PerspectiveSettings`, `VectorPath`
- `ShapeType`, `AccessibilityInfo/Action/TreeNode/TreeBuilder`

**Rendering**
- `RTree`, `SpatialIndexManager`, `ViewportCuller`, `StrokeOptimizer`,
  `OptimizedPathBuilder`, `PaintPool`, `DirtyRegionTracker`,
  `LodConfig`, `MemoryPressureLevel`
- `PathRenderer`, `BatchRenderer`
- `ShapePainter`, `DigitalTextPainter`, `OriginIndicatorPainter`,
  `PaperPatternPainter`, `PaperGrainPainter`
- `BrushTexture`

**GPU live-stroke bridge (Dart side)**
- `NativeStrokeOverlay` + `NativeStrokeOverlayController` façade
- `VulkanStrokeOverlayService`, `WebGpuStrokeOverlayService`,
  `WebGpuOverlayView`, `NativeStrokeFfi`

**Export + import**
- `RasterImageEncoder`, `RasterEncoderChannel`, `BinaryCanvasFormat`,
  `ExportPreset`, `ExportConfig` (rich preset variant with `pageFormat`,
  `background`, `copyWith`, PDF fields), `ExportFormat` (png/jpeg)
- `FlueraFileHeader/TOC/Writer/Reader/ExportService`
- `SvgImporter`, `TimelapseExportConfig`
- `PdfBookmark`, `PdfWatermark`, `WatermarkPosition`, `PdfPageLabel`,
  `PdfTextField/Checkbox/Dropdown`, `PdfImageXObject`,
  `PdfLinkAnnotation`

**Core utilities**
- `EngineError`, `ErrorSeverity`, `ErrorDomain`, `EngineTelemetry` +
  counters/gauges/histograms, `SchemaVersionException`, `generateUid`

**Native GPU live-stroke pipeline (full cross-platform)**
- Android: Vulkan (`libfluera_vk_stroke.so`, Kotlin `FlueraCanvasPlugin`)
- iOS: Metal (`MetalStrokeOverlayPlugin` + CADisplayLink 120 Hz sync)
- macOS: Metal (`MetalStrokeOverlayPlugin` + `StrokeShaders.metal`)
- Linux: OpenGL (GTK+EGL/GL, `FlueraCanvasPlugin`)
- Windows: D3D11 (`FlueraCanvasPluginCApi`)
- Web: WebGPU (`WebGpuStrokeOverlayService` + `WebGpuOverlayView`,
  gated on `navigator.gpu` availability, Dart fallback otherwise)

Single MethodChannel name on all native platforms:
`fluera_canvas/native_stroke`. Web uses a direct JS interop bridge.

### Known limitations

- The `SceneGraph` class, transaction / snapshot / integrity helpers,
  and the `document_node` are resident in the private `fluera_engine`
  package — they depend on `EngineScope`, the design-variables /
  animation-timeline systems, and the spatial-index wrapper that hold
  `CanvasNode` references. Consumers who need the full scene graph
  should depend on `fluera_engine` directly.
- Tools (`PenTool`, `EraserTool`, `UnifiedShapeTool`, `DigitalTextTool`),
  navigation widgets (`CanvasMinimap`, `ZoomLevelIndicator`,
  `ContentBoundsTracker`, `CameraActions`), and concrete brush engines
  (`BallpointBrush`, `PencilBrush`, `HighlighterBrush`) remain engine-
  resident — their transitive dependencies cross into
  `FlueraLayerController`, `SceneGraph`, and the GPU shader services.

### Note

API is pre-`1.0` and may break between minor versions until the surface
stabilises.
