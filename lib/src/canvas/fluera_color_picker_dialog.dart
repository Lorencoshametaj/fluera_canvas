// ════════════════════════════════════════════════════════════════════════════
// 🎨 FlueraColorPickerDialog — minimal HSV color picker dialog.
//
// Zero-dependency, single-file picker that the toolbar (or any consumer
// UI) can pop up when the user wants a colour beyond the 6-swatch
// palette. Intentionally simple — square saturation/value box + hue
// slider + alpha slider + hex input. No popular `flutter_colorpicker`
// dependency, no external assets.
// ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shows the [FlueraColorPickerDialog] and returns the user-picked
/// color, or `null` if the dialog was dismissed.
///
/// ```dart
/// final picked = await showFlueraColorPicker(
///   context: context,
///   initial: currentColor,
/// );
/// if (picked != null) setState(() => currentColor = picked);
/// ```
Future<Color?> showFlueraColorPicker({
  required BuildContext context,
  required Color initial,
  String title = 'Pick a color',
  bool enableAlpha = true,
}) {
  return showDialog<Color>(
    context: context,
    builder:
        (ctx) => FlueraColorPickerDialog(
          initial: initial,
          title: title,
          enableAlpha: enableAlpha,
        ),
  );
}

/// Material dialog wrapping a colour picker. Pops the picked color
/// (or `null` on cancel). Use [showFlueraColorPicker] for the
/// imperative form.
class FlueraColorPickerDialog extends StatefulWidget {
  const FlueraColorPickerDialog({
    super.key,
    required this.initial,
    this.title = 'Pick a color',
    this.enableAlpha = true,
  });

  final Color initial;
  final String title;
  final bool enableAlpha;

  @override
  State<FlueraColorPickerDialog> createState() =>
      _FlueraColorPickerDialogState();
}

class _FlueraColorPickerDialogState extends State<FlueraColorPickerDialog> {
  late HSVColor _hsv;
  late TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initial);
    _hexController = TextEditingController(text: _hexFromColor(widget.initial));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Color get _color => _hsv.toColor();

  void _updateFromHsv(HSVColor hsv) {
    setState(() {
      _hsv = hsv;
      _hexController.text = _hexFromColor(hsv.toColor());
    });
  }

  void _updateFromHex(String text) {
    final c = _colorFromHex(text);
    if (c == null) return;
    setState(() {
      _hsv = HSVColor.fromColor(c);
    });
  }

  static String _hexFromColor(Color c) {
    String two(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
    final argb = c.toARGB32();
    return '#${two((argb >> 24) & 0xFF)}${two((argb >> 16) & 0xFF)}'
        '${two((argb >> 8) & 0xFF)}${two(argb & 0xFF)}';
  }

  static Color? _colorFromHex(String input) {
    var s = input.trim().replaceFirst('#', '');
    if (s.length == 6) s = 'FF$s';
    if (s.length != 8) return null;
    final v = int.tryParse(s, radix: 16);
    if (v == null) return null;
    return Color(v);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // SV box: 220×140
            AspectRatio(
              aspectRatio: 1.6,
              child: _SaturationValueBox(
                hue: _hsv.hue,
                saturation: _hsv.saturation,
                value: _hsv.value,
                onChanged:
                    (s, v) =>
                        _updateFromHsv(_hsv.withSaturation(s).withValue(v)),
              ),
            ),
            const SizedBox(height: 16),
            _HueSlider(
              hue: _hsv.hue,
              onChanged: (h) => _updateFromHsv(_hsv.withHue(h)),
            ),
            if (widget.enableAlpha) ...[
              const SizedBox(height: 12),
              _AlphaSlider(
                color: _hsv.withAlpha(1.0).toColor(),
                alpha: _hsv.alpha,
                onChanged: (a) => _updateFromHsv(_hsv.withAlpha(a)),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _color,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hexController,
                    decoration: const InputDecoration(
                      labelText: 'Hex',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[#0-9a-fA-F]'),
                      ),
                      LengthLimitingTextInputFormatter(9),
                    ],
                    onSubmitted: _updateFromHex,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_color),
          child: const Text('OK'),
        ),
      ],
    );
  }
}

// ─── Saturation × Value box ────────────────────────────────────────────────

