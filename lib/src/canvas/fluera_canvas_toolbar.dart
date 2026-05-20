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
import 'fluera_strings.dart';
import 'fluera_toolbar_theme.dart';
import 'tools/image_tool.dart';
import 'widgets/fluera_sticker_panel.dart';

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
  /// API element `FlueraCanvasToolbar`.
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
    this.showLassoTool = false,
    this.showImageTool = false,
    this.showTextTool = false,
    this.showStickerPanel = false,
    this.stickers = kFlueraDefaultStickers,
    this.stickersBottomSheetTitle,
    this.showTransformActions = false,
    this.eraserRadius,
    this.onEraserRadiusChanged,
    this.minEraserRadius = 8.0,
    this.maxEraserRadius = 80.0,
    this.eraserRadiusDivisions = 18,
    this.showOpacitySlider = true,
    this.padding = const EdgeInsets.all(12),
    this.background,
    this.theme,
    this.compactBreakpoint = 600.0,
    this.strings,
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
  /// Field `maxStrokeWidth`.
  final double maxStrokeWidth;
  /// Field `strokeWidthDivisions`.
  final int strokeWidthDivisions;

  /// Toggle individual buttons off if your UI provides them elsewhere.
  final bool showUndo;
  /// Field `showRedo`.
  final bool showRedo;
  /// Field `showClear`.
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

  /// When `true`, the tool segmented control gains a `Lasso` segment
  /// that maps to [CanvasTool.lasso] — free-form selection by
  /// dragging a closed path; concave shapes are honoured (vs the
  /// rectangular marquee). Default `false`.
  final bool showLassoTool;

  /// When `true`, a "picture" trailing IconButton invokes
  /// [FlueraImageTool.pickAndCommit] — opens the platform-native file
  /// picker, decodes the chosen image and commits it on the active
  /// layer. Imperative on purpose: tapping the button doesn't change
  /// `tool`. Default `false`.
  final bool showImageTool;

  /// When `true`, the tool segmented control gains a `Text` segment
  /// that maps to [CanvasTool.text]. Tap empty canvas to drop a fresh
  /// `TextNode` and open the live editor; tap an existing text node
  /// to re-enter editing. Wires through `FlueraTextEditor`. Default
  /// `false`.
  final bool showTextTool;

  /// When `true`, a trailing emoji-emotions IconButton opens
  /// [FlueraStickerPanel] in a Material bottom sheet. The host can
  /// supply a custom catalogue via [stickers]; the default
  /// [kFlueraDefaultStickers] is empty (the panel renders a
  /// "no stickers configured" placeholder until the host provides
  /// its own). Default `false`.
  final bool showStickerPanel;

  /// Sticker catalogue rendered by [FlueraStickerPanel] when
  /// [showStickerPanel] is `true`. Defaults to
  /// [kFlueraDefaultStickers] (empty).
  final List<FlueraSticker> stickers;

  /// Optional title shown above the sticker panel inside its bottom
  /// sheet. Defaults to "Stickers".
  final String? stickersBottomSheetTitle;

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
  /// Field `maxEraserRadius`.
  final double maxEraserRadius;
  /// Field `eraserRadiusDivisions`.
  final int eraserRadiusDivisions;

  /// When `true`, an opacity slider appears next to the stroke-width
  /// slider. Drives the alpha channel of [color] via [onColorChanged]
  /// — no separate callback required. Hidden automatically while the
  /// eraser tool is active (opacity has no meaning for erase). Default
  /// `true` (added in 0.11.0).
  final bool showOpacitySlider;

  /// Inner padding around the toolbar content.
  final EdgeInsetsGeometry padding;

  /// Optional background color. Defaults to
  /// `Theme.of(context).colorScheme.surfaceContainerHighest`.
  final Color? background;

  /// Optional theme override for radii / spacing / motion / colours.
  /// `null` (default) → uses [FlueraToolbarTheme] from
  /// `Theme.of(context).extension<FlueraToolbarTheme>()` if present,
  /// otherwise [FlueraToolbarTheme.defaults]. A non-null value here
  /// wins over a global extension. Added in 0.11.1.
  final FlueraToolbarTheme? theme;

  /// Viewport-width threshold (px) below which the toolbar switches
  /// to a vertical 3-row "compact" layout. Above the threshold the
  /// classic 2-row layout is used. Pass `0` to disable compact mode
  /// entirely. Default `600.0`. Added in 0.11.1.
  final double compactBreakpoint;

  /// Optional localised string set (tooltips, sheet titles, slider
  /// labels). `null` (default) → uses [FlueraStrings] from
  /// `Theme.of(context).extension<FlueraStrings>()` if present,
  /// otherwise [FlueraStrings.defaults] (English). Non-null wins
  /// over a global extension. Added in 0.16.0.
  final FlueraStrings? strings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = theme
        ?? Theme.of(context).extension<FlueraToolbarTheme>()
        ?? FlueraToolbarTheme.defaults;
    final s = strings
        ?? Theme.of(context).extension<FlueraStrings>()
        ?? FlueraStrings.defaults;

    final tools = <_ToolSpec>[
      _ToolSpec(CanvasTool.draw, Icons.edit_rounded, s.toolPen),
      _ToolSpec(
        CanvasTool.erase,
        Icons.cleaning_services_rounded,
        s.toolErase,
      ),
      if (showPixelEraser)
        _ToolSpec(
          CanvasTool.erasePixel,
          Icons.content_cut_rounded,
          s.toolPixel,
        ),
      if (showShapeTools) ...[
        _ToolSpec(CanvasTool.line, Icons.horizontal_rule_rounded, s.toolLine),
        _ToolSpec(
          CanvasTool.rectangle,
          Icons.crop_square_rounded,
          s.toolRect,
        ),
        _ToolSpec(CanvasTool.ellipse, Icons.circle_outlined, s.toolOval),
      ],
      if (showSelectionTool)
        _ToolSpec(CanvasTool.select, Icons.crop_free_rounded, s.toolSelect),
      if (showLassoTool)
        _ToolSpec(CanvasTool.lasso, Icons.gesture_rounded, s.toolLasso),
      if (showTextTool)
        _ToolSpec(CanvasTool.text, Icons.text_fields_rounded, s.toolText),
    ];

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final compact = compactBreakpoint > 0 &&
            constraints.maxWidth.isFinite &&
            constraints.maxWidth < compactBreakpoint;
        return _buildLayout(
          context,
          scheme: scheme,
          t: t,
          s: s,
          tools: tools,
          compact: compact,
        );
      },
    );
  }

  Widget _buildLayout(
    BuildContext context, {
    required ColorScheme scheme,
    required FlueraToolbarTheme t,
    required FlueraStrings s,
    required List<_ToolSpec> tools,
    required bool compact,
  }) {
    final outline = t.outlineColor ?? scheme.outlineVariant;
    final gradStart = t.surfaceGradientStart ?? scheme.surfaceContainerHigh;
    final gradEnd = t.surfaceGradientEnd ?? scheme.surfaceContainerHighest;
    final sliderW = compact ? t.compactSliderWidth : t.sliderWidth;

    final toolsRow = Wrap(
      spacing: t.spacingTight,
      runSpacing: t.spacingTight,
      children: [
        for (final spec in tools)
          _ToolPill(
            spec: spec,
            selected: spec.tool == tool,
            onTap: () => onToolChanged(spec.tool),
            theme: t,
          ),
      ],
    );

    final trailingChildren = <Widget>[
      if (showImageTool)
        _TrailingIconButton(
          icon: Icons.image_rounded,
          tooltip: s.insertImageTooltip,
          onPressed: () {
            final state = canvasKey.currentState;
            if (state == null) return;
            FlueraImageTool.pickAndCommit(context, state);
          },
          theme: t,
        ),
      if (showStickerPanel)
        _TrailingIconButton(
          icon: Icons.emoji_emotions_rounded,
          tooltip: s.stickersTooltip,
          onPressed: () => _openStickerSheet(context),
          theme: t,
        ),
      if (showLayers)
        _TrailingIconButton(
          icon: Icons.layers_rounded,
          tooltip: s.layersTooltip,
          onPressed: () => _openLayersSheet(context),
          theme: t,
        ),
      _HistoryButtons(
        canvasKey: canvasKey,
        showUndo: showUndo,
        showRedo: showRedo,
        showClear: showClear,
        theme: t,
        strings: s,
      ),
    ];

    final paletteRow = Wrap(
      spacing: t.spacingTight,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final c in palette)
          _ColorSwatch(
            color: c,
            selected: _sameRgb(c, color),
            onTap: () => onColorChanged(c.withValues(alpha: color.a)),
            theme: t,
          ),
        if (showColorPickerButton)
          _MoreColorsButton(
            currentColor: color,
            onPicked: onColorChanged,
            theme: t,
          ),
      ],
    );

    final sizeSlider = SizedBox(
      width: sliderW,
      child: _SizeSlider(
        tool: tool,
        color: color,
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
        theme: t,
      ),
    );

    final showOpacity = showOpacitySlider &&
        tool != CanvasTool.erase &&
        tool != CanvasTool.erasePixel;
    final opacitySlider = showOpacity
        ? SizedBox(
            width: sliderW,
            child: _OpacitySlider(
              color: color,
              onColorChanged: onColorChanged,
              theme: t,
            ),
          )
        : null;

    final List<Widget> bodyChildren;
    if (compact) {
      // 3-row stack: tools / palette+size / opacity+trailing
      bodyChildren = [
        Align(alignment: Alignment.centerLeft, child: toolsRow),
        SizedBox(height: t.spacing),
        Wrap(
          spacing: t.spacing,
          runSpacing: t.spacing,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [paletteRow, sizeSlider],
        ),
        SizedBox(height: t.spacing),
        Wrap(
          spacing: t.spacing,
          runSpacing: t.spacing,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (opacitySlider != null) opacitySlider,
            ...trailingChildren,
          ],
        ),
        if (showTransformActions)
          _SelectionActionsRow(canvasKey: canvasKey),
      ];
    } else {
      // Wide 2-row layout (the classic 0.11.0 shape).
      bodyChildren = [
        Row(
          children: [
            Expanded(child: toolsRow),
            SizedBox(width: t.spacingTight),
            ...trailingChildren,
          ],
        ),
        SizedBox(height: t.spacing),
        Wrap(
          spacing: t.spacing,
          runSpacing: t.spacing,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            paletteRow,
            sizeSlider,
            if (opacitySlider != null) opacitySlider,
          ],
        ),
        if (showTransformActions)
          _SelectionActionsRow(canvasKey: canvasKey),
      ];
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: background == null
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [gradStart, gradEnd],
              )
            : null,
        color: background,
        border: Border(
          top: BorderSide(
            color: outline.withValues(alpha: 0.5),
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: bodyChildren,
          ),
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

  /// Open the [FlueraStickerPanel] in a Material bottom sheet. Wired
  /// from the trailing emoji IconButton when [showStickerPanel] is
  /// `true`. Closes itself when the user taps a sticker so the canvas
  /// is immediately visible to position the freshly-dropped node.
  void _openStickerSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        return FractionallySizedBox(
          heightFactor: 0.55,
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
                    stickersBottomSheetTitle ?? 'Stickers',
                    style: Theme.of(sheetCtx).textTheme.titleMedium,
                  ),
                ),
                Expanded(
                  child: FlueraStickerPanel(
                    canvasKey: canvasKey,
                    stickers: stickers,
                    onSelected: (_, __) => Navigator.of(sheetCtx).maybePop(),
                  ),
                ),
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
    required this.color,
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
    required this.theme,
  });

  final CanvasTool tool;
  final Color color;
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
  final FlueraToolbarTheme theme;

  bool get _isEraserTool =>
      tool == CanvasTool.erase || tool == CanvasTool.erasePixel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final useEraser = _isEraserTool &&
        eraserRadius != null &&
        onEraserRadiusChanged != null;

    final double value;
    final double minV;
    final double maxV;
    final int divisions;
    final ValueChanged<double> onChanged;
    if (useEraser) {
      value = eraserRadius!.clamp(minEraserRadius, maxEraserRadius);
      minV = minEraserRadius;
      maxV = maxEraserRadius;
      divisions = eraserRadiusDivisions;
      onChanged = onEraserRadiusChanged!;
    } else {
      value = strokeWidth.clamp(minStrokeWidth, maxStrokeWidth);
      minV = minStrokeWidth;
      maxV = maxStrokeWidth;
      divisions = strokeWidthDivisions;
      onChanged = onStrokeWidthChanged;
    }

    // Preview indicator — scales the live value into the previewSize
    // box so the consumer SEES the stroke / eraser radius without
    // drawing. Floor at 30% of the box so thin strokes remain visible.
    final previewDiameter = (value / maxV).clamp(0.30, 1.0) * (theme.previewSize - 4);
    final outline = theme.outlineColor ?? scheme.onSurfaceVariant;
    final previewWidget = SizedBox(
      width: theme.previewSize,
      height: theme.previewSize,
      child: Center(
        child: Container(
          width: previewDiameter,
          height: previewDiameter,
          decoration: BoxDecoration(
            color: useEraser ? Colors.transparent : color,
            shape: BoxShape.circle,
            border: Border.all(
              color: useEraser
                  ? outline
                  : Colors.black.withValues(alpha: 0.15),
              width: useEraser ? 1.5 : 1,
            ),
          ),
        ),
      ),
    );

    final activeTrack = theme.selectedFill ?? scheme.primary;
    return Row(
      children: [
        previewWidget,
        const SizedBox(width: 8),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: activeTrack,
              inactiveTrackColor:
                  theme.surfaceGradientStart ?? scheme.surfaceContainerHigh,
              thumbColor: activeTrack,
              overlayColor: activeTrack.withValues(alpha: 0.12),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            ),
            child: Slider(
              value: value,
              min: minV,
              max: maxV,
              divisions: divisions,
              label: useEraser
                  ? 'Eraser ${value.toStringAsFixed(0)} px'
                  : '${value.toStringAsFixed(1)} px',
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}

class _MoreColorsButton extends StatelessWidget {
  const _MoreColorsButton({
    required this.currentColor,
    required this.onPicked,
    required this.theme,
  });
  final Color currentColor;
  final ValueChanged<Color> onPicked;
  final FlueraToolbarTheme theme;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () async {
          final picked = await showFlueraColorPicker(
            context: context,
            initial: currentColor,
          );
          if (picked != null) onPicked(picked);
        },
        child: Container(
          width: theme.swatchSize,
          height: theme.swatchSize,
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
              color: theme.outlineColor ?? scheme.outlineVariant,
              width: 1,
            ),
          ),
          child: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
        ),
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
    required this.theme,
    required this.strings,
  });

  final GlobalKey<FlueraCanvasState> canvasKey;
  final bool showUndo;
  final bool showRedo;
  final bool showClear;
  final FlueraToolbarTheme theme;
  final FlueraStrings strings;

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
          _TrailingIconButton(
            icon: Icons.undo_rounded,
            tooltip: strings.undoTooltip,
            onPressed: canUndo ? () => state?.undo() : null,
            theme: theme,
          ),
        if (showRedo)
          _TrailingIconButton(
            icon: Icons.redo_rounded,
            tooltip: strings.redoTooltip,
            onPressed: canRedo ? () => state?.redo() : null,
            theme: theme,
          ),
        if (showClear)
          _TrailingIconButton(
            icon: Icons.delete_outline_rounded,
            tooltip: strings.clearTooltip,
            destructive: true,
            onPressed: state == null ? null : () => state.clear(),
            theme: theme,
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
    required this.theme,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;
  final FlueraToolbarTheme theme;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ring = theme.swatchRingColor ?? scheme.primary;
    final outline = theme.outlineColor ?? scheme.outlineVariant;
    final isWhite = color.r > 0.95 && color.g > 0.95 && color.b > 0.95;
    return Tooltip(
      message: '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
      verticalOffset: 18,
      child: SizedBox(
        width: theme.swatchSize,
        height: theme.swatchSize,
        child: Material(
          color: Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: AnimatedContainer(
              duration: theme.motion,
              curve: theme.motionCurve,
              padding: EdgeInsets.all(selected ? 3 : 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(color: ring, width: 2.5)
                    : null,
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: ring.withValues(
                            alpha: theme.elevatedShadowOpacity,
                          ),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ]
                    : null,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: isWhite
                      ? Border.all(color: outline, width: 1)
                      : null,
                  boxShadow: selected
                      ? null
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 1.5,
                            offset: const Offset(0, 1),
                          ),
                        ],
                ),
              ),
            ),
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

