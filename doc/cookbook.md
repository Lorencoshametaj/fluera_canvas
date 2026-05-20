# Cookbook — 10 copy-paste recipes

Ten common asks every Flutter dev hits when integrating
`fluera_canvas`. Each recipe is one snippet you can drop into your
codebase and adapt. For deeper customization, see
[customization.md](customization.md); for the full export matrix,
see [export.md](export.md).

## 1. Add drawing to my app in 1 line

The shortest path: `FlueraSketchApp` is a complete, ready-to-run
drawing app — toolbar, autosave-friendly callbacks, Material 3
chrome, every feature wired.

```dart
import 'package:flutter/material.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

void main() => runApp(const FlueraSketchApp());
```

Pick a preset to scope the toolbar to your use case:
- `FlueraSketchPreset.notes` — pen + eraser only, lined paper.
- `FlueraSketchPreset.whiteboard` — full kit (default).
- `FlueraSketchPreset.signature` — single-pad signature shape.

```dart
runApp(const FlueraSketchApp(preset: FlueraSketchPreset.notes));
```

**Notes**: the app picks `useMaterial3: true` automatically. To
embed in your existing app shell instead of `runApp`, drop down a
level to `FlueraSketchScaffold` (page-level) or `FlueraSketch`
(widget-level).

## 2. Autosave to disk with debounce

Use `FlueraDocument` for the dirty-flag + debounce plumbing.
Persist FCV0 v8 binary bytes via `path_provider`.

```dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:path_provider/path_provider.dart';

class _NotePageState extends State<NotePage> {
  final canvasKey = GlobalKey<FlueraCanvasState>();
  late final FlueraDocument doc;

  @override
  void initState() {
    super.initState();
    doc = FlueraDocument(
      canvasKey: canvasKey,
      meta: const FlueraDocumentMeta(id: 'note-42', title: 'My note'),
      autosaveDebounce: const Duration(seconds: 2),
      onAutoSave: (bytes, meta) async {
        final dir = await getApplicationDocumentsDirectory();
        await File('${dir.path}/${meta.id}.fcv').writeAsBytes(bytes);
      },
      onAutoLoad: () async {
        final dir = await getApplicationDocumentsDirectory();
        final f = File('${dir.path}/note-42.fcv');
        if (!f.existsSync()) return null;
        return (bytes: await f.readAsBytes(), meta: doc.meta);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      doc.wire();
      doc.load();
    });
  }

  @override
  void dispose() { doc.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext c) => Scaffold(
    body: FlueraCanvas(key: canvasKey),
  );
}
```

**Notes**:
- `autosaveDebounce` is reset on every stroke commit; rapid drawing
  won't spam disk writes.
- `doc.save()` forces an immediate save (useful for "Save" buttons).
- The FCV0 v8 format is forward-compat: v8 readers load v7 / v6 / v5
  files unchanged.

## 3. Export the canvas as PNG with transparent background

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:fluera_canvas/fluera_canvas.dart';

Future<Uint8List> exportPng(FlueraCanvasState state) async {
  final image = await state.renderToImage(
    bounds: FlueraExportBounds.allContent,  // union of every visible node
    pixelRatio: 2.0,                         // HiDPI / print
    padding: 24,                             // world-px margin
    transparent: true,                       // skip background fill
  );
  final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
      .buffer.asUint8List();
  image.dispose();
  return png;
}
```

**Notes**: `bounds` modes — `viewport` (legacy WYSIWYG), `allContent`,
`selection`, `custom`. Pair `transparent: true` with any mode for
real alpha output.

## 4. Export as SVG vector

```dart
import 'dart:io';
import 'package:fluera_canvas/fluera_canvas.dart';

Future<void> exportSvg(FlueraCanvasState state, File out) async {
  final svgBytes = state.toSvgBytes();
  await out.writeAsBytes(svgBytes);
}
```

**Notes**: free-tier SVG covers strokes + per-layer opacity + 12
CSS-mappable blend modes. Image annotations / text / shapes
emit XML comments and are skipped (use PNG for raster scenes, or
install `fluera_canvas_gpu` for high-fidelity SVG with full
preservation). See [export.md](export.md) for the full matrix.

## 5. Limit zoom to a single page

```dart
import 'package:fluera_canvas/fluera_canvas.dart';

final controller = InfiniteCanvasController(
  minScale: 0.5,                                    // can't zoom out past 50%
  maxScale: 3.0,                                    // can't zoom in past 300%
  panBoundary: const Rect.fromLTWH(0, 0, 1000, 1500), // single-page bounds
);

FlueraCanvas(controller: controller, /* ... */);
```

**Notes**: `panBoundary: null` (default) leaves the canvas truly
infinite. `null` for any of the three preserves 0.12.0 behaviour
exactly. Useful for notes apps that want a fixed-page feel inside
an infinite-canvas SDK.

## 6. Copy / paste between canvas instances

Built-in via the system clipboard (FCV0 base64 + magic prefix).
`Ctrl+C` / `Ctrl+V` (or `⌘+C` / `⌘+V` on macOS) are wired by
default; the programmatic API is also exposed.

```dart
// Programmatic copy:
await canvasKey.currentState!.copySelection();

