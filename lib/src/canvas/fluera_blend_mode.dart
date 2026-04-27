// ════════════════════════════════════════════════════════════════════════════
// FlueraBlendMode — superset of Flutter's `ui.BlendMode` covering the 26
// Photoshop standard blend modes used by professional drawing apps.
//
// 17 modes are direct one-to-one mappings to `ui.BlendMode` (the renderer
// path is a plain `Canvas.saveLayer` + native blend) and ship in the free
// pub.dev `fluera_canvas` core. The remaining 9 modes are the Photoshop
// "extended" set that `ui.BlendMode` doesn't expose (LinearBurn,
// LinearDodge, VividLight, LinearLight, PinLight, HardMix, DarkerColor,
// LighterColor, Subtract, Divide). The free core falls back to the closest
// `ui.BlendMode` for those (best-effort approximation); the commercial
// `fluera_canvas_gpu` compositor unlocks accurate compositing via custom
// fragment shaders.
//
// API design:
//
// - Each enum value carries a stable `code` int (used by the compositor
//   ABI to dispatch without dart:ui types crossing the boundary), a
//   user-facing `name`, and a `flutterBlendMode` (nullable: present for
//   the 17 standard modes, null for the 9 extended ones).
// - The free fallback path uses `flutterBlendMode ?? closestStandard` to
//   pick a substitute when the consumer asks for an extended mode but no
//   GPU compositor is registered.
//
// Stable codes (DO NOT REORDER OR REMAP — they are part of the ABI):
//   0..16  → 17 standard modes (in `ui.BlendMode` order convenience)
//   100+   → 9 extended Photoshop modes
// ════════════════════════════════════════════════════════════════════════════

import 'dart:ui' as ui;

/// Canvas-core enumeration of every blend mode the layer compositor knows
/// how to handle. See file header for the design rationale.
enum FlueraBlendMode {
  // ─── 17 standard modes (one-to-one with ui.BlendMode) ──────────────────
  normal(code: 0, name: 'Normal', flutterBlendMode: ui.BlendMode.srcOver),
  darken(code: 1, name: 'Darken', flutterBlendMode: ui.BlendMode.darken),
  multiply(code: 2, name: 'Multiply', flutterBlendMode: ui.BlendMode.multiply),
  colorBurn(
    code: 3,
    name: 'Color Burn',
    flutterBlendMode: ui.BlendMode.colorBurn,
  ),
  lighten(code: 4, name: 'Lighten', flutterBlendMode: ui.BlendMode.lighten),
  screen(code: 5, name: 'Screen', flutterBlendMode: ui.BlendMode.screen),
  colorDodge(
    code: 6,
    name: 'Color Dodge',
    flutterBlendMode: ui.BlendMode.colorDodge,
  ),
  overlay(code: 7, name: 'Overlay', flutterBlendMode: ui.BlendMode.overlay),
  softLight(
    code: 8,
    name: 'Soft Light',
    flutterBlendMode: ui.BlendMode.softLight,
  ),
  hardLight(
    code: 9,
    name: 'Hard Light',
    flutterBlendMode: ui.BlendMode.hardLight,
  ),
  difference(
    code: 10,
    name: 'Difference',
    flutterBlendMode: ui.BlendMode.difference,
  ),
  exclusion(
    code: 11,
    name: 'Exclusion',
    flutterBlendMode: ui.BlendMode.exclusion,
  ),
  hue(code: 12, name: 'Hue', flutterBlendMode: ui.BlendMode.hue),
  saturation(
    code: 13,
    name: 'Saturation',
    flutterBlendMode: ui.BlendMode.saturation,
  ),
  color(code: 14, name: 'Color', flutterBlendMode: ui.BlendMode.color),
  luminosity(
    code: 15,
    name: 'Luminosity',
    flutterBlendMode: ui.BlendMode.luminosity,
  ),
  plus(
    code: 16,
    name: 'Linear Dodge (Add)',
    flutterBlendMode: ui.BlendMode.plus,
  ),

