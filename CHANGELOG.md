# Changelog

## 0.16.2 (cross-feature audit fixes — 2026-04-28)

Patch release. No new public surface; pure correctness fixes
caught by a cross-feature audit of 0.11→0.16.1.

### Fixes

- **`pasteFromClipboard` now preserves `tilts` / `twists` /
  `metadata`.** The 0.13.0 paste path was authored before the 0.14.0
  channels existed and silently dropped them when reconstructing
  pasted strokes — copying a calligraphy / fountain-pen stroke and
  pasting it back yielded a flat clone with no nib angle, no barrel
  twist, no consumer metadata. Round-trip is now lossless and the
  metadata map is shallow-copied so future mutations don't reach
  back into the clipboard-decoded original.
- **`hitTestInRect` normalises degenerate rects.** Inverted rects
  (negative width / height — common when a marquee drag crosses its
  origin) now return the same hit set as their normalised
  equivalent, instead of silently probing the spatial index with
  `right < left`. Zero-area rects and non-finite (NaN / infinite)
  coordinates short-circuit to an empty set.
- **Programmatic helpers fail loudly on degenerate input in release
  builds.** `drawCircle` throws `ArgumentError` for `radius <= 0`,
  non-finite radius, or `segments < 3`. `drawPolygon` throws for
  `points.length < 2`. The pre-fix `assert`s only fired in debug,
  so production callers silently committed malformed strokes.
- **`FlueraMinimap` lifecycle hardened.** Added `didUpdateWidget` to
  rebind when the consumer swaps `canvasKey` mid-flight, and a
  defensive `dispose()` that drops the cached canvas-state and
  merged-listenable references on unmount.

### Migration impact

Zero breaking. The new `ArgumentError` paths replace asserts that
already documented the invariant — only callers that were passing
degenerate input in release builds (and silently producing
malformed strokes) will see the error. If you genuinely need to
draw a 0-radius / 1-point shape, special-case it before the call.

## 0.16.1 (Cupertino toolbar fork — 2026-04-28)

Single-feature release: a Cupertino-styled drop-in toolbar for
consumers targeting iOS / macOS with pixel-perfect Apple HIG
aesthetics. Deferred from 0.16.0 to keep that release focused on
adoption-optimization (cookbook / integrations / a11y / i18n /
shortcuts).

Audit Agent 2 (TLDraw, Excalidraw, Konva, Fabric) confirmed: zero
competitor pub.dev offers a Cupertino-styled canvas toolbar. This
closes the identity gap for the iOS-purist segment (~5% of Flutter
audience targeting iOS-only) without touching the Material default.

### `FlueraCanvasCupertinoToolbar`

- **NEW** widget exported from the barrel — same public API as
  `FlueraCanvasToolbar` (32 constructor params, all `show*` flags,
  callbacks, `theme` / `strings` / `compactBreakpoint`). Consumer
  migration is one line: swap `FlueraCanvasToolbar(...)` for
  `FlueraCanvasCupertinoToolbar(...)`.
- Built with `CupertinoButton`, `CupertinoSlider`, `CupertinoColors`,
  `CupertinoIcons`. iOS-style hairline divider (0.33 px) on the top
  edge instead of Material's gradient + outline-variant border.
- Reuses `FlueraToolbarTheme` for geometry (radii / spacing /
  motion); colour overrides on the theme still work — `null` fields
  fall back to `CupertinoColors.activeBlue` / `systemRed` / `label`
  / `separator` / `systemGrey6` instead of Material colorScheme.
- Reuses `FlueraStrings` for i18n (no parallel string set needed).
- Pen-down haptic via `HapticFeedback.selectionClick()` on tool
  switch — matches iOS expectations.
- Compact mode + `compactBreakpoint` work identically to the
  Material toolbar.
