// ════════════════════════════════════════════════════════════════════════════
// 🎨 fluera_sketch — zero-config drop-in widgets that wire `FlueraCanvas` +
// `FlueraCanvasToolbar` (and optionally a Material `Scaffold` + `MaterialApp`)
// into a working drawing surface with no glue code.
//
// Three layers of "magic", pick the level you want:
//   • [FlueraSketch]          — canvas + toolbar with internal tool / color /
//                               width state. Drop into any Scaffold body.
//   • [FlueraSketchScaffold]  — Scaffold + AppBar (undo / redo / clear /
//                               export) wrapping a [FlueraSketch].
//   • [FlueraSketchApp]       — full MaterialApp wrapping a
//                               [FlueraSketchScaffold].
//
// All three share the [FlueraSketchPreset] enum, which pre-configures the
// toolbar tool set + canvas background for three common UX shapes
// (notes / whiteboard / signature).
// ════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../canvas_background.dart';
import '../fluera_canvas_toolbar.dart';
import '../fluera_canvas_widget.dart';

/// Preset that pre-configures the toolbar tool set + canvas background of a
/// [FlueraSketch] / [FlueraSketchScaffold] / [FlueraSketchApp].
///
/// Use [FlueraCanvas] + [FlueraCanvasToolbar] directly if you need finer
/// control than the three presets provide.
enum FlueraSketchPreset {
  /// Note-taking minimal: pen + eraser (stroke + pixel) + text + undo +
  /// color picker. No shapes, no lasso, no sticker panel, no layers.
  /// Notability-style. Default background: lined paper.
  notes,

  /// Full design / whiteboard kit: every tool ON. Shape tools, lasso,
  /// text, sticker panel, image import, layers, transform actions,
  /// snap-to-grid (16 px) + smart guides. Default background: dotted.
  whiteboard,

  /// Signature-pad-like: 1 pen, no zoom-out below 1×, no background
  /// pattern, no text / shapes / stickers / eraser-pixel. UX
  /// equivalent to the `signature` package — drop straight into a
  /// "sign here" form.
  signature,
}

// ─── FlueraSketch ──────────────────────────────────────────────────────────

/// Canvas + toolbar incapsulated in one widget. Owns the `tool`, `color`
/// and `strokeWidth` state internally so the consumer doesn't have to
/// wire any setState plumbing.
///
/// ```dart
/// const FlueraSketch();                                        // whiteboard
/// const FlueraSketch(preset: FlueraSketchPreset.notes);        // notes
/// FlueraSketch(canvasKey: myKey, initialBytes: bytesFromDisk); // restore
/// ```
class FlueraSketch extends StatefulWidget {
  const FlueraSketch({
    super.key,
    this.preset = FlueraSketchPreset.whiteboard,
    this.canvasKey,
    this.initialBytes,
    this.background,
    this.onChanged,
  });

  /// Pre-configured tool set + background. See [FlueraSketchPreset].
  final FlueraSketchPreset preset;

  /// Optional caller-supplied key. When `null`, [FlueraSketch] mints
  /// its own; in either case the key is reachable via the public
  /// `canvasKey` field of the State (use `findCanvasState`).
  final GlobalKey<FlueraCanvasState>? canvasKey;

  /// Optional FCV0 bytes used to restore a previously-saved canvas.
  /// Read once at first build; later changes are ignored (replace the
  /// widget with a new key to reload from a different blob).
  final Uint8List? initialBytes;

  /// Override the preset's default background.
  final CanvasBackground? background;

  /// Called once after every committed canvas mutation (stroke /
  /// erase / undo / redo / layer change / text edit / image import).
  /// Useful for triggering autosave from a parent widget.
  final VoidCallback? onChanged;

  @override
  State<FlueraSketch> createState() => _FlueraSketchState();
}

class _FlueraSketchState extends State<FlueraSketch> {
  late final GlobalKey<FlueraCanvasState> _canvasKey;
  CanvasTool _tool = CanvasTool.draw;
  Color _color = const Color(0xFF1A1A1A);
  double _width = 2.5;
  Listenable? _historyL;

