# Export — PNG, SVG, FCV0

This guide covers the three formats `fluera_canvas` writes today, what
each preserves, and which features stay reserved for the commercial
[`fluera_canvas_gpu`](https://pub.dev/packages/fluera_canvas_gpu)
add-on. Every API on this page is in the free tier.

## Quick reference

| Format | Method | Tier | Best for |
|---|---|---|---|
| **PNG** | `state.renderToImage(...)` | free | What you see is what you ship — flat raster, all features preserved |
| **SVG** (basic) | `state.toSvgBytes()` | free | Geometry-only vector — strokes, layers, opacity, 12 CSS-mappable blend modes |
| **FCV0** (binary) | `state.toBytes()` | free | Lossless save / load round-trip — every feature, including image annotations |
| **SVG** (high-fidelity) | same `state.toSvgBytes()` (auto-upgraded) | `canvas_gpu` | All 16 Photoshop blend modes, vector text on path, image annotations as inline raster |
| **PDF** (annotation + export) | `state.toPdfBytes()` | `canvas_gpu` | Multi-page documents with PDF/A-2u compliance |

The `toSvgBytes()` method is the same call for both tiers — installing
`canvas_gpu` transparently upgrades the writer through the public
extension point. Your application code stays identical.

## PNG — flat raster

```dart
final image = await state.renderToImage(
  bounds: FlueraExportBounds.allContent,  // union of every visible node
  pixelRatio: 2.0,                        // HiDPI / print
  padding: 24,                            // world-px margin
);
final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
    .buffer.asUint8List();
```

**Bounds modes:**
- `viewport` — WYSIWYG of the on-screen view (requires `width` / `height`)
- `allContent` — auto-sized union of every visible node (default)
- `selection` — only the currently-selected nodes
- `custom` — explicit world-space `Rect` via `region:`

Pair any mode with `transparent: true` to skip the background fill
and get a real alpha channel.

## SVG (basic, 0.13.0+) — geometry-only vector

```dart
final svgBytes = state.toSvgBytes();
await File('drawing.svg').writeAsBytes(svgBytes);
```

Or use the lower-level API directly when you have a stroke list in
hand without a full canvas state:

```dart
final svgString = FlueraSvgWriter.encodeStrokes(myStrokes);
```

**What's preserved (free tier):**
- Strokes — emitted as `<path d="M x y L x y...">` polylines
- Single-point strokes — degenerate to `<circle>`
- Stroke colour + width + alpha (alpha via `opacity`)
- Per-layer opacity — emitted on the `<g>` wrapper
- 12 CSS-mappable blend modes — `multiply`, `screen`, `overlay`,
  `darken`, `lighten`, `color-dodge`, `color-burn`, `difference`,
  `exclusion`, `hard-light`, `soft-light`, plus the implicit `normal`
- Hidden layers (`isVisible: false`) skipped entirely

**What's NOT preserved (free tier — falls back gracefully):**
- Image annotations — emit an XML comment placeholder; use PNG export
  for image-bearing scenes, or install `canvas_gpu` for inline raster
- Text nodes — same (planned for 0.13.1)
- Shape nodes (line/rect/ellipse) — same (planned for 0.13.1)
- The 4 Photoshop blend modes (hue, saturation, color, luminosity) —
  these have no SVG mapping; require `canvas_gpu`'s extended writer
- Mask layers, adjustment layers, vector text on path — `canvas_gpu`

## FCV0 — lossless binary round-trip

```dart
// Save
final bytes = state.toBytes();
await File('drawing.fcv').writeAsBytes(bytes);

// Load
final loaded = await File('drawing.fcv').readAsBytes();
state.loadFromBytes(loaded);
```

FCV0 v7 preserves **everything** the canvas knows about — strokes,
shapes, text nodes, image annotations, layer hierarchy, opacity,
blend modes (all 26 including the Photoshop set), even the alpha
channel of image annotations. The format is forward-compatible: v6 /
v5 / v4 / v3 / v2 / v1 readers continue to load via the same
`loadFromBytes` entry point.

For **selection-scoped** snapshots (cut / copy across canvas
instances) the same encoder powers the new clipboard API:

```dart
// Copy selection to system clipboard (writes FCV0 base64 + magic prefix).
await state.copySelection();

// Paste back (returns the IDs of the newly-added nodes).
final newIds = await state.pasteFromClipboard();
```

`Ctrl+C` / `Ctrl+V` (or `⌘+C` / `⌘+V` on macOS) are wired by default
when `enableKeyboardShortcuts: true` (the default).

## When to use which

- **Save / restore your user's work** → FCV0. Lossless, compact, fast.
- **Share to social / embed in a doc / generate a thumbnail** → PNG.
  All features preserved as raster.
- **Hand off to a vector editor (Inkscape / Illustrator / Figma) for
  post-processing** → SVG basic. Geometry survives the round-trip.
- **Production design tool with full Photoshop fidelity** →
  install `canvas_gpu` for high-fidelity SVG + PDF. Same call sites,
  better output.

## Tier matrix

| Feature | free `fluera_canvas` | commercial `fluera_canvas_gpu` |
|---|---|---|
| PNG export | ✅ all features | ✅ same |
| FCV0 save / load | ✅ every node type | ✅ same |
| SVG strokes | ✅ | ✅ |
| SVG layer opacity + 12 blend modes | ✅ | ✅ |
| SVG shapes (line/rect/ellipse) | 🟡 0.13.1 | ✅ |
| SVG text on canvas | 🟡 0.13.1 | ✅ vector text on path |
| SVG image annotations | ❌ skipped | ✅ inline raster |
| SVG all 16 PS blend modes | ❌ subset | ✅ full set |
| SVG mask + adjustment layers | ❌ | ✅ |
| PDF export (multi-page) | ❌ | ✅ PDF/A-2u |
| PDF annotation editing | ❌ | ✅ |

`fluera_canvas` is the **free SDK**. `fluera_canvas_gpu` is a
**commercial** add-on that plugs in transparently — no API change in
your application, just install the extra dependency and your existing
`toSvgBytes()` / `toPdfBytes()` calls get the high-fidelity writer.