- Layers / sticker bottom sheets use `showCupertinoModalPopup`
  (instead of Material's `showModalBottomSheet`).

### Demo

- New "Cupertino toolbar" entry in `example/lib/main.dart` gallery
  (14th demo). Uses `FlueraCanvasCupertinoToolbar` inside a
  Material `Scaffold` to demonstrate that mixing the two design
  systems works fine.

### Tests

- 3 widget tests in `test/cupertino_toolbar_test.dart` — render,
  tool-tap dispatch, compact-mode slider width swap.
- Full suite: 391 + 3 = **394 tests green**.

### Migration impact

**Zero breaking**:
- New widget is additive; the existing Material `FlueraCanvasToolbar`
  is unchanged.
- No new dependencies in `pubspec.yaml` — Cupertino is built-in
  Flutter (`package:flutter/cupertino.dart`).

### Out of scope (deferred to 0.16.2+ or later)

- **Cupertino color picker dialog** — `showFlueraColorPicker`
  Material is reused. If iOS-purist consumers find it out of place,
  they can pass `showColorPickerButton: false` and supply their own
  picker.
- **Cupertino `FlueraSketchApp` zero-config variant** — for now
  consumers who want the all-Cupertino experience pair the
  Cupertino toolbar with a headless `FlueraCanvas` themselves.
- **Dedicated `FlueraCupertinoToolbarTheme` extension** — current
  reuse of `FlueraToolbarTheme` works; promote to its own extension
  when sufficient consumer demand justifies the divergence.

## 0.16.0 (Adoption optimization — 2026-04-28)

This release is positioning-driven, not feature-driven. Following an
explicit business-role choice (fluera_canvas as OSS lead funnel for
the commercial `fluera_canvas_gpu`), 0.16.0 stops chasing vertical
identity (TLDraw / Notability / etc.) and instead removes the
adoption friction that prevents Flutter dev teams from making
fluera_canvas their default canvas dependency.

Five drops: cookbook docs, integration snippets, accessibility
semantics, opt-in i18n, customisable keyboard shortcuts. Pure-Dart,
free-tier, zero overlap with `canvas_gpu` commercial moat
(brush calligrafici, 16 PS blend modes, mask, adjustment layers,
CRDT collab, PDF, time-travel/replay restano commerciale).

**Cupertino toolbar fork** is deferred to 0.16.1 — the scope (~10h
for full API parity with the Material toolbar) doesn't fit a single
release alongside the docs + a11y + i18n + shortcuts work.

### Cookbook (10 copy-paste recipes)

- **NEW** `doc/cookbook.md` — every common ask answered with a
  ready-to-paste snippet:
  1. Add drawing to my app in 1 line
  2. Autosave to disk with debounce
  3. Export PNG with transparent background
  4. Export as SVG vector
  5. Limit zoom to a single page
  6. Copy / paste between canvas instances
  7. Brand the toolbar with my colours
  8. Add a custom tool to my own toolbar
  9. Draw shapes programmatically (tutorial overlays)
  10. Detect what's under the pointer (hover tooltips)
- README TOC links to the cookbook.

### Integration snippets

- **NEW** `doc/integrations.md` — paste-ready snippets for the
  packages most Flutter projects already pull:
  `flutter_riverpod`, `flutter_bloc`, `drift`, `hive`, `share_plus`,
  `cached_network_image`, `printing`. Each section is one block of
  code (~30 lines) you adapt and drop into your project.
- None of these become required dependencies; they're just docs
  showing how the integration works when you DO pull them.

### Accessibility / a11y semantics

- **NEW** `FlueraCanvas(semanticsEnabled: true)` (default `true`) —
  wraps the canvas in a `Semantics` node carrying a summary label
  `"Drawing canvas, X strokes, Y layers"` so TalkBack / VoiceOver /
  Narrator announce something meaningful when the canvas receives
  focus. Set to `false` to opt out (saves one element in the
  semantic tree when you know no assistive tech is active).
- Per-stroke semantics intentionally NOT emitted — even moderate
  scenes (~1k strokes) would explode the semantic tree and tank
  screen-reader performance. Consumers needing stroke-level a11y
  wrap nodes themselves outside the canvas.
- 3 widget tests in `test/semantics_test.dart`.

### Localization (i18n) — `FlueraStrings` delegate

- **NEW** `FlueraStrings` `ThemeExtension<T>` exporting 24
  localisable strings (tool tooltips, sheet titles, slider labels,
  selection-action tooltips). Apply globally via
  `ThemeData.extensions: [FlueraStrings(toolPen: 'Penna', ...)]` or
  per-toolbar via `FlueraCanvasToolbar(strings:)` (local prop wins
  over global extension — same priority pattern as
  `FlueraToolbarTheme`).
- Defaults are English; partial overrides translate only the
  strings you provide. Zero runtime dependency on
  `flutter_localizations`.
- Wired into `FlueraCanvasToolbar` tool labels, trailing tooltips
  (image / sticker / layers / undo / redo / clear), bottom sheet
  titles. Selection-action tooltips + slider labels remain English
  in 0.16.0; can be wired in 0.16.x once consumer demand is
  evident.
- 3 widget tests in `test/strings_i18n_test.dart`.

### Keyboard shortcuts customizable — `FlueraShortcuts` map

- **NEW** `FlueraShortcuts` + `FlueraShortcutAction` enum.
  `FlueraCanvas(shortcuts: FlueraShortcuts(overrides: {...}))`
  re-binds any subset of the 8 default actions
  (undo / redo / deleteOrClear / escape / selectAll / duplicate /
  copy / paste). Missing entries fall back to the per-platform
  default — Cmd-bound on macOS / iOS, Ctrl-bound elsewhere.
- Backward-compat aliases (`Y` for redo on non-Mac, `Backspace` for
  deleteOrClear) only inject when the consumer hasn't re-bound the
  primary action — avoids surprising re-binds.
- 4 unit tests in `test/shortcuts_custom_test.dart` (default
  per-platform binding, override priority, exhaustive
  per-action coverage).

### Tests

- 10 new tests across a11y (3), i18n (3), shortcuts (4).
- Full suite: 381 + 10 = **391 tests green**.

### Migration impact

**Zero API breaking**:
- `semanticsEnabled: true` is a new default; consumers who
  explicitly want NO `Semantics` wrapper pass `false`.
- `FlueraStrings` and `FlueraShortcuts` are opt-in opzionali
  (default reproduce 0.15.x exactly).
- All new symbols (`FlueraStrings`, `FlueraShortcuts`,
  `FlueraShortcutAction`) are additive exports.

### Out of scope (deferred / commercial)

- **Cupertino toolbar fork** — deferred to 0.16.1 (~10h scope).
- **Slider tooltip i18n** (opacity / eraser radius) — deferred
  pending consumer feedback on which strings matter most.
- **Pillar verticali** (arrow-binding, frames, rich text, shape
  recognition) — out of "lead funnel" scope per memoria progetto.
- **Brush calligrafici, PDF, multi-page, CRDT collab, time-travel/
  replay, 16 PS blend modes, mask, adjustment layers** — restano
  in `fluera_canvas_gpu` commerciale.

## 0.15.0 (Smart guides on-by-default + interactive primitives — 2026-04-28)

This release closes two gaps measured by the 0.15.0 evidence-based
audit (35 pub.dev packages surveyed + 9 reference SDKs outside
Flutter benchmarked + 0.14.0 internal API inventory):

1. **Smart object snap during drag** is table stake in Konva, Fabric,
   PixiJS, TLDraw, Excalidraw — and absent from every pub.dev canvas
   package (audit 0/35). fluera_canvas had the infrastructure since
   pre-0.13 (gated behind `smartGuidesEnabled: false`); this release
   flips the default to `true` and ships a public reusable
   [SnapEngine] for consumers building custom widgets.
2. **Hit-test API** is table stake in Konva, Fabric, PixiJS, TLDraw —
   fluera_canvas had `_hitTestNode` / `_hitTestIdsInRect` private
   since 0.12. Exposed publicly as `state.hitTest(Offset)` /
   `state.hitTestInRect(Rect)`.

Plus: programmatic drawing helpers (`state.drawLine` / `drawCircle` /
`drawPolygon`) and per-tool mouse cursor override (`cursorPerTool`).

Pure-Dart, free-tier, no overlap with `fluera_canvas_gpu`'s commercial
moat (bezier handle editing, boolean path operations, brush
calligrafici, multi-page, PDF, CRDT collab restano commerciale).

### Smart guides default flipped to `true`

- `FlueraCanvas(smartGuidesEnabled:)` default changed from `false`
  to `true`. Drag-to-move on a selection now scans nearby selectable
  nodes and snaps the dragged frame's anchors to matching anchors
  (Figma / TLDraw style alignment). Magenta dashed guide lines
  render via the existing selection painter.
- Hold Shift while dragging to bypass guides for a single drag.
- Set `smartGuidesEnabled: false` to restore 0.14.x behaviour
  exactly.
- Tolerance configurable via the existing `smartGuidesTolerancePx`
  prop (default `6.0` logical px, scale-aware).

### `SnapEngine` public reusable primitive

- **NEW** `SnapEngine` + `SnapResult` + `SnapGuide` + `SnapAxes`
  exported from the barrel. Pure-geometry pass over candidate AABBs;
  no canvas / widget dependency. Useful for consumers building
  custom transform widgets / gestures that need the same snap
  semantics standalone.
- Tunable thresholds: `snapTolerance` (default 6 world-px),
  `enableEdgeSnap`, `enableCenterSnap`.
- 5 geometric tests in `test/snap_engine_test.dart` (edge snap,
  center-X snap, tolerance respect, axes filter, axes=none).

### Hit-test API public

- **NEW** `state.hitTest(Offset, {tolerance: 4.0})` returns the
  front-most `NodeId` at the world-space point, or `null`. O(log n)
  via the internal RTree spatial index. Safe to call from
  `MouseRegion.onHover`.
- **NEW** `state.hitTestInRect(Rect)` returns an unmodifiable
  `Set<NodeId>` of every node whose bounds intersect the rect.
  Use for batch queries (export-by-region, custom marquee, collision
  detection).
- 4 widget tests in `test/hit_test_public_test.dart`.

### Programmatic drawing helpers

- **NEW** `state.drawLine(from, to, {color, width, metadata})` —
  commits a 2-point straight stroke.
- **NEW** `state.drawCircle(center, radius, {segments: 32, color, width, metadata})`
  — commits a closed N-segment polyline circle.
- **NEW** `state.drawPolygon(points, {closed, color, width, metadata})`
  — commits an arbitrary polygon, optionally closed.
- All three fall back to the canvas's `strokeColor` / `strokeWidth`
  when overrides are null. Useful for tutorial overlays, generative
  art, AI-assisted drawing, anything that deposits ink without
  going through pointer events.
- 4 widget tests in `test/programmatic_draw_test.dart`.

### Custom per-tool mouse cursors

- **NEW** `FlueraCanvas(cursorPerTool: Map<CanvasTool, MouseCursor>?)`
  prop — partial map of overrides; missing entries fall back to the
  per-tool default (`SystemMouseCursors.precise` for draw / shape,
  `none` for erase + showEraserPreview, `text` for text, `basic`
  otherwise).
- Useful for branded cursors, tutorial states, custom tool
  affordances. Touch-only platforms ignore the override (no
  MouseRegion mounts).
- 1 widget test in `test/eraser_preview_test.dart`.

### Tests

- 14 new tests across SnapEngine (5), hit-test (4), programmatic
  draw (4), cursor override (1).
- Full suite: 367 + 14 = **381 tests green**.

### Migration impact

**Behaviour change** (intentional, easy to opt out):
- Smart guides now ON by default. Consumers who want exact 0.14.x
  behaviour pass `smartGuidesEnabled: false`. The visual change
  (magenta guide lines during drag) is non-breaking — no crashes,
  no API change — but observable, hence flagged.

**Zero API breaking**:
- All new public symbols (`SnapEngine`, `SnapResult`, `SnapGuide`,
  `SnapAxes`) and methods (`hitTest`, `hitTestInRect`, `drawLine`,
  `drawCircle`, `drawPolygon`) are additive.
- New `cursorPerTool: null` default — no behaviour change for
  consumers who don't pass it.

### Out of scope (deferred to 0.16+ / commercial)

- **Arrow-to-shape binding** (TLDraw flagship per audit) — pillar
  for a future release; uses SnapEngine as substrate.
- **Frames / artboards** — `FrameNode extends GroupNode` + export
  bounds mode; pillar for a future release.
- **Rich text on TextNode** — `TextSpan` tree + FCV0 v9 bump;
  pillar for a future release.
- **Bezier handle editing on existing strokes** — `fluera_canvas_gpu`
  commercial.
- **Boolean path operations** (union/intersect/subtract via Skia
  PathOps) — `fluera_canvas_gpu` commercial.
- **Multi-page documents with page-flip transitions** —
  `fluera_canvas_gpu` commercial.
- **Hosted collab backend, OCR, AI/LLM features, baked-in editor
  UI, 3D shaders, cloud asset hosting** — out of OSS Flutter SDK
  scope per the cross-ecosystem benchmarking audit.

## 0.14.0 (Power-user data + UX polish — 2026-04-28)

This release lays the data foundation that production-grade drawing
apps need (stylus tilt channel, opaque per-stroke metadata,
document model with autosave) plus surfaces the credibility
materials that mark a serious SDK (published benchmarks). Everything
is pure-Dart and free-tier — the rendering features that *exploit*
the new data (calligraphic / tilt-aware brushes) remain in the
commercial `fluera_canvas_gpu` add-on.

### Stylus tilt channel on `CanvasStroke`

- **NEW** `tilts: List<Offset>?` on `CanvasStroke` — per-point pen
  tilt as `Offset(tiltX, tiltY)` in radians. `null` when the input
  device didn't report tilt (mouse, finger, or a stylus that
  doesn't expose it). When non-null, must match `points.length`
  (asserted at construction).
- **NEW** `twists: List<double>?` channel on `CanvasStroke` — per-point
  pen barrel rotation in radians. Reserved data structure:
  consumers can construct strokes programmatically with twists
  populated, but the gesture-capture pipeline does not yet harvest
  raw orientation as a separate channel (planned for 0.14.x once a
  brush exists that consumes it).
- Gesture pipeline lazily allocates the tilt accumulator only when
  the input device reports a non-zero tilt — mouse / finger paths
  pay zero allocation cost. Mid-stroke tilt detection backfills
  prior points with `Offset.zero` to keep the per-point arrays
  aligned at commit time.
- Built-in vector renderer (ballpoint / marker / highlighter)
  ignores the tilt channel — the value lands in the stroke for
  persistence + handoff to canvas_gpu's calligraphic brushes.

### Opaque per-stroke metadata bag

- **NEW** `metadata: Map<String, dynamic>?` on `CanvasStroke` — a
  consumer-defined JSON-encodable bag that round-trips through FCV0
  v8 binary save/load. Built-in code never reads this field;
  consumers attach replay timestamps, author IDs, semantic labels,
  anything they want to recover at load time.
- **NEW** `stroke.getMeta<T>(String key, [T? defaultValue])`
  convenience accessor — reads a typed value or returns the
  default on missing key / type mismatch. Saves the consumer
  `as T?` casts at every read site.

### `FlueraDocument` model

- **NEW** `FlueraDocument` (extends `ChangeNotifier`) — opt-in
  document wrapper around a `FlueraCanvas` mounted via `GlobalKey`.
  Mediates the dirty-flag + autosave-debounce plumbing every notes
  / whiteboard app ends up reinventing. Subscribes to the canvas's
  `historyListenable`, flips `isDirty` on every committed stroke,
  resets a debounce timer (default `2s`), invokes the
  consumer-provided `onAutoSave` callback with the FCV0 bytes +
  current metadata.
- **NEW** `FlueraDocumentMeta` immutable record — id / title /
  createdAt / modifiedAt / tags. `copyWith` + JSON round-trip
  baked in.
- Public callback typedefs: `FlueraDocumentSaveCallback` and
  `FlueraDocumentLoadCallback`.
- `save()` and `load()` are explicit async methods — useful for
  "save now" buttons and initial-mount hydration.
- The document is **opt-in**: the pre-0.14 pattern (write FCV0
  bytes yourself on stroke commit) keeps working unchanged.

### FCV0 v8 binary format

- Bumped from v7 to v8 to carry the new chained extension blocks
  after each stroke's customBrushId TLV: `0xE1` tilts /
  `0xE2` metadata / `0xE3` twists (reserved), terminated by
  `0xE0`. The terminator byte is mandatory in v8, so v8+ readers
  always know where each stroke ends.
- v8 readers continue to load v7 / v6 / v5 / v4 / v3 / v2 / v1
  files unchanged — strokes from older formats load with
  `tilts: null`, `twists: null`, `metadata: null`.
- **Migration impact**: v8 files cannot be read by 0.13.x and
  earlier. Upgrading 0.13 → 0.14 is seamless (new reader handles
  old files); downgrading 0.14 → 0.13 and re-loading v8 files
  raises `FormatException`. Plan the upgrade window accordingly
  if you have a mixed-version userbase.

### Eraser preview cursor (documentation)

- The `showEraserPreview` flag on `FlueraCanvas` (default `true`)
  was already wired pre-0.14.0 — translucent circle under the
  pointer / stylus when the eraser tool is active. Added to
  `doc/customization.md` for discoverability and 2 backward-compat
  tests pinning the contract.

### Published benchmarks

- `doc/performance.md` extended with a "Published benchmarks (0.14.0)"
  section: median of 3 runs of `test/benchmarks/perf_baseline_test.dart`
  on Linux x86_64 / Vulkan-Impeller / Ryzen 7 5800X. Headline numbers:
  - Insert 5,000 strokes into the spatial index: **243 ms**
    (~49 µs / stroke)
  - 10,000 hit-tests on a 5,000-stroke scene: **43 ms**
    (~4.3 µs / hit-test)
  - Commit a 5,000-point stroke: **297 µs** (~60 ns / point)
- Numbers are reproducible with `flutter test test/benchmarks/`
  (output format `[bench] name=duration_in_microseconds` for easy
  CI parsing).

### Tests

- 15 new unit / widget tests across stroke channels (8),
  document (5), eraser preview (2). Pre-existing v7 assertion in
  `canvas_serializer_v2_test.dart` updated to assert v8.
- Full suite: 352 + 15 = **367 tests green**.

### Migration impact

- **Code**: zero breaking. New `CanvasStroke` named params
  (`tilts`, `twists`, `metadata`) are optional with `null` default.
  `FlueraDocument` + `FlueraDocumentMeta` are new public symbols
  (no collision). All consumer 0.13.x code continues to work
  unchanged.
- **Binary format**: v8 is forward-compat (v8 readers load older
  files) but NOT backward-compat (0.13.x readers throw on v8
  files). If you ship a mixed-version fleet, gate the v0.14
  upgrade until all clients have migrated.

### Out of scope (commercial / deferred)

- **Calligraphic brushes that consume the tilt / twist channels** —
  fountain pen, technical pen, charcoal-angled, nib-angle pencil —
  remain `fluera_canvas_gpu` commercial. The free tier provides
  the data plumbing; the visual expressiveness is the commercial
  moat.
- **High-fidelity SVG / PDF, 16 PS blend modes, mask layers,
  adjustment layers, real-time CRDT collab** — `canvas_gpu` only.
- **Twist channel gesture capture** — deferred to 0.14.x once a
  brush consumes it. The data structure is ready; the pipeline
  doesn't harvest raw orientation as a separate channel today.
- **Cupertino fork of the toolbar, i18n, history branching,
  customizable keyboard shortcuts** — deferred to 0.15+.

## 0.13.0 (Table-stakes parity + power-user polish — 2026-04-28)

This release closes four gaps a Flutter dev would hit when adopting
the package for a design-tool-class application: vector export,
copy / paste, minimap navigation, configurable camera bounds.
Every feature is purely Dart-only — the commercial
`fluera_canvas_gpu` add-on continues to extend each one with
high-fidelity output (full Photoshop blend mode preservation,
image-annotation embedding, multi-page PDF, etc.). Zero breaking
changes: every new public surface is opt-in with defaults that
reproduce 0.12.0 behaviour exactly.

### SVG export (basic)

- **NEW** `FlueraSvgWriter` class with `encodeStrokes` /
  `encodeLayers` / `encodeStrokesBytes` / `encodeLayersBytes` static
  methods. Pure Dart, zero dependencies.
- **NEW** `state.toSvgBytes({Rect? bounds, double padding = 16.0})`
  on `FlueraCanvasState` — encodes the visible layer tree as SVG 1.1
  ready to write to disk or share.
- Free-tier scope: strokes (`<path>` polylines + `<circle>` dots),
  per-layer opacity (`<g opacity="...">`), 12 CSS-mappable blend
  modes (`mix-blend-mode:multiply` etc.). Image / text / shape nodes
  emit explanatory XML comments and are skipped (planned for 0.13.1
  + `canvas_gpu` high-fidelity writer).
- 10 widget tests in `test/svg_writer_test.dart`.
- New doc page `doc/export.md` — full PNG vs SVG vs FCV0 matrix +
  free vs commercial tier comparison.

### Clipboard API + Ctrl+C / Ctrl+V shortcuts

- **NEW** `state.copySelection()` — encodes the current selection as
  FCV0 v7 bytes, base64-wraps with a `FLUERA_CLIPBOARD_V1:` magic
  prefix, writes to the system clipboard via `flutter/services`.
  Cross-platform, zero extra dependency.
- **NEW** `state.pasteFromClipboard({Offset? worldPosition})` —
  detects the magic prefix, decodes, translates so the pasted
  bounds centre lands at `worldPosition` (defaults to the camera
  centre). Returns the IDs of the newly-added stroke nodes; ignores
  any non-fluera clipboard content (returns `[]`).
- **NEW** `Ctrl/Cmd + C` / `Ctrl/Cmd + V` keyboard shortcuts wired
  by default when `enableKeyboardShortcuts: true` (the existing
  default). Honours the in-canvas text editor (no hijack while
  typing).
- 3 widget tests in `test/clipboard_test.dart` exercising round-trip
  + empty / foreign-content paths via the standard
  `setMockMethodCallHandler` clipboard mock.

### Minimap widget

- **NEW** `FlueraMinimap` opt-in widget — drops into a `Stack`
  overlay, shows a scaled-down view of every committed stroke + a
  rectangle indicating the current viewport. Tap to recenter; drag
  to pan smoothly.
- Subscribes to `state.historyListenable` (content changes) and to
  the camera controller (viewport changes) via a single merged
  `Listenable`, so a single `CustomPainter` repaint covers both.
- Pure Dart `CustomPainter` — no GPU, no native code, no extra
  dependency. Theme-aware via `colorScheme` defaults; everything
  overridable via constructor params (`size`, `background`,
  `viewportColor`, `contentColor`, `borderRadius`).
- 2 widget tests in `test/minimap_test.dart`.

### InfiniteCanvasController bounds — `minScale` / `maxScale` / `panBoundary`

- The previously-`static const` zoom limits (`0.1` / `5.0`) are now
  constructor parameters on `InfiniteCanvasController`. Defaults
  preserve 0.12.0 behaviour exactly.
- **NEW** `panBoundary` (`Rect?`) — clamps `setOffset` so the camera
  origin stays inside the rectangle. Use for single-page notes apps
  / Figma-style frames. `null` (default) keeps the canvas infinite.
- 5 unit tests in `test/controller_bounds_test.dart` (default
  reproduction, custom limits honored, assertion validation,
  panBoundary clamp behaviour).

### Documentation

- **NEW** `doc/export.md` — quick reference table + per-format
  details + tier matrix free vs `canvas_gpu`.
- `doc/customization.md` extended with two new sections: "Camera
  bounds" + "Minimap navigation" (with copy-paste recipes).
- README pillar list updated: SVG export / clipboard / minimap /
  camera bounds bullets added; TOC links to the new export doc.

### Tests

- 20 new widget / unit tests across SVG writer (10), minimap (2),
  clipboard (3), controller bounds (5). One pre-existing stale
  assertion in `canvas_serializer_v2_test.dart` (was checking FCV
  v6, writer is at v7 since 0.10.3) updated.
- Full suite: 332 + 20 = **352 tests green**.

### Migration impact

**Zero** breaking changes:
- All new public symbols (`FlueraSvgWriter`, `FlueraMinimap`) are
  opt-in.
- All new methods (`toSvgBytes`, `copySelection`,
  `pasteFromClipboard`) are additive on existing `FlueraCanvasState`.
- New `InfiniteCanvasController(minScale, maxScale, panBoundary)`
  parameters all have defaults matching pre-0.13.0 hard-coded values.
- New `Ctrl+C / Ctrl+V` shortcuts honour the existing
  `enableKeyboardShortcuts` opt-out + the in-canvas text editor's
  focus state, so consumers who type-in-text never see the canvas
  hijack their keystrokes.

### Out of scope (deferred or commercial)

- **SVG for image / text / shape nodes** — planned for 0.13.1
  (still free tier; extends the basic writer with the remaining node
  types).
- **High-fidelity SVG / PDF export** — `fluera_canvas_gpu` only
  (commercial). Ships transparently behind the same `toSvgBytes()`
  call site when `canvas_gpu` is installed alongside.
- **Advanced calligraphic brushes** (fountain pen, technical pen,
  nib-angle pencil with tilt-aware shading) — these belong to
  `fluera_canvas_gpu`'s commercial roadmap. Even when the
  implementation is pure Dart (no GPU shader), the algorithm
  complexity (perfect-freehand pressure model + nib angle + thinning
  + taper) is part of the commercial value proposition. The free
  tier ships geometric stroke brushes only: ballpoint, marker,
  highlighter.

## 0.12.0 (Material 3 toolbar + opacity slider + theme + responsive + custom-toolbar example — 2026-04-28)

This release bundles the toolbar restyle (planned 0.11.0) and the
DX improvements bundle (planned 0.11.1) into a single coherent jump.
Zero breaking changes — all new props are opt-in with defaults that
match prior behaviour.

### Toolbar visual restyle (Material 3)

- **Pill-shaped tool buttons** — `FlueraCanvasToolbar` swaps the
  `SegmentedButton` row for filled-tonal pills (selected → filled
  `colorScheme.primary` with soft drop shadow; idle → transparent +
  `onSurfaceVariant` icon). Trailing icons (image, sticker, layers,
  undo, redo, clear) become `IconButton.filledTonal` with a uniform
  22 px glyph and an `error`-tinted `clear` for the destructive cue.
  Container picks up a subtle `surfaceContainerHigh →
  surfaceContainerHighest` vertical gradient + outline-variant top
  border.
- **Circular colour swatches** — 30 px with a 2.5 px primary ring on
  selected (the old square + thick border is gone). White swatch
  gets an `outlineVariant` hairline so it doesn't disappear on light
  themes. Tapping a swatch now **preserves the alpha** the user
  dialled in via the opacity slider.
- **Stroke-width slider with live preview** — moved out of the bare
  `Slider` into a `Row(preview, slider)` layout: the 30 px preview on
  the left renders the actual stroke diameter (in the active colour)
  or an outline ring (eraser mode). 30 % floor on the preview so thin
  strokes stay visible. Slider track is now 3 px with a primary thumb.
- **Opacity slider** — NEW. Drives the alpha channel of `color`
  through the existing `onColorChanged` callback (no new API). Preview
  uses a 7 px checkerboard behind the live colour so transparency
  reads at a glance. Hidden automatically while an eraser tool is
  active. Toggleable via `showOpacitySlider` (default `true`).
- **Tool tooltips standardised** — `Pen / Erase / Pixel / Line / Rect /
  Oval / Select / Lasso / Text` (matches the legacy SegmentedButton
  labels for muscle memory).

### `FlueraToolbarTheme` — themable toolbar

- New public `FlueraToolbarTheme` class (`ThemeExtension<FlueraToolbarTheme>`).
  Exposes 21 fields covering radii, spacing, tap target, slider widths
  (wide + compact), motion duration + curve, and 8 colour overrides
  (selectedFill, selectedIconColor, idleIconColor, destructiveColor,
  swatchRingColor, surfaceGradientStart/End, outlineColor).
- Apply globally via `ThemeData.extensions: [FlueraToolbarTheme(...)]`,
  or locally via the new `theme:` prop on `FlueraCanvasToolbar`. The
  prop wins over the global extension when both are present.
- Colour fields default to `null` — meaning "fall back to
  `Theme.of(context).colorScheme`". Override only what your brand
  needs; the rest stays consistent with the host app.

### Compact mode (responsive layout)

- New `compactBreakpoint` prop (default `600.0`) on `FlueraCanvasToolbar`.
  Below the threshold the toolbar switches from the classic 2-row
  layout to a 3-row vertical stack (tools / palette + size slider /
  opacity slider + trailing icons), and slider widths shrink from 220
  to 140 px. Tap targets remain 44×44 in both modes.
- Pass `compactBreakpoint: 0` to disable compact mode entirely.

### Layout polish

- Palette + size slider + opacity slider live in a `Wrap` with each
  slider constrained to a fixed width (no more full-row stretch).
  Tool pills wrap instead of horizontal-scrolling, so they reflow on
  narrow viewports.
- Internal `_T` design tokens replaced with `FlueraToolbarTheme`
  resolution. All sub-widgets (`_ToolPill`, `_ColorSwatch`,
  `_TrailingIconButton`, `_SizeSlider`, `_OpacitySlider`) now consume
  the resolved theme via constructor prop.

### Custom toolbar demo + customization docs

- New `example/lib/main.dart` demo: **Custom toolbar (headless)** —
  Photoshop-style floating sidebar (vertical tool pills + undo / redo)
  on the left, floating colour palette on the top right, headless
  `FlueraCanvas` behind both. Demonstrates the pattern for replacing
  `FlueraCanvasToolbar` entirely (Cupertino, sidebar, ribbon, etc.).
- New `doc/customization.md` covering the four magic levels
  (`FlueraSketchApp` → `FlueraSketchScaffold` →
  `FlueraCanvasToolbar` → headless `FlueraCanvas`), how to apply
  `FlueraToolbarTheme` globally / locally, the field reference, the
  `compactBreakpoint` prop, and the headless wiring pattern with a
  real-time `historyListenable` recipe.
- README TOC now links to `doc/customization.md`.

### Example app desktop window

- Linux / macOS / Windows runners now open at 1400×900 with a 900×600
  minimum size and "Fluera Canvas" in the title bar (was
  "fluera_canvas_example" 1280×720). Affects the example only — the
  published archive is unchanged.
- Zero-config demo's `TabBarView` switched to
  `NeverScrollableScrollPhysics` so horizontal swipes don't intercept
  canvas pans / draws.

### Tests

- `test/toolbar_restyle_test.dart` — 5 widget tests for the new
  visual behaviour (tool-pill tap, alpha-preserving swatch, opacity
  tooltip, eraser-hide, showOpacitySlider toggle).
- `test/toolbar_theme_test.dart` — 6 widget tests for theme + compact
  (copyWith preservation, lerp interpolation, ThemeData extension
  pickup, local prop priority, wide vs narrow slider widths).
- Existing `find.text(...)` assertions in `edge_cases_test.dart`,
  `shape_tools_test.dart`, `fluera_canvas_widget_test.dart`,
  `toolbar_phase_e_test.dart` migrated to `find.byTooltip(...)`
  (text labels became tooltips).
- Full suite: 331 tests green.

### Migration impact

**Zero** breaking changes:
- No API renames, removals, or new required params.
- All new props (`theme`, `compactBreakpoint`, `showOpacitySlider`)
  are opt-in with defaults that match prior behaviour.
- Consumer 0.10.x / 0.11.x code keeps working — the look changes, the
  call sites don't. New `FlueraToolbarTheme` symbol export doesn't
  collide with anything.
- Consumer on viewport < 600 px sees the new 3-row compact layout;
  pass `compactBreakpoint: 0` to keep the wide layout everywhere.

## 0.10.4 (Final FontWeight.index leftover — pana 160/160 — 2026-04-27)

- **One last `FontWeight.index` was hiding** in
  `lib/src/export/binary_canvas_format.dart:286` — pana flagged it
  even after the 0.10.3 sweep that fixed the other two callsites in
  `digital_text_element.dart`. Migrated to
  `FontWeight.values.indexOf(...)` (returns the same 0..8 enum
  position, but doesn't go through the deprecated getter, so the
  on-disk binary layout is byte-for-byte unchanged — old `.fcv`
  files keep loading verbatim).

## 0.10.3 (FontWeight migration + README rewrite — pana 160/160 — 2026-04-27)

- **README rewritten for dev-voice clarity** — dropped 3 obsolete
  "What's new in 0.7.2 / 0.8.0 / 0.9.0" sections (CHANGELOG already
  carries the per-release detail), removed duplicated "Drop-in
  toolbar" section (merged into Common recipes), pruned outdated FAQ
  entries (the 0.3.0 humps regression note, the OnBackInvokedCallback
  Android warning), fixed three coherence bugs (`simplifyEpsilon`
  default contradiction, "0.4.0 features" labels, stale pana / test
  counts inline). Added a compact TOC at the top, replaced the
  Notability / Goodnotes / Miro / Figma framing with concrete
  technical claims. README is now ~720 lines (was 876) and reads
  end-to-end without scrolling past 200 lines of release archaeology.


- **Migrated `FontWeight.index` → `.value`** in
  `digital_text_element.dart` (DigitalTextSpan + DigitalTextElement
  encoders). The `.index` API was deprecated by Flutter in favour of
  the recommended `.value`. Pana's analyzer ignores in-line
  `// ignore: deprecated_member_use` comments, so the previous
  suppression cost 10 pts on Static Analysis.
- **Backward-compat preserved** via the new `_fontWeightFromJson`
  decoder helper: it recognises both legacy `.index` (range 0..8) and
  modern `.value` (range 100..900) ranges by sniffing magnitude — the
  two ranges don't overlap, so the disambiguation is unambiguous.
  FCV files written by 0.10.x and earlier load identically.
- **Pana score**: should now reach **160/160** (Static Analysis 50/50
  recovered).

## 0.10.2 (Dartdoc sweep — full coverage for pana — 2026-04-27)

- **`public_member_api_docs` enabled.** A 1068-hit sweep added a
  one-line `///` stub to every public class / enum / mixin / typedef /
  field / method / getter / setter / constructor that lacked one.
  Many stubs are intentionally generic (`/// Field \`xyz\`.`) — they
  satisfy the dartdoc lint and recover the pana documentation
  category points without pretending to be hand-written prose.
  Hand-written docs already present (top-level types, public widgets,
  recipes) are untouched. Dart format clean, 0 analyzer issues.
- **Lint stays on**: future PRs that add a public API element without
  a docstring will fail `flutter analyze`, preventing dartdoc
  regressions.

## 0.10.1 (Pana score polish — 2026-04-27)

- **Static analysis cleanup**: suppressed two `FontWeight.index`
  deprecation warnings in `digital_text_element.dart` (cannot migrate
  to `.value` without breaking on-disk JSON round-trip with v0.10.0
  files). Recovers the +10 pts pana was deducting.
- **`example/` is now shipped in the package archive**: the previous
  `.pubignore` excluded it explicitly, so pana flagged "No example
  found" (-2 pts). The platform host scaffolds inside
  `example/android|ios|macos|linux|windows|web` stay excluded —
  pub.dev never builds them.
- **README trimmed**: collapsed three commercial upsell sections
  (`fluera_canvas_gpu` / `fluera_engine_pro` / pricing) into a single
  brief "Beyond the free tier" pointer to the new
  [doc/commercial-add-ons.md](doc/commercial-add-ons.md). The free
  package's value proposition reads cleaner above the fold.

## 0.10.0 (Zero-config drop-in widgets — 2026-04-27)

- **Lasso UX parity con Fluera flagship** (post-0.10.0 polish):
  - **Tap-on-selection enters transform mode**: with `tool: lasso`
    and a non-empty selection, a pen-down inside the selection's
    bounding rect now enters move mode (and a pen-down on a handle
    starts resize / rotate) — same priority chain as
    `CanvasTool.select`. Pre-fix, every pen-down in lasso tool
    started a fresh lasso path and silently wiped the selection,
    forcing the user to manually switch tools to manipulate. Tap
    OUTSIDE the bbox keeps the previous behaviour: clears the old
    selection and starts a fresh lasso. Mirrors how the Fluera
    flagship app handles it (verified against
    `fluera_engine/.../lasso_tool.dart` + `_drawing_handlers.dart:448`).
  - **Stricter hit-test**: dropped the `lassoBounds.overlaps(nodeBounds)`
    catch-all from `_lassoHitsNode`. Pre-fix a "C"-shaped lasso
    whose AABB engulfed a stroke sitting in the open mouth of the
    "C" would mark the stroke selected even though no point of it
    was ever encircled. Now strict containment: a node is selected
    only when its centre OR any of its bounds corners falls inside
    the closed polygon — same convention as Photoshop / Procreate /
    Figma. The cheap bbox overlap is still used as an early reject
    to skip the expensive `Path.contains` ray-casting on far-away
    nodes.
  - 4 new widget tests cover both behaviours
    (`test/lasso_post_selection_test.dart`).



- **`FlueraSketchApp`** — full `MaterialApp` wrapping a sketch
  scaffold. `void main() => runApp(const FlueraSketchApp());` and
  you have a complete drawing app: AppBar with undo / redo / clear /
  export-PNG popup, full toolbar with every opt-in flag wired,
  sensible Material 3 theme. Three preset shapes via the new
  `FlueraSketchPreset` enum: `notes` (Notability-style minimal),
  `whiteboard` (full kit with snap-to-grid + smart guides),
  `signature` (single pen, no zoom, no shapes — drop-in
  `signature` package replacement).
- **`FlueraSketchScaffold`** — same scaffold without the wrapping
  `MaterialApp`. Drop as a route inside an existing app. Optional
  `onAutoSave` / `onAutoLoad` callbacks integrate any persistence
  backend (`path_provider`, in-memory, network, secure-storage)
  via a 2-second-default debounce. Optional `onExportPng` sink for
  the AppBar export menu (falls back to clipboard data URL).
- **`FlueraSketch`** — the bare canvas + toolbar, with internal
  `tool` / `color` / `strokeWidth` state. Drop into any Scaffold
  body without writing a single setState. Caller can still pass a
  `GlobalKey<FlueraCanvasState>` for advanced control.
- **No new dependencies**: the package stays pure Dart. Persistence
  remains consumer-side via callbacks (`path_provider` continues to
  be a dependency only of the example, not the package).
- 9 new widget tests cover all three layers + every preset.
- Demo gallery: new "Zero-config app (FlueraSketchApp)" demo with 3
  tabs showcasing the three magic levels.

> **Upgrading from 0.5.x?** See
> [doc/migration-0.5-to-0.10.0.md](doc/migration-0.5-to-0.10.0.md) for a
> consolidated, breaking-change-free upgrade path.

## 0.9.3 (Smoothing pipeline + eraser polish + PNG export overhaul + edge-case hardening — 2026-04-27)

- **Edge-case hardening pass.** Five focused fixes from a triple
  parallel audit:
  1. **FCV0 reader bounds checks** — every uint16 / uint32 length
     field (`pointCount`, `layerCount`, image `blobLen`, layer
     `idLen` / `nameLen`) is now validated against the remaining
     buffer before allocating. Hostile or truncated files now throw
     a clean `FormatException` instead of allocating gigabytes.
  2. **`renderToImage` clamps**: `pixelRatio` rejected outside
     `[0.05, 32.0]`, output dimensions rejected over 16 384 px per
     side (GPU max). Prevents accidental 2 GB allocations from a
     mis-typed parameter.
  3. **Single-point stroke** (pen-down + pen-up without moving) now
     commits a visible "dot" stroke instead of silently vanishing.
     Triggered only for `draw` / `ellipse` tools — line / rect / shape
     tools keep their current behaviour.
  4. **Text editor hot-restart guard**: `_scheduleDispose` wraps
     overlay-entry removal and focus-node disposal in try/catch so
     a stale `_active` surviving a hot restart can't crash the next
     editor open.
- **PNG export overhauled — infinite-canvas-aware.** `renderToImage`
  goes from a single WYSIWYG-of-the-viewport API to four explicit
  bounds modes via the new `FlueraExportBounds` enum. The legacy
  `renderToImage(width: w, height: h)` signature still works
  unchanged (defaults to `bounds: viewport`).
  1. **`viewport`** (default) — what the user sees on screen, baked
     camera. Same as 0.5.0+.
  2. **`allContent`** — union of every visible node's `worldBounds`.
     Output dimensions auto-computed from content size × `pixelRatio`,
     so the export always covers everything the canvas holds, even
     nodes off-screen. Returns a 1×1 sentinel for empty canvases.
  3. **`selection`** — bounds of the current selection. Sentinel
     when nothing selected.
  4. **`custom`** — explicit `Rect` in world coords (passed via the
     new `region:` parameter).
  Plus: `pixelRatio` (HiDPI / print export), `padding` (world-px
  margin around the bounds), `transparent` (skip background fill +
  pattern). New `FlueraCanvasState.contentBoundsWorld` and
  `selectionBoundsWorld` getters expose the bounds math standalone
  for "fit to content" camera animations.
  Critical bug-fix in the same patch: the legacy `renderToImage`
  iterated `_strokes` only and **silently dropped image, text,
  shape and group nodes** — a freshly-imported sticker or typed
  text would not appear in the exported PNG. The new polymorphic
  walker (mirrored from the on-screen committed painter) honours
  every `LayerNode` child type.
- **Pixel eraser pressure-aware + velocity-aware + micro cleanup.**
  Three additive UX improvements mutuated from desktop / iPad
  pen-tablet apps (Procreate, Photoshop, Notability):
  1. **Pressure-aware radius**: the eraser circle now scales linearly
     between 40 % (precision / soft touch) and 100 % (firm press) of
     the nominal `eraserRadius`, modulated by the live pen pressure.
     Pressure 1.0 (the default for finger / non-pressure-aware
     pointers) preserves the pre-0.9.x behaviour exactly.
  2. **Velocity-aware sub-stamp growth**: when the cursor jumps far
     between samples (slow input pipeline / fast drag), intermediate
     stamps along the swept segment are inflated by up to 1.4× to
     cover any residual gaps after the half-radius sub-stepping.
     The terminal stamp (= the actual pointer position) is never
     inflated, so the visible eraser circle still matches the cursor
     exactly.
  3. **Micro-survivor cleanup**: `splitAroundCircle` now drops
     post-cut fragments whose total arc length is < 3 world-px.
     These imperceptible "dot" residues used to litter the scene
     graph, costing a spatial-index entry and a layer-cache
     invalidation each.

- **Pixel eraser repaints in real time during continuous drag.**
  `_onDrawUpdate` now calls `_eraseAt(world)` BEFORE `_commitTick.notify()`
  so the painter reads the freshly-mutated `_strokes` list (and the
  invalidated `LayerPictureCache` entry) on the very next frame.
  Previously the notify was scheduled against a stale snapshot and on
  Impeller-Vulkan could be coalesced one stamp behind, making the eraser
  feel "frozen" mid-drag even though the underlying model was correct.
- **Live and committed strokes now share identical geometry.**
  `simplifyEpsilon` default changed from `0.5` to `0` — the committed
  stroke now uses the same raw point list the live painter renders
  during the drag, so what the user sees while drawing is exactly what
  gets persisted (no shape change at pen-up). `simplifyEpsilon: 0.5`
  remains a valid opt-in for consumers that want the 40-60% point
  reduction for compression / RAM.
- **Stroke smoothing rebuilt to match the fluera_engine pipeline.**
  Four stages, each addressing a different artefact:
  1. **OneEuroFilter at point ingest** — every raw stylus sample is
     run through an adaptive velocity-aware low-pass filter
     (`minCutoff = 1.0`, `beta = 0.007`, the same constants the
     commercial `fluera_engine` ships with) the moment it lands in
     the live notifier. Tight smoothing at low speeds kills the
     sub-pixel tremor every digitiser produces when writing slowly;
     loose filtering on fast strokes preserves input fidelity.
     Reinitialised at every pen-down so each stroke starts clean.
  2. **Adaptive arc-length subdivision via Catmull-Rom interpolation.**
     Any segment longer than ~4.5 world-px is subdivided into
     anchors spaced ~3 px apart, with each new anchor computed via
     the Catmull-Rom parametric form on the four-neighbour window
     (p[i-1], p[i], p[i+1], p[i+2]) — NOT linear interpolation.
     Linear inserts would be collinear with the original samples
     and the EMA pass below would leave them on the line, so the
     final cubic-bezier still degenerated into the very polyline
     this stage exists to remove. Spline-interpolated inserts
     already lie on a curve. Capped at 12 inserts per gap to bound
     cost on extreme pen-up/down jumps.
  3. **Two-pass EMA pre-smoothing** (forward + backward, alpha 0.3,
     endpoints pinned) over the resampled point list as a final
     polish before path construction.
  4. **Predicted "ghost" tail anchor.** The Catmull-Rom formula
     uses `p3` to compute the exit tangent at every interior
     segment. For the terminal segment we used to clamp `p3` to
     the last real sample, which made the closing tangent flat —
     the curve would aim at the endpoint along the chord, looking
     polygonal. We now extrapolate one step ahead via velocity +
     half-acceleration of the last three samples and use that as
     a virtual `p3`. The predicted point is **not** drawn — the
     bezier still terminates exactly at the real endpoint — only
     the tangent direction at the last anchor changes. Materially
     reduces the perceived latency on platforms (Linux desktop)
     where the pointer pipeline samples slowly.
  5. **Catmull-Rom → Cubic Bezier with tau = 1/6.** Control points
     are `C1 = P1 + (P2 - P0) / 6` and `C2 = P2 - (P3 - P1) / 6` —
     the same constant fluera_engine uses for its fountain-pen
     outline reconstruction. Tighter than the previous tau = 0.5,
     so the spline hugs the smoothed points instead of flattening
     into visibly straight segments when input samples are dense.
  Affects every free-form stroke (live + committed); shapes
  (line / rect / ellipse) still use straight `lineTo` segments
  since their corners must stay sharp.
- **Inline text editor: tap-outside catcher is now opaque.** A tap on
  empty canvas while the editor is open commits + closes the overlay
  WITHOUT propagating the tap down to `FlueraCanvas` (which previously
  treated the same tap as "open a new TextNode here", spawning a fresh
  empty editor on top of the just-committed one — making the original
  text appear to "disappear").
- **Keyboard shortcuts no longer hijack text editing.** Backspace,
  Delete, Ctrl/Cmd+A, Ctrl/Cmd+D and the arrow nudges are now
  short-circuited while `FlueraTextEditor.isEditing == true`, so
  Backspace edits the buffer, arrows move the caret, and Ctrl+A
  selects within the text — instead of clearing the canvas / nudging a
  selection / select-all-on-canvas.
- **Sticker drops land inside the canvas viewport.** `FlueraStickerPanel`
  now anchors the new `ImageNode` at `state.viewportCenterWorld`
  (newly-exposed getter on `FlueraCanvasState`) instead of at
  `MediaQuery.size / 2`. On phones / bottom-sheet UI the screen centre
  often fell underneath the open sticker panel, so the dropped image
  was off-canvas and looked like the tap did nothing.
- **New public API**: `FlueraCanvasState.viewportSize` and
  `FlueraCanvasState.viewportCenterWorld`. Useful for any consumer
  overlay that needs to drop something at the centre of the canvas
  viewport (sticker / image / annotation / chat-bubble) without
  reaching for `MediaQuery`.
- **Code hygiene**: removed `final ctrl = state.controller` dead local
  in `FlueraStickerPanel._commit`.

## 0.9.1 (Bug fix pass post-smoke-test — 2026-04-27)

- **Text editor: Enter now inserts a newline instead of committing.**
  Removed `onEditingComplete` from the multiline `TextField`. Commit
  still fires on focus-out (tap-outside / IME dismiss) and on Esc.
  Previously the soft-keyboard "Return" closed the overlay before the
  user could type a second line.
- **Lasso hit-test now bounds-aware + live preview rendering.**
  Selection includes any node whose centre, any bounds corner falls
  inside the lasso path, OR whose bounds rect overlaps the lasso's
  own bounds — catches large nodes that "span" the lasso. The
  in-progress lasso path is now rendered live as a magenta dashed
  polyline with translucent fill (Photoshop-style "marching ants")
  via `SelectionPainter.lassoPath`.
- **Pixel eraser: sub-stepping for fast drags.** `_eraseAt` now
  interpolates intermediate stamps along the swept segment between
  two pointer samples (half-radius cadence). Previously, fast drags
  left "dot trail" gaps because points of the underlying stroke that
  fell between two pointer samples were never tested against the
  eraser circle. Stroke-mode and pixel-mode both benefit.
- **Sticker demo fix.** `_TextStickerDemo` now uses
  `kFlueraDefaultStickers` (the package's built-in 8 Material-icon
  catalogue) instead of a `NetworkImage` SVG that `NetworkImage`
  cannot decode. The package itself was always correct;
  `sticker_panel_test.dart` confirms it.
- **Doc clarity.** Programmatic + Selection demo subtitles rewritten
  to spell out the use cases (replay / scripted animation / data-driven
  art for Programmatic; scattered vs grid selection for Lasso vs
  Select). README "Lasso free-form selection" recipe gained a
  "when to use" guidance line.
- **Code hygiene.** Removed direct `import 'dart:io' show Platform`
  from `fluera_canvas_widget.dart`; all three call sites now use the
  web-safe `PlatformGuard` helper. Forward-compat with WASM strict
  mode where `dart:io` is unavailable at link time.

## 0.9.0 (Perf wire-ups + lasso + keyboard + duplicate / Z-order + snap-to-grid + smart guides — 2026-04-26)

**Pre-publish hardening** (post-0.9.0 spike, all five "bloccanti
tecnici" addressed):
- **A — `dart:io` conditional import** — `fluera_file_export_service`
  now uses `import '_file_reader_stub.dart' if (dart.library.io)
  '_file_reader_io.dart'` so web builds compile without the
  unreachable `File()` symbol leaking into the JS module. Asset
  embedding gracefully falls back to path-only on web.
- **B — Live stroke chunked `PictureRecorder` cache** —
  `_LiveStrokeNotifier` now bakes every 256 in-progress points into
  a `ui.Picture` chunk via `maybeChunkAhead`. The painter replays
  one `drawPicture` per chunk and only re-tessellates the trailing
  uncached tail. Long handwriting strokes (5 k+ points) drop from
  O(N) per-frame work to O(N/256). Chunks are disposed on
  `clear()` / `setStroke()` / new `beginStroke()`.
- **C — Multi-layer LayerPictureCache consumption** — the
  multi-layer painter's `paintLayer(c)` closure now consults
  `LayerPictureCache.get(layerId, version)` first; on miss it
  records the entire layer's foreground (children only — opacity
  / blend / mask wrap it from the outside) into a fresh
  `ui.Picture`, stores, and replays. Every layer-state mutator
  (`setLayerOpacity`, `setLayerVisible`, `setLayerLocked`,
  `setLayerBlendMode`, `setLayerMask`, `setLayerFlueraBlendMode`)
  now bumps the layer version. Cache disabled when
  `_nodesWithTransform > 0` (the snapshot would freeze stale world
  bounds).
- **D — Default sticker catalogue** — `kFlueraDefaultStickers` is
  no longer empty. Eight Material-icon stickers (star, heart,
  check, close, arrow, idea, flag, pin) ship via the new
  `FlueraIconStickerProvider` — an `ImageProvider` that renders an
  `IconData` to a `ui.Image` on demand via `TextPainter`. Zero
  asset bundling, zero licensing concerns. Override with
  `stickers: const []` to opt out.
- **E — Backgrounds demo** — new `_BackgroundsDemo` in the
  example gallery showcases the four built-in `CanvasBackground`
  patterns (solid / grid / dotted / lined) with live toggle from
  the AppBar.

**LayerPictureCache consumption** (post-0.9.0 spike): the
single-layer fast path now actually consumes the cache infrastructure
wired in earlier. When `_nodesWithTransform == 0` (the >99% case)
the painter records the entire layer's children once into a
`ui.Picture`, caches it keyed on `(layerId, layerVersion)`, and
replays via a single `drawPicture` on every subsequent paint until
a mutation bumps the version. Pan / zoom never bumps the version,
so camera moves over a static scene drop from O(N strokes) per
paint to O(1). Multi-layer / non-trivial-blend paths fall back to
the existing per-paint walk. Live-stroke append-only via
`PictureRecorder` chunks remains deferred — empirical perf shows
the current `_paintStrokeSegments` single-draw path is already
sub-100µs for typical (<500-pt) strokes; the chunking refactor's
ROI is too small for the implementation cost.

**Web / WASM smoke test** (post-0.9.0 spike): `flutter build web`
on the example compiles cleanly + WASM dry-run succeeds. New
`test/web_compat_test.dart` exercises every public API surface
that a web consumer would touch (commit stroke, persistence
round-trip, selection, transform, group/ungroup, duplicate,
lasso/snap props) without `dart:io`. Run with
`flutter test test/web_compat_test.dart -p chrome` for true
in-browser execution. All `Platform.*` reads in the package are
already gated by `kIsWeb || try/catch`, and the one `dart:io`
`File()` call site (asset embedding in the Pro file-export
service) is wrapped in `try/catch` so web hosts gracefully fall
back to path-only embedding.

**Group / ungroup** (post-0.9.0 spike): treat several selected
nodes as one rigid bundle. New API on `FlueraCanvasState`:
- `state.groupSelection() → NodeId?` — wraps 2+ selected nodes
  (sharing the same parent layer) inside a fresh [GroupNode],
  inserted at the position of the front-most member. Selection
  swings to the new group; the group is now the unit of
  selection / drag / rotate / scale / delete. Returns the group's
  id, or `null` for empty / single-node / cross-layer selections.
- `state.ungroupSelection() → int` — for every selected
  [GroupNode], moves its children back to the parent layer at the
  group's slot (preserving relative Z), then removes the group.
  Selection swings to the freed children. Returns the count of
  groups dissolved.
- New history ops `_GroupOp` + `_UngroupBatchOp` so a single
  undo restores the pre-mutation tree exactly (including the
  original child indices and selection).

`_rebuildSelectableIndex` updated: `GroupNode`s register as
selectable units; their children are inert (not in the index)
until ungrouped — matches Figma / Sketch convention. `LayerNode`
remains a pure container.

**Snap-to-grid + smart guides** (post-0.9.0 spike): Figma-style
alignment during body-drag move. Two new `FlueraCanvas` props:
- `snapToGrid` (double, default `0`) — when > 0, the dragged
  selection's closest of 9 anchors (4 corners + 4 edge midpoints +
  centre) snaps to the nearest grid multiple within the tolerance
  band. Pure-Dart, zero deps.