  @override
  void initState() {
    super.initState();
    _canvasKey = widget.canvasKey ?? GlobalKey<FlueraCanvasState>();
    if (widget.onChanged != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final state = _canvasKey.currentState;
        if (state == null) return;
        _historyL = state.historyListenable;
        _historyL!.addListener(_emitChanged);
      });
    }
  }

  @override
  void dispose() {
    _historyL?.removeListener(_emitChanged);
    super.dispose();
  }

  void _emitChanged() => widget.onChanged?.call();

  @override
  Widget build(BuildContext context) {
    final preset = widget.preset;
    final bg = widget.background ?? _defaultBackground(preset);
    final isSignature = preset == FlueraSketchPreset.signature;
    final isWhiteboard = preset == FlueraSketchPreset.whiteboard;
    return Column(
      children: [
        Expanded(
          child: FlueraCanvas(
            key: _canvasKey,
            tool: _tool,
            strokeColor: _color,
            strokeWidth: _width,
            background: bg,
            initialBytes: widget.initialBytes,
            snapToGrid: isWhiteboard ? 16 : 0,
            smartGuidesEnabled: isWhiteboard,
          ),
        ),
        FlueraCanvasToolbar(
          canvasKey: _canvasKey,
          tool: _tool,
          onToolChanged: (t) => setState(() => _tool = t),
          color: _color,
          onColorChanged: (c) => setState(() => _color = c),
          strokeWidth: _width,
          onStrokeWidthChanged: (w) => setState(() => _width = w),
          showShapeTools: isWhiteboard,
          showPixelEraser: !isSignature,
          showColorPickerButton: !isSignature,
          showSelectionTool: isWhiteboard,
          showLassoTool: isWhiteboard,
          showImageTool: isWhiteboard,
          showTextTool: preset != FlueraSketchPreset.signature,
          showStickerPanel: isWhiteboard,
          showTransformActions: isWhiteboard,
          showLayers: isWhiteboard,
        ),
      ],
    );
  }

  static CanvasBackground _defaultBackground(FlueraSketchPreset preset) {
    switch (preset) {
      case FlueraSketchPreset.notes:
        return const CanvasBackground.lined();
      case FlueraSketchPreset.whiteboard:
        return const CanvasBackground.dotted();
      case FlueraSketchPreset.signature:
        return const CanvasBackground.solid(Color(0xFFFFFFFF));
    }
  }
}

// ─── FlueraSketchScaffold ──────────────────────────────────────────────────

/// `Scaffold` + `AppBar` with undo / redo / clear / export wrapping a
/// [FlueraSketch]. Wires optional autosave + autoload callbacks so the
/// host app only has to provide a persistence backend (e.g. a
/// `path_provider` file).
///
/// ```dart
/// FlueraSketchScaffold(
///   title: 'My note',
///   preset: FlueraSketchPreset.notes,
///   onAutoSave: (bytes) => File('$dir/note.fcv').writeAsBytes(bytes),
///   onAutoLoad: () async => File('$dir/note.fcv').readAsBytes(),
/// );
/// ```
class FlueraSketchScaffold extends StatefulWidget {
  const FlueraSketchScaffold({
    super.key,
    this.title = 'Sketch',
    this.preset = FlueraSketchPreset.whiteboard,
    this.background,
    this.onAutoSave,
    this.onAutoLoad,
    this.autoSaveDebounce = const Duration(seconds: 2),
    this.onExportPng,
    this.actions,
  });

  /// AppBar title.
  final String title;

  /// Pre-configured tool set + background. See [FlueraSketchPreset].
  final FlueraSketchPreset preset;

  /// Override the preset's default background.
  final CanvasBackground? background;

  /// Called [autoSaveDebounce] after the most recent canvas mutation
  /// with the FCV0 bytes the consumer should persist (e.g. write to
  /// disk via `path_provider`). When `null`, no autosave runs.
  final Future<void> Function(Uint8List bytes)? onAutoSave;

