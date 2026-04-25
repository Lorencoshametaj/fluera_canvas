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
        label: Text('Eraser'),
        icon: Icon(Icons.cleaning_services_rounded),
      ),
      if (showPixelEraser)
        const ButtonSegment(
          value: CanvasTool.erasePixel,
          label: Text('Pixel'),
          icon: Icon(Icons.auto_fix_high_rounded),
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
                  child: Slider(
                    value: strokeWidth.clamp(minStrokeWidth, maxStrokeWidth),
                    min: minStrokeWidth,
                    max: maxStrokeWidth,
                    divisions: strokeWidthDivisions,
                    label: '${strokeWidth.toStringAsFixed(1)} px',
                    onChanged: onStrokeWidthChanged,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