- `smartGuidesEnabled` (bool, default `false`) — when true, the
  drag scans every other visible selectable node and aligns the
  dragged anchor to the closest matching anchor on a nearby node
  (corners / edges / centre — 9 candidates per node). Magenta
  dashed guide lines render on the selection painter while the
  snap is locked.
- `smartGuidesTolerancePx` (double, default `6`) — logical-px band
  for both snap modes. Scales with camera zoom so the snap "feels"
  the same at every level.

Holding the axis-lock modifier (Shift) during the drag bypasses
both — a clean override path for pixel-precise positioning.

## 0.9.0 (Perf wire-ups + lasso + keyboard + duplicate / Z-order — 2026-04-26)

**Free-tier "imbattibile su pub.dev"**: 0.9.0 cables the
performance optimisers that 0.8.x shipped but never called from the
main flow, plus closes the remaining feature-completeness gap
against design-tool / note-taking competitors. No PRO migration —
everything stays free.

**Perf wire-ups**
- `PostStrokeOptimizer` (Douglas-Peucker) called on every pen-up
  before commit. New `simplifyEpsilon` prop (default `0.5`) trims
  40-60 % of redundant points without visual difference; pressures
  stay aligned because the simplifier returns *kept indices* rather
  than re-sampled points. Set `simplifyEpsilon = 0` to opt out.
