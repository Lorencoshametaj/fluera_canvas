# Customization — theming, responsive layout, custom toolbars

This guide covers the four levels of integration available in
`fluera_canvas` and how to brand or replace the drop-in toolbar without
forking. Every feature on this page is **opt-in and additive** — the
zero-config defaults remain unchanged, you only pay for what you use.

**TL;DR**

| Need | Reach for |
|---|---|
| A full Material 3 drawing app in 1 line | `FlueraSketchApp` |
| A drawing page inside your existing app | `FlueraSketchScaffold` |
| The drop-in toolbar with brand colours / radii | `FlueraCanvasToolbar` + `FlueraToolbarTheme` |
| A custom toolbar (Cupertino / sidebar / floating) | `FlueraCanvas` headless + your own widgets |

## The four magic levels

```
┌─────────────────────────────────────────────────────────────────┐
│ Level 4 — FlueraSketchApp                                       │
│   `runApp(const FlueraSketchApp())` — the whole app, one line.  │
├─────────────────────────────────────────────────────────────────┤
│ Level 3 — FlueraSketchScaffold                                  │
│   A page-level Scaffold with the canvas + toolbar pre-wired.    │
├─────────────────────────────────────────────────────────────────┤
│ Level 2 — FlueraCanvasToolbar (drop-in)                         │
│   Bottom Material 3 toolbar around your own FlueraCanvas.       │
│   Themable via FlueraToolbarTheme.                              │
├─────────────────────────────────────────────────────────────────┤
│ Level 1 — FlueraCanvas (headless)                               │
│   Just the canvas. Wire tool / color / undo through your own    │
│   widgets. Use this for Cupertino, sidebars, vertical layouts.  │
└─────────────────────────────────────────────────────────────────┘
```

You can drop down a level any time you need more control. The lower
levels never depend on the higher ones, so the size cost of `Level 4`
is the same as `Level 1` — Flutter tree-shaking removes the unused
widgets at compile time.

## Theming the drop-in toolbar

`FlueraToolbarTheme` is a `ThemeExtension<T>`, so it integrates with
the standard Material `ThemeData` pipeline. Two ways to apply it:

### Globally (via `ThemeData.extensions`)

```dart
MaterialApp(
  theme: ThemeData(
    useMaterial3: true,
    colorSchemeSeed: const Color(0xFF6750A4),
    extensions: const [
      FlueraToolbarTheme(
        radius: 18,                       // softer pill corners
        swatchSize: 36,                   // bigger colour dots
        motion: Duration(milliseconds: 150),
        selectedFill: Color(0xFF00CC88),  // brand green for selected
      ),
    ],
  ),
  home: ...,
);
```

Every `FlueraCanvasToolbar` inside the subtree picks it up
automatically — no per-widget changes.

### Locally (via the `theme:` prop)

```dart
FlueraCanvasToolbar(
  canvasKey: canvasKey,
  // ... required props ...
  theme: const FlueraToolbarTheme(
    radius: 8,                            // squarer corners on this one
    motion: Duration(milliseconds: 100),  // snappier
  ),
)
```

A non-null `theme:` prop **wins** over the global `ThemeData.extension`,
so you can have a default brand theme app-wide and override it for a
single toolbar (e.g., a denser variant inside a side panel).

### What you can override

| Field | Default | Use for |
|---|---|---|
| `radius`, `radiusSmall` | 14, 10 | corner rounding of pills + trailing icons |
| `swatchSize`, `previewSize` | 30, 30 | size of colour swatches and slider previews |
| `tap` | 44 | tool pill size (44 = Material 3 minimum) |
| `spacing`, `spacingTight` | 10, 6 | inter-element gaps |
| `sliderWidth`, `compactSliderWidth` | 220, 140 | slider widths in wide / compact modes |
| `motion`, `motionCurve` | 200ms, easeOutCubic | tool-state animation timing |
| `selectedFill`, `selectedIconColor` | colorScheme.primary / onPrimary | active pill background + icon |
| `idleIconColor` | colorScheme.onSurfaceVariant | idle pill / trailing icon |
| `destructiveColor` | colorScheme.error | clear button icon |
| `swatchRingColor` | colorScheme.primary | ring around active swatch |
| `surfaceGradientStart`, `surfaceGradientEnd` | colorScheme.surfaceContainerHigh / Highest | toolbar background gradient |
| `outlineColor` | colorScheme.outlineVariant | hairlines + slider track secondary |
| `elevatedShadowBlur`, `elevatedShadowOpacity` | 6, 0.25 | drop shadow on selected elements |