  /// Called once at startup to retrieve previously-saved bytes.
  /// Returning `null` (or omitting) starts the canvas blank. While
  /// the future is in flight a small spinner is shown in place of
  /// the canvas.
  final Future<Uint8List?> Function()? onAutoLoad;

  /// Debounce window for [onAutoSave]. Defaults to 2 seconds —
  /// strikes a balance between battery / disk wear and "lost work"
  /// risk on app kill.
  final Duration autoSaveDebounce;

  /// Optional handler for the AppBar export menu. Receives the
  /// rasterised PNG bytes. When `null`, [FlueraSketchScaffold] falls
  /// back to copying the bytes (base64) to the system clipboard and
  /// shows a Snackbar — works on every platform but is mostly a
  /// last-resort cue. Real apps should pass a proper sink (file
  /// write, share-sheet, network upload).
  final Future<void> Function(Uint8List bytes)? onExportPng;

  /// Extra actions appended to the AppBar after the built-in ones.
  final List<Widget>? actions;

  @override
  State<FlueraSketchScaffold> createState() => _FlueraSketchScaffoldState();
}

class _FlueraSketchScaffoldState extends State<FlueraSketchScaffold> {
  final _canvasKey = GlobalKey<FlueraCanvasState>();
  Uint8List? _initial;
  bool _loading = true;
  Timer? _debounce;
  Listenable? _historyL;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      _initial = await widget.onAutoLoad?.call();
    } catch (_) {
      _initial = null;
    }
    if (!mounted) return;
    setState(() => _loading = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _attachHistoryListener();
    });
  }

  void _attachHistoryListener() {
    final state = _canvasKey.currentState;
    if (state == null) return;
    _historyL = state.historyListenable;
    _historyL!.addListener(_onCanvasMutated);
  }

  void _onCanvasMutated() {
    setState(() {}); // refresh undo / redo button enabled state
    if (widget.onAutoSave == null) return;
    _debounce?.cancel();
    _debounce = Timer(widget.autoSaveDebounce, _flushAutoSave);
  }

  Future<void> _flushAutoSave() async {
    final state = _canvasKey.currentState;
    if (state == null) return;
    try {
      await widget.onAutoSave?.call(state.toBytes());
    } catch (_) {/* host app's responsibility to surface */}
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _historyL?.removeListener(_onCanvasMutated);
    super.dispose();
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear canvas?'),
        content: const Text('This removes every stroke, image and '
            'text node. Use Undo to restore.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (ok == true) {
      _canvasKey.currentState?.clear();
    }
  }

  Future<void> _exportAs(FlueraExportBounds bounds) async {
    final state = _canvasKey.currentState;
    if (state == null) return;
    int? w;
    int? h;
    if (bounds == FlueraExportBounds.viewport) {
      final size = state.viewportSize;
      if (size.isEmpty) return;
      w = size.width.round();
      h = size.height.round();
    }
    final image = await state.renderToImage(
      bounds: bounds,
      width: w,
      height: h,
      pixelRatio: bounds == FlueraExportBounds.viewport ? 1.0 : 2.0,
      padding: bounds == FlueraExportBounds.viewport ? 0 : 16,
    );
    final bd = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bd == null) return;
    final bytes = bd.buffer.asUint8List();
    if (widget.onExportPng != null) {
      await widget.onExportPng!(bytes);
    } else {
      // No sink wired — paste base64 into the clipboard as a usable
      // last-resort fallback on every platform (web included).
      // Real apps should pass `onExportPng:` to write to disk
      // (path_provider) or open a share sheet (share_plus).
      await Clipboard.setData(
        ClipboardData(text: 'data:image/png;base64,${_b64(bytes)}'),
      );
      if (!mounted) return;
      final kb = (bytes.lengthInBytes / 1024).toStringAsFixed(1);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Text(
            'PNG ($kb KB) copied to clipboard as a data URL — fallback. '
            'Wire `onExportPng:` to write to disk or share instead.',
          ),
        ),
      );
    }
  }

  /// Inline base64 encoder so we don't have to depend on `dart:convert`
  /// from the wider tree (it's already pulled in transitively, but
  /// avoiding the import keeps this file self-contained).
  static String _b64(Uint8List bytes) {
    const t = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final out = StringBuffer();
    for (int i = 0; i < bytes.length; i += 3) {
      final b0 = bytes[i];
      final b1 = i + 1 < bytes.length ? bytes[i + 1] : 0;
      final b2 = i + 2 < bytes.length ? bytes[i + 2] : 0;
      out.write(t[b0 >> 2]);
      out.write(t[((b0 & 0x03) << 4) | (b1 >> 4)]);
      out.write(i + 1 < bytes.length ? t[((b1 & 0x0F) << 2) | (b2 >> 6)] : '=');
      out.write(i + 2 < bytes.length ? t[b2 & 0x3F] : '=');
    }
    return out.toString();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final state = _canvasKey.currentState;
    final canUndo = state?.canUndo ?? false;
    final canRedo = state?.canRedo ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Undo',
            icon: const Icon(Icons.undo_rounded),
            onPressed: canUndo ? () => state?.undo() : null,
          ),
          IconButton(
            tooltip: 'Redo',
            icon: const Icon(Icons.redo_rounded),
            onPressed: canRedo ? () => state?.redo() : null,
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.clear_all_rounded),
            onPressed: _confirmClear,
          ),
          PopupMenuButton<FlueraExportBounds>(
            tooltip: 'Export PNG',
            icon: const Icon(Icons.save_alt_rounded),
            onSelected: _exportAs,
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: FlueraExportBounds.viewport,
                child: Text('Export viewport'),
              ),
              PopupMenuItem(
                value: FlueraExportBounds.allContent,
                child: Text('Export all content @2×'),
              ),
              PopupMenuItem(
                value: FlueraExportBounds.selection,
                child: Text('Export selection @2×'),
              ),
            ],
          ),
          ...?widget.actions,
        ],
      ),
      body: FlueraSketch(
        canvasKey: _canvasKey,
        preset: widget.preset,
        background: widget.background,
        initialBytes: _initial,
      ),
    );
  }
}

