// ════════════════════════════════════════════════════════════════════════════
// 🌍 FlueraStrings — i18n delegate for the drop-in toolbar.
//
// Localise every visible string in `FlueraCanvasToolbar` (tooltips,
// labels, dialog titles, sheet titles) without forking the widget.
// Apply globally via `ThemeData.extensions: [FlueraStrings(...)]`,
// or per-toolbar via the `strings:` parameter (wins over the global
// extension when both are set — same priority pattern as
// FlueraToolbarTheme).
//
// Defaults are English. Pass a translated instance to ship in any
// other language without taking a runtime dependency on
// `flutter_localizations`.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

/// Localisable strings consumed by [FlueraCanvasToolbar].
///
/// ```dart
/// MaterialApp(
///   theme: ThemeData(
///     extensions: const [
///       FlueraStrings(
///         toolPen: 'Penna',
///         toolErase: 'Gomma',
///         clearTooltip: 'Pulisci',
///       ),
///     ],
///   ),
///   home: ...,
/// );
/// ```
///
/// Every field has a sensible English default — partial overrides
/// only translate the strings you provide.
///
/// Added in 0.16.0.
@immutable
class FlueraStrings extends ThemeExtension<FlueraStrings> {
  /// Build a custom string set. Every field is optional and defaults
  /// to its English label.
  const FlueraStrings({
    this.toolPen = 'Pen',
    this.toolErase = 'Erase',
    this.toolPixel = 'Pixel',
    this.toolLine = 'Line',
    this.toolRect = 'Rect',
    this.toolOval = 'Oval',
    this.toolSelect = 'Select',
    this.toolLasso = 'Lasso',
    this.toolText = 'Text',
    this.insertImageTooltip = 'Insert image',
    this.stickersTooltip = 'Stickers',
    this.layersTooltip = 'Layers',
    this.undoTooltip = 'Undo',
    this.redoTooltip = 'Redo',
    this.clearTooltip = 'Clear',
    this.layersBottomSheetTitle = 'Layers',
    this.stickersBottomSheetTitle = 'Stickers',
    this.mirrorHorizontalTooltip = 'Mirror horizontally',
    this.mirrorVerticalTooltip = 'Mirror vertically',
    this.deleteSelectionTooltip = 'Delete selection',
    this.clearSelectionTooltip = 'Clear selection',
    this.opacityLabel = 'Opacity',
    this.eraserLabel = 'Eraser',
    this.selectedSuffix = 'selected',
  });

  /// Tooltip for the pen / draw tool pill.
  final String toolPen;

  /// Tooltip for the stroke-eraser tool pill.
  final String toolErase;

  /// Tooltip for the pixel-eraser tool pill (when `showPixelEraser`).
  final String toolPixel;

  /// Tooltip for the line-shape tool pill (when `showShapeTools`).
  final String toolLine;

  /// Tooltip for the rectangle-shape tool pill.
  final String toolRect;

  /// Tooltip for the ellipse-shape tool pill.
  final String toolOval;

  /// Tooltip for the selection-marquee tool pill (when `showSelectionTool`).
  final String toolSelect;

  /// Tooltip for the lasso tool pill (when `showLassoTool`).
  final String toolLasso;

  /// Tooltip for the text tool pill (when `showTextTool`).
  final String toolText;

  /// Tooltip on the trailing image-insertion icon (when `showImageTool`).
  final String insertImageTooltip;

  /// Tooltip on the trailing sticker-panel icon (when `showStickerPanel`).
  final String stickersTooltip;

  /// Tooltip on the trailing layers-panel icon (when `showLayers`).
  final String layersTooltip;

  /// Tooltip on the trailing undo button.
  final String undoTooltip;

  /// Tooltip on the trailing redo button.
  final String redoTooltip;

  /// Tooltip on the trailing clear-canvas button.
  final String clearTooltip;

  /// Header text shown above the layers bottom sheet.
  final String layersBottomSheetTitle;

  /// Header text shown above the stickers bottom sheet.
  final String stickersBottomSheetTitle;