// Programmatic paste at the camera centre:
final newIds = await canvasKey.currentState!.pasteFromClipboard();
// Returns [] if the clipboard contained no fluera_canvas payload.

// Paste at a specific world point:
await canvasKey.currentState!.pasteFromClipboard(
  worldPosition: const Offset(200, 200),
);
```

**Notes**: keyboard shortcuts respect the in-canvas text editor
(no hijack while typing). Set `enableKeyboardShortcuts: false` on
`FlueraCanvas` to opt out entirely.

## 7. Brand the toolbar with my colors

Use `FlueraToolbarTheme` as a global `ThemeData.extension`:

```dart
MaterialApp(
  theme: ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF6750A4),
    extensions: const [
      FlueraToolbarTheme(
        radius: 18,                       // softer pill corners
        swatchSize: 36,                   // bigger color dots
        selectedFill: Color(0xFF00CC88),  // brand green
      ),
    ],
  ),
  home: const MyDrawingPage(),
);
```

Or per-toolbar via the `theme:` prop (wins over the global extension):

```dart
FlueraCanvasToolbar(
  // ...
  theme: const FlueraToolbarTheme(radius: 8, motion: Duration(milliseconds: 100)),
);
```

**Notes**: 21 fields — see [customization.md](customization.md) for
the full reference. Color fields default to `null` (use scheme); only
override what your brand needs.

## 8. Add a custom tool to my own toolbar

Skip the drop-in toolbar entirely and drive the canvas headlessly.
The `_CustomToolbarDemo` in the example app shows a Photoshop-style
floating sidebar — copy that pattern.

```dart
class _MyDrawingPageState extends State<MyDrawingPage> {
  final canvasKey = GlobalKey<FlueraCanvasState>();
  CanvasTool _tool = CanvasTool.draw;
  Color _color = Colors.black;

  @override
  Widget build(BuildContext c) => Scaffold(
    body: Stack(children: [
      FlueraCanvas(
        key: canvasKey,
        tool: _tool,
        strokeColor: _color,
        strokeWidth: 3,
      ),
      // Your toolbar — Cupertino, sidebar, ribbon, anything goes:
      Positioned(
        left: 16, top: 16, bottom: 16,
        child: MyCustomSidebar(
          tool: _tool,
          onTool: (t) => setState(() => _tool = t),
          onUndo: () => canvasKey.currentState?.undo(),
          canUndo: canvasKey.currentState?.canUndo ?? false,
        ),
      ),
    ]),
  );
}
```

**Notes**: subscribe to `state.historyListenable` and
`state.selectionListenable` for real-time enable/disable of your
buttons without polling. See `_CustomToolbarDemo` in
`example/lib/main.dart` for a complete runnable example.

## 9. Draw shapes programmatically (tutorial overlays)

Skip pointer events and deposit ink directly. Useful for tutorial
overlays, generative art, AI-driven canvases.

```dart
final state = canvasKey.currentState!;

// Straight line:
state.drawLine(const Offset(10, 10), const Offset(60, 60));

// Circle approximated as 32-segment polyline:
state.drawCircle(const Offset(100, 100), 40);

// Arbitrary closed polygon:
state.drawPolygon(
  const [Offset(200, 0), Offset(250, 0), Offset(225, 50)],
  closed: true,
);

// All three accept color/width/metadata overrides:
state.drawLine(
  const Offset(0, 0), const Offset(100, 0),
  color: Colors.red,
  width: 5,
  metadata: const {'tutorial-step': 'arrow-1'},
);
```

**Notes**: each helper returns the committed `CanvasStroke` so you
can store the reference for later removal or transformation.
Defaults (color / width) inherit from the canvas's current
`strokeColor` / `strokeWidth`.

## 10. Detect what's under the pointer (hover tooltips)

Use the public hit-test API. Both methods are O(log n) via the
internal RTree spatial index — safe to call from `MouseRegion.onHover`.

```dart
import 'package:flutter/material.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

class _HoverableCanvas extends StatefulWidget {
  // ...
}

class _HoverableCanvasState extends State<_HoverableCanvas> {
  final canvasKey = GlobalKey<FlueraCanvasState>();
  NodeId? _hoveredId;

  @override
  Widget build(BuildContext c) => MouseRegion(
    onHover: (event) {
      final state = canvasKey.currentState;
      if (state == null) return;
      final world = state.controller.screenToCanvas(event.localPosition);
      final hit = state.hitTest(world, tolerance: 6);
      if (hit != _hoveredId) setState(() => _hoveredId = hit);
    },
    child: Stack(children: [
      FlueraCanvas(key: canvasKey),
      if (_hoveredId != null)
        Positioned(
          top: 8, right: 8,
          child: Chip(label: Text('Hovering: $_hoveredId')),
        ),
    ]),
  );
}
```

For batch queries:

```dart
// All node IDs whose AABB intersects a rect (back-to-front paint order).
final ids = state.hitTestInRect(const Rect.fromLTWH(0, 0, 200, 200));
```

**Notes**: `tolerance` (default `4.0`) inflates per-node bounds —
useful for thin strokes that would otherwise need pixel-perfect aim.
For tap-select behaviour out of the box, use `CanvasTool.select`
(toolbar handles the hit-test for you).
