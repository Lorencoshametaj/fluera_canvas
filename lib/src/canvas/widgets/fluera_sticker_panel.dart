import 'dart:async' show Completer;
import 'dart:typed_data' show Uint8List;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../core/models/image_element.dart';
import '../../core/nodes/image_node.dart';
import '../../core/scene_graph/node_id.dart';
import '../../rendering/canvas/image_node_painter.dart';
import '../../utils/uid.dart' show generateUid;
import '../fluera_canvas_widget.dart' show FlueraCanvasState;

/// Single entry in a [FlueraStickerPanel]. Pairs a stable identifier
/// with a thumbnail [ImageProvider] (`AssetImage`, `MemoryImage`,
/// `NetworkImage` — anything Flutter can decode) and an optional
/// preferred world-space size in canvas units.
///
/// The [id] is reused as the cache key prefix for `ImageNodePainter`,
/// so the same sticker tapped twice shares the decoded `ui.Image`
/// (one decode per process, regardless of how many times the user
/// drops the same sticker).
@immutable
class FlueraSticker {
  const FlueraSticker({
    required this.id,
    required this.label,
    required this.provider,
    this.size = const Size(120, 120),
  });

  /// Convenience constructor for icon-based stickers — paints the
  /// supplied [icon] (any [IconData] from the Flutter SDK or a
  /// custom font) into a square ImageProvider via
  /// [FlueraIconStickerProvider]. Zero asset bundling, zero
  /// licensing concerns. Used by [kFlueraDefaultStickers] for the
  /// out-of-the-box catalogue.
  factory FlueraSticker.fromIcon({
    required String id,
    required String label,
    required IconData icon,
    Color color = const Color(0xFF1A1A1A),
    double pixelSize = 128,
    Size size = const Size(96, 96),
  }) {
    return FlueraSticker(
      id: id,
      label: label,
      provider: FlueraIconStickerProvider(
        icon: icon,
        color: color,
        pixelSize: pixelSize,
      ),
      size: size,
    );
  }

  final String id;
  final String label;
  final ImageProvider provider;
  final Size size;
}

/// `ImageProvider` that renders an [IconData] (typically a Material
/// icon from the Flutter SDK, or any custom icon-font glyph) into a
/// square `ui.Image` on first load. Cached by Flutter's
/// `imageCache` keyed on `(icon.codePoint, color, pixelSize,
/// fontFamily)`, so dropping the same sticker N times resolves to
/// the same handle without re-rasterisation.
@immutable
class FlueraIconStickerProvider
    extends ImageProvider<FlueraIconStickerProvider> {
  const FlueraIconStickerProvider({
    required this.icon,
    this.color = const Color(0xFF1A1A1A),
    this.pixelSize = 128,
  });

  final IconData icon;
  final Color color;
  final double pixelSize;

  @override
  Future<FlueraIconStickerProvider> obtainKey(ImageConfiguration cfg) {
    return SynchronousFuture<FlueraIconStickerProvider>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    FlueraIconStickerProvider key,
    ImageDecoderCallback decode,
  ) {
    return OneFrameImageStreamCompleter(_render(key));
  }

  Future<ImageInfo> _render(FlueraIconStickerProvider key) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // Center the glyph in a `pixelSize × pixelSize` box and paint
    // it through TextPainter — same renderer Flutter's `Icon`
    // widget uses, so font ligatures + variable-glyph metrics are
    // honoured.
    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(key.icon.codePoint),
        style: TextStyle(
          fontFamily: key.icon.fontFamily,
          package: key.icon.fontPackage,
          fontSize: key.pixelSize,
          color: key.color,
          inherit: false,
          fontFamilyFallback: const ['MaterialIcons'],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = (key.pixelSize - tp.width) / 2;
    final dy = (key.pixelSize - tp.height) / 2;
    tp.paint(canvas, Offset(dx, dy));
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      key.pixelSize.toInt(),
      key.pixelSize.toInt(),
    );
    return ImageInfo(image: image);
  }

  @override
  bool operator ==(Object other) =>
      other is FlueraIconStickerProvider &&
      other.icon.codePoint == icon.codePoint &&
      other.icon.fontFamily == icon.fontFamily &&
      other.color.toARGB32() == color.toARGB32() &&
      other.pixelSize == pixelSize;

  @override
  int get hashCode =>
      Object.hash(icon.codePoint, icon.fontFamily, color.toARGB32(), pixelSize);
}