  /// Tooltip on the selection-action mirror-horizontal button.
  final String mirrorHorizontalTooltip;

  /// Tooltip on the selection-action mirror-vertical button.
  final String mirrorVerticalTooltip;

  /// Tooltip on the selection-action delete button.
  final String deleteSelectionTooltip;

  /// Tooltip on the selection-action clear button.
  final String clearSelectionTooltip;

  /// Label prefix shown by the opacity slider tooltip
  /// (`"$opacityLabel 50%"`).
  final String opacityLabel;

  /// Label prefix shown by the eraser-radius slider
  /// (`"$eraserLabel 32 px"`).
  final String eraserLabel;

  /// Suffix appended to the selection count
  /// (`"3 $selectedSuffix"`).
  final String selectedSuffix;

  /// Default English string set — equivalent to a zero-arg
  /// `FlueraStrings()`. Provided as a static so consumers can write
  /// `FlueraStrings.defaults.copyWith(toolPen: 'Penna')`.
  static const FlueraStrings defaults = FlueraStrings();

  @override
  FlueraStrings copyWith({
    String? toolPen,
    String? toolErase,
    String? toolPixel,
    String? toolLine,
    String? toolRect,
    String? toolOval,
    String? toolSelect,
    String? toolLasso,
    String? toolText,
    String? insertImageTooltip,
    String? stickersTooltip,
    String? layersTooltip,
    String? undoTooltip,
    String? redoTooltip,
    String? clearTooltip,
    String? layersBottomSheetTitle,
    String? stickersBottomSheetTitle,
    String? mirrorHorizontalTooltip,
    String? mirrorVerticalTooltip,
    String? deleteSelectionTooltip,
    String? clearSelectionTooltip,
    String? opacityLabel,
    String? eraserLabel,
    String? selectedSuffix,
  }) {
    return FlueraStrings(
      toolPen: toolPen ?? this.toolPen,
      toolErase: toolErase ?? this.toolErase,
      toolPixel: toolPixel ?? this.toolPixel,
      toolLine: toolLine ?? this.toolLine,
      toolRect: toolRect ?? this.toolRect,
      toolOval: toolOval ?? this.toolOval,
      toolSelect: toolSelect ?? this.toolSelect,
      toolLasso: toolLasso ?? this.toolLasso,
      toolText: toolText ?? this.toolText,
      insertImageTooltip: insertImageTooltip ?? this.insertImageTooltip,
      stickersTooltip: stickersTooltip ?? this.stickersTooltip,
      layersTooltip: layersTooltip ?? this.layersTooltip,
      undoTooltip: undoTooltip ?? this.undoTooltip,
      redoTooltip: redoTooltip ?? this.redoTooltip,
      clearTooltip: clearTooltip ?? this.clearTooltip,
      layersBottomSheetTitle:
          layersBottomSheetTitle ?? this.layersBottomSheetTitle,
      stickersBottomSheetTitle:
          stickersBottomSheetTitle ?? this.stickersBottomSheetTitle,
      mirrorHorizontalTooltip:
          mirrorHorizontalTooltip ?? this.mirrorHorizontalTooltip,
      mirrorVerticalTooltip:
          mirrorVerticalTooltip ?? this.mirrorVerticalTooltip,
      deleteSelectionTooltip:
          deleteSelectionTooltip ?? this.deleteSelectionTooltip,
      clearSelectionTooltip:
          clearSelectionTooltip ?? this.clearSelectionTooltip,
      opacityLabel: opacityLabel ?? this.opacityLabel,
      eraserLabel: eraserLabel ?? this.eraserLabel,
      selectedSuffix: selectedSuffix ?? this.selectedSuffix,
    );
  }

  @override
  FlueraStrings lerp(
    covariant ThemeExtension<FlueraStrings>? other,
    double t,
  ) {
    // Strings don't lerp — pick the destination instance once we
    // cross the midpoint. Keeps animations between themes monotonic.
    if (other is! FlueraStrings) return this;
    return t < 0.5 ? this : other;
  }
}