class _SaturationValueBox extends StatelessWidget {
  const _SaturationValueBox({
    required this.hue,
    required this.saturation,
    required this.value,
    required this.onChanged,
  });

  final double hue;
  final double saturation;
  final double value;
  final void Function(double saturation, double value) onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        void emit(Offset local) {
          final s = (local.dx / size.width).clamp(0.0, 1.0);
          final v = 1.0 - (local.dy / size.height).clamp(0.0, 1.0);
          onChanged(s, v);
        }

        return GestureDetector(
          onPanDown: (d) => emit(d.localPosition),
          onPanUpdate: (d) => emit(d.localPosition),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CustomPaint(
              size: size,
              painter: _SVBoxPainter(
                hue: hue,
                saturation: saturation,
                value: value,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SVBoxPainter extends CustomPainter {
  _SVBoxPainter({
    required this.hue,
    required this.saturation,
    required this.value,
  });
  final double hue;
  final double saturation;
  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final hueColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    // Horizontal: white → fully saturated hue.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, hueColor],
        ).createShader(rect),
    );
    // Vertical: transparent → black overlay.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    // Picker dot.
    final dot = Offset(saturation * size.width, (1 - value) * size.height);
    canvas.drawCircle(
      dot,
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    canvas.drawCircle(
      dot,
      8,
      Paint()
        ..color = Colors.black54
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _SVBoxPainter old) =>
      old.hue != hue || old.saturation != saturation || old.value != value;
}

// ─── Hue slider ────────────────────────────────────────────────────────────

class _HueSlider extends StatelessWidget {
  const _HueSlider({required this.hue, required this.onChanged});
  final double hue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final w = constraints.maxWidth;
          void emit(double dx) {
            onChanged((dx / w * 360).clamp(0.0, 360.0));
          }

          return GestureDetector(
            onPanDown: (d) => emit(d.localPosition.dx),
            onPanUpdate: (d) => emit(d.localPosition.dx),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                painter: _HueGradientPainter(hue: hue),
                size: Size(w, 24),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HueGradientPainter extends CustomPainter {
  _HueGradientPainter({required this.hue});
  final double hue;

  static const _hues = <Color>[
    Color(0xFFFF0000),
    Color(0xFFFFFF00),
    Color(0xFF00FF00),
    Color(0xFF00FFFF),
    Color(0xFF0000FF),
    Color(0xFFFF00FF),
    Color(0xFFFF0000),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()..shader = const LinearGradient(colors: _hues).createShader(rect),
    );
    final x = hue / 360 * size.width;
    canvas.drawCircle(
      Offset(x, size.height / 2),
      size.height / 2 - 1,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _HueGradientPainter old) => old.hue != hue;
}

// ─── Alpha slider ──────────────────────────────────────────────────────────

class _AlphaSlider extends StatelessWidget {
  const _AlphaSlider({
    required this.color,
    required this.alpha,
    required this.onChanged,
  });
  final Color color;
  final double alpha;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final w = constraints.maxWidth;
          void emit(double dx) {
            onChanged((dx / w).clamp(0.0, 1.0));
          }

          return GestureDetector(
            onPanDown: (d) => emit(d.localPosition.dx),
            onPanUpdate: (d) => emit(d.localPosition.dx),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                painter: _AlphaGradientPainter(color: color, alpha: alpha),
                size: Size(w, 24),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AlphaGradientPainter extends CustomPainter {
  _AlphaGradientPainter({required this.color, required this.alpha});
  final Color color;
  final double alpha;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // Checker pattern background to suggest transparency.
    const tile = 6.0;
    final cells = (size.width / tile).ceil();
    for (int y = 0; y * tile < size.height; y++) {
      for (int x = 0; x < cells; x++) {
        final isLight = (x + y) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x * tile, y * tile, tile, tile),
          Paint()
            ..color =
                isLight ? const Color(0xFFE0E0E0) : const Color(0xFFF8F8F8),
        );
      }
    }
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [color.withValues(alpha: 0), color],
        ).createShader(rect),
    );
    final x = alpha * size.width;
    canvas.drawCircle(
      Offset(x, size.height / 2),
      size.height / 2 - 1,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _AlphaGradientPainter old) =>
      old.color != color || old.alpha != alpha;
}
