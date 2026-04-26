// ════════════════════════════════════════════════════════════════════════════
// 🎨 FlueraCanvasToolbar — drop-in Material toolbar for [FlueraCanvas].
//
// Wires the most common controls (tool, color, stroke width, undo, redo,
// clear) into a single ready-to-use widget. Zero configuration beyond
// passing the [GlobalKey] of the [FlueraCanvas] you want to control.
//
// This widget is OPT-IN. The [FlueraCanvas] itself is intentionally
// headless — consumers wanting a different layout (Cupertino,
// floating, sidebar, gestural) should drive the canvas's `tool`,
// `strokeColor` and `strokeWidth` props from their own UI and ignore
// this toolbar.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import 'fluera_canvas_widget.dart';
import 'fluera_color_picker_dialog.dart';
import 'fluera_layer_panel.dart';
import 'tools/image_tool.dart';

/// Default 6-color preset used by [FlueraCanvasToolbar] when no
/// `palette` is provided. Black + 5 saturated hues, consistent with the
/// example app.
const List<Color> kFlueraDefaultPalette = <Color>[
  Color(0xFF1A1A1A),
  Color(0xFFE53935),
  Color(0xFF1E88E5),
  Color(0xFF43A047),
  Color(0xFFFB8C00),
  Color(0xFF8E24AA),
];

/// Drop-in Material toolbar for [FlueraCanvas]. Renders pen / eraser
/// segmented control, color swatches, stroke-width slider, and
/// undo / redo / clear buttons.
///
/// Usage:
/// ```dart
/// final canvasKey = GlobalKey<FlueraCanvasState>();
/// CanvasTool tool = CanvasTool.draw;
/// Color color = Colors.black;
/// double width = 2.5;
///
/// Column(children: [
///   Expanded(child: FlueraCanvas(
///     key: canvasKey,
///     tool: tool,
///     strokeColor: color,
///     strokeWidth: width,
///   )),
///   FlueraCanvasToolbar(
///     canvasKey: canvasKey,
///     tool: tool,
///     onToolChanged: (t) => setState(() => tool = t),
///     color: color,
///     onColorChanged: (c) => setState(() => color = c),
///     strokeWidth: width,
///     onStrokeWidthChanged: (w) => setState(() => width = w),
///   ),
/// ])
/// ```
///
/// The toolbar listens to the canvas's [FlueraCanvasState.historyListenable]
/// so undo / redo buttons reflect the live history state without the
/// caller having to wire `onStrokeCommitted` + `setState` manually.
class FlueraCanvasToolbar extends StatelessWidget {
  const FlueraCanvasToolbar({
    super.key,
    required this.canvasKey,
    required this.tool,
    required this.onToolChanged,
    required this.color,
    required this.onColorChanged,
    required this.strokeWidth,
    required this.onStrokeWidthChanged,
    this.palette = kFlueraDefaultPalette,
    this.minStrokeWidth = 1.0,
    this.maxStrokeWidth = 16.0,
    this.strokeWidthDivisions = 15,
    this.showUndo = true,
    this.showRedo = true,
    this.showClear = true,
    this.showShapeTools = false,
    this.showPixelEraser = false,
    this.showColorPickerButton = false,
    this.showLayers = false,
    this.layersBottomSheetTitle,
    this.showSelectionTool = false,
    this.showImageTool = false,
    this.showTransformActions = false,
    this.eraserRadius,
    this.onEraserRadiusChanged,
    this.minEraserRadius = 8.0,
    this.maxEraserRadius = 80.0,
    this.eraserRadiusDivisions = 18,
    this.padding = const EdgeInsets.all(12),
    this.background,
  });

  /// Key of the [FlueraCanvas] this toolbar controls. Used to call
  /// `undo()`, `redo()` and `clear()` and to subscribe to
  /// `historyListenable` for button enable / disable state.
  final GlobalKey<FlueraCanvasState> canvasKey;

  /// Currently selected tool. Reflected in the segmented control.
  final CanvasTool tool;

  /// Fired when the user picks a different tool. Forward into your
  /// State and pass the new value down to [FlueraCanvas.tool].
  final ValueChanged<CanvasTool> onToolChanged;

  /// Currently selected color. Reflected in the palette swatches.
  final Color color;

  /// Fired when the user picks a color. Forward into your State and
  /// pass the new value down to [FlueraCanvas.strokeColor].
  final ValueChanged<Color> onColorChanged;

  /// Currently selected stroke width. Reflected in the slider.
  final double strokeWidth;

  /// Fired when the user drags the slider. Forward into your State
  /// and pass the new value down to [FlueraCanvas.strokeWidth].
  final ValueChanged<double> onStrokeWidthChanged;