// ─── New widgets (0.11.0 toolbar restyle) ──────────────────────────────────

/// Compares two colors ignoring their alpha channel. Used by the
/// palette-row swatches so picking a colour preserves the alpha the
/// user already dialled in via the opacity slider.
bool _sameRgb(Color a, Color b) =>
    a.r == b.r && a.g == b.g && a.b == b.b;

/// Immutable triple binding a [CanvasTool] to its rendered icon + tooltip
/// label. Internal — built once per `build()` and consumed by [_ToolPill].
@immutable
class _ToolSpec {
  const _ToolSpec(this.tool, this.icon, this.label);
  final CanvasTool tool;
  final IconData icon;
  final String label;
}

/// Pill-shaped Material 3 tool button. Selected → filled-tonal with the
/// scheme's primary container; idle → transparent + onSurfaceVariant icon.
/// Animates the background swap so tool switches feel deliberate without
/// being noisy.
class _ToolPill extends StatelessWidget {
  const _ToolPill({
    required this.spec,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  final _ToolSpec spec;
  final bool selected;
  final VoidCallback onTap;
  final FlueraToolbarTheme theme;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = theme.selectedFill ?? scheme.primary;
    final selectedIcon = theme.selectedIconColor ?? scheme.onPrimary;
    final idleIcon = theme.idleIconColor ?? scheme.onSurfaceVariant;
    return Tooltip(
      message: spec.label,
      verticalOffset: 18,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(theme.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(theme.radius),
          onTap: onTap,
          child: AnimatedContainer(
            duration: theme.motion,
            curve: theme.motionCurve,
            width: theme.tap,
            height: theme.tap,
            decoration: BoxDecoration(
              color: selected ? fill : Colors.transparent,
              borderRadius: BorderRadius.circular(theme.radius),
              boxShadow: selected && theme.elevatedShadowBlur > 0
                  ? [
                      BoxShadow(
                        color: fill.withValues(
                          alpha: theme.elevatedShadowOpacity,
                        ),
                        blurRadius: theme.elevatedShadowBlur,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              spec.icon,
              size: 22,
              color: selected ? selectedIcon : idleIcon,
            ),
          ),
        ),
      ),
    );
  }
}

/// Filled-tonal trailing icon button used for image / sticker / layers /
/// undo / redo / clear actions. Disabled state is rendered automatically
/// by `IconButton.filledTonal` when `onPressed` is null. Pass
/// `destructive: true` to tint the icon with `colorScheme.error` (used by
/// the clear button).
class _TrailingIconButton extends StatelessWidget {
  const _TrailingIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.theme,
    this.destructive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool destructive;
  final FlueraToolbarTheme theme;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final destructiveCol = theme.destructiveColor ?? scheme.error;
    final idleCol = theme.idleIconColor ?? scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton.filledTonal(
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: 22,
        style: IconButton.styleFrom(
          foregroundColor: destructive ? destructiveCol : idleCol,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.radiusSmall),
          ),
        ),
        icon: Icon(icon),
      ),
    );
  }
}

