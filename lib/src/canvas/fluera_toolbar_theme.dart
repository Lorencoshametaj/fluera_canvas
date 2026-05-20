// ════════════════════════════════════════════════════════════════════════════
// 🎨 FlueraToolbarTheme — opt-in theming for [FlueraCanvasToolbar].
//
// A `ThemeExtension<T>` that lets consumers override the toolbar's
// geometry, motion and colour decisions WITHOUT forking the widget.
// Apply globally via `ThemeData.extensions: [FlueraToolbarTheme(...)]`,
// or locally per-toolbar via the `theme:` parameter.
//
// Geometry fields are concrete (always have a value); colour fields are
// nullable — `null` means "derive from `Theme.of(context).colorScheme`",
// so a consumer who only wants to override `selectedFill` doesn't have to
// re-specify the whole palette.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

/// Theme extension for the drop-in [FlueraCanvasToolbar].
///
/// Apply globally so every `FlueraCanvasToolbar` in the subtree picks
/// it up automatically:
///
/// ```dart
/// MaterialApp(
///   theme: ThemeData(
///     useMaterial3: true,
///     extensions: const [
///       FlueraToolbarTheme(
///         selectedFill: Color(0xFF6750A4),
///         swatchSize: 36,
///       ),
///     ],
///   ),
///   home: ...,
/// );
/// ```
///
/// Or apply locally on a single toolbar (this wins over the global
/// extension if both are set):
///
/// ```dart
/// FlueraCanvasToolbar(
///   theme: const FlueraToolbarTheme(radius: 8, motion: Duration(milliseconds: 120)),
///   ...
/// )
/// ```
///
/// Colour fields default to `null`, meaning the toolbar falls back to
/// `Theme.of(context).colorScheme`. This is intentional — most consumers
/// only want to tweak one or two accents (brand selectedFill, brand
/// destructive) and let the rest follow their existing colorScheme.
@immutable
class FlueraToolbarTheme extends ThemeExtension<FlueraToolbarTheme> {
  /// Build a custom toolbar theme. Every field has a sensible default
  /// matching the unbranded Material 3 look used by the package's own
  /// `FlueraSketchApp`.
  const FlueraToolbarTheme({
    this.radius = 14.0,
    this.radiusSmall = 10.0,
    this.swatchSize = 30.0,
    this.previewSize = 30.0,
    this.tap = 44.0,
    this.spacing = 10.0,
    this.spacingTight = 6.0,
    this.sliderWidth = 220.0,
    this.compactSliderWidth = 140.0,
    this.motion = const Duration(milliseconds: 200),
    this.motionCurve = Curves.easeOutCubic,
    this.selectedFill,
    this.selectedIconColor,
    this.idleIconColor,
    this.destructiveColor,
    this.swatchRingColor,
    this.surfaceGradientStart,
    this.surfaceGradientEnd,
    this.outlineColor,
    this.elevatedShadowBlur = 6.0,
    this.elevatedShadowOpacity = 0.25,
  });

  /// Standard rounded-corner radius for tool pills and the slider's
  /// preview chip. Default `14.0`.
  final double radius;

  /// Smaller radius used for trailing filled-tonal icon buttons.
  /// Default `10.0`.
  final double radiusSmall;

  /// Diameter (px) of the circular colour swatches in the palette row.
  /// Default `30.0`.
  final double swatchSize;

  /// Diameter (px) of the stroke-width / opacity preview indicator
  /// shown to the left of each slider. Default `30.0`.
  final double previewSize;

  /// Minimum touch-target size (px) of tool pills and trailing buttons.
  /// Material 3 minimum is `44`; lower values risk failing accessibility
  /// audits. Default `44.0`.
  final double tap;

  /// Default inter-element spacing (px) between toolbar groups.
  /// Default `10.0`.
  final double spacing;

  /// Tighter spacing (px) between adjacent siblings inside a single
  /// button group (e.g. between two tool pills). Default `6.0`.
  final double spacingTight;

  /// Width (px) of each slider in the wide layout (>= `compactBreakpoint`).
  /// Default `220.0`.
  final double sliderWidth;

  /// Width (px) of each slider in the compact layout (< `compactBreakpoint`).
  /// Default `140.0`.
  final double compactSliderWidth;

  /// Duration of the cross-state transition on selected ↔ idle pills
  /// and swatch ring. Default `200ms`.
  final Duration motion;

  /// Curve applied to [motion]. Default [Curves.easeOutCubic].
  final Curve motionCurve;

  /// Background of a SELECTED tool pill. `null` → `colorScheme.primary`.
  final Color? selectedFill;

  /// Foreground (icon) of a SELECTED tool pill. `null` → `colorScheme.onPrimary`.
  final Color? selectedIconColor;

  /// Foreground (icon) of an IDLE tool pill or trailing button.
  /// `null` → `colorScheme.onSurfaceVariant`.
  final Color? idleIconColor;

  /// Foreground colour for destructive actions (e.g. clear). `null` →
  /// `colorScheme.error`.
  final Color? destructiveColor;

  /// Ring colour around a SELECTED colour swatch. `null` → `colorScheme.primary`.
  final Color? swatchRingColor;

  /// Top stop of the toolbar's vertical surface gradient.
  /// `null` → `colorScheme.surfaceContainerHigh`.
  final Color? surfaceGradientStart;

  /// Bottom stop of the toolbar's vertical surface gradient.
  /// `null` → `colorScheme.surfaceContainerHighest`.
  final Color? surfaceGradientEnd;

