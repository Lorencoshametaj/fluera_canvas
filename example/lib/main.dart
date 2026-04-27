// fluera_canvas example — gallery of 11 self-contained demos covering the
// v0.9 feature set: drawing tools, drop-in toolbar, multi-canvas + autosave,
// stress test (10 k strokes), programmatic stroke builder, PNG export,
// grid paper + persistence, layers, text + stickers, paper backgrounds,
// and selection + snap-to-grid + smart guides.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'fluera_canvas examples',
    theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
    home: const _Gallery(),
  );
}

class _Gallery extends StatelessWidget {
  const _Gallery();

  @override
  Widget build(BuildContext context) {
    final demos = <(String, String, IconData, Widget Function())>[
      (
        'Drawing tools',
        'Pen + eraser + undo / redo. Core canvas UX.',
        Icons.edit_rounded,
        () => const _DrawingToolsDemo(),
      ),
      (
        'Built-in toolbar',
        'Drop-in [FlueraCanvasToolbar] — zero glue code.',
        Icons.toggle_on_rounded,
        () => const _ToolbarDemo(),
      ),
      (
        'Multi-canvas + autosave',
        'File-system gallery, create / delete / autosave on every stroke.',
        Icons.folder_rounded,
        () => const _MultiCanvasDemo(),
      ),
      (
        'Stress test',
        '10 000 strokes pre-loaded. Spatial-index culling keeps it fluid.',
        Icons.speed_rounded,
        () => const _StressDemo(),
      ),
      (
        'Programmatic',
        'state.pushStroke() from code — replay of recorded sessions, '
            'scripted animation, procedural art, data-driven canvases.',
        Icons.code_rounded,
        () => const _ProgrammaticDemo(),
      ),
      (
        'PNG export',
        'Rasterize the current camera view to a PNG bitmap.',
        Icons.save_alt_rounded,
        () => const _ExportDemo(),
      ),
      (
        'Grid paper + save/load',
        'Dotted grid background, toBytes/loadFromBytes roundtrip.',
        Icons.grid_on_rounded,
        () => const _PersistenceDemo(),
      ),
      (
        'Layers',
        'Multi-layer drawing — visibility, lock, opacity, blend mode, drag reorder.',
        Icons.layers_rounded,
        () => const _LayersDemo(),
      ),
      (
        'Text + Stickers',
        'Tap to type — overlay caret, undo / redo, sticker panel.',
        Icons.text_fields_rounded,
        () => const _TextStickerDemo(),
      ),
      (
        'Backgrounds',
        'Solid / grid / dotted / lined paper — toggle live.',
        Icons.dashboard_rounded,
        () => const _BackgroundsDemo(),
      ),
      (
        'Selection + snap',
        'Select / lasso tool, drag with snap-to-grid + magenta smart '
            'guides. Lasso = freeform path for scattered strokes; select '
            '= rectangular marquee for grid layouts.',
        Icons.transform_rounded,
        () => const _SelectionDemo(),
      ),
      (
        'Zero-config app (FlueraSketchApp)',
        'Drop FlueraSketchApp into runApp() and you have a full drawing '
            'app — no glue code. 3 tabs show the 3 magic levels '
            '(FlueraSketch / Scaffold / App) and 3 presets.',
        Icons.flash_on_rounded,
        () => const _ZeroConfigDemo(),
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('fluera_canvas examples')),
      body: ListView.separated(
        itemCount: demos.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final d = demos[i];
          return ListTile(
            leading: Icon(d.$3),
            title: Text(d.$1),
            subtitle: Text(d.$2),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(
              ctx,
            ).push(MaterialPageRoute(builder: (_) => d.$4())),
          );
        },
      ),
    );
  }
}

// ─── Demo 1 · drawing tools ────────────────────────────────────────────────

class _DrawingToolsDemo extends StatefulWidget {
  const _DrawingToolsDemo();
  @override
  State<_DrawingToolsDemo> createState() => _DrawingToolsDemoState();
}

class _DrawingToolsDemoState extends State<_DrawingToolsDemo> {
  final _canvasKey = GlobalKey<FlueraCanvasState>();
  CanvasTool _tool = CanvasTool.draw;
  Color _color = const Color(0xFF1A1A1A);
  double _width = 2.5;