  /// Color swatches shown in the toolbar. Defaults to
  /// [kFlueraDefaultPalette].
  final List<Color> palette;

  /// Stroke-width slider bounds (in world units, same scale as
  /// [FlueraCanvas.strokeWidth]).
  final double minStrokeWidth;
  final double maxStrokeWidth;
  final int strokeWidthDivisions;

  /// Toggle individual buttons off if your UI provides them elsewhere.
  final bool showUndo;
  final bool showRedo;
  final bool showClear;

  /// When `true`, the segmented control gains line / rectangle /
  /// ellipse buttons in addition to pen / eraser. Default `false` to
  /// keep the toolbar minimal for consumers that only need free-form
  /// drawing.
  final bool showShapeTools;

  /// When `true`, the eraser segment is replaced by a 2-mode segmented
  /// row (stroke eraser + pixel eraser). Default `false` — most apps
  /// only need stroke-mode erase.
  final bool showPixelEraser;

  /// When `true`, a "more colors" trailing button on the palette row
  /// pops up [FlueraColorPickerDialog] for arbitrary HSV / hex picks
  /// beyond the 6-swatch preset. Default `false`.
  final bool showColorPickerButton;

  /// When `true`, a layers (stack-of-paper) IconButton in the trailing
  /// row opens [FlueraLayerPanel] as a bottom sheet — drop-in layer
  /// management without the consumer having to mount the panel
  /// themselves. Default `false` to keep the toolbar minimal for
  /// notes-app workloads that don't need multi-layer support.
  final bool showLayers;

  /// Optional title shown above the layer panel inside the bottom
  /// sheet. Defaults to "Layers".
  final String? layersBottomSheetTitle;

  /// When `true`, the tool segmented control gains a `Select` segment
  /// that maps to [CanvasTool.select]. Tap a stroke to select, drag on
  /// empty space to marquee-select, drag a handle to scale / rotate
  /// (Phase C2). Default `false`.
  final bool showSelectionTool;

  /// When `true`, a "picture" trailing IconButton invokes
  /// [FlueraImageTool.pickAndCommit] — opens the platform-native file
  /// picker, decodes the chosen image and commits it on the active
  /// layer. Imperative on purpose: tapping the button doesn't change
  /// `tool`. Default `false`.
  final bool showImageTool;

  /// When `true` AND a non-empty selection exists, mirror-H / mirror-V
  /// trailing buttons appear in the selection-action row. Wires
  /// directly into `state.mirrorSelection(Axis)`. Default `false`.
  final bool showTransformActions;

  /// Current eraser radius in screen pixels. When non-null AND
  /// [onEraserRadiusChanged] is also provided, the toolbar's slider
  /// switches between controlling [strokeWidth] (for draw / line /
  /// rectangle / ellipse tools) and [eraserRadius] (for erase /
  /// erasePixel tools). The eraser preview circle drawn under the
  /// pointer matches this value, so the user always sees what they're
  /// about to cut.
  final double? eraserRadius;

  /// Fired when the user drags the slider while the eraser tool is
  /// active. Forward into your State and pass the new value down to
  /// [FlueraCanvas.eraserRadius].
  final ValueChanged<double>? onEraserRadiusChanged;

  /// Eraser-radius slider bounds (screen pixels). Defaults give a
  /// touch-friendly range — small enough for fine cuts, large enough
  /// to wipe whole strokes in one tap.
  final double minEraserRadius;
  final double maxEraserRadius;
  final int eraserRadiusDivisions;

  /// Inner padding around the toolbar content.
  final EdgeInsetsGeometry padding;