/// Default catalogue used by [FlueraCanvasToolbar.showStickerPanel]
/// when the host doesn't supply its own. Built from Material Icons
/// rendered into PNG bytes at first access via
/// [FlueraIconStickerProvider] — zero asset bundling, zero licensing
/// concerns (Material Icons ship with the Flutter SDK). Override
/// with a custom catalogue when you want emoji / clip-art.
const List<FlueraSticker> kFlueraDefaultStickers = <FlueraSticker>[
  FlueraSticker(
    id: 'star',
    label: 'Star',
    provider: FlueraIconStickerProvider(
      icon: Icons.star_rounded,
      color: Color(0xFFFFB300),
    ),
    size: Size(96, 96),
  ),
  FlueraSticker(
    id: 'heart',
    label: 'Heart',
    provider: FlueraIconStickerProvider(
      icon: Icons.favorite_rounded,
      color: Color(0xFFE53935),
    ),
    size: Size(96, 96),
  ),
  FlueraSticker(
    id: 'check',
    label: 'Check',
    provider: FlueraIconStickerProvider(
      icon: Icons.check_circle_rounded,
      color: Color(0xFF43A047),
    ),
    size: Size(96, 96),
  ),
  FlueraSticker(
    id: 'close',
    label: 'Close',
    provider: FlueraIconStickerProvider(
      icon: Icons.cancel_rounded,
      color: Color(0xFFE53935),
    ),
    size: Size(96, 96),
  ),
  FlueraSticker(
    id: 'arrow',
    label: 'Arrow',
    provider: FlueraIconStickerProvider(
      icon: Icons.arrow_forward_rounded,
      color: Color(0xFF1E88E5),
    ),
    size: Size(96, 96),
  ),
  FlueraSticker(
    id: 'lightbulb',
    label: 'Idea',
    provider: FlueraIconStickerProvider(
      icon: Icons.lightbulb_rounded,
      color: Color(0xFFFFB300),
    ),
    size: Size(96, 96),
  ),
  FlueraSticker(
    id: 'flag',
    label: 'Flag',
    provider: FlueraIconStickerProvider(
      icon: Icons.flag_rounded,
      color: Color(0xFFE53935),
    ),
    size: Size(96, 96),
  ),
  FlueraSticker(
    id: 'pin',
    label: 'Pin',
    provider: FlueraIconStickerProvider(
      icon: Icons.push_pin_rounded,
      color: Color(0xFF8E24AA),
    ),
    size: Size(96, 96),
  ),
];

/// Drop-in panel that lets the user browse and tap a sticker to
/// commit it as an [ImageNode] on the active layer. Pair it with
/// `FlueraCanvasToolbar.showStickerPanel: true` for the standard
/// bottom-sheet UX, or mount it anywhere in your widget tree.
///
/// ```dart
/// FlueraStickerPanel(
///   canvasKey: _canvasKey,
///   stickers: const [
///     FlueraSticker(
///       id: 'cat',
///       label: 'Cat',
///       provider: AssetImage('assets/stickers/cat.png'),
///     ),
///   ],
/// );
/// ```
class FlueraStickerPanel extends StatelessWidget {
  const FlueraStickerPanel({
    super.key,
    required this.canvasKey,
    this.stickers = kFlueraDefaultStickers,
    this.crossAxisCount = 4,
    this.thumbnailPadding = const EdgeInsets.all(8),
    this.onSelected,
  });

  /// Key of the [FlueraCanvas] this panel commits stickers onto.
  final GlobalKey<FlueraCanvasState> canvasKey;

  /// Catalogue rendered as a grid. Defaults to
  /// [kFlueraDefaultStickers] (empty); pass your own list to populate.
  final List<FlueraSticker> stickers;

  /// Columns in the thumbnail grid.
  final int crossAxisCount;

  /// Padding around each thumbnail.
  final EdgeInsetsGeometry thumbnailPadding;