  static const _palette = <Color>[
    Color(0xFF1A1A1A),
    Color(0xFFE53935),
    Color(0xFF1E88E5),
    Color(0xFF43A047),
    Color(0xFFFB8C00),
    Color(0xFF8E24AA),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Drawing tools'),
        actions: [
          IconButton(
            tooltip: 'Undo',
            icon: const Icon(Icons.undo_rounded),
            onPressed: () => setState(() {
              _canvasKey.currentState?.undo();
            }),
          ),
          IconButton(
            tooltip: 'Redo',
            icon: const Icon(Icons.redo_rounded),
            onPressed: () => setState(() {
              _canvasKey.currentState?.redo();
            }),
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => setState(() {
              _canvasKey.currentState?.clear();
            }),
          ),
        ],
      ),
      body: Column(
        children: [
          // Toolbar TOP — coerente con `fluera_canvas_gpu/example` e con
          // l'app Fluera flagship: evita il conflitto con il `Texture`
          // hardware-overlay su Android Vulkan, che compone il
          // live-stroke surface SOPRA i widget Flutter.
          SafeArea(
            bottom: false,
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<CanvasTool>(
                    segments: const [
                      ButtonSegment(
                        value: CanvasTool.draw,
                        label: Text('Pen'),
                        icon: Icon(Icons.edit_rounded),
                      ),
                      ButtonSegment(
                        value: CanvasTool.erase,
                        label: Text('Eraser'),
                        icon: Icon(Icons.cleaning_services_rounded),
                      ),
                    ],
                    selected: {_tool},
                    onSelectionChanged: (s) => setState(() => _tool = s.first),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final c in _palette)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _ColorChip(
                            color: c,
                            selected: c.toARGB32() == _color.toARGB32(),
                            onTap: () => setState(() => _color = c),
                          ),
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Slider(
                          value: _width,
                          min: 1,
                          max: 16,
                          divisions: 15,
                          label: '${_width.toStringAsFixed(1)} px',
                          onChanged: (v) => setState(() => _width = v),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FlueraCanvas(
              key: _canvasKey,
              tool: _tool,
              strokeColor: _color,
              strokeWidth: _width,
              onStrokeCommitted: (_) => setState(() {}),
              onStrokesErased: (_) => setState(() {}),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Demo · built-in toolbar ───────────────────────────────────────────────

class _ToolbarDemo extends StatefulWidget {
  const _ToolbarDemo();
  @override
  State<_ToolbarDemo> createState() => _ToolbarDemoState();
}

class _ToolbarDemoState extends State<_ToolbarDemo> {
  final _canvasKey = GlobalKey<FlueraCanvasState>();
  CanvasTool _tool = CanvasTool.draw;
  Color _color = const Color(0xFF1A1A1A);
  double _width = 2.5;
  double _eraserRadius = 32.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Built-in toolbar')),
      body: Column(
        children: [
          // Toolbar TOP — coerente con `fluera_canvas_gpu/example` e con
          // l'app Fluera flagship: evita il conflitto con il `Texture`
          // hardware-overlay su Android Vulkan.
          FlueraCanvasToolbar(
            canvasKey: _canvasKey,
            tool: _tool,
            onToolChanged: (t) => setState(() => _tool = t),
            color: _color,
            onColorChanged: (c) => setState(() => _color = c),
            strokeWidth: _width,
            onStrokeWidthChanged: (w) => setState(() => _width = w),
            eraserRadius: _eraserRadius,
            onEraserRadiusChanged: (r) => setState(() => _eraserRadius = r),
            showShapeTools: true,
            showPixelEraser: true,
            showColorPickerButton: true,
            // ── 0.6.0 toolbar features ──
            showSelectionTool: true,
            showImageTool: true,
            showTransformActions: true,
            showLayers: true,
          ),
          Expanded(
            child: FlueraCanvas(
              key: _canvasKey,
              tool: _tool,
              strokeColor: _color,
              strokeWidth: _width,
              eraserRadius: _eraserRadius,
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorChip extends StatelessWidget {
  const _ColorChip({
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
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.black.withValues(alpha: 0.2),
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}

// ─── Demo 2 · stress test ──────────────────────────────────────────────────

class _StressDemo extends StatefulWidget {
  const _StressDemo();
  @override
  State<_StressDemo> createState() => _StressDemoState();
}

class _StressDemoState extends State<_StressDemo> {
  final _canvasKey = GlobalKey<FlueraCanvasState>();
  bool _loaded = false;
  int _count = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    if (!mounted) return;
    final rnd = math.Random(42);
    final batch = <CanvasStroke>[];
    const n = 10000;
    for (int i = 0; i < n; i++) {
      final cx = rnd.nextDouble() * 40000 - 20000;
      final cy = rnd.nextDouble() * 40000 - 20000;
      final len = 4 + rnd.nextInt(24);
      final pts = <Offset>[];
      final prs = <double>[];
      double x = cx, y = cy;
      for (int k = 0; k < len; k++) {
        pts.add(Offset(x, y));
        prs.add(0.4 + rnd.nextDouble() * 0.6);
        x += rnd.nextDouble() * 20 - 10;
        y += rnd.nextDouble() * 20 - 10;
      }
      batch.add(
        CanvasStroke(
          points: pts,
          pressures: prs,
          color: HSVColor.fromAHSV(
            1,
            rnd.nextDouble() * 360,
            0.7,
            0.85,
          ).toColor(),
          baseWidth: 1.0 + rnd.nextDouble() * 3,
        ),
      );
    }
    _canvasKey.currentState?.pushStrokes(batch);
    setState(() {
      _loaded = true;
      _count = n;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _loaded ? 'Stress — $_count strokes' : 'Stress — generating…',
        ),
      ),
      body: FlueraCanvas(
        key: _canvasKey,
        strokeWidth: 2.0,
        // We only need to see the culling win, not draw more.
        enableNativeLiveStroke: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          _canvasKey.currentState?.clear();
          setState(() => _count = 0);
        },
        icon: const Icon(Icons.delete_sweep_rounded),
        label: const Text('Clear'),
      ),
    );
  }
}

// ─── Demo 3 · programmatic ─────────────────────────────────────────────────

class _ProgrammaticDemo extends StatefulWidget {
  const _ProgrammaticDemo();
  @override
  State<_ProgrammaticDemo> createState() => _ProgrammaticDemoState();
}

class _ProgrammaticDemoState extends State<_ProgrammaticDemo> {
  final _canvasKey = GlobalKey<FlueraCanvasState>();

  void _loadLogo() {
    final canvas = _canvasKey.currentState;
    if (canvas == null) return;
    canvas.clear();

    // Circle
    final circle = <Offset>[];
    final pr = <double>[];
    const center = Offset(200, 200);
    for (int i = 0; i <= 60; i++) {
      final t = i / 60.0 * 2 * math.pi;
      circle.add(
        Offset(center.dx + 100 * math.cos(t), center.dy + 100 * math.sin(t)),
      );
      pr.add(0.6 + 0.3 * math.sin(t * 4));
    }
    canvas.pushStroke(
      CanvasStroke(
        points: circle,
        pressures: pr,
        color: Colors.indigo,
        baseWidth: 5,
      ),
    );

    // Star
    final star = <Offset>[];
    const sc = Offset(500, 200);
    for (int i = 0; i <= 10; i++) {
      final t = i / 10.0 * 2 * math.pi - math.pi / 2;
      final r = i.isEven ? 100.0 : 45.0;
      star.add(Offset(sc.dx + r * math.cos(t), sc.dy + r * math.sin(t)));
    }
    canvas.pushStroke(
      CanvasStroke(
        points: star,
        pressures: List.filled(star.length, 0.9),
        color: Colors.amber[700]!,
        baseWidth: 6,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Programmatic'),
        actions: [
          IconButton(
            tooltip: 'Undo',
            icon: const Icon(Icons.undo_rounded),
            onPressed: () => _canvasKey.currentState?.undo(),
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _canvasKey.currentState?.clear(),
          ),
        ],
      ),
      body: FlueraCanvas(key: _canvasKey, strokeColor: Colors.black87),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loadLogo,
        icon: const Icon(Icons.play_arrow_rounded),
        label: const Text('Load sample'),
      ),
    );
  }
}

// ─── Demo 4 · PNG export ───────────────────────────────────────────────────

class _ExportDemo extends StatefulWidget {
  const _ExportDemo();
  @override
  State<_ExportDemo> createState() => _ExportDemoState();
}

class _ExportDemoState extends State<_ExportDemo> {
  final _canvasKey = GlobalKey<FlueraCanvasState>();
  Uint8List? _preview;
  String? _meta;

  Future<void> _exportViewport() async {
    final canvas = _canvasKey.currentState;
    if (canvas == null) return;
    final size = canvas.viewportSize;
    if (size.isEmpty) return;
    await _emit(
      canvas.renderToImage(
        width: size.width.round(),
        height: size.height.round(),
      ),
      'viewport',
    );
  }

  Future<void> _exportAllContent({double pixelRatio = 1.0}) async {
    final canvas = _canvasKey.currentState;
    if (canvas == null) return;
    await _emit(
      canvas.renderToImage(
        bounds: FlueraExportBounds.allContent,
        pixelRatio: pixelRatio,
        padding: 24,
      ),
      'allContent ${pixelRatio}x',
    );
  }

  Future<void> _exportSelection() async {
    final canvas = _canvasKey.currentState;
    if (canvas == null) return;
    await _emit(
      canvas.renderToImage(
        bounds: FlueraExportBounds.selection,
        pixelRatio: 2.0,
        padding: 12,
      ),
      'selection 2x',
    );
  }

  Future<void> _exportTransparent() async {
    final canvas = _canvasKey.currentState;
    if (canvas == null) return;
    await _emit(
      canvas.renderToImage(
        bounds: FlueraExportBounds.allContent,
        pixelRatio: 2.0,
        padding: 16,
        transparent: true,
      ),
      'allContent transparent 2x',
    );
  }

  Future<void> _emit(Future<ui.Image> imageF, String mode) async {
    final image = await imageF;
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dims = '${image.width}×${image.height}';
    image.dispose();
    if (!mounted || bytes == null) return;
    setState(() {
      _preview = bytes.buffer.asUint8List();
      _meta = '$mode · $dims · ${(bytes.lengthInBytes / 1024).toStringAsFixed(1)} KB';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PNG export · 4 modes'),
        actions: [
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () {
              _canvasKey.currentState?.clear();
              setState(() {
                _preview = null;
                _meta = null;
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: FlueraCanvas(
              key: _canvasKey,
              strokeColor: Colors.indigo,
              strokeWidth: 3,
              background: const CanvasBackground.dotted(),
            ),
          ),
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _exportViewport,
                  icon: const Icon(Icons.crop_free_rounded),
                  label: const Text('Viewport'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _exportAllContent(),
                  icon: const Icon(Icons.fit_screen_rounded),
                  label: const Text('All content'),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => _exportAllContent(pixelRatio: 2.0),
                  icon: const Icon(Icons.high_quality_rounded),
                  label: const Text('All content @2×'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _exportSelection,
                  icon: const Icon(Icons.select_all_rounded),
                  label: const Text('Selection @2×'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _exportTransparent,
                  icon: const Icon(Icons.layers_clear_rounded),
                  label: const Text('Transparent @2×'),
                ),
              ],
            ),
          ),
          if (_preview != null)
            Expanded(
              flex: 2,
              child: Container(
                color: const Color(0xFFE0E0E0),
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    if (_meta != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          _meta!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    Expanded(
                      child: Center(
                        child: Image.memory(
                          _preview!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Demo 5 · grid paper + save / load ─────────────────────────────────────

class _PersistenceDemo extends StatefulWidget {
  const _PersistenceDemo();
  @override
  State<_PersistenceDemo> createState() => _PersistenceDemoState();
}

class _PersistenceDemoState extends State<_PersistenceDemo> {
  final _canvasKey = GlobalKey<FlueraCanvasState>();
  Uint8List? _saved;

  void _save() {
    final bytes = _canvasKey.currentState?.toBytes();
    if (bytes == null) return;
    setState(() => _saved = bytes);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✓ Saved ${bytes.lengthInBytes} bytes in memory')),
    );
  }

  void _load() {
    final bytes = _saved;
    if (bytes == null) return;
    _canvasKey.currentState?.loadFromBytes(bytes);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('✓ Restored from memory')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grid paper + save / load'),
        actions: [
          IconButton(
            tooltip: 'Save',
            icon: const Icon(Icons.save_rounded),
            onPressed: _save,
          ),
          IconButton(
            tooltip: 'Load',
            icon: const Icon(Icons.folder_open_rounded),
            onPressed: _saved == null ? null : _load,
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _canvasKey.currentState?.clear(),
          ),
        ],
      ),
      body: FlueraCanvas(
        key: _canvasKey,
        strokeColor: const Color(0xFF1A1A1A),
        strokeWidth: 2.2,
        background: const CanvasBackground.dotted(spacing: 28, dotRadius: 1.2),
      ),
    );
  }
}

// ─── Demo · multi-canvas + filesystem autosave ────────────────────────────
//
// Shows the SDK's `toBytes` / `loadFromBytes` primitives wired to a real
// gallery: each canvas is a `.fcv` file in the app docs dir; the home
// page lists them by mtime, taps open the editor, long-press deletes,
// and every committed/erased stroke schedules a debounced autosave.
//
// This is APP-SIDE code — the SDK is intentionally headless on storage
// (no path_provider dep) so consumers stay free to pick file system,
// SQLite, Hive, encrypted storage, cloud sync, etc.

class _CanvasMeta {
  _CanvasMeta(this.file, this.modified, this.sizeBytes);
  final File file;
  final DateTime modified;
  final int sizeBytes;
  String get id => file.uri.pathSegments.last.replaceAll('.fcv', '');
}

class _CanvasRepo {
  _CanvasRepo(this.dir);
  final Directory dir;

  static Future<_CanvasRepo> open() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/fluera_example_canvases');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _CanvasRepo(dir);
  }

  Future<List<_CanvasMeta>> list() async {
    final entries = await dir
        .list()
        .where((e) => e is File && e.path.endsWith('.fcv'))
        .cast<File>()
        .toList();
    final metas = <_CanvasMeta>[];
    for (final f in entries) {
      final stat = await f.stat();
      metas.add(_CanvasMeta(f, stat.modified, stat.size));
    }
    metas.sort((a, b) => b.modified.compareTo(a.modified));
    return metas;
  }

  File _fileFor(String id) => File('${dir.path}/$id.fcv');

  Future<File> create() async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final f = _fileFor(id);
    await f.writeAsBytes(CanvasSerializer.encodeBytes(const []));
    return f;
  }

  Future<Uint8List?> read(String id) async {
    final f = _fileFor(id);
    if (!await f.exists()) return null;
    return await f.readAsBytes();
  }

  Future<void> write(String id, Uint8List bytes) async {
    await _fileFor(id).writeAsBytes(bytes, flush: true);
  }

  /// Synchronous variant — used as a "last-chance flush" inside
  /// `dispose`, where we cannot await an async write before the parent
  /// route is popped and the home page re-lists files.
  void writeSync(String id, Uint8List bytes) {
    _fileFor(id).writeAsBytesSync(bytes, flush: true);
  }

  Future<void> delete(String id) async {
    final f = _fileFor(id);
    if (await f.exists()) await f.delete();
  }
}

class _MultiCanvasDemo extends StatefulWidget {
  const _MultiCanvasDemo();
  @override
  State<_MultiCanvasDemo> createState() => _MultiCanvasDemoState();
}

class _MultiCanvasDemoState extends State<_MultiCanvasDemo> {
  _CanvasRepo? _repo;
  List<_CanvasMeta> _canvases = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final repo = await _CanvasRepo.open();
    final list = await repo.list();
    if (!mounted) return;
    setState(() {
      _repo = repo;
      _canvases = list;
      _loading = false;
    });
  }

  Future<void> _refresh() async {
    final list = await _repo!.list();
    if (!mounted) return;
    setState(() => _canvases = list);
  }

  Future<void> _create() async {
    final f = await _repo!.create();
    final id = f.uri.pathSegments.last.replaceAll('.fcv', '');
    if (!mounted) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _CanvasEditor(repo: _repo!, canvasId: id),
      ),
    );
    await _refresh();
  }

  Future<void> _open(_CanvasMeta meta) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _CanvasEditor(repo: _repo!, canvasId: meta.id),
      ),
    );
    await _refresh();
  }

  Future<void> _delete(_CanvasMeta meta) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete canvas?'),
        content: Text(
          'Canvas from ${_fmt(meta.modified)} '
          '(${(meta.sizeBytes / 1024).toStringAsFixed(1)} KB).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _repo!.delete(meta.id);
      await _refresh();
    }
  }

  static String _fmt(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Multi-canvas + autosave')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _canvases.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.brush_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No canvases yet',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Tap + to create your first one. Every stroke is '
                      'autosaved to disk.',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              itemCount: _canvases.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final m = _canvases[i];
                return ListTile(
                  leading: const Icon(Icons.brush_rounded),
                  title: Text('Canvas ${i + 1}'),
                  subtitle: Text(
                    '${_fmt(m.modified)} · '
                    '${(m.sizeBytes / 1024).toStringAsFixed(1)} KB',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _open(m),
                  onLongPress: () => _delete(m),
                );
              },
            ),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New canvas'),
            ),
    );
  }
}

class _CanvasEditor extends StatefulWidget {
  const _CanvasEditor({required this.repo, required this.canvasId});
  final _CanvasRepo repo;
  final String canvasId;

  @override
  State<_CanvasEditor> createState() => _CanvasEditorState();
}

class _CanvasEditorState extends State<_CanvasEditor> {
  final _canvasKey = GlobalKey<FlueraCanvasState>();
  CanvasTool _tool = CanvasTool.draw;
  Color _color = const Color(0xFF1A1A1A);
  double _width = 3.0;
  double _eraserRadius = 32.0;

  bool _loaded = false;
  Uint8List? _initialBytes;
  Timer? _autosaveDebounce;
  bool _autosaving = false;
  DateTime? _lastSavedAt;

  /// Latest serialised bytes captured synchronously inside the stroke
  /// callbacks. `dispose()` uses this snapshot for a sync flush,
  /// because Flutter disposes State objects bottom-up — the child
  /// FlueraCanvasState is already gone by the time this runs and
  /// `_canvasKey.currentState` is `null`.
  Uint8List? _latestBytes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitial());
  }

  @override
  void dispose() {
    _autosaveDebounce?.cancel();
    // Last-chance SYNCHRONOUS flush of the snapshot captured in the
    // most recent stroke callback. Sync I/O completes before the
    // gallery re-list runs, so the home always sees the latest bytes
    // regardless of how the user left the editor.
    final bytes = _latestBytes;
    if (bytes != null && _loaded) {
      try {
        widget.repo.writeSync(widget.canvasId, bytes);
      } catch (_) {
        // Best-effort — don't block dispose.
      }
    }
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final bytes = await widget.repo.read(widget.canvasId);
    if (!mounted) return;
    // Pass bytes via the SDK's `initialBytes` parameter. The canvas
    // decodes them inside `initState` BEFORE the first paint, so the
    // first frame already shows the persisted strokes — no race with
    // RepaintBoundary cached layers, no second-paint coalescing on
    // Impeller-Vulkan.
    setState(() {
      _initialBytes = bytes;
      _loaded = true;
    });
  }

  // Debounced autosave: every state change schedules a write 500 ms later.
  // Multiple changes within the window collapse into a single I/O.
  void _scheduleAutosave() {
    _autosaveDebounce?.cancel();
    _autosaveDebounce = Timer(const Duration(milliseconds: 500), _doSave);
  }

  Future<void> _doSave() async {
    final state = _canvasKey.currentState;
    if (state == null || !_loaded) return;
    setState(() => _autosaving = true);
    try {
      await widget.repo.write(widget.canvasId, state.toBytes());
      if (mounted) {
        setState(() {
          _autosaving = false;
          _lastSavedAt = DateTime.now();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _autosaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text('Canvas'),
            const SizedBox(width: 12),
            if (_autosaving)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (_lastSavedAt != null)
              Icon(
                Icons.cloud_done_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.outline,
              ),
            if (_lastSavedAt != null && !_autosaving) ...[
              const SizedBox(width: 4),
              Text('saved', style: Theme.of(context).textTheme.labelSmall),
            ],
          ],
        ),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: FlueraCanvas(
                    key: _canvasKey,
                    tool: _tool,
                    strokeColor: _color,
                    strokeWidth: _width,
                    eraserRadius: _eraserRadius,
                    background: const CanvasBackground.solid(Color(0xFFFAFAFA)),
                    initialBytes: _initialBytes,
                    onStrokeCommitted: (_) => _scheduleAutosave(),
                    onStrokesErased: (_) => _scheduleAutosave(),
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
                  eraserRadius: _eraserRadius,
                  onEraserRadiusChanged: (r) =>
                      setState(() => _eraserRadius = r),
                  showShapeTools: true,
                  showPixelEraser: true,
                  showColorPickerButton: true,
                  showSelectionTool: true,
                  showImageTool: true,
                  showTransformActions: true,
                  showLayers: true,
                ),
              ],
            ),
    );
  }
}

// ─── Demo · multi-layer + FlueraLayerPanel ──────────────────────────────────

class _LayersDemo extends StatefulWidget {
  const _LayersDemo();
  @override
  State<_LayersDemo> createState() => _LayersDemoState();
}

class _LayersDemoState extends State<_LayersDemo> {
  final _canvasKey = GlobalKey<FlueraCanvasState>();
  CanvasTool _tool = CanvasTool.draw;
  Color _color = const Color(0xFF1A1A1A);
  double _width = 3.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Layers — multi-layer drawing'),
        actions: [
          IconButton(
            tooltip: 'Add layer',
            icon: const Icon(Icons.add_rounded),
            onPressed: () => _canvasKey.currentState?.addLayer(),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (ctx, constraints) {
          // Wide layout: side-by-side. Narrow layout: stacked, panel below.
          final wide = constraints.maxWidth >= 720;
          final canvas = FlueraCanvas(
            key: _canvasKey,
            tool: _tool,
            strokeColor: _color,
            strokeWidth: _width,
          );
          final panel = FlueraLayerPanel(canvasKey: _canvasKey);
          if (wide) {
            return Row(
              children: [
                Expanded(child: canvas),
                SizedBox(
                  width: 280,
                  child: Material(
                    color: Theme.of(ctx).colorScheme.surfaceContainerLow,
                    child: Column(
                      children: [
                        Expanded(child: panel),
                        _PaletteRow(
                          color: _color,
                          onColorChanged: (c) => setState(() => _color = c),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }
          return Column(
            children: [
              FlueraCanvasToolbar(
                canvasKey: _canvasKey,
                tool: _tool,
                onToolChanged: (t) => setState(() => _tool = t),
                color: _color,
                onColorChanged: (c) => setState(() => _color = c),
                strokeWidth: _width,
                onStrokeWidthChanged: (w) => setState(() => _width = w),
                eraserRadius: 32,
                onEraserRadiusChanged: (_) {},
              ),
              Expanded(child: canvas),
              SizedBox(height: 280, child: panel),
            ],
          );
        },
      ),
    );
  }
}

class _PaletteRow extends StatelessWidget {
  const _PaletteRow({required this.color, required this.onColorChanged});

  final Color color;
  final ValueChanged<Color> onColorChanged;

  @override
  Widget build(BuildContext context) {
    const palette = <Color>[
      Color(0xFF1A1A1A),
      Color(0xFFE53935),
      Color(0xFF1E88E5),
      Color(0xFF43A047),
      Color(0xFFFB8C00),
      Color(0xFF8E24AA),
    ];
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          for (final c in palette)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _ColorChip(
                color: c,
                selected: c.toARGB32() == color.toARGB32(),
                onTap: () => onColorChanged(c),
              ),
            ),
        ],
      ),
    );
  }
}

// Vector export demo (SVG / PDF) lives in `fluera_canvas_gpu/example/`
// — feature #3 was relocated to the commercial `fluera_canvas_gpu`
// package in canvas 0.7.1. Free pub.dev `fluera_canvas` keeps PNG
// raster export only, via `state.renderToImage(...)` (see "PNG export"
// demo above).

// ─── Demo · text tool + sticker panel (0.8.0) ──────────────────────────
//
// Showcases the new live text editor + sticker drop flow:
//   • Tap with the text tool → caret-positioned Material TextField
//     overlay; type → commit on Done / blur. Esc cancels.
//   • Tap the smiley toolbar button → sticker panel bottom sheet;
//     pick one → it lands at the viewport center as an `ImageNode`.
// Both flows produce nodes that participate in the standard
// selection / transform / undo pipeline.

class _TextStickerDemo extends StatefulWidget {
  const _TextStickerDemo();
  @override
  State<_TextStickerDemo> createState() => _TextStickerDemoState();
}

class _TextStickerDemoState extends State<_TextStickerDemo> {
  final _canvasKey = GlobalKey<FlueraCanvasState>();
  CanvasTool _tool = CanvasTool.text;
  Color _color = const Color(0xFF1A1A1A);
  double _width = 2.5;

  // Demo uses the built-in `kFlueraDefaultStickers` catalogue —
  // 8 Material-icon stickers rendered to a `ui.Image` via
  // `FlueraIconStickerProvider`. Zero asset bundling required.
  // Consumers can pass a custom `List<FlueraSticker>` here for
  // emoji / clip-art / brand kits.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Text + Stickers')),
      body: Column(
        children: [
          Expanded(
            child: FlueraCanvas(
              key: _canvasKey,
              tool: _tool,
              strokeColor: _color,
              strokeWidth: _width,
              snapToGrid: 16,
              smartGuidesEnabled: true,
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
            showSelectionTool: true,
            showImageTool: true,
            showTransformActions: true,
            showLayers: true,
            showTextTool: true,
            showStickerPanel: true,
            stickers: kFlueraDefaultStickers,
          ),
        ],
      ),
    );
  }
}

// ─── Demo · canvas backgrounds (0.9.x) ────────────────────────────────
//
// Demonstrates the four built-in `CanvasBackground` patterns: solid /
// grid / dotted / lined. The background is a widget prop so swapping
// it is a single setState — pixels redraw next frame, no scene-graph
// mutation required.

class _BackgroundsDemo extends StatefulWidget {
  const _BackgroundsDemo();
  @override
  State<_BackgroundsDemo> createState() => _BackgroundsDemoState();
}

class _BackgroundsDemoState extends State<_BackgroundsDemo> {
  final _canvasKey = GlobalKey<FlueraCanvasState>();
  CanvasBackground _bg = const CanvasBackground.dotted();
  String _label = 'Dotted';

  void _swap(CanvasBackground bg, String label) {
    setState(() {
      _bg = bg;
      _label = label;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Backgrounds · $_label'),
        actions: [
          IconButton(
            tooltip: 'Solid',
            icon: const Icon(Icons.format_color_fill_rounded),
            onPressed: () =>
                _swap(const CanvasBackground.solid(Color(0xFFFAFAFA)), 'Solid'),
          ),
          IconButton(
            tooltip: 'Grid',
            icon: const Icon(Icons.grid_4x4_rounded),
            onPressed: () => _swap(const CanvasBackground.grid(), 'Grid'),
          ),
          IconButton(
            tooltip: 'Dotted',
            icon: const Icon(Icons.grain_rounded),
            onPressed: () => _swap(const CanvasBackground.dotted(), 'Dotted'),
          ),
          IconButton(
            tooltip: 'Lined',
            icon: const Icon(Icons.notes_rounded),
            onPressed: () => _swap(const CanvasBackground.lined(), 'Lined'),
          ),
        ],
      ),
      body: FlueraCanvas(
        key: _canvasKey,
        background: _bg,
        tool: CanvasTool.draw,
      ),
    );
  }
}

// ─── Demo 11 · selection + snap-to-grid + smart guides ─────────────────────

class _SelectionDemo extends StatefulWidget {
  const _SelectionDemo();
  @override
  State<_SelectionDemo> createState() => _SelectionDemoState();
}

class _SelectionDemoState extends State<_SelectionDemo> {
  final _canvasKey = GlobalKey<FlueraCanvasState>();
  CanvasTool _tool = CanvasTool.select;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _seed();
      if (mounted) setState(() => _ready = true);
    });
  }

  void _seed() {
    final canvas = _canvasKey.currentState;
    if (canvas == null) return;

    Offset rectAt(double x, double y, double w, double h, int i) =>
        Offset(x + (i == 1 || i == 2 ? w : 0), y + (i >= 2 ? h : 0));

    // Three rectangles aligned on the same Y baseline so the smart-guide
    // engine has plenty of horizontal alignments to lock onto when the
    // user drags one of them.
    void pushRect(double x, double y, double w, double h, Color c) {
      final pts = <Offset>[
        rectAt(x, y, w, h, 0),
        rectAt(x, y, w, h, 1),
        rectAt(x, y, w, h, 2),
        rectAt(x, y, w, h, 3),
        rectAt(x, y, w, h, 0),
      ];
      canvas.pushStroke(
        CanvasStroke(
          points: pts,
          pressures: List.filled(pts.length, 0.85),
          color: c,
          baseWidth: 4,
          smooth: false, // sharp corners — these are rectangles
        ),
      );
    }

    pushRect(120, 240, 110, 80, const Color(0xFF1E88E5));
    pushRect(320, 240, 110, 80, const Color(0xFFE53935));
    pushRect(520, 240, 110, 80, const Color(0xFF43A047));

    // A circle below to give the selection something to align with on
    // the vertical axis too.
    final circle = <Offset>[];
    const cc = Offset(380, 460);
    for (int i = 0; i <= 60; i++) {
      final t = i / 60.0 * 2 * math.pi;
      circle.add(Offset(cc.dx + 70 * math.cos(t), cc.dy + 70 * math.sin(t)));
    }
    canvas.pushStroke(
      CanvasStroke(
        points: circle,
        pressures: List.filled(circle.length, 0.85),
        color: const Color(0xFFFB8C00),
        baseWidth: 4,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Selection + snap'),
        actions: [
          IconButton(
            tooltip: 'Undo',
            icon: const Icon(Icons.undo_rounded),
            onPressed: () => _canvasKey.currentState?.undo(),
          ),
          IconButton(
            tooltip: 'Duplicate selection',
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: () => _canvasKey.currentState?.duplicateSelection(),
          ),
          IconButton(
            tooltip: 'Delete selection',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () => _canvasKey.currentState?.deleteSelection(),
          ),
        ],
      ),
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<CanvasTool>(
                    segments: const [
                      ButtonSegment(
                        value: CanvasTool.select,
                        label: Text('Select'),
                        icon: Icon(Icons.touch_app_rounded),
                      ),
                      ButtonSegment(
                        value: CanvasTool.lasso,
                        label: Text('Lasso'),
                        icon: Icon(Icons.gesture_rounded),
                      ),
                      ButtonSegment(
                        value: CanvasTool.draw,
                        label: Text('Draw'),
                        icon: Icon(Icons.edit_rounded),
                      ),
                    ],
                    selected: {_tool},
                    onSelectionChanged: (s) => setState(() => _tool = s.first),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _ready
                        ? 'Tap a shape to select. Drag to move — guides snap to '
                              'the grid (16 px) and to neighbour-alignments.'
                        : 'Loading…',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: FlueraCanvas(
              key: _canvasKey,
              tool: _tool,
              snapToGrid: 16,
              smartGuidesEnabled: true,
              background: const CanvasBackground.grid(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Demo 12 · Zero-config FlueraSketch family ─────────────────────────────

class _ZeroConfigDemo extends StatelessWidget {
  const _ZeroConfigDemo();
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Zero-config (3 magic levels)'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'FlueraSketch'),
              Tab(text: 'Scaffold'),
              Tab(text: 'App'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _SketchOnlyDemo(),
            _ScaffoldDemo(),
            _AppDemo(),
          ],
        ),
      ),
    );
  }
}

class _SketchOnlyDemo extends StatelessWidget {
  const _SketchOnlyDemo();
  @override
  Widget build(BuildContext context) {
    // Lowest magic: just FlueraSketch as a body widget. Caller owns
    // the Scaffold; we picked the `notes` preset so you see how a
    // minimal preset reduces the toolbar.
    return const FlueraSketch(preset: FlueraSketchPreset.notes);
  }
}

class _ScaffoldDemo extends StatefulWidget {
  const _ScaffoldDemo();
  @override
  State<_ScaffoldDemo> createState() => _ScaffoldDemoState();
}

class _ScaffoldDemoState extends State<_ScaffoldDemo> {
  Uint8List? _saved;

  @override
  Widget build(BuildContext context) {
    // Mid magic: drop FlueraSketchScaffold into a parent route. This
    // one wires onAutoSave / onAutoLoad to in-memory bytes (a real
    // app would use path_provider). Note: nested Scaffold means our
    // AppBar lives below the demo's TabBar — fine for a demo.
    return FlueraSketchScaffold(
      title: 'My whiteboard',
      preset: FlueraSketchPreset.whiteboard,
      onAutoSave: (bytes) async {
        setState(() => _saved = bytes);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Autosaved ${(bytes.lengthInBytes / 1024).toStringAsFixed(1)} KB',
            ),
            duration: const Duration(milliseconds: 800),
          ),
        );
      },
      onAutoLoad: () async => _saved,
      onExportPng: (bytes) async {
        // Real-world PNG export: write to disk via path_provider.
        // The package itself is pure-Dart so it doesn't ship a
        // filesystem opinion — the consumer wires the sink.
        final dir = await getApplicationDocumentsDirectory();
        final ts = DateTime.now().millisecondsSinceEpoch;
        final file = File('${dir.path}/fluera-export-$ts.png');
        await file.writeAsBytes(bytes);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PNG exported → ${file.path}'),
            duration: const Duration(seconds: 4),
          ),
        );
      },
    );
  }
}

class _AppDemo extends StatelessWidget {
  const _AppDemo();
  @override
  Widget build(BuildContext context) {
    // Highest magic: the entire MaterialApp. In production you'd put
    // FlueraSketchApp directly in runApp(); here we nest it inside a
    // demo route just to showcase what it looks like.
    return FlueraSketchApp(
      title: 'Sign here',
      preset: FlueraSketchPreset.signature,
      onExportPng: (bytes) async {
        final dir = await getApplicationDocumentsDirectory();
        final ts = DateTime.now().millisecondsSinceEpoch;
        final file = File('${dir.path}/fluera-signature-$ts.png');
        await file.writeAsBytes(bytes);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Signature → ${file.path}')),
        );
      },
    );
  }
}