  /// Optional background color. Defaults to
  /// `Theme.of(context).colorScheme.surfaceContainerHighest`.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final segments = <ButtonSegment<CanvasTool>>[
      const ButtonSegment(
        value: CanvasTool.draw,
        label: Text('Pen'),
        icon: Icon(Icons.edit_rounded),
      ),
      const ButtonSegment(
        value: CanvasTool.erase,
        label: Text('Erase'),
        icon: Icon(Icons.cleaning_services_rounded),
        tooltip: 'Erase whole strokes',
      ),
      if (showPixelEraser)
        const ButtonSegment(
          value: CanvasTool.erasePixel,
          label: Text('Cut'),
          icon: Icon(Icons.content_cut_rounded),
          tooltip: 'Cut the touched portion of strokes',
        ),
      if (showShapeTools) ...[
        const ButtonSegment(
          value: CanvasTool.line,
          label: Text('Line'),
          icon: Icon(Icons.horizontal_rule_rounded),
        ),
        const ButtonSegment(
          value: CanvasTool.rectangle,
          label: Text('Rect'),
          icon: Icon(Icons.crop_square_rounded),
        ),
        const ButtonSegment(
          value: CanvasTool.ellipse,
          label: Text('Oval'),
          icon: Icon(Icons.circle_outlined),
        ),
      ],
      if (showSelectionTool)
        const ButtonSegment(
          value: CanvasTool.select,
          label: Text('Select'),
          icon: Icon(Icons.crop_free_rounded),
          tooltip: 'Tap to select, drag empty space to marquee-select',
        ),
    ];

    return Container(
      padding: padding,
      color: background ?? scheme.surfaceContainerHighest,

      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SegmentedButton<CanvasTool>(
                      segments: segments,
                      selected: {tool},
                      onSelectionChanged: (s) => onToolChanged(s.first),
                    ),
                  ),
                ),
                if (showImageTool)
                  IconButton(
                    icon: const Icon(Icons.image_rounded),
                    tooltip: 'Insert image',
                    onPressed: () {
                      final state = canvasKey.currentState;
                      if (state == null) return;
                      FlueraImageTool.pickAndCommit(context, state);
                    },
                  ),
                if (showLayers)
                  IconButton(
                    icon: const Icon(Icons.layers_rounded),
                    tooltip: 'Layers',
                    onPressed: () => _openLayersSheet(context),
                  ),
                _HistoryButtons(
                  canvasKey: canvasKey,
                  showUndo: showUndo,
                  showRedo: showRedo,
                  showClear: showClear,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final c in palette)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _ColorSwatch(
                      color: c,
                      selected: c.toARGB32() == color.toARGB32(),
                      onTap: () => onColorChanged(c),
                    ),
                  ),
                if (showColorPickerButton)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _MoreColorsButton(
                      currentColor: color,
                      onPicked: onColorChanged,
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: _SizeSlider(
                    tool: tool,
                    strokeWidth: strokeWidth,
                    onStrokeWidthChanged: onStrokeWidthChanged,
                    minStrokeWidth: minStrokeWidth,
                    maxStrokeWidth: maxStrokeWidth,
                    strokeWidthDivisions: strokeWidthDivisions,
                    eraserRadius: eraserRadius,
                    onEraserRadiusChanged: onEraserRadiusChanged,
                    minEraserRadius: minEraserRadius,
                    maxEraserRadius: maxEraserRadius,
                    eraserRadiusDivisions: eraserRadiusDivisions,
                  ),
                ),
              ],
            ),
            if (showTransformActions)
              _SelectionActionsRow(canvasKey: canvasKey),
          ],
        ),
      ),
    );
  }

  /// Open the [FlueraLayerPanel] in a Material bottom sheet. Wired
  /// from the trailing layers IconButton when [showLayers] is `true`.
  /// Half-screen by default, draggable up to full height — the panel
  /// itself is scrollable.
  void _openLayersSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        // FlueraLayerPanel internally uses a `Column` with `Expanded`
        // children for the reorderable list, so the sheet body needs a
        // bounded height. We use FractionallySizedBox to give it 60%
        // of the viewport — generous enough for ~12 layer rows; the
        // panel's own list scrolls beyond that.
        return FractionallySizedBox(
          heightFactor: 0.6,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    layersBottomSheetTitle ?? 'Layers',
                    style: Theme.of(sheetCtx).textTheme.titleMedium,
                  ),
                ),
                Expanded(child: FlueraLayerPanel(canvasKey: canvasKey)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Slider that shows the stroke width when a draw / shape tool is
/// active and the eraser radius when an eraser tool is active.
/// Falls back to the stroke-width slider if the consumer didn't wire
/// up `eraserRadius` + `onEraserRadiusChanged` — backward-compatible
/// with toolbars built before 0.4.0.
class _SizeSlider extends StatelessWidget {
  const _SizeSlider({
    required this.tool,
    required this.strokeWidth,
    required this.onStrokeWidthChanged,
    required this.minStrokeWidth,
    required this.maxStrokeWidth,
    required this.strokeWidthDivisions,
    required this.eraserRadius,
    required this.onEraserRadiusChanged,
    required this.minEraserRadius,
    required this.maxEraserRadius,
    required this.eraserRadiusDivisions,
  });

  final CanvasTool tool;
  final double strokeWidth;
  final ValueChanged<double> onStrokeWidthChanged;
  final double minStrokeWidth;
  final double maxStrokeWidth;
  final int strokeWidthDivisions;
  final double? eraserRadius;
  final ValueChanged<double>? onEraserRadiusChanged;
  final double minEraserRadius;
  final double maxEraserRadius;
  final int eraserRadiusDivisions;

  bool get _isEraserTool =>
      tool == CanvasTool.erase || tool == CanvasTool.erasePixel;

  @override
  Widget build(BuildContext context) {
    if (_isEraserTool &&
        eraserRadius != null &&
        onEraserRadiusChanged != null) {
      return Slider(
        value: eraserRadius!.clamp(minEraserRadius, maxEraserRadius),
        min: minEraserRadius,
        max: maxEraserRadius,
        divisions: eraserRadiusDivisions,
        label: 'Eraser ${eraserRadius!.toStringAsFixed(0)} px',
        onChanged: onEraserRadiusChanged,
      );
    }
    return Slider(
      value: strokeWidth.clamp(minStrokeWidth, maxStrokeWidth),
      min: minStrokeWidth,
      max: maxStrokeWidth,
      divisions: strokeWidthDivisions,
      label: '${strokeWidth.toStringAsFixed(1)} px',
      onChanged: onStrokeWidthChanged,
    );
  }
}

class _MoreColorsButton extends StatelessWidget {
  const _MoreColorsButton({required this.currentColor, required this.onPicked});
  final Color currentColor;
  final ValueChanged<Color> onPicked;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final picked = await showFlueraColorPicker(
          context: context,
          initial: currentColor,
        );
        if (picked != null) onPicked(picked);
      },
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const SweepGradient(
            colors: [
              Color(0xFFFF0000),
              Color(0xFFFFFF00),
              Color(0xFF00FF00),
              Color(0xFF00FFFF),
              Color(0xFF0000FF),
              Color(0xFFFF00FF),
              Color(0xFFFF0000),
            ],
          ),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: const Icon(Icons.add_rounded, size: 18, color: Colors.white),
      ),
    );
  }
}

