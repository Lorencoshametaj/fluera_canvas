# Changelog

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

### Known limitations

- The `SceneGraph` class itself, transaction/snapshot/integrity helpers,
  and the `document_node` are still resident in `fluera_engine` because
  they depend on `EngineScope`, the design-variables / animation-timeline
  systems, and the spatial-index wrapper that hold `CanvasNode`
  references. An advanced user who needs the full scene graph should
  depend on `fluera_engine` directly.
- Tools (`PenTool`, `EraserTool`, `UnifiedShapeTool`, `DigitalTextTool`),
  navigation widgets (`CanvasMinimap`, `ZoomLevelIndicator`,
  `ContentBoundsTracker`, `CameraActions`), and concrete brush engines
  (`BallpointBrush`, `PencilBrush`, `HighlighterBrush`) remain engine-
  resident — their transitive dependencies cross into
  `FlueraLayerController`, `SceneGraph`, and GPU shader services.
- The native Vulkan / Metal / OpenGL / Direct3D 11 stroke renderers
  still ship through the private `fluera_engine` Flutter plugin. The
  MethodChannel name remains `fluera_engine/vulkan_stroke` (will rename
  to `fluera_canvas/native_stroke` once the native code physically moves
  into this package).

### Dev note

This package is currently consumed via `path:` inside the Fluera
workspace. `publish_to: 'none'` has not been added because the
intention is to publish to pub.dev once the 1.0.0 API stabilises.