Colour fields default to `null` — meaning the toolbar pulls from
`Theme.of(context).colorScheme`. Override only what you need to brand;
the rest stays consistent with the host app's M3 colour scheme.

## Compact mode (responsive layout)

By default `FlueraCanvasToolbar` switches to a **3-row vertical stack**
layout when its parent constraint is narrower than `compactBreakpoint`
(default `600` px). Above the breakpoint it uses the classic 2-row
layout; the slider widths shrink from `sliderWidth` (220) to
`compactSliderWidth` (140) automatically.

```dart
FlueraCanvasToolbar(
  // ...
  compactBreakpoint: 720,  // switch earlier — useful for tablet portrait
)
```

Pass `0` to **disable compact mode entirely** (the toolbar will always
use the wide layout, regardless of viewport):

```dart
FlueraCanvasToolbar(
  compactBreakpoint: 0,
)
```

Tap targets remain `44×44` in both modes — only the layout topology
changes, not the accessibility surface.

## Building your own toolbar

When the drop-in doesn't fit your design language (Cupertino, vertical
sidebar, floating overlay, top-of-screen ribbon), drop down to the
headless `FlueraCanvas` and wire the controls yourself. The pattern:

```dart
class MyDrawingPage extends StatefulWidget {
  const MyDrawingPage({super.key});
  @override
  State<MyDrawingPage> createState() => _MyDrawingPageState();
}

class _MyDrawingPageState extends State<MyDrawingPage> {
  final _canvasKey = GlobalKey<FlueraCanvasState>();
  CanvasTool _tool = CanvasTool.draw;
  Color _color = Colors.black;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          FlueraCanvas(
            key: _canvasKey,
            tool: _tool,
            strokeColor: _color,
            strokeWidth: 3,
          ),
          // Your toolbar — Cupertino, sidebar, overlay, anything goes.
          Positioned(
            left: 16, top: 16, bottom: 16,
            child: MyToolbar(
              tool: _tool,
              onTool: (t) => setState(() => _tool = t),
              onUndo: () => _canvasKey.currentState?.undo(),
              canUndo: _canvasKey.currentState?.canUndo ?? false,
            ),
          ),
        ],
      ),
    );
  }
}
```

### History buttons that update in real time

`canvasKey.currentState` exposes a `historyListenable` that fires every
time the undo / redo stack changes. Wrap your buttons in a
`ListenableBuilder` to enable / disable them automatically:

```dart
ListenableBuilder(
  listenable: _canvasKey.currentState!.historyListenable,
  builder: (ctx, _) {
    final state = _canvasKey.currentState!;
    return Row(children: [
      IconButton(
        onPressed: state.canUndo ? state.undo : null,
        icon: const Icon(Icons.undo_rounded),
      ),
      IconButton(
        onPressed: state.canRedo ? state.redo : null,
        icon: const Icon(Icons.redo_rounded),
      ),
    ]);
  },
)
```

There's a similar `selectionListenable` for showing / hiding selection
actions (rotate, mirror, delete) when the user picks or clears a
selection.

### See it live

The `example/` app ships a runnable demo of this pattern:
**Custom toolbar (headless)**. It shows a Photoshop-style floating
sidebar (vertical tools + undo/redo) on the left, a colour palette
floating top-right, and the canvas behind everything. Source: search
`_CustomToolbarDemo` in `example/lib/main.dart`.