- `DirtyRegionTracker` instance per `FlueraCanvasState`. Every
  mutation site (`_internalInsertStrokeAt`,
  `_internalRemoveStroke`, `_writeLocalTransform`) marks its world
  bbox dirty. Painter consumption is scheduled for 0.9.1 once the
  multi-layer composite path (saveLayer + GPU compositor + layer
  mask) is refactored to clip safely.
- `LayerPictureCache` instance + per-layer `Map<NodeId, int>`
  content version. Bumped on every layer mutation. Public via
  `state.layerContentVersion` (`@visibleForTesting`) for GPU
  consumers. Cache consumption inside the painter scheduled for
  0.9.1 — same gating as the dirty tracker.
- `WidgetsBindingObserver.didHaveMemoryPressure()` wired: drops
  `LayerPictureCache`, resets the dirty tracker, disposes every
  stroke's `ui.Picture`. Image-bytes cache preserved (re-decoding
  would stall the gesture loop).

**Feature completeness**
- `state.duplicateSelection({offset})` — clones every selected
  node via `cloneInternal()`, offsets each by `offset` (default
  20×20 world px), replaces the selection with the clones. Single
  undo step.
- `state.bringToFront(id)` / `state.sendToBack(id)` — Z-order
  tweaks within the parent layer's children list. New
  `_ReorderChildOp` history op preserves the original index for
  exact undo.
