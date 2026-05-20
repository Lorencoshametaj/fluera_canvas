// ════════════════════════════════════════════════════════════════════════════
// 🍎 FlueraCanvasCupertinoToolbar — Apple HIG-styled drop-in toolbar.
//
// Mirror of [FlueraCanvasToolbar]'s public API (same canvasKey, tool,
// color, callbacks, theming, compact mode, i18n, all the show* flags)
// but built with Cupertino widgets — `CupertinoButton`,
// `CupertinoSlider`, `CupertinoColors`, `CupertinoIcons` — so iOS /
// macOS-targeted apps get pixel-perfect Apple aesthetics without the
// Material 3 chrome.
//
// Reuses [FlueraToolbarTheme] for geometry (radii, spacing, motion)
// and [FlueraStrings] for i18n. Color overrides on the theme still
// work; null defaults fall back to [CupertinoColors] instead of
// `Theme.of(context).colorScheme`.
//
// Consumer migration is one-line: swap `FlueraCanvasToolbar(...)` for
// `FlueraCanvasCupertinoToolbar(...)`. Same behavior, Cupertino look.
//
// Added in 0.16.1.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show Material, MaterialType, Tooltip;
import 'package:flutter/services.dart' show HapticFeedback;

import 'fluera_canvas_toolbar.dart' show kFlueraDefaultPalette;
import 'fluera_canvas_widget.dart';
import 'fluera_color_picker_dialog.dart';
import 'fluera_layer_panel.dart';
import 'fluera_strings.dart';
import 'fluera_toolbar_theme.dart';
import 'tools/image_tool.dart';
import 'widgets/fluera_sticker_panel.dart';