  /// Hairline / outline colour for swatch borders and slider track
  /// secondary lines. `null` → `colorScheme.outlineVariant`.
  final Color? outlineColor;

  /// Blur radius (px) of the soft drop shadow under SELECTED pills /
  /// swatches. Default `6.0`. Set to `0` to disable.
  final double elevatedShadowBlur;

  /// Alpha (0..1) of the drop shadow under SELECTED elements (computed
  /// over [selectedFill] or `colorScheme.primary`). Default `0.25`.
  final double elevatedShadowOpacity;

  /// Default theme — equivalent to a zero-arg `FlueraToolbarTheme()`.
  /// Provided as a static so consumers can write
  /// `FlueraToolbarTheme.defaults.copyWith(swatchSize: 40)` instead of
  /// repeating every field.
  static const FlueraToolbarTheme defaults = FlueraToolbarTheme();

  @override
  FlueraToolbarTheme copyWith({
    double? radius,
    double? radiusSmall,
    double? swatchSize,
    double? previewSize,
    double? tap,
    double? spacing,
    double? spacingTight,
    double? sliderWidth,
    double? compactSliderWidth,
    Duration? motion,
    Curve? motionCurve,
    Color? selectedFill,
    Color? selectedIconColor,
    Color? idleIconColor,
    Color? destructiveColor,
    Color? swatchRingColor,
    Color? surfaceGradientStart,
    Color? surfaceGradientEnd,
    Color? outlineColor,
    double? elevatedShadowBlur,
    double? elevatedShadowOpacity,
  }) {
    return FlueraToolbarTheme(
      radius: radius ?? this.radius,
      radiusSmall: radiusSmall ?? this.radiusSmall,
      swatchSize: swatchSize ?? this.swatchSize,
      previewSize: previewSize ?? this.previewSize,
      tap: tap ?? this.tap,
      spacing: spacing ?? this.spacing,
      spacingTight: spacingTight ?? this.spacingTight,
      sliderWidth: sliderWidth ?? this.sliderWidth,
      compactSliderWidth: compactSliderWidth ?? this.compactSliderWidth,
      motion: motion ?? this.motion,
      motionCurve: motionCurve ?? this.motionCurve,
      selectedFill: selectedFill ?? this.selectedFill,
      selectedIconColor: selectedIconColor ?? this.selectedIconColor,
      idleIconColor: idleIconColor ?? this.idleIconColor,
      destructiveColor: destructiveColor ?? this.destructiveColor,
      swatchRingColor: swatchRingColor ?? this.swatchRingColor,
      surfaceGradientStart: surfaceGradientStart ?? this.surfaceGradientStart,
      surfaceGradientEnd: surfaceGradientEnd ?? this.surfaceGradientEnd,
      outlineColor: outlineColor ?? this.outlineColor,
      elevatedShadowBlur: elevatedShadowBlur ?? this.elevatedShadowBlur,
      elevatedShadowOpacity:
          elevatedShadowOpacity ?? this.elevatedShadowOpacity,
    );
  }

  @override
  FlueraToolbarTheme lerp(
    covariant ThemeExtension<FlueraToolbarTheme>? other,
    double t,
  ) {
    if (other is! FlueraToolbarTheme) return this;
    return FlueraToolbarTheme(
      radius: _lerpDouble(radius, other.radius, t),
      radiusSmall: _lerpDouble(radiusSmall, other.radiusSmall, t),
      swatchSize: _lerpDouble(swatchSize, other.swatchSize, t),
      previewSize: _lerpDouble(previewSize, other.previewSize, t),
      tap: _lerpDouble(tap, other.tap, t),
      spacing: _lerpDouble(spacing, other.spacing, t),
      spacingTight: _lerpDouble(spacingTight, other.spacingTight, t),
      sliderWidth: _lerpDouble(sliderWidth, other.sliderWidth, t),
      compactSliderWidth: _lerpDouble(
        compactSliderWidth,
        other.compactSliderWidth,
        t,
      ),
      motion: _lerpDuration(motion, other.motion, t),
      motionCurve: t < 0.5 ? motionCurve : other.motionCurve,
      selectedFill: Color.lerp(selectedFill, other.selectedFill, t),
      selectedIconColor: Color.lerp(
        selectedIconColor,
        other.selectedIconColor,
        t,
      ),
      idleIconColor: Color.lerp(idleIconColor, other.idleIconColor, t),
      destructiveColor: Color.lerp(
        destructiveColor,
        other.destructiveColor,
        t,
      ),
      swatchRingColor: Color.lerp(
        swatchRingColor,
        other.swatchRingColor,
        t,
      ),
      surfaceGradientStart: Color.lerp(
        surfaceGradientStart,
        other.surfaceGradientStart,
        t,
      ),
      surfaceGradientEnd: Color.lerp(
        surfaceGradientEnd,
        other.surfaceGradientEnd,
        t,
      ),
      outlineColor: Color.lerp(outlineColor, other.outlineColor, t),
      elevatedShadowBlur: _lerpDouble(
        elevatedShadowBlur,
        other.elevatedShadowBlur,
        t,
      ),
      elevatedShadowOpacity: _lerpDouble(
        elevatedShadowOpacity,
        other.elevatedShadowOpacity,
        t,
      ),
    );
  }
}

double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

Duration _lerpDuration(Duration a, Duration b, double t) {
  final ms = (a.inMilliseconds + (b.inMilliseconds - a.inMilliseconds) * t)
      .round();
  return Duration(milliseconds: ms);
}