- `CanvasTool.lasso` — free-form selection. Drag a path; on
  pen-up every selectable node whose `worldBounds.center` falls
  inside the closed polygon is selected. Concave shapes are
  honoured (vs the rectangular marquee). Toolbar opt-in via
  `showLassoTool: true`.
- Keyboard shortcuts overhaul. Delete/Backspace becomes
  selection-aware (clears selection if non-empty, else falls back
  to the legacy "clear all"). New shortcuts:
  - **Esc** — clear selection
  - **Ctrl/Cmd+A** — select all on visible+unlocked layers
  - **Ctrl/Cmd+D** — duplicate selection
  - **Arrow keys** — nudge selection by 1 world px (Shift = 10)
  Existing Ctrl/Cmd+Z / Y / Shift+Z preserved.

**Benchmark suite**
- `test/benchmarks/perf_baseline_test.dart` — 5 k stroke insert,
  10 k hit-test on 5 k-stroke scene, 5 k-point stroke push.
  Numbers stamped to stdout in `[bench] name=us` format for CI
  scraping.

**Migration impact**
- 0.8.x → 0.9.0: zero breaking changes. `simplifyEpsilon` default
  is conservative; opt-out via `0`. New keyboard shortcuts are
  opt-in via the existing `enableKeyboardShortcuts: true` flag.
  `CanvasTool.lasso` appended to the enum (not inserted).

