# Integrations — common Flutter packages + fluera_canvas

Drop-in snippets showing how to wire `fluera_canvas` with the
state-management / persistence / sharing packages most Flutter
projects already pull. Every snippet here is paste-ready — drop it
into your project and adapt names. None of the integration packages
below are required dependencies of `fluera_canvas`; pick the ones
matching your stack.

## Compatibility matrix

| Package | Version tested | Use case |
|---|---|---|
| `flutter_riverpod` | 2.x | State-driven canvas (selected color / tool live in providers) |
| `flutter_bloc` | 8.x | Event-driven canvas (user gestures dispatched as events) |
| `drift` | 2.x | FCV0 bytes persisted in SQLite |
| `hive` | 2.x | FCV0 bytes persisted in a Hive box (mobile-friendly) |
| `path_provider` | 2.x | FCV0 bytes saved to disk (see [cookbook.md](cookbook.md) recipe #2) |
| `share_plus` | 10.x | Share PNG export via OS native share sheet |
| `cached_network_image` | 3.x | Image annotations from a URL |
| `printing` | 5.x | Print canvas via the OS print pipeline |

## Riverpod (`flutter_riverpod`)

Hold the active `tool` / `color` / `strokeWidth` in providers; the
canvas widget reads them and rebuilds when they change.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

final toolProvider = StateProvider((_) => CanvasTool.draw);
final colorProvider = StateProvider((_) => const Color(0xFF1A1A1A));
final widthProvider = StateProvider((_) => 2.5);

class RiverpodCanvas extends ConsumerWidget {
  const RiverpodCanvas({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canvasKey = GlobalKey<FlueraCanvasState>();
    return Column(children: [
      Expanded(child: FlueraCanvas(
        key: canvasKey,
        tool: ref.watch(toolProvider),
        strokeColor: ref.watch(colorProvider),
        strokeWidth: ref.watch(widthProvider),
      )),
      FlueraCanvasToolbar(
        canvasKey: canvasKey,
        tool: ref.watch(toolProvider),
        onToolChanged: (t) => ref.read(toolProvider.notifier).state = t,
        color: ref.watch(colorProvider),
        onColorChanged: (c) => ref.read(colorProvider.notifier).state = c,
        strokeWidth: ref.watch(widthProvider),
        onStrokeWidthChanged: (w) => ref.read(widthProvider.notifier).state = w,
      ),
    ]);
  }
}
```

## Bloc (`flutter_bloc`)

Treat user actions as events; `CanvasBloc` emits state updates the
widget consumes.

```dart
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

sealed class CanvasEvent {}
class ToolChanged extends CanvasEvent { ToolChanged(this.tool); final CanvasTool tool; }
class ColorChanged extends CanvasEvent { ColorChanged(this.color); final Color color; }

class CanvasState {
  const CanvasState({required this.tool, required this.color});
  final CanvasTool tool;
  final Color color;
  CanvasState copyWith({CanvasTool? tool, Color? color}) =>
      CanvasState(tool: tool ?? this.tool, color: color ?? this.color);
}

class CanvasBloc extends Bloc<CanvasEvent, CanvasState> {
  CanvasBloc() : super(const CanvasState(tool: CanvasTool.draw, color: Color(0xFF1A1A1A))) {
    on<ToolChanged>((e, emit) => emit(state.copyWith(tool: e.tool)));
    on<ColorChanged>((e, emit) => emit(state.copyWith(color: e.color)));
  }
}

// Wire-up: BlocBuilder<CanvasBloc, CanvasState> around FlueraCanvas + Toolbar.
```

## Drift (`drift`) — persist FCV0 in SQLite

Bytes round-trip via Drift's `Uint8List` column type. Match the
notes-app pattern: each row = one canvas; `BLOB` column holds FCV0
v8 bytes.

```dart
import 'package:drift/drift.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

class CanvasNotes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withDefault(const Constant(''))();
  BlobColumn get fcvBytes => blob()();
  DateTimeColumn get modifiedAt => dateTime()();
}

// Save:
await db.into(db.canvasNotes).insertOnConflictUpdate(CanvasNotesCompanion.insert(
  title: 'Meeting notes',
  fcvBytes: state.toBytes(),
  modifiedAt: DateTime.now(),
));

// Load:
final row = await (db.select(db.canvasNotes)..where((t) => t.id.equals(42))).getSingle();
state.loadFromBytes(row.fcvBytes);
```

## Hive (`hive`) — FCV0 in a Hive box

Mobile-friendly key-value store. One box, one canvas per key.

```dart
import 'package:hive/hive.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

final box = await Hive.openBox<Uint8List>('notes');

// Save:
await box.put('note-42', state.toBytes());

// Load:
final bytes = box.get('note-42');
if (bytes != null) state.loadFromBytes(bytes);
```

## share_plus — share PNG via native sheet

Pair `state.renderToImage` with `share_plus` for a "Share" button.

```dart
import 'dart:io';
import 'dart:ui' as ui;
import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> shareAsPng(FlueraCanvasState state, BuildContext context) async {
  final image = await state.renderToImage(
    bounds: FlueraExportBounds.allContent,
    pixelRatio: 2.0,
  );
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
      .buffer.asUint8List();
  image.dispose();
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/canvas-export.png')..writeAsBytesSync(bytes);
  await Share.shareXFiles([XFile(file.path)], text: 'My drawing');
}
```

## cached_network_image — image annotations from URL

When you want to attach a remote image as an annotation backdrop
(strokes drawn on top stick to the image's local frame).

```dart
import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

Future<void> attachImageFromUrl(
  FlueraCanvasState state,
  String url,
  Offset worldPosition,
) async {
  // Reuse cached_network_image's disk cache — avoids re-download on each load.
  final file = await DefaultCacheManager().getSingleFile(url);
  final bytes = await file.readAsBytes();
  state.attachImageFromBytes(
    bytes: bytes,
    worldPosition: worldPosition,
  );
}
```

(Substitute `attachImageFromBytes` with whichever public image-attach
API your version of fluera_canvas exposes — the pattern is the same.)

## printing — OS print pipeline

Wrap the PNG in a `pdf` document via `printing`.

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

Future<void> printCanvas(FlueraCanvasState state) async {
  final image = await state.renderToImage(
    bounds: FlueraExportBounds.allContent,
    pixelRatio: 3.0,  // 3× for print DPI
  );
  final png = (await image.toByteData(format: ui.ImageByteFormat.png))!
      .buffer.asUint8List();
  image.dispose();
  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    build: (_) => pw.Image(pw.MemoryImage(png), fit: pw.BoxFit.contain),
  ));
  await Printing.layoutPdf(onLayout: (_) async => doc.save());
}
```

**Note**: native PDF export with vector preservation (instead of
PNG → PDF wrapping) is a `fluera_canvas_gpu` commercial feature. The
free tier wraps a raster — adequate for a print button, lossy for
true vector workflows.

## When to reach for `fluera_canvas_gpu` instead

The integrations above all sit on top of the free SDK. When your
app needs:

- Real-time multi-user collaboration (CRDT)
- 16 Photoshop blend modes / mask layers / adjustment layers
- High-fidelity SVG / native PDF (vector preservation)
- Brush calligrafici (fountain pen, technical pen, charcoal angled)
- Stroke replay / time-travel viewer

…install [`fluera_canvas_gpu`](https://pub.dev/packages/fluera_canvas_gpu)
alongside. It plugs into the same scene graph via the public
`GpuStrokeBackend` hook — no API changes in your application code,
just an extra dependency.
