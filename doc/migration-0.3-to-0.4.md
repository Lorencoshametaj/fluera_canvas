# Migration guide: 0.3 → 0.4

`fluera_canvas` 0.4.0 is **non-breaking** for consumers of the 0.3.x
public API. Existing apps recompile and run unchanged. The four new
feature blocks — shape tools, pixel-mode eraser, color picker dialog,
and a public `CanvasStroke.splitAroundCircle` primitive — are fully
opt-in.

## TL;DR

```diff
 FlueraCanvasToolbar(
   canvasKey: canvasKey,
   tool: tool,
   onToolChanged: (t) => setState(() => tool = t),
   color: color,
   onColorChanged: (c) => setState(() => color = c),
   strokeWidth: width,
   onStrokeWidthChanged: (w) => setState(() => width = w),
+  showShapeTools: true,        // Line / Rect / Oval segments
+  showPixelEraser: true,       // Pixel eraser segment
+  showColorPickerButton: true, // "+ more colors" gradient button
 )
```

That's the entire migration if you want the new UI. If you don't, no
code changes are required.

## What's new

### 1. Shape tools

Three new values on the `CanvasTool` enum:

```dart
CanvasTool.line       // drag A → B for a straight line
CanvasTool.rectangle  // drag corner-to-corner for a rectangle outline
CanvasTool.ellipse    // drag for a 32-segment ellipse outline
```

Shape strokes commit as ordinary `CanvasStroke` instances, so they
participate in:

- Undo / redo (`_AddOp`)
- Persistence (`toBytes`, `loadFromBytes`, `toJson`, `loadFromJson`)
- Spatial-index hit-test (`strokeAt`, `strokesInRect`)
- Per-stroke `ui.Picture` cache + `RepaintBoundary` performance path
- Eraser (both stroke- and pixel-mode)

No new model types, no breaking changes to the file format — the
strokes just happen to have geometry that traces a line / rectangle
/ ellipse.

### 2. Pixel-mode eraser

```dart
FlueraCanvas(tool: CanvasTool.erasePixel, ...)
```

Where `CanvasTool.erase` removes whole strokes the eraser circle
touches, `erasePixel` **splits each touched stroke around the circle**
and keeps the surviving pieces. The original Z-order is preserved
and `undo` restores the original stroke (history op:
`_PixelEraseOp`).

If you've built custom pixel-mode UX (e.g. lasso-to-cut, polygon
erase, magnetic erase) you can re-use the underlying primitive:

```dart
final survivors = CanvasStroke.splitAroundCircle(
  myStroke,
  centerInWorldCoords,
  radius * radius, // r squared, not r
);
// survivors: List<CanvasStroke> — empty if every point was inside
// the circle, 1+ entries otherwise. Each entry inherits color and
// baseWidth from the original.
```

This is a pure function — no canvas state, no widgets. Test it
directly without driving gestures.

### 3. Color picker dialog

Zero-dependency HSV picker with hue + saturation/value box + alpha
slider + hex input.

```dart
final picked = await showFlueraColorPicker(
  context: context,
  initial: currentColor,
  enableAlpha: true,                 // optional, default true
  title: 'Pick a stroke color',      // optional
);
if (picked != null) setState(() => currentColor = picked);
```

If you've been depending on `flutter_colorpicker` or rolling your own
dialog, you can drop the dep — `FlueraColorPickerDialog` is exported
from `package:fluera_canvas/fluera_canvas.dart`.

### 4. Toolbar opt-in flags

`FlueraCanvasToolbar` gains three new boolean parameters, all default
`false` (so the 0.3.x rendering is preserved):

| Parameter | Effect |
|---|---|
| `showShapeTools: true` | Adds `Line` / `Rect` / `Oval` segments to the tool segmented control. |
| `showPixelEraser: true` | Adds a `Pixel` segment next to `Eraser`. |
| `showColorPickerButton: true` | Adds a sweep-gradient `+` button at the end of the palette row that pops up `FlueraColorPickerDialog`. |

The tool segmented control is now horizontally scrollable so that 6
tool buttons + history buttons fit on narrow screens without
overflow. (No code change required — if your toolbar previously fit
2 buttons, it still does.)

## Behaviour changes

None. All public 0.3.x methods preserve their semantics. The
`CanvasTool` enum gains values; if your code does an exhaustive
`switch (tool) { ... }` without a `default` clause, you'll get
analyser warnings until you handle the new cases:

```diff
 switch (widget.tool) {
   case CanvasTool.draw:
     return SystemMouseCursors.precise;
   case CanvasTool.erase:
     return SystemMouseCursors.none;
+  case CanvasTool.erasePixel:
+    return SystemMouseCursors.none;
+  case CanvasTool.line:
+  case CanvasTool.rectangle:
+  case CanvasTool.ellipse:
+    return SystemMouseCursors.precise;
 }
```

## Performance

Nothing to migrate. Shape strokes ride the same per-stroke
`ui.Picture` cache as free-form strokes. The pixel eraser allocates
a small list of survivor strokes per `_eraseAtPixel` call (typically
< 5 entries with ≤ a few dozen points each); the cost is bounded by
the spatial-index viewport cull and stays well under 1 ms per frame
for typical scenes. See [`performance.md`](performance.md) for the
full breakdown.

## Deprecated APIs

None in 0.4.0. Full 0.3.x surface preserved.

## Rollback plan

If 0.4.0 misbehaves, pin to 0.3.0:

```yaml
dependencies:
  fluera_canvas: 0.3.0
```

Then file an issue with the
[`bug_report.md`](../.github/ISSUE_TEMPLATE/bug_report.md) template
filled in.