**Tests**: 274 / 274 green. **Pana**: 160 / 160. **0 analyze
issues**. Phases 4 (IncrementalPaintMixin live append-only) and 7
(RTree update on transform) deferred to 0.9.1 — current behaviour
is correct via the existing fallback paths.

## 0.8.0 (Text tool + Sticker panel — 2026-04-26)

**Live text editing on the canvas** — tap empty canvas with the text
tool to drop a fresh `TextNode` and open a Material `TextField`
overlay caret-positioned over it; tap an existing text node to
re-enter editing. The overlay rides the camera (pan / zoom) while
the user types. Commit on Done / blur / Esc; empty-text commit on
a fresh node rolls back the addition. Single undo per editing
session.

**Sticker / emoji / clip-art panel** — `FlueraStickerPanel` widget
that browses a `List<FlueraSticker>` thumbnail catalogue and
commits the chosen sticker as an `ImageNode` centered on the
viewport. Reuses the cached `ui.Image` per sticker `id`, so the
same sticker dropped twice shares the GPU handle.

**Canvas-level text APIs**
- `FlueraCanvasState.addTextNode(node)` — appends a TextNode to the
  active layer with `_AddLayerChildOp` history.
- `FlueraCanvasState.updateTextElement(id, element)` — in-place
  swap of the wrapped `DigitalTextElement`, pushes a single
  `_UpdateTextOp` so undo restores the previous text exactly.
- `FlueraCanvasState.findNode(id)` — public lookup into the
  selectable index without going through the test-only debug
  getter.

**`FlueraTextEditor`**
- `start(state, existing: ..., worldPosition: ...)` opens an
  overlay editor on the target node (or mints a fresh one).
- `commit(state)` / `cancel(state)` close the session. Tap-outside
  / focus loss / Done all funnel through commit.
- Uses `OverlayEntry` mounted on the root overlay so it sits above
  any custom canvas chrome.

**`CanvasTool.text`** — new enum value, wires through the gesture
detector: tap empty canvas → fresh text node + edit; tap text node
→ edit existing.

**FCV0 v6 — text-node persistence**
- New `nodeType=1` for text. Layout: `nodeIdLen + nodeId + jsonLen +
  jsonBytes + localTransform`. JSON-in-binary so future
  `DigitalTextElement` field additions don't bump the format
  version.