// ─── FlueraSketchApp ───────────────────────────────────────────────────────

/// Full `MaterialApp` wrapping a [FlueraSketchScaffold]. Letteralmente:
///
/// ```dart
/// void main() => runApp(const FlueraSketchApp());
/// ```
///
/// All scaffold parameters are forwarded as-is. Use [FlueraSketchScaffold]
/// directly when you need to embed the sketch as a page inside an
/// existing `MaterialApp`.
class FlueraSketchApp extends StatelessWidget {
  const FlueraSketchApp({
    super.key,
    this.title = 'Sketch',
    this.preset = FlueraSketchPreset.whiteboard,
    this.themeMode,
    this.background,
    this.onAutoSave,
    this.onAutoLoad,
    this.autoSaveDebounce = const Duration(seconds: 2),
    this.onExportPng,
  });

  final String title;
  final FlueraSketchPreset preset;
  final ThemeMode? themeMode;
  final CanvasBackground? background;
  final Future<void> Function(Uint8List bytes)? onAutoSave;
  final Future<Uint8List?> Function()? onAutoLoad;
  final Duration autoSaveDebounce;
  final Future<void> Function(Uint8List bytes)? onExportPng;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: title,
      themeMode: themeMode,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      darkTheme: ThemeData.dark(useMaterial3: true),
      home: FlueraSketchScaffold(
        title: title,
        preset: preset,
        background: background,
        onAutoSave: onAutoSave,
        onAutoLoad: onAutoLoad,
        autoSaveDebounce: autoSaveDebounce,
        onExportPng: onExportPng,
      ),
    );
  }
}