/// Cupertino-styled drop-in toolbar for [FlueraCanvas]. Same API as
/// [FlueraCanvasToolbar] but built with Cupertino widgets — pick this
/// when your app targets iOS / macOS with pixel-perfect Apple HIG
/// aesthetics.
///
/// ```dart
/// FlueraCanvasCupertinoToolbar(
///   canvasKey: canvasKey,
///   tool: tool,
///   onToolChanged: (t) => setState(() => tool = t),
///   color: color,
///   onColorChanged: (c) => setState(() => color = c),
///   strokeWidth: width,
///   onStrokeWidthChanged: (w) => setState(() => width = w),
/// );
/// ```
///
/// Reuses [FlueraToolbarTheme] (geometry / motion / colour overrides)
/// and [FlueraStrings] (i18n). Color overrides on the theme work
/// transparently — `null` fields fall back to [CupertinoColors]
/// defaults instead of Material `colorScheme`.
///
/// Added in 0.16.1.
class FlueraCanvasCupertinoToolbar extends StatelessWidget {
  /// Build a Cupertino-styled toolbar bound to [canvasKey]. Every
  /// parameter mirrors [FlueraCanvasToolbar] 1:1.
  const FlueraCanvasCupertinoToolbar({
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

  /// Key of the [FlueraCanvas] this toolbar controls.
  final GlobalKey<FlueraCanvasState> canvasKey;

  /// Currently selected tool.
  final CanvasTool tool;

  /// Fired when the user picks a different tool.
  final ValueChanged<CanvasTool> onToolChanged;

  /// Currently selected color.
  final Color color;

  /// Fired when the user picks a color.
  final ValueChanged<Color> onColorChanged;

  /// Currently selected stroke width.
  final double strokeWidth;

  /// Fired when the user drags the slider.
  final ValueChanged<double> onStrokeWidthChanged;

  /// Color swatches shown in the toolbar.
  final List<Color> palette;

  /// Stroke-width slider lower bound.
  final double minStrokeWidth;

  /// Stroke-width slider upper bound.
  final double maxStrokeWidth;

  /// Stroke-width slider divisions.
  final int strokeWidthDivisions;

  /// Toggle the undo trailing button.
  final bool showUndo;

  /// Toggle the redo trailing button.
  final bool showRedo;

  /// Toggle the clear trailing button.
  final bool showClear;

  /// Toggle line / rectangle / ellipse tools.
  final bool showShapeTools;

  /// Toggle the pixel-eraser tool.
  final bool showPixelEraser;

  /// Toggle the more-colors picker trailing button.
  final bool showColorPickerButton;

  /// Toggle the layers trailing button + bottom sheet.
  final bool showLayers;

  /// Override the layers bottom-sheet title.
  final String? layersBottomSheetTitle;

  /// Toggle the selection-marquee tool.
  final bool showSelectionTool;

  /// Toggle the lasso tool.
  final bool showLassoTool;

  /// Toggle the image-import trailing button.
  final bool showImageTool;

  /// Toggle the text tool.
  final bool showTextTool;

  /// Toggle the sticker-panel trailing button.
  final bool showStickerPanel;

  /// Sticker catalogue.
  final List<FlueraSticker> stickers;

  /// Override the stickers bottom-sheet title.
  final String? stickersBottomSheetTitle;

  /// Toggle the selection-action row.
  final bool showTransformActions;

  /// Current eraser radius in screen pixels.
  final double? eraserRadius;

  /// Fired when the user drags the slider while the eraser is active.
  final ValueChanged<double>? onEraserRadiusChanged;

  /// Eraser-radius slider lower bound.
  final double minEraserRadius;

  /// Eraser-radius slider upper bound.
  final double maxEraserRadius;

  /// Eraser-radius slider divisions.
  final int eraserRadiusDivisions;

  /// Toggle the opacity slider.
  final bool showOpacitySlider;

  /// Inner padding around the toolbar content.
  final EdgeInsetsGeometry padding;

  /// Optional background color override.
  final Color? background;

  /// Optional theme override.
  final FlueraToolbarTheme? theme;

  /// Compact-mode breakpoint (px). Pass `0` to disable.
  final double compactBreakpoint;

  /// Optional localised string set.
  final FlueraStrings? strings;

  @override
  Widget build(BuildContext context) {
    // FlueraToolbarTheme uses geometry-only for Cupertino (color
    // overrides remain valid; null fields fall back to CupertinoColors
    // at consume time instead of Material colorScheme). We don't
    // attempt to read it via `Theme.of(context).extension<...>()`
    // because Cupertino apps may not have a Material ancestor;
    // consumers who want a custom theme pass it via the [theme] prop.
    final t = theme ?? FlueraToolbarTheme.defaults;
    final s = strings ?? FlueraStrings.defaults;

    final tools = <_CTool>[
      _CTool(CanvasTool.draw, CupertinoIcons.pencil, s.toolPen),
      _CTool(CanvasTool.erase, CupertinoIcons.bandage, s.toolErase),
      if (showPixelEraser)
        _CTool(CanvasTool.erasePixel, CupertinoIcons.scissors, s.toolPixel),
      if (showShapeTools) ...[
        _CTool(CanvasTool.line, CupertinoIcons.minus, s.toolLine),
        _CTool(CanvasTool.rectangle, CupertinoIcons.rectangle, s.toolRect),
        _CTool(CanvasTool.ellipse, CupertinoIcons.circle, s.toolOval),
      ],
      if (showSelectionTool)
        _CTool(CanvasTool.select, CupertinoIcons.crop, s.toolSelect),
      if (showLassoTool)
        _CTool(CanvasTool.lasso, CupertinoIcons.lasso, s.toolLasso),
      if (showTextTool)
        _CTool(CanvasTool.text, CupertinoIcons.textformat, s.toolText),
    ];

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final compact = compactBreakpoint > 0 &&
            constraints.maxWidth.isFinite &&
            constraints.maxWidth < compactBreakpoint;
        return _buildLayout(
          context,
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
    required FlueraToolbarTheme t,
    required FlueraStrings s,
    required List<_CTool> tools,
    required bool compact,
  }) {
    final separator = t.outlineColor ?? CupertinoColors.separator;
    final surface = background ??
        CupertinoDynamicColor.resolve(
          CupertinoColors.systemGrey6,
          context,
        );
    final sliderW = compact ? t.compactSliderWidth : t.sliderWidth;

    final toolsRow = Wrap(
      spacing: t.spacingTight,
      runSpacing: t.spacingTight,
      children: [
        for (final spec in tools)
          _CupertinoToolPill(
            spec: spec,
            selected: spec.tool == tool,
            onTap: () => onToolChanged(spec.tool),
            theme: t,
          ),
      ],
    );

    final trailingChildren = <Widget>[
      if (showImageTool)
        _CupertinoTrailingButton(
          icon: CupertinoIcons.photo,
          tooltip: s.insertImageTooltip,
          onPressed: () {
            final state = canvasKey.currentState;
            if (state == null) return;
            FlueraImageTool.pickAndCommit(context, state);
          },
          theme: t,
        ),
      if (showStickerPanel)
        _CupertinoTrailingButton(
          icon: CupertinoIcons.smiley,
          tooltip: s.stickersTooltip,
          onPressed: () => _openStickerSheet(context, s),
          theme: t,
        ),
      if (showLayers)
        _CupertinoTrailingButton(
          icon: CupertinoIcons.square_stack_3d_up,
          tooltip: s.layersTooltip,
          onPressed: () => _openLayersSheet(context, s),
          theme: t,
        ),
      _CupertinoHistoryButtons(
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
          _CupertinoSwatch(
            color: c,
            selected: _sameRgb(c, color),
            onTap: () => onColorChanged(c.withValues(alpha: color.a)),
            theme: t,
          ),
        if (showColorPickerButton)
          _CupertinoMoreColorsButton(
            currentColor: color,
            onPicked: onColorChanged,
            theme: t,
          ),
      ],
    );

    final sizeSlider = SizedBox(
      width: sliderW,
      child: _CupertinoSizeSlider(
        tool: tool,
        color: color,
        strokeWidth: strokeWidth,
        onStrokeWidthChanged: onStrokeWidthChanged,
        minStrokeWidth: minStrokeWidth,
        maxStrokeWidth: maxStrokeWidth,
        eraserRadius: eraserRadius,
        onEraserRadiusChanged: onEraserRadiusChanged,
        minEraserRadius: minEraserRadius,
        maxEraserRadius: maxEraserRadius,
        theme: t,
      ),
    );

    final showOpacity = showOpacitySlider &&
        tool != CanvasTool.erase &&
        tool != CanvasTool.erasePixel;
    final opacitySlider = showOpacity
        ? SizedBox(
            width: sliderW,
            child: _CupertinoOpacitySlider(
              color: color,
              onColorChanged: onColorChanged,
              theme: t,
            ),
          )
        : null;

    final List<Widget> bodyChildren;
    if (compact) {
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
          _CupertinoSelectionActionsRow(
            canvasKey: canvasKey,
            strings: s,
            theme: t,
          ),
      ];
    } else {
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
          _CupertinoSelectionActionsRow(
            canvasKey: canvasKey,
            strings: s,
            theme: t,
          ),
      ];
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
        // iOS-style hairline divider on the top edge — 0.33 px is the
        // actual UIKit thickness used in tab bars / toolbars.
        border: Border(
          top: BorderSide(color: separator, width: 0.33),
        ),
      ),
      child: SafeArea(
        top: false,
        // Material wrapper so any descendant Tooltip / InkWell still
        // works (Cupertino doesn't ship a tooltip primitive).
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: bodyChildren,
            ),
          ),
        ),
      ),
    );
  }

  void _openLayersSheet(BuildContext context, FlueraStrings s) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetCtx) {
        return Container(
          height: MediaQuery.of(sheetCtx).size.height * 0.6,
          color: CupertinoColors.systemBackground.resolveFrom(sheetCtx),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        layersBottomSheetTitle ?? s.layersBottomSheetTitle,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(child: FlueraLayerPanel(canvasKey: canvasKey)),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openStickerSheet(BuildContext context, FlueraStrings s) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetCtx) {
        return Container(
          height: MediaQuery.of(sheetCtx).size.height * 0.55,
          color: CupertinoColors.systemBackground.resolveFrom(sheetCtx),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(
                        stickersBottomSheetTitle ?? s.stickersBottomSheetTitle,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: FlueraStickerPanel(
                        canvasKey: canvasKey,
                        stickers: stickers,
                        onSelected: (_, __) =>
                            Navigator.of(sheetCtx).maybePop(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

bool _sameRgb(Color a, Color b) =>
    a.r == b.r && a.g == b.g && a.b == b.b;

class _CTool {
  const _CTool(this.tool, this.icon, this.label);
  final CanvasTool tool;
  final IconData icon;
  final String label;
}

class _CupertinoToolPill extends StatelessWidget {
  const _CupertinoToolPill({
    required this.spec,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  final _CTool spec;
  final bool selected;
  final VoidCallback onTap;
  final FlueraToolbarTheme theme;

  @override
  Widget build(BuildContext context) {
    final fill = theme.selectedFill ??
        CupertinoColors.activeBlue.resolveFrom(context);
    final selectedIcon = theme.selectedIconColor ?? CupertinoColors.white;
    final idleIcon = theme.idleIconColor ??
        CupertinoColors.label.resolveFrom(context);
    return Tooltip(
      message: spec.label,
      verticalOffset: 18,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: theme.motion,
          curve: theme.motionCurve,
          width: theme.tap,
          height: theme.tap,
          decoration: BoxDecoration(
            color: selected ? fill : CupertinoColors.transparent,
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
    );
  }
}

class _CupertinoSwatch extends StatelessWidget {
  const _CupertinoSwatch({
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
    final ring = theme.swatchRingColor ??
        CupertinoColors.activeBlue.resolveFrom(context);
    final outline = theme.outlineColor ??
        CupertinoColors.separator.resolveFrom(context);
    final isWhite = color.r > 0.95 && color.g > 0.95 && color.b > 0.95;
    return Tooltip(
      message:
          '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
      verticalOffset: 18,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: theme.motion,
          curve: theme.motionCurve,
          width: theme.swatchSize,
          height: theme.swatchSize,
          padding: EdgeInsets.all(selected ? 3 : 0),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: selected ? Border.all(color: ring, width: 2.5) : null,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border:
                  isWhite ? Border.all(color: outline, width: 1) : null,
            ),
          ),
        ),
      ),
    );
  }
}

class _CupertinoMoreColorsButton extends StatelessWidget {
  const _CupertinoMoreColorsButton({
    required this.currentColor,
    required this.onPicked,
    required this.theme,
  });
  final Color currentColor;
  final ValueChanged<Color> onPicked;
  final FlueraToolbarTheme theme;

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
        width: theme.swatchSize,
        height: theme.swatchSize,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
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
        ),
        child: const Icon(
          CupertinoIcons.add,
          size: 16,
          color: CupertinoColors.white,
        ),
      ),
    );
  }
}

class _CupertinoTrailingButton extends StatelessWidget {
  const _CupertinoTrailingButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.theme,
    this.destructive = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final FlueraToolbarTheme theme;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final destructiveCol = theme.destructiveColor ??
        CupertinoColors.systemRed.resolveFrom(context);
    final idleCol = theme.idleIconColor ??
        CupertinoColors.label.resolveFrom(context);
    final disabled = onPressed == null;
    return Tooltip(
      message: tooltip,
      verticalOffset: 18,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: Size(theme.tap, theme.tap),
          borderRadius: BorderRadius.circular(theme.radiusSmall),
          onPressed: onPressed,
          child: Icon(
            icon,
            size: 22,
            color: disabled
                ? CupertinoColors.systemGrey3.resolveFrom(context)
                : (destructive ? destructiveCol : idleCol),
          ),
        ),
      ),
    );
  }
}