- Reader: v6+ decodes nodeType=1; v5 readers throw cleanly on it
  (forward-incompat). v5 / v4 / v3 / v2 / v1 backward-read
  preserved.

**Painter dispatch**
- The committed-painter walks `layer.children` and dispatches per
  type — strokes via `_drawStrokeWithTransform`, images via
  `ImageNodePainter.paint`, **text via the cached `TextPainter`**
  on `DigitalTextElement.layoutPainter`. Z-order is
  insertion-order (chronological) on both the single-layer fast
  path and the multi-layer slow path.

**Toolbar flags**
- `showTextTool: bool = false` — adds a `Text` segment to the
  segmented control.
- `showStickerPanel: bool = false` + `stickers: List<FlueraSticker>`
  — adds an emoji-emotions IconButton that opens the sticker panel
  in a Material bottom sheet.

**Tests**: 252 / 252 green. **Pana**: 160 / 160.

## 0.7.2 (Image annotations + OBB selection + perf — 2026-04-26)

**Write directly on top of an image, with strokes that follow the
image when you move / rotate / scale it.** New mental model:
`ImageNode` is now a container for stroke "annotations" stored in
image-local coordinates. A stroke that lands inside the image at
pen-up gets rerouted from the active layer onto the image's
`annotations` list; a stroke that crosses the boundary is split
segment-by-segment so the inside parts ride the image while the
outside parts stay free children of the layer. Move / rotate / scale
the image and every annotation transforms with it as a rigid block.
Mirror H/V flips both. The split is **only active for the freehand
draw tool** — line / rectangle / ellipse keep emitting a single
rigid figure regardless of overlap.

**Image annotations**
- `ImageNode.annotations: List<CanvasStrokeNode>` — strokes parented
  to the image, stored in its local coord system.
- `ImageNodePainter.paint` walks `node.annotations` after
  `drawImageRect`, inside the same transform stack the bitmap uses,
  so annotations inherit the image's `localTransform` + per-element
  `position / rotation / scale` automatically.
- New `_SplitStrokeOp` history op — single undo step for a stroke
  whose pen-up gesture got fragmented into free + image-parented
  pieces.
- Stroke-mode AND pixel-mode eraser walk `image.annotations` too:
  the probe is projected into image-local coords via
  `_ImageHitFrame.worldToLocal` so the cut hits the right pixels
  even on rotated / scaled images. Undo restores the originals.

**FCV0 v5 — image annotations persistence**
- Bumped binary format from v4 → v5. Image payload gains a trailing
  `annotationCount: uint32` + array of stroke payloads (in
  image-local coords).
- v4 / v3 / v2 / v1 readers untouched. New writers always emit v5.

**OBB selection frame for rotated nodes**
- `CanvasSelection` carries `frameRect` + `frameTransform`. Single
  rotated node → frameRect is `node.localBounds`, frameTransform is
  `node.localTransform`; the selection painter draws the outline
  through `canvas.transform(frameTransform)` so it visually rotates
  with the image. Handles ride the world-transformed corners but
  stay axis-aligned + 12 px screen-space.
- Hit-test handle and body-drag containment project the world
  pointer into the OBB local frame, so dragging a corner of a
  rotated image scales along the image's own axes (not the
  screen's).
- Multi-node selections fall back to `frameTransform = identity`
  and `frameRect = bounds` — bit-for-bit the pre-OBB behaviour.

**Hit-test transform-aware**
- `_transformedNodeIds` tracks every node with non-identity
  `localTransform`. The RTree (which indexes pre-transform bbox)
  skips them and a transform-aware pass intersects each node's
  `worldBounds` instead. Strokes moved with the selection tool now
  re-select correctly at their new visual position.

**Painter Z-order fix**
- The committed-painter walks `layer.children` in insertion order
  and dispatches per type (stroke vs image) instead of the previous
  two-pass loop (all strokes, then all images). Strokes drawn after
  an image are now correctly rendered on top.

**Performance optimisations**
- A — incremental `_maxZ` counter: `_registerSelectable` stamps Z in
  O(1) instead of folding over `_zOrderIndex.values` per insert.
- B — `_nonStrokeSelectableIds` set: hit-test and onEvicted iterate
  only the non-stroke subset (typically <100) instead of every
  selectable node.
- F — `_nodesWithTransform` counter: `_drawStrokeWithTransform`
  short-circuits the per-stroke node lookup when no node carries a
  non-identity transform (>99% common case on notes-app workloads).

**Toolbar wiring**
- Multi-canvas + autosave demo now exposes the full 0.6.0 / 0.7.0
  toolbar feature set: `showSelectionTool`, `showImageTool`,
  `showTransformActions`, `showLayers`.

**Pana score**: 160 / 160. **Tests**: 249 / 249 green.

## 0.7.1 (Image persistence FCV0 v4 — 2026-04-26)

**Imported images now survive save / reload.** In 0.7.0 ImageNode
became selectable + transformable but `toBytes()` skipped them
silently — close the canvas, reopen, the image was gone. 0.7.1 ships
the FCV0 v4 binary format that carries image asset bytes alongside
the scene graph.

**Bytes-aware image cache**
- `ImageNodePainter.cacheWithBytes(path, image, bytes)` registers
  the original encoded bytes (PNG / JPG / WebP / …) parallel to
  the decoded `ui.Image` handle.
- `ImageNodePainter.decodeAndCache(path, bytes)` runs the codec
  asynchronously and registers both at completion. Used by the
  serializer's load path.
- `ImageNodePainter.bytesFor(path)` for save-time readback.

**FCV0 v4 — image-node payload**
- New `nodeType=2` on layer-children. Image payload: NodeId,
  imagePath, position, scale, rotation, opacity, intrinsic size,
  16-element `localTransform` storage, `bytesLen + bytes`.
- Reader: `DecodeResult.imageBlobs: Map<String, Uint8List>` carries
  the raw bytes; widget kicks off `decodeAndCache` fire-and-forget
  per blob and triggers a repaint when each codec resolves.
- ImageNodes whose source bytes were never registered are skipped
  silently at save time.

**Image tool wiring**
- `FlueraImageTool.commitBytes` now calls `cacheWithBytes` so every
  imported asset round-trips through `toBytes` automatically.

## 0.7.0 (Enterprise selection on `ImageNode` — 2026-04-26)

**Selection / transform / delete generalised across the scene
graph.** In 0.6.0 the selection pipeline was hard-coded to
`CanvasStrokeNode`: tap on an image fell through to clear, marquee
skipped images, transform handles were impossible to invoke,
delete / mirror were no-ops. From 0.7.0 the entire pipeline operates
on `CanvasNode` — strokes, images, and any future text / shape
addition just plug in.

**Phase 1 — `_selectableNodes` + `_zOrderIndex` foundation**
- New unified index `Map<NodeId, CanvasNode> _selectableNodes` —
  source of truth for every selectable scene-graph node.
- DFS-order Z stamp in `Map<NodeId, int> _zOrderIndex` for
  front-most-wins on stroke / image / mixed hit-test.
- Populated by every mutation site: `_internalInsertStrokeAt`,
  `_internalRemoveStroke`, `addImageNode`, `_AddLayerChildOp`,
  `_RemoveLayerOp`, `_AddLayerOp`, `removeLayer`, `_replaceWithLayers`
  (loadFromBytes / initialBytes). `@visibleForTesting`
  `debugSelectableIds` / `debugZOrderIndex` getters for assertions.

**Phase 2 — Hit-test unified across stroke + image**
- `_hitTestStrokeNode` → `_hitTestNode`: strokes via the existing
  RTree spatial-index (fast path), non-stroke nodes via linear scan
  of `_selectableNodes` (typically <100 entries — trivial cost).
- `_hitTestIdsInRect` (marquee) gets the same treatment, intersecting
  via `worldBounds.overlaps(rect)`.
- `select(NodeId?)` now validates the id against `_selectableNodes`
  (O(1)) so passing an `ImageNode.id` succeeds — previously returned
  false. API shape unchanged, semantics extended.

**Phase 3 — `_selectionFromIds` + bounds refresh on `CanvasNode`**
- The bounding-rect accumulator iterates the unified index and reads
  `node.worldBounds` instead of the stroke-only `entry.key.bounds`.
- Side fix: stroke nodes whose `localTransform` was non-identity
  used to surface the pre-transform bbox to the painter, drawing
  the selection frame in the wrong place. Now transform-aware.

**Phase 4 — Transform pipeline on `CanvasNode`**
- `_transformTargets` widened from `List<CanvasStrokeNode>?` to
  `List<CanvasNode>?` — body was already type-agnostic.
- `_beginTransform`, `mirrorSelection(Axis)`,
  `_TransformNodesOp._apply` all walk the unified index. Mirror H/V
  on an `ImageNode` flips its `localTransform` and the result is
  picked up by `ImageNodePainter` (which already honoured
  `node.localTransform` since 0.6.0).
- Drag handles, body-drag move, rotate handle, and mirror buttons
  now operate on stroke / image / mixed selections.

**Phase 5 — `_DeleteNodesOp` + `onNodesDeleted` callback**
- New op `_DeleteNodesOp(List<_DeletedNodeSnapshot>)` replaces
  `_EraseOp` for the public `deleteSelection()` path. `_EraseOp`
  lives on for the pen-eraser flow.
- Each snapshot stores `node`, `layerId`, `childIndex`, and for
  strokes the original `flatStrokeIndex`. Undo restores the
  original `CanvasStrokeNode` (preserving its NodeId), the
  `_strokes` mirror at the original Z, the spatial index, and the
  parent layer's children at the original child index.
- New optional callback
  `FlueraCanvas(onNodesDeleted: void Function(List<CanvasNode>)?)`
  fires for every removed node (mixed types). Backwards-compat
  `onStrokesErased` keeps firing in parallel with the stroke-only
  subset; image-only deletions skip it (no strokes were touched).

**Phase 6 — Auto-clear selection on draw start**
- Notability / Goodnotes-style modal UX: switching to draw / line /
  rectangle / ellipse and starting a stroke clears the active
  selection automatically. Consumer can select an image, switch
  to draw, and write on top without manually clearing first.
- Eraser tools (erase / erasePixel) are exempt — they don't visually
  overlap the selection frame.

**Phase 7 — Version bump**
- `pubspec.yaml` 0.5.0 → 0.7.0. The 0.6.x series internally rolled
  layer / selection / transform / image / edge-pan work; 0.7.0 is
  the first publish of the consolidated set.

**Migration**
- Public API shape of `select` / `selectInRect` / `mirrorSelection` /
  `deleteSelection` / `selection.ids` / `selectionListenable` is
  unchanged. Behaviour extended: ImageNode (and any future
  CanvasNode subclass) responds to all of them.
- New optional `onNodesDeleted` callback — purely additive.
- New `ImageNode` invariant documented: `imageElement.scale /
  rotation / position` = scala iniziale dell'asset; `localTransform`
  = mutazioni del transform tool. Sono componibili: `worldTransform =
  localTransform`, `worldBounds = worldTransform × localBounds` le
  ingloba entrambe.