/// Opacity slider — drives the alpha channel of [color] via
/// [onColorChanged]. Preview indicator on the left shows a checkerboard
/// background behind the live colour at the current alpha so the
/// effective transparency reads at a glance.
class _OpacitySlider extends StatelessWidget {
  const _OpacitySlider({
    required this.color,
    required this.onColorChanged,
    required this.theme,
  });

  final Color color;
  final ValueChanged<Color> onColorChanged;
  final FlueraToolbarTheme theme;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final alpha = color.a.clamp(0.0, 1.0);
    final activeTrack = theme.selectedFill ?? scheme.primary;
    return Tooltip(
      message: 'Opacity ${(alpha * 100).round()}%',
      verticalOffset: 18,
      child: Row(
        children: [
          // Preview: checkerboard behind the colour swatch so partial
          // alpha is visually obvious (a flat tint over the toolbar
          // background looks misleading at, say, 40 %).
          SizedBox(
            width: theme.previewSize,
            height: theme.previewSize,
            child: ClipOval(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _CheckerPainter()),
                  ColoredBox(color: color),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: activeTrack,
                inactiveTrackColor:
                    theme.surfaceGradientStart ?? scheme.surfaceContainerHigh,
                thumbColor: activeTrack,
                overlayColor: activeTrack.withValues(alpha: 0.12),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
              ),
              child: Slider(
                value: alpha,
                divisions: 20,
                label: '${(alpha * 100).round()}%',
                onChanged: (v) => onColorChanged(color.withValues(alpha: v)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lightweight checkerboard painter for the opacity preview.
/// 2 × 2 grid of 8-px squares — large enough to read but small enough
/// to fit inside the 30-px preview circle.
class _CheckerPainter extends CustomPainter {
  static final Paint _light = Paint()..color = const Color(0xFFE0E0E0);
  static final Paint _dark = Paint()..color = const Color(0xFFBDBDBD);

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 7.0;
    canvas.drawRect(Offset.zero & size, _light);
    for (var y = 0; y < (size.height / cell).ceil(); y++) {
      for (var x = 0; x < (size.width / cell).ceil(); x++) {
        if ((x + y).isOdd) {
          canvas.drawRect(
            Rect.fromLTWH(x * cell, y * cell, cell, cell),
            _dark,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