  /// Optional hook invoked AFTER the sticker has been committed.
  /// Useful for analytics or to dismiss the host bottom-sheet.
  final void Function(FlueraSticker sticker, ImageNode node)? onSelected;

  @override
  Widget build(BuildContext context) {
    if (stickers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No stickers configured.\nPass a `stickers:` list to populate.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: stickers.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemBuilder: (ctx, i) {
        final sticker = stickers[i];
        return _StickerTile(
          sticker: sticker,
          padding: thumbnailPadding,
          onTap: () => _commit(ctx, sticker),
        );
      },
    );
  }

  Future<void> _commit(BuildContext context, FlueraSticker sticker) async {
    final state = canvasKey.currentState;
    if (state == null) return;
    // Capture the canvas's own viewport BEFORE we await the codec —
    // the original BuildContext (which lives inside the bottom-sheet)
    // isn't safe to touch once we resume, and `MediaQuery.size` would
    // give us the entire screen, not the canvas area, so the sticker
    // could land underneath the open bottom sheet on phones.
    final viewportCenter = state.viewportCenterWorld;

    // Cache key reuses the sticker id so duplicate drops share the
    // GPU handle. Adding a per-instance suffix would force one
    // decode per drop — wasteful for stickers, which are repeatable.
    final imagePath = 'fluera-canvas://sticker/${sticker.id}';

    // Fast path: if this sticker has already been decoded once in
    // this process (any prior drop, even on a different canvas
    // instance), skip the codec round-trip entirely.
    if (!ImageNodePainter.isCached(imagePath)) {
      Uint8List? bytes;
      try {
        bytes = await _readBytes(sticker.provider);
      } catch (_) {
        bytes = null;
      }
      if (bytes == null) return;

      final ui.Image decoded;
      try {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        decoded = frame.image;
      } catch (_) {
        return;
      }
      ImageNodePainter.cacheWithBytes(imagePath, decoded, bytes);
    }

    // Anchor the sticker at the canvas viewport's centre (world
    // coords) — captured before the await above so it reflects where
    // the user could see the canvas at the moment they tapped the
    // thumbnail. Falls back to (0,0) if the canvas hasn't laid out
    // yet (consumer dropped a sticker before the first frame).
    final centerWorld = viewportCenter;
    final natural = sticker.size;
    final origin = Offset(
      centerWorld.dx - natural.width / 2,
      centerWorld.dy - natural.height / 2,
    );

    final id = generateUid();
    final element = ImageElement(
      id: id,
      imagePath: imagePath,
      position: origin,
      createdAt: DateTime.now(),
      pageIndex: 0,
    );
    final node = ImageNode(
      id: NodeId(id),
      imageElement: element,
      imageSize: natural,
    );
    state.addImageNode(node);
    onSelected?.call(sticker, node);
  }

  static Future<Uint8List?> _readBytes(ImageProvider provider) async {
    if (provider is AssetImage) {
      final byteData = await rootBundle.load(provider.assetName);
      return byteData.buffer.asUint8List();
    }
    if (provider is MemoryImage) {
      return provider.bytes;
    }
    // For NetworkImage / FileImage and other providers, defer to the
    // standard ImageStream resolver. We materialize the resulting
    // ui.Image as PNG bytes so the cache + serializer pipeline
    // (which expects encoded asset bytes) gets a usable payload.
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(const ImageConfiguration());
    bool removed = false;
    late final ImageStreamListener listener;
    void cleanup() {
      if (removed) return;
      removed = true;
      stream.removeListener(listener);
    }

    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) completer.complete(info.image);
        cleanup();
      },
      onError: (e, st) {
        if (!completer.isCompleted) completer.completeError(e);
        cleanup();
      },
    );
    stream.addListener(listener);
    final image = await completer.future;
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }
}

class _StickerTile extends StatelessWidget {
  const _StickerTile({
    required this.sticker,
    required this.padding,
    required this.onTap,
  });

  final FlueraSticker sticker;
  final EdgeInsetsGeometry padding;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: Image(image: sticker.provider, fit: BoxFit.contain),
              ),
              const SizedBox(height: 4),
              Text(
                sticker.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