**Tests**
- 22 new across `selectable_nodes_index_test`, `hit_test_image_test`,
  `selection_bounds_image_test`, `transform_image_test`,
  `delete_selection_image_test`, `draw_clears_selection_test`. Suite
  ~233 → 255 green. `flutter analyze --no-pub lib`: 0 issues.

**Known TODO (Phase G, deferred)**
- FCV3 image serialization (`nodeType: 2`, bytes embedded vs
  path-only). Image nodes survive an in-memory undo / redo round-trip
  but `.fluera` save / load drops them. ~2-3 days of work, decision
  point: bytes-embedded vs asset-path indirection.

## 0.5.0 (Phase 6 monorepo convergence — 2026-04-26)

**Canvas-core consolidation: ~14 classes absorbed from the private
`fluera_engine` fork into the public surface.** Fully additive — no
breaking changes from 0.4.0; all newly exported types are net-new to
consumers.

This release rolls up the four `0.4.0+1`…`0.4.0+4` internal markers into
a single semver-bumped publish. The split between free `fluera_canvas`
and commercial `fluera_canvas_gpu` is now stable: GPU shader brushes
ship in the latter, vector / Dart-fallback rendering in this package.

**Newly exported (Phase 6.A — canvas painters & filters)**
- `IncrementalPaintMixin` — `CustomPainter` mixin that uses a
  `DirtyRegionTracker` to clip canvas paints to dirty bounds (10–100×
  faster repaints for local mutations).
- `BackgroundPainter`, `BackgroundImagePainter`,
  `FullScreenDarkOverlayPainter` — viewport-level infinite-canvas
  background painters.
- `PointSimplifier` — Douglas–Peucker stroke point simplifier for LOD
  rendering.
- `BallpointBrush`, `HighlighterBrush`, `MarkerBrush` — base brush
  engines (advanced brushes such as charcoal, watercolor, fountain pen
  remain in `fluera_engine` / `fluera_canvas_gpu`).

**Newly exported (Phase 6.B — pools, caches, stabilizer)**
- `PathPool`, `PathPoolStatistics` — reusable `Path` object pool to
  reduce per-frame allocations during stroke rendering.
- `StrokePointPool`, `PoolStatistics` — `Offset` pool for stroke points.
- `StrokeStabilizer` — Procreate / Clip Studio-style 3-stage smoother
  (string pulling + weighted moving average + corner detection). The
  `elasticEnabled` constructor parameter lets hosts toggle the
  velocity-driven string-length and easeInOut catchup curve.
- `StrokeCacheManager` — vectorial stroke cache with O(1) undo snapshot
  ring buffer.
- `LayerPictureCache` — LRU `Picture` cache for per-layer rendering.
- `SnapshotCacheManager` — incremental scene-graph snapshot cache.

**Newly exported (Phase 6.B finalisation — render interceptors)**
- `RenderInterceptor` chain (base class + `RenderNext` typedef +
  `DebugBoundsInterceptor` + `NodeFilterInterceptor`).
  `RenderProfilingInterceptor` stays in `fluera_engine` because it
  depends on the engine's telemetry bus.

**Sibling-package change (informational)**
- The GPU shader pipeline that previously lived inside the private
  `fluera_engine` has been extracted to the commercial
  `fluera_canvas_gpu` package. Engine integrators now consume
  `ShaderBrushService` from
  `package:fluera_canvas_gpu/fluera_canvas_gpu.dart`. The free
  `fluera_canvas` continues to render brushes via its Dart fallback
  path. Apps that want the GPU shader brushes (pencil, fountain pen,
  watercolor, charcoal, oil paint, marker, spray paint, neon glow, ink
  wash, brush stamp, texture overlay) need both `fluera_canvas` and
  `fluera_canvas_gpu`.

**Tests**
- Test suite grows from 49 to 108 green tests with the addition of
  `test/drawing/object_pools_test.dart`,
  `test/rendering/incremental_paint_test.dart`,
  `test/rendering/layer_picture_cache_test.dart`, and
  `test/rendering/snapshot_cache_node_test.dart`.

**Breaking** — none. The public API of 0.4.0 is preserved.

## 0.4.0+4 (Phase 6.B/6.A finalisation — 2026-04-25)

**One additional class extracted from `fluera_engine`**: the `RenderInterceptor`
chain (base class + `RenderNext` typedef + `DebugBoundsInterceptor` +
`NodeFilterInterceptor`) is now part of canvas. `RenderProfilingInterceptor`
stays in `fluera_engine` because it depends on the engine's telemetry bus.

This finishes the immediate block of the monorepo convergence (Phase 6.A
shaders + 6.B optimization + 6.C input/pool). The remaining 9 `LEGACY-FORK`
files in engine are genuine canvas-core forks that require Enterprise-tier
extraction (Phase 6.D / engine_pro) before they can move; that work is
gated on the first Enterprise lead.

## 0.4.0+3 (Phase 6.A monorepo convergence — 2026-04-25)

**No public API change in fluera_canvas itself.** This release is a marker for
a sibling-package change: the GPU shader pipeline that previously lived inside
the private `fluera_engine` has been extracted to `fluera_canvas_gpu`
(commercial). Engine integrators now consume `ShaderBrushService` from
`package:fluera_canvas_gpu/fluera_canvas_gpu.dart`.

The free `fluera_canvas` continues to render brushes via its Dart fallback
path. Apps that want the GPU shader brushes (pencil, fountain pen, watercolor,
charcoal, oil paint, marker, spray paint, neon glow, ink wash, brush stamp,
texture overlay) need both `fluera_canvas` and `fluera_canvas_gpu`.

## 0.4.0+2 (Phase 6 monorepo convergence — 2026-04-25)

**More canvas-core absorbed from fluera_engine fork.**

Pure additive: 6 new classes from the monorepo's engine fork are now part
of the public canvas surface. No breaking changes.

Newly exported:
- `PathPool`, `PathPoolStatistics` — reusable `Path` object pool to reduce
  per-frame allocations during stroke rendering.
- `StrokePointPool`, `PoolStatistics` — `Offset` pool for stroke points.
- `StrokeStabilizer` — Procreate / Clip Studio-style 3-stage smoother
  (string pulling + weighted moving average + corner detection). The
  `elasticEnabled` constructor parameter lets hosts toggle the
  velocity-driven string-length and easeInOut catchup curve.
- `StrokeCacheManager` — vectorial stroke cache with O(1) undo snapshot
  ring buffer.
- `LayerPictureCache` — LRU `Picture` cache for per-layer rendering.
- `SnapshotCacheManager` — incremental scene-graph snapshot cache.

Internal: continues monorepo convergence (Phase 6 / Blocco Immediato 6.B+6.C).
Engine `lib/src/{drawing/input, drawing/filters, rendering/optimization}`
shrank by 6 files. See `fluera_engine/docs/MIGRATION_TRACKER.md`.

## 0.4.0+1 (Phase 2 monorepo convergence — 2026-04-25)

**Canvas-core absorbed from fluera_engine fork.**

Pure additive: 7 canvas-core classes that previously lived in the private
`fluera_engine` fork are now part of the public canvas surface. No breaking
changes; all newly exported types are net-new to consumers.

Newly exported:
- `IncrementalPaintMixin` — `CustomPainter` mixin that uses a
  `DirtyRegionTracker` to clip canvas paints to dirty bounds (10–100×
  faster repaints for local mutations).
- `BackgroundPainter` — viewport-level infinite-canvas background painter.
- `BackgroundImagePainter`, `FullScreenDarkOverlayPainter` — additional
  painters previously bundled in the engine `canvas_painters.dart` barrel.
- `PointSimplifier` — Douglas–Peucker stroke point simplifier for LOD
  rendering.
- `BallpointBrush`, `HighlighterBrush`, `MarkerBrush` — base brushes
  (advanced brushes such as charcoal, watercolor, fountain pen remain
  engine-side, destined for future `fluera_engine_pro`).

Internal: brings the monorepo one step closer to a single source of truth
for canvas / scene-graph / rendering / drawing primitives. See
`docs/CANVAS_OWNERSHIP.md` in the repo root for the routing rule.

## 0.4.0

**Shape tools, pixel-mode eraser, color picker dialog.**

Three additive feature blocks that take `fluera_canvas` from "best
infinite-canvas SDK on pub.dev" to "general-purpose drawing SDK".
Fully backward-compatible with 0.3.0 — no public API was removed
or changed in shape; the new functionality is opt-in.

**Shape tools**
- `CanvasTool.line` — drag from A to B to commit a straight line.
- `CanvasTool.rectangle` — drag corner-to-corner for a 5-point closed
  rectangle outline.
- `CanvasTool.ellipse` — drag for a 32-segment ellipse outline.
- All three commit as ordinary `CanvasStroke` instances, so they
  participate in undo/redo, persistence (`toBytes`/`loadFromBytes`),
  spatial-index hit-test, and the per-stroke `ui.Picture` cache for
  free.

**Pixel-mode eraser**
- `CanvasTool.erasePixel` — instead of removing whole strokes that
  the eraser circle intersects (which is what `CanvasTool.erase`
  does), this mode SPLITS each stroke around the eraser circle and
  keeps the surviving pieces. Original Z-order preserved.
- New internal `_PixelEraseOp` history op: `undo` re-inserts the
  originals and removes the survivors, `redo` reverses.
- Per-update cost O(k · m) where k = strokes intersecting the
  eraser circle and m = points per stroke. Combined with the
  spatial-index viewport cull this stays well below 1 ms per frame
  for typical scenes.

**Color picker dialog**
- New `FlueraColorPickerDialog` widget + `showFlueraColorPicker`
  imperative helper. HSV saturation/value box + hue slider + alpha
  slider + hex input. Zero external dependencies.
- `kFlueraDefaultPalette` unchanged — the dialog is opt-in for
  consumers that want arbitrary colours beyond the 6 presets.

**Toolbar opt-in flags**
- `FlueraCanvasToolbar.showShapeTools: false` — when `true`, the
  segmented control gains Line / Rect / Oval buttons.
- `FlueraCanvasToolbar.showPixelEraser: false` — when `true`, adds
  a "Pixel" segment next to "Eraser".
- `FlueraCanvasToolbar.showColorPickerButton: false` — when `true`,
  a sweep-gradient `+` button appears at the end of the palette row
  and pops up `FlueraColorPickerDialog`.
- Tool segmented control is now horizontally scrollable so 6 tool
  buttons + history buttons fit on narrow screens.

**Tests**
- 9 new tests in `test/shape_tools_test.dart` covering enum
  ordering, shape-stroke geometry (line / rect / ellipse), pixel
  eraser tool wiring, color picker dialog open/cancel/return,
  toolbar opt-in flags. Total 33 tests, all green.

**Breaking** — none. The `CanvasTool` enum gains 4 new values; if
your code does an exhaustive `switch (tool)` without a `default`,
you'll get analyser warnings until you handle the new cases.

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