  // ─── 9 extended Photoshop modes (require custom shader for accuracy) ───
  linearBurn(
    code: 100,
    name: 'Linear Burn',
    flutterBlendMode: null,
    fallback: ui.BlendMode.multiply,
  ),
  vividLight(
    code: 101,
    name: 'Vivid Light',
    flutterBlendMode: null,
    fallback: ui.BlendMode.overlay,
  ),
  linearLight(
    code: 102,
    name: 'Linear Light',
    flutterBlendMode: null,
    fallback: ui.BlendMode.hardLight,
  ),
  pinLight(
    code: 103,
    name: 'Pin Light',
    flutterBlendMode: null,
    fallback: ui.BlendMode.hardLight,
  ),
  hardMix(
    code: 104,
    name: 'Hard Mix',
    flutterBlendMode: null,
    fallback: ui.BlendMode.hardLight,
  ),
  darkerColor(
    code: 105,
    name: 'Darker Color',
    flutterBlendMode: null,
    fallback: ui.BlendMode.darken,
  ),
  lighterColor(
    code: 106,
    name: 'Lighter Color',
    flutterBlendMode: null,
    fallback: ui.BlendMode.lighten,
  ),
  subtract(
    code: 107,
    name: 'Subtract',
    flutterBlendMode: null,
    fallback: ui.BlendMode.difference,
  ),
  divide(
    code: 108,
    name: 'Divide',
    flutterBlendMode: null,
    fallback: ui.BlendMode.colorDodge,
  );

  const FlueraBlendMode({
    required this.code,
    required this.name,
    required this.flutterBlendMode,
    ui.BlendMode? fallback,
  }) : _fallback = fallback;

  /// Stable numeric identifier — part of the compositor ABI. The
  /// committed-strokes painter reads it from the side-table on
  /// `FlueraCanvasState` and passes it through to the compositor as
  /// `extendedBlendModeCode` (only for `isExtended == true` modes).
  /// Standard modes go through the regular `ui.BlendMode` channel.
  final int code;

  /// Human-readable label for layer panels and dropdowns.
  final String name;

  /// Native Flutter blend mode for the 17 standard values; `null` for
  /// the 9 Photoshop extended ones (they must be approximated or
  /// shader-rendered by the compositor).
  final ui.BlendMode? flutterBlendMode;

  /// Best-effort fallback used by the free core when this mode is
  /// extended (no `flutterBlendMode`) and no GPU compositor is
  /// registered. For standard modes it is unused.
  final ui.BlendMode? _fallback;

  /// `true` for modes that are NOT in `ui.BlendMode` — the commercial
  /// `fluera_canvas_gpu` compositor handles them via fragment shaders;
  /// the free core uses [closestStandard] as a best-effort fallback.
  bool get isExtended => flutterBlendMode == null;

  /// The blend mode the free core uses when it cannot honour an
  /// extended request. For standard modes returns the same value as
  /// [flutterBlendMode]. Always non-null.
  ui.BlendMode get closestStandard =>
      flutterBlendMode ?? _fallback ?? ui.BlendMode.srcOver;

  /// Lowest stable code reserved for extended (Photoshop-grade) modes.
  /// Codes < this map one-to-one to `ui.BlendMode`; codes ≥ this require
  /// a custom shader to be honoured pixel-accurately.
  static const int kExtendedCodeMin = 100;

  /// Highest currently-defined extended code. Future extensions add
  /// values above this — readers that don't know a code MUST drop it
  /// silently rather than crash (see `decodeBytesFull` in canvas
  /// serializer).
  static const int kExtendedCodeMax = 108;

  /// True iff [code] falls in the extended-mode range AND maps to a
  /// known [FlueraBlendMode] value. Used by the serializer and the
  /// shader dispatch to gate-keep without open-coding the magic
  /// range constants.
  static bool isExtendedCode(int code) =>
      code >= kExtendedCodeMin && code <= kExtendedCodeMax;

  /// Reverse lookup by stable code. Useful when re-hydrating from
  /// persisted scenes. Returns [normal] for unknown codes.
  static FlueraBlendMode fromCode(int code) {
    for (final m in FlueraBlendMode.values) {
      if (m.code == code) return m;
    }
    return FlueraBlendMode.normal;
  }

  /// Closest `FlueraBlendMode` that maps to the given `ui.BlendMode`.
  /// Returns [normal] when no match. Convenient when migrating consumer
  /// state that was written against `LayerNode.blendMode` directly.
  static FlueraBlendMode fromFlutterBlendMode(ui.BlendMode mode) {
    for (final m in FlueraBlendMode.values) {
      if (m.flutterBlendMode == mode) return m;
    }
    return FlueraBlendMode.normal;
  }
}