class _CupertinoHistoryButtons extends StatelessWidget {
  const _CupertinoHistoryButtons({
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
    final state = canvasKey.currentState;
    if (state == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) (context as Element).markNeedsBuild();
      });
      return _buildButtons(context, canUndo: false, canRedo: false);
    }
    return ListenableBuilder(
      listenable: state.historyListenable,
      builder: (ctx, _) => _buildButtons(
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
          _CupertinoTrailingButton(
            icon: CupertinoIcons.arrow_uturn_left,
            tooltip: strings.undoTooltip,
            onPressed: canUndo ? () => state?.undo() : null,
            theme: theme,
          ),
        if (showRedo)
          _CupertinoTrailingButton(
            icon: CupertinoIcons.arrow_uturn_right,
            tooltip: strings.redoTooltip,
            onPressed: canRedo ? () => state?.redo() : null,
            theme: theme,
          ),
        if (showClear)
          _CupertinoTrailingButton(
            icon: CupertinoIcons.delete,
            tooltip: strings.clearTooltip,
            destructive: true,
            onPressed: state == null ? null : () => state.clear(),
            theme: theme,
          ),
      ],
    );
  }
}

class _CupertinoSizeSlider extends StatelessWidget {
  const _CupertinoSizeSlider({
    required this.tool,
    required this.color,
    required this.strokeWidth,
    required this.onStrokeWidthChanged,
    required this.minStrokeWidth,
    required this.maxStrokeWidth,
    required this.eraserRadius,
    required this.onEraserRadiusChanged,
    required this.minEraserRadius,
    required this.maxEraserRadius,
    required this.theme,
  });