## Camera bounds — `minScale` / `maxScale` / `panBoundary` (0.13.0+)

By default the canvas is genuinely infinite — you can pan in any
direction forever and zoom from `0.1×` to `5×`. For document-shaped
apps (single-page notes, fixed-size whiteboards, Figma-style frames)
that's overkill. The `InfiniteCanvasController` constructor takes
three optional bounds:

```dart
final controller = InfiniteCanvasController(
  minScale: 0.5,                                    // can't zoom out past 50%
  maxScale: 3.0,                                    // can't zoom in past 300%
  panBoundary: const Rect.fromLTWH(0, 0, 5000, 5000), // single-page app
);

FlueraCanvas(
  controller: controller,
  // ...
);
```

`panBoundary` clamps `setOffset` (and therefore every consumer-facing
pan operation) so the camera origin can't escape the rectangle.
Defaults reproduce 0.12.0 behaviour exactly: `minScale: 0.1`,
`maxScale: 5.0`, `panBoundary: null` (unbounded).

## Minimap navigation (0.13.0+)

When the canvas grows past one viewport, users get lost. Drop a
`FlueraMinimap` into a `Stack` overlay and they always see where they
are + can tap to jump:

```dart
Stack(
  children: [
    FlueraCanvas(key: canvasKey, ...),
    Positioned(
      top: 16, right: 16,
      child: FlueraMinimap(canvasKey: canvasKey),
    ),
  ],
);
```

The minimap subscribes to the canvas's `historyListenable` (so the
overview updates when strokes are added / removed) and to the camera
controller (so the viewport rectangle moves with pan / zoom). Tap
inside the minimap to recenter the camera at that world point; drag
to pan smoothly.

Customize via the constructor:

```dart
FlueraMinimap(
  canvasKey: canvasKey,
  size: const Size(220, 140),                  // bigger overview
  background: Colors.white,                    // override surface
  viewportColor: const Color(0xFFE53935),      // brand-red indicator
  contentColor: Colors.black54,
  borderRadius: 16,
);
```

Pure Dart `CustomPainter` — no GPU, no native code, no extra deps.

## Document model + autosave (0.14.0+)

`FlueraDocument` wraps a `FlueraCanvas` mounted via `GlobalKey` and
mediates the dirty-flag + autosave-debounce plumbing every notes app
reinvents. It's **opt-in** — the pre-0.14 pattern (write FCV0 bytes
yourself on stroke commit) keeps working.

```dart
final canvasKey = GlobalKey<FlueraCanvasState>();
late final FlueraDocument doc;

@override
void initState() {
  super.initState();
  doc = FlueraDocument(
    canvasKey: canvasKey,
    meta: const FlueraDocumentMeta(id: 'note-42', title: 'Meeting notes'),
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
void dispose() {
  doc.dispose();
  super.dispose();
}
```

`doc.isDirty` reflects whether anything has changed since the last
save. `doc.save()` forces an immediate save (cancels pending
debounce). `doc.setMeta(...)` updates the title / tags / etc. without
marking the document dirty (metadata is sidecar — only canvas
content changes the binary blob).

## Eraser preview cursor

When the eraser tool is active, `FlueraCanvas` draws a translucent
circle (`eraserRadius` wide) under the pointer / hovering stylus to
show the user what they're about to delete. On by default
(`showEraserPreview: true`). Pass `false` to opt out:

```dart
FlueraCanvas(
  tool: CanvasTool.erase,
  eraserRadius: 24,
  showEraserPreview: false,  // hide the preview circle
);
```

Mouse hover (desktop) and stylus hover (iOS / Android Pencil) both
trigger the preview. Pure touch input doesn't (no hover phase).

## Smart guides during transform (0.15.0+)