class _HistoryButtons extends StatelessWidget {
  const _HistoryButtons({
    required this.canvasKey,
    required this.showUndo,
    required this.showRedo,
    required this.showClear,
  });

  final GlobalKey<FlueraCanvasState> canvasKey;
  final bool showUndo;
  final bool showRedo;
  final bool showClear;

  @override
  Widget build(BuildContext context) {
    // canvasKey.currentState is null on the very first build (the canvas
    // mounts in the same frame as the toolbar). Once it's available we
    // subscribe to historyListenable so undo / redo reflect history
    // changes without the caller plumbing setState manually.
    final state = canvasKey.currentState;
    if (state == null) {
      // Schedule a rebuild after the first frame so we pick the state up.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) (context as Element).markNeedsBuild();
      });
      return _buildButtons(context, canUndo: false, canRedo: false);
    }
    return ListenableBuilder(
      listenable: state.historyListenable,
      builder:
          (ctx, _) => _buildButtons(
            ctx,
            canUndo: state.canUndo,
            canRedo: state.canRedo,
          ),
    );
  }

  Widget _buildButtons(
    BuildContext context, {
    required bool canUndo,
    required bool canRedo,
  }) {
    final state = canvasKey.currentState;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showUndo)
          IconButton(
            tooltip: 'Undo',
            icon: const Icon(Icons.undo_rounded),
            onPressed: canUndo ? () => state?.undo() : null,
          ),
        if (showRedo)
          IconButton(
            tooltip: 'Redo',
            icon: const Icon(Icons.redo_rounded),
            onPressed: canRedo ? () => state?.redo() : null,
          ),
        if (showClear)
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: state == null ? null : () => state.clear(),
          ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: selected ? 30 : 24,
        height: selected ? 30 : 24,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color:
                selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.black.withValues(alpha: 0.2),
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}

/// Inline action row that appears below the slider row when
/// `showTransformActions` is `true`. Subscribes to the canvas's
/// [FlueraCanvasState.selectionListenable] so the buttons fade in /
/// out as the user picks or clears the selection — no consumer-side
/// `setState` plumbing required.
class _SelectionActionsRow extends StatelessWidget {
  const _SelectionActionsRow({required this.canvasKey});

  final GlobalKey<FlueraCanvasState> canvasKey;

  @override
  Widget build(BuildContext context) {
    final state = canvasKey.currentState;
    if (state == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: state.selectionListenable,
      builder: (context, _) {
        final hasSelection = state.selection.isNotEmpty;
        if (!hasSelection) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            children: [
              Text(
                '${state.selection.length} selected',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.flip_rounded),
                tooltip: 'Mirror horizontally',
                onPressed: () => state.mirrorSelection(Axis.horizontal),
              ),
              Transform.rotate(
                angle: 1.5707963, // 90° — turn the same icon vertical
                child: IconButton(
                  icon: const Icon(Icons.flip_rounded),
                  tooltip: 'Mirror vertically',
                  onPressed: () => state.mirrorSelection(Axis.vertical),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: 'Delete selection',
                onPressed: () => state.deleteSelection(),
              ),
              IconButton(
                icon: const Icon(Icons.deselect_rounded),
                tooltip: 'Clear selection',
                onPressed: () => state.clearSelection(),
              ),
            ],
          ),
        );
      },
    );
  }
}