  final CanvasTool tool;
  final Color color;
  final double strokeWidth;
  final ValueChanged<double> onStrokeWidthChanged;
  final double minStrokeWidth;
  final double maxStrokeWidth;
  final double? eraserRadius;
  final ValueChanged<double>? onEraserRadiusChanged;
  final double minEraserRadius;
  final double maxEraserRadius;
  final FlueraToolbarTheme theme;

  bool get _isEraserTool =>
      tool == CanvasTool.erase || tool == CanvasTool.erasePixel;

  @override
  Widget build(BuildContext context) {
    final useEraser = _isEraserTool &&
        eraserRadius != null &&
        onEraserRadiusChanged != null;

    final value = useEraser
        ? eraserRadius!.clamp(minEraserRadius, maxEraserRadius)
        : strokeWidth.clamp(minStrokeWidth, maxStrokeWidth);
    final minV = useEraser ? minEraserRadius : minStrokeWidth;
    final maxV = useEraser ? maxEraserRadius : maxStrokeWidth;
    final onChanged = useEraser ? onEraserRadiusChanged! : onStrokeWidthChanged;

    final previewDiameter =
        (value / maxV).clamp(0.30, 1.0) * (theme.previewSize - 4);
    final outline = theme.outlineColor ??
        CupertinoColors.systemGrey.resolveFrom(context);
    final preview = SizedBox(
      width: theme.previewSize,
      height: theme.previewSize,
      child: Center(
        child: Container(
          width: previewDiameter,
          height: previewDiameter,
          decoration: BoxDecoration(
            color: useEraser ? CupertinoColors.transparent : color,
            shape: BoxShape.circle,
            border: Border.all(
              color: useEraser
                  ? outline
                  : CupertinoColors.black.withValues(alpha: 0.15),
              width: useEraser ? 1.5 : 1,
            ),
          ),
        ),
      ),
    );

    return Row(
      children: [
        preview,
        const SizedBox(width: 8),
        Expanded(
          child: CupertinoSlider(
            value: value,
            min: minV,
            max: maxV,
            activeColor: theme.selectedFill ??
                CupertinoColors.activeBlue.resolveFrom(context),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _CupertinoOpacitySlider extends StatelessWidget {
  const _CupertinoOpacitySlider({
    required this.color,
    required this.onColorChanged,
    required this.theme,
  });

  final Color color;
  final ValueChanged<Color> onColorChanged;
  final FlueraToolbarTheme theme;

  @override
  Widget build(BuildContext context) {
    final alpha = color.a.clamp(0.0, 1.0);
    final activeTrack = theme.selectedFill ??
        CupertinoColors.activeBlue.resolveFrom(context);
    return Tooltip(
      message: 'Opacity ${(alpha * 100).round()}%',
      verticalOffset: 18,
      child: Row(
        children: [
          SizedBox(
            width: theme.previewSize,
            height: theme.previewSize,
            child: ClipOval(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _CupertinoCheckerPainter()),
                  ColoredBox(color: color),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: CupertinoSlider(
              value: alpha,
              activeColor: activeTrack,
              onChanged: (v) => onColorChanged(color.withValues(alpha: v)),
            ),
          ),
        ],
      ),
    );
  }
}

class _CupertinoCheckerPainter extends CustomPainter {
  static final Paint _light = Paint()..color = const Color(0xFFE0E0E0);
  static final Paint _dark = Paint()..color = const Color(0xFFBDBDBD);

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 7.0;
    canvas.drawRect(Offset.zero & size, _light);
    final cols = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
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

class _CupertinoSelectionActionsRow extends StatelessWidget {
  const _CupertinoSelectionActionsRow({
    required this.canvasKey,
    required this.strings,
    required this.theme,
  });

  final GlobalKey<FlueraCanvasState> canvasKey;
  final FlueraStrings strings;
  final FlueraToolbarTheme theme;

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
                '${state.selection.length} ${strings.selectedSuffix}',
                style: TextStyle(
                  fontSize: 13,
                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
              const Spacer(),
              _CupertinoTrailingButton(
                icon: CupertinoIcons.arrow_left_right,
                tooltip: strings.mirrorHorizontalTooltip,
                onPressed: () => state.mirrorSelection(Axis.horizontal),
                theme: theme,
              ),
              Transform.rotate(
                angle: math.pi / 2,
                child: _CupertinoTrailingButton(
                  icon: CupertinoIcons.arrow_left_right,
                  tooltip: strings.mirrorVerticalTooltip,
                  onPressed: () => state.mirrorSelection(Axis.vertical),
                  theme: theme,
                ),
              ),
              _CupertinoTrailingButton(
                icon: CupertinoIcons.delete,
                tooltip: strings.deleteSelectionTooltip,
                onPressed: () => state.deleteSelection(),
                theme: theme,
                destructive: true,
              ),
              _CupertinoTrailingButton(
                icon: CupertinoIcons.clear,
                tooltip: strings.clearSelectionTooltip,
                onPressed: () => state.clearSelection(),
                theme: theme,
              ),
            ],
          ),
        );
      },
    );
  }
}