`FlueraCanvas` ships smart guides ON by default since 0.15.0. Drag
a selected node and the dragged frame's anchors (top / bottom / left
/ right edges + center) snap to matching anchors on nearby visible
nodes — Figma / TLDraw style alignment. Magenta dashed guide lines
render via the selection painter while a snap is locked.

```dart
FlueraCanvas(
  // smart guides on by default; set to false to opt out
  smartGuidesEnabled: false,
  // tolerance band in logical px (scale-aware); default 6
  smartGuidesTolerancePx: 6,
);
```

Hold **Shift** while dragging to bypass guides for a single drag
without reconfiguring the widget.

For consumers building custom transform widgets / gestures that need
the same snap math standalone, the public `SnapEngine` primitive is
exported from the barrel:

```dart
final engine = SnapEngine();
final result = engine.snap(
  draggedBounds: mySelectionBounds,
  candidates: [for (final n in nearbyNodes) n.bounds],
  axes: SnapAxes.both,
);
if (result.didSnap) {
  // result.bounds is the snapped AABB; result.guides is the
  // list of magenta lines to render this frame.
}
```

## Hit-test API (0.15.0+)

Two public methods on `FlueraCanvasState` for spatial queries
backed by the internal RTree spatial index. Both are O(log n) and
allocation-free; safe to call from `MouseRegion.onHover` for hover
tooltips, custom select implementations, click-through detection.

```dart
// Front-most node at world point (or null if nothing's there).
final NodeId? hit = canvasKey.currentState!.hitTest(
  worldPoint,
  tolerance: 4.0, // world-px inflation around node bounds
);

// All node IDs whose AABB intersects a world rect (back-to-front
// paint order; pick `last` for the front-most).
final Set<NodeId> ids = canvasKey.currentState!.hitTestInRect(
  Rect.fromLTWH(0, 0, 200, 200),
);
```

## Programmatic drawing helpers (0.15.0+)

Deposit ink without going through pointer events. Useful for
tutorial overlays, generative art, AI-driven canvases, anything
that builds strokes in code.

```dart
final state = canvasKey.currentState!;
state.drawLine(const Offset(10, 10), const Offset(60, 60));
state.drawCircle(const Offset(100, 100), 40, segments: 32);
state.drawPolygon(
  const [Offset(200, 0), Offset(250, 0), Offset(225, 50)],
  closed: true,
);
```

All three accept optional `color`, `width`, and `metadata`
overrides; missing values fall back to the canvas's `strokeColor` /
`strokeWidth`. The committed `CanvasStroke` is returned so consumers
can store its reference for later removal or transformation.

## Custom per-tool mouse cursors (0.15.0+)

```dart
FlueraCanvas(
  cursorPerTool: const {
    CanvasTool.draw: SystemMouseCursors.cell,
    CanvasTool.select: SystemMouseCursors.move,
    // missing entries fall back to the per-tool default
  },
);
```

Touch-only platforms ignore the override (no `MouseRegion` mounts).

## Accessibility (0.16.0+)

`FlueraCanvas(semanticsEnabled: true)` (default `true` since 0.16.0)
wraps the canvas in a `Semantics` node with a summary label
(`"Drawing canvas, X strokes, Y layers"`) so TalkBack / VoiceOver /
Narrator announce something meaningful when the canvas receives
focus. Set to `false` to skip the wrapper entirely (saves one
element in the semantic tree on canvases known to be off-screen
for assistive tech).

```dart
FlueraCanvas(
  semanticsEnabled: false, // explicit opt-out
  // ...
);
```

Per-stroke `Semantics` are intentionally NOT emitted — even moderate
scenes (~1k strokes) would explode the tree and tank screen-reader
performance. Consumers who need stroke-level a11y wrap individual
nodes themselves outside the canvas.

## Localization (i18n) — `FlueraStrings` (0.16.0+)

`FlueraStrings` is a `ThemeExtension<T>` carrying every visible
string in `FlueraCanvasToolbar`. Apply globally:

```dart
MaterialApp(
  theme: ThemeData(
    extensions: const [
      FlueraStrings(
        toolPen: 'Penna',
        toolErase: 'Gomma',
        layersTooltip: 'Livelli',
        undoTooltip: 'Annulla',
        clearTooltip: 'Pulisci',
      ),
    ],
  ),
);
```

Or per-toolbar via the `strings:` prop (wins over the global
extension — same priority pattern as `FlueraToolbarTheme`):

```dart
FlueraCanvasToolbar(
  // ...
  strings: const FlueraStrings(toolPen: 'Stilo', toolErase: 'Cancella'),
);
```

Defaults are English; partial overrides translate only the strings
you provide. Zero runtime dependency on `flutter_localizations`.

## Customizable keyboard shortcuts — `FlueraShortcuts` (0.16.0+)

```dart
FlueraCanvas(
  shortcuts: const FlueraShortcuts(
    overrides: {
      // Re-bind undo to Ctrl+U; redo / copy / paste / etc. keep defaults
      FlueraShortcutAction.undo:
          SingleActivator(LogicalKeyboardKey.keyU, control: true),
    },
  ),
);
```

The 8 actions in `FlueraShortcutAction`: `undo`, `redo`,
`deleteOrClear`, `escape`, `selectAll`, `duplicate`, `copy`, `paste`.
Missing entries fall back to the per-platform default — Cmd-bound
on macOS / iOS, Ctrl-bound elsewhere. Backward-compat aliases
(`Y` for redo on non-Mac; `Backspace` for deleteOrClear) only
inject when you haven't re-bound the primary action.

## Cupertino toolbar variant (0.16.1+)

When targeting iOS / macOS with pixel-perfect Apple HIG aesthetics,
swap `FlueraCanvasToolbar` for the Cupertino-styled mirror:

```dart
import 'package:fluera_canvas/fluera_canvas.dart';

FlueraCanvasCupertinoToolbar(
  canvasKey: canvasKey,
  tool: _tool,
  onToolChanged: (t) => setState(() => _tool = t),
  color: _color,
  onColorChanged: (c) => setState(() => _color = c),
  strokeWidth: _width,
  onStrokeWidthChanged: (w) => setState(() => _width = w),
  // every show* flag, theme, strings, compactBreakpoint work identically
);
```

**Same API** as `FlueraCanvasToolbar` — every constructor parameter
mirrors 1:1. Internally uses `CupertinoButton`, `CupertinoSlider`,
`CupertinoColors`, `CupertinoIcons` — zero new dependencies (Cupertino
is built into Flutter via `package:flutter/cupertino.dart`).

`FlueraToolbarTheme` and `FlueraStrings` are reused. Color overrides
on the theme still work; `null` fields fall back to `CupertinoColors`
defaults instead of Material `colorScheme`. Pen-down haptic
(`HapticFeedback.selectionClick()`) fires on tool switch — matches
iOS expectations.

When to pick which:
- **iOS + Material elsewhere?** Material toolbar — looks "Flutter
  cross-platform default", less jarring on Android.
- **iOS-only / iOS-first product?** Cupertino toolbar — users
  expect SF Symbols + Cupertino sliders.
- **iPadOS / macOS Catalyst?** Cupertino toolbar — Apple platforms
  reward HIG conformance.

## When to use what

- **`FlueraSketchApp`** — prototypes, internal tools, demos.
- **`FlueraSketchScaffold`** — your app already has navigation; you want
  a drawing screen as one of many.
- **`FlueraCanvasToolbar` + `FlueraToolbarTheme`** — your app uses
  Material 3, you want to brand the colours / shapes; bottom toolbar
  layout works for you.
- **`FlueraCanvas` headless** — you need Cupertino, a sidebar, a
  floating UI, integration with your own command palette, multi-canvas
  sync UI, anything that doesn't fit the bottom-Material assumption.

All four levels share the same scene graph, the same persistence
format, and the same export pipeline. Switching from one to another
later is just a widget swap.
