// ════════════════════════════════════════════════════════════════════════════
// 🧁 FlueraLayerPanel — drop-in layer panel widget for FlueraCanvas (0.6.0+).
//
// Wraps the layer model exposed by `FlueraCanvasState` with a Material 3 UX:
// reorderable list, per-layer opacity slider, visibility toggle, lock toggle,
// blend-mode picker, inline rename and add/duplicate/delete actions. Hosts
// can mount the panel anywhere — modal sheet, side rail, drawer — by passing
// the canvas's `GlobalKey<FlueraCanvasState>`.
//
// The panel is self-rebuilding: it subscribes to the canvas's layer-change
// listenable (`canvasState.layerChanges`) and re-renders on every commit
// without forcing the parent widget to do its own state management.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:ui' as ui show Image;
import 'dart:ui' show BlendMode;

import 'package:flutter/material.dart';

import '../core/nodes/layer_node.dart';
import '../core/scene_graph/node_id.dart';
import 'fluera_blend_mode.dart';
import 'fluera_canvas_widget.dart';

/// Drop-in layer panel for [FlueraCanvas].
///
/// Mount it next to the canvas (modal bottom sheet, side rail, drawer, …)
/// and pass the canvas's `GlobalKey` via [canvasKey]. The panel
/// auto-rebuilds whenever the canvas notifies a layer change.
///
/// ```dart
/// final canvasKey = GlobalKey<FlueraCanvasState>();
/// // … inside build:
/// Row(children: [
///   Expanded(child: FlueraCanvas(key: canvasKey)),
///   SizedBox(width: 280, child: FlueraLayerPanel(canvasKey: canvasKey)),
/// ]);
/// ```
class FlueraLayerPanel extends StatefulWidget {
  /// API element `FlueraLayerPanel`.
  const FlueraLayerPanel({
    super.key,
    required this.canvasKey,
    this.blendModes = _defaultBlendModes,
    this.flueraBlendModes,
    this.showAddButton = true,
    this.showDuplicateButton = true,
    this.showOpacitySlider = true,
    this.showBlendModePicker = true,
    this.padding = const EdgeInsets.all(8),
    this.showThumbnail = false,
    this.thumbnailSize = const Size(40, 40),
    this.colorTagPalette = _defaultColorTagPalette,
    this.enableSwipeActions = false,
    this.showRenameButton = true,
  });

  /// Reference to the canvas this panel drives. The panel calls public
  /// methods on `canvasKey.currentState` (`addLayer`, `removeLayer`,
  /// `setLayerOpacity`, …) so layer changes round-trip correctly through
  /// the canvas's notification pipeline.
  final GlobalKey<FlueraCanvasState> canvasKey;

  /// Blend modes shown in the per-layer dropdown. Defaults to a curated
  /// set of nine standard `BlendMode` values that are useful for vector
  /// drawing apps. Override with a longer list to expose Photoshop-grade
  /// modes (recommended only when the commercial `fluera_canvas_gpu`
  /// compositor is registered).
  ///
  /// Ignored when [flueraBlendModes] is non-null — the richer
  /// `FlueraBlendMode` enum (26 modes including 9 Photoshop extended
  /// values) takes precedence then.
  final List<BlendMode> blendModes;

  /// When non-null, the blend-mode dropdown shows this list of
  /// [FlueraBlendMode] values instead of the [blendModes] `ui.BlendMode`
  /// list. Use this to expose the 9 Photoshop-grade extended modes
  /// (LinearBurn, VividLight, …) — they are honoured pixel-accurately by
  /// the commercial `fluera_canvas_gpu` compositor (Stage 2B+) and fall
  /// back to the closest `ui.BlendMode` when the free pub.dev core
  /// renders without the GPU add-on.
  final List<FlueraBlendMode>? flueraBlendModes;

  /// Show the `+` button in the header (calls `addLayer`).
  final bool showAddButton;

  /// Show the `copy` button per row (calls `duplicateLayer`).
  final bool showDuplicateButton;

  /// Render the inline opacity slider on each row.
  final bool showOpacitySlider;

  /// Render the blend-mode dropdown on each row.
  final bool showBlendModePicker;

  /// Padding around the entire panel.
  final EdgeInsetsGeometry padding;

  /// When `true`, each row renders a small bitmap preview of the
  /// layer's content via `FlueraCanvasState.renderLayerThumbnail`.
  /// Disabled by default — thumbnails involve a `toImageSync` per
  /// rebuild, so consumers that show 100+ layers should opt-in only
  /// when the panel is open. The thumbnail invalidates automatically
  /// on layer changes through `layerChanges`.
  final bool showThumbnail;

  /// Pixel size of each thumbnail when [showThumbnail] is `true`.
  final Size thumbnailSize;

  /// Palette of colors offered when the user taps the per-row color
  /// tag chip. The first chip is always "no tag" (`null`); the rest
  /// come from this list. Override to customise (Procreate uses 6
  /// muted accents).
  final List<Color> colorTagPalette;

  /// When `true`, each row is wrapped in a `Dismissible` so the user
  /// can swipe-left to delete or swipe-right to duplicate. Disabled
  /// by default to keep the panel keyboard / mouse-first.
  final bool enableSwipeActions;

  /// When `true`, each row shows a pencil icon next to the layer name
  /// that opens the inline rename TextField. Double-tap on the name
  /// is also wired as a shortcut. Set `false` to remove the icon when
  /// the panel is read-only.
  final bool showRenameButton;

  static const List<Color> _defaultColorTagPalette = <Color>[
    Color(0xFFE53935), // red
    Color(0xFFFB8C00), // orange
    Color(0xFFFDD835), // yellow
    Color(0xFF43A047), // green
    Color(0xFF1E88E5), // blue
    Color(0xFF8E24AA), // purple
  ];

  static const List<BlendMode> _defaultBlendModes = <BlendMode>[
    BlendMode.srcOver, // Normal
    BlendMode.multiply,
    BlendMode.screen,
    BlendMode.overlay,
    BlendMode.darken,
    BlendMode.lighten,
    BlendMode.colorDodge,
    BlendMode.colorBurn,
    BlendMode.difference,
  ];

  @override
  State<FlueraLayerPanel> createState() => _FlueraLayerPanelState();
}

class _FlueraLayerPanelState extends State<FlueraLayerPanel> {
  Listenable? _subscribed;

  void _onLayerChanged() {
    if (mounted) setState(() {});
  }

  void _ensureSubscription() {
    final state = widget.canvasKey.currentState;
    final source = state?.layerChanges;
    if (identical(source, _subscribed)) return;
    _subscribed?.removeListener(_onLayerChanged);
    _subscribed = source;
    _subscribed?.addListener(_onLayerChanged);
  }

  @override
  void initState() {
    super.initState();
    // The canvas may not be mounted yet on the first build; defer the
    // subscription to the next frame so `currentState` resolves.
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSubscription());
  }

  @override
  void didUpdateWidget(covariant FlueraLayerPanel old) {
    super.didUpdateWidget(old);
    if (old.canvasKey != widget.canvasKey) {
      _subscribed?.removeListener(_onLayerChanged);
      _subscribed = null;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureSubscription(),
      );
    }
  }

  @override
  void dispose() {
    _subscribed?.removeListener(_onLayerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _ensureSubscription();
    final state = widget.canvasKey.currentState;
    final theme = Theme.of(context);
    if (state == null) {
      // Canvas not mounted yet — render an empty placeholder. The
      // post-frame callback will trigger the rebuild once it is.
      return Padding(
        padding: widget.padding,
        child: Center(
          child: Text(
            'Layer panel — canvas not mounted yet',
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    // Bottom-to-top in scene graph order, but visually we list top-to-
    // bottom (top = first in the list) — that's the convention every
    // drawing app uses.
    final layers = state.layers.reversed.toList();
    final activeLayerId = state.activeLayer.id;

    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            title: 'Layers',
            onAdd: widget.showAddButton ? () => state.addLayer() : null,
            count: layers.length,
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              itemCount: layers.length,
              onReorder: (oldIdx, newIdx) {
                // The list is rendered top-to-bottom but the scene graph
                // stores bottom-to-top, so flip the indices.
                final n = layers.length;
                final fromSceneIdx = n - 1 - oldIdx;
                // Flutter's ReorderableListView reports `newIdx` AFTER
                // the removal on a downward drag, so adjust.
                final adjustedNewIdx = newIdx > oldIdx ? newIdx - 1 : newIdx;
                final toSceneIdx = n - 1 - adjustedNewIdx;
                state.reorderLayer(layers[oldIdx].id, toSceneIdx);
              },
              itemBuilder: (ctx, i) {
                final layer = layers[i];
                // Render the thumbnail lazily here (per rebuild) — the
                // canvas's `layerChanges` Listenable triggers our
                // setState, so the bitmap stays fresh as strokes are
                // drawn / undone. We don't try to cache (would need
                // dispose tracking + per-layer-id keys).
                ui.Image? thumb;
                if (widget.showThumbnail) {
                  thumb = state.renderLayerThumbnail(
                    layer.id,
                    widget.thumbnailSize,
                  );
                }
                return _LayerRow(
                  key: ValueKey(layer.id.value),
                  index: i,
                  layer: layer,
                  active: layer.id == activeLayerId,
                  blendModes: widget.blendModes,
                  flueraBlendModes: widget.flueraBlendModes,
                  currentFlueraMode: state.flueraBlendModeFor(layer),
                  showOpacitySlider: widget.showOpacitySlider,
                  showBlendModePicker: widget.showBlendModePicker,
                  showDuplicateButton: widget.showDuplicateButton,
                  canDelete: layers.length > 1,
                  thumbnail: thumb,
                  thumbnailSize: widget.thumbnailSize,
                  colorTag: state.layerColorTagFor(layer.id),
                  colorTagPalette: widget.colorTagPalette,
                  enableSwipeActions: widget.enableSwipeActions,
                  showRenameButton: widget.showRenameButton,
                  onTap: () => state.setActiveLayer(layer.id),
                  onToggleVisible:
                      () => state.setLayerVisible(layer.id, !layer.isVisible),
                  onToggleLocked:
                      () => state.setLayerLocked(layer.id, !layer.isLocked),
                  onOpacityChanged: (v) => state.setLayerOpacity(layer.id, v),
                  onBlendModeChanged:
                      (m) => state.setLayerBlendMode(layer.id, m),
                  onFlueraBlendModeChanged:
                      (m) => state.setLayerFlueraBlendMode(layer.id, m),
                  onRename: (newName) => state.setLayerName(layer.id, newName),
                  onDuplicate: () => state.duplicateLayer(layer.id),
                  onDelete: () => state.removeLayer(layer.id),
                  onColorTagChanged: (c) => state.setLayerColorTag(layer.id, c),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.count, this.onAdd});

  final String title;
  final int count;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Text(
          '$title  ($count)',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        if (onAdd != null)
          IconButton(
            tooltip: 'Add layer',
            icon: const Icon(Icons.add_rounded),
            onPressed: onAdd,
            visualDensity: VisualDensity.compact,
          ),
      ],
    );
  }
}

class _LayerRow extends StatefulWidget {
  const _LayerRow({
    super.key,
    required this.index,
    required this.layer,
    required this.active,
    required this.blendModes,
    required this.flueraBlendModes,
    required this.currentFlueraMode,
    required this.showOpacitySlider,
    required this.showBlendModePicker,
    required this.showDuplicateButton,
    required this.canDelete,
    required this.thumbnail,
    required this.thumbnailSize,
    required this.colorTag,
    required this.colorTagPalette,
    required this.enableSwipeActions,
    required this.showRenameButton,
    required this.onTap,
    required this.onToggleVisible,
    required this.onToggleLocked,
    required this.onOpacityChanged,
    required this.onBlendModeChanged,
    required this.onFlueraBlendModeChanged,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
    required this.onColorTagChanged,
  });

  final int index;
  final LayerNode layer;
  final bool active;
  final List<BlendMode> blendModes;
  final List<FlueraBlendMode>? flueraBlendModes;
  final FlueraBlendMode currentFlueraMode;
  final bool showOpacitySlider;
  final bool showBlendModePicker;
  final bool showDuplicateButton;
  final bool canDelete;
  final ui.Image? thumbnail;
  final Size thumbnailSize;
  final Color? colorTag;
  final List<Color> colorTagPalette;
  final bool enableSwipeActions;
  final bool showRenameButton;
  final VoidCallback onTap;
  final VoidCallback onToggleVisible;
  final VoidCallback onToggleLocked;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<BlendMode> onBlendModeChanged;
  final ValueChanged<FlueraBlendMode> onFlueraBlendModeChanged;
  final ValueChanged<String> onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final ValueChanged<Color?> onColorTagChanged;

  @override
  State<_LayerRow> createState() => _LayerRowState();
}

class _LayerRowState extends State<_LayerRow> {
  bool _editingName = false;
  late TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.layer.name);
  }

  @override
  void didUpdateWidget(covariant _LayerRow old) {
    super.didUpdateWidget(old);
    if (old.layer.name != widget.layer.name && !_editingName) {
      _nameCtrl.text = widget.layer.name;
    }
    // Thumbnails are produced by the panel via `renderLayerThumbnail`,
    // which transfers ownership of a fresh `ui.Image` to the row on
    // every rebuild. Dispose the previous handle here so the GPU
    // texture is released — the panel re-renders on every commit, so
    // long-running sessions would otherwise leak one image per row
    // per tick.
    if (!identical(old.thumbnail, widget.thumbnail)) {
      old.thumbnail?.dispose();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    widget.thumbnail?.dispose();
    super.dispose();
  }

  void _commitRename() {
    final v = _nameCtrl.text.trim();
    if (v.isNotEmpty && v != widget.layer.name) {
      widget.onRename(v);
    } else {
      _nameCtrl.text = widget.layer.name;
    }
    setState(() => _editingName = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final layer = widget.layer;
    final highlight = widget.active ? cs.primaryContainer : cs.surfaceContainer;
    final fg = widget.active ? cs.onPrimaryContainer : cs.onSurface;
    final card = Material(
      color: highlight,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ReorderableDragStartListener(
                    index: widget.index,
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 18,
                      color: fg.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Color tag chip — tappable popup palette. Compact
                  // 10×10 dot visible only when a tag is set; an
                  // outlined ring when empty so the user discovers
                  // it without it adding visual noise.
                  _ColorTagChip(
                    current: widget.colorTag,
                    palette: widget.colorTagPalette,
                    onChanged: widget.onColorTagChanged,
                  ),
                  const SizedBox(width: 4),
                  // Thumbnail preview of layer content. Rendered by
                  // the panel via `state.renderLayerThumbnail` and
                  // handed to us as `widget.thumbnail`. Owner is the
                  // panel — we just display.
                  if (widget.thumbnail != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          width: widget.thumbnailSize.width,
                          height: widget.thumbnailSize.height,
                          child: RawImage(
                            image: widget.thumbnail,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  IconButton(
                    tooltip: layer.isVisible ? 'Hide layer' : 'Show layer',
                    icon: Icon(
                      layer.isVisible
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      size: 18,
                    ),
                    onPressed: widget.onToggleVisible,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                  IconButton(
                    tooltip: layer.isLocked ? 'Unlock' : 'Lock',
                    icon: Icon(
                      layer.isLocked
                          ? Icons.lock_rounded
                          : Icons.lock_open_rounded,
                      size: 18,
                      color: layer.isLocked ? cs.error : null,
                    ),
                    onPressed: widget.onToggleLocked,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child:
                        _editingName
                            ? TextField(
                              controller: _nameCtrl,
                              autofocus: true,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: fg,
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => _commitRename(),
                              onTapOutside: (_) => _commitRename(),
                            )
                            : GestureDetector(
                              onDoubleTap:
                                  () => setState(() => _editingName = true),
                              child: Text(
                                layer.name,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: fg,
                                  fontWeight:
                                      widget.active
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                ),
                              ),
                            ),
                  ),
                  if (widget.showRenameButton && !_editingName)
                    IconButton(
                      tooltip: 'Rename',
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      onPressed: () => setState(() => _editingName = true),
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                  if (widget.showDuplicateButton)
                    IconButton(
                      tooltip: 'Duplicate',
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      onPressed: widget.onDuplicate,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                  IconButton(
                    tooltip:
                        widget.canDelete
                            ? 'Delete'
                            : 'Cannot delete the last layer',
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      size: 16,
                      color:
                          widget.canDelete
                              ? cs.error
                              : fg.withValues(alpha: 0.3),
                    ),
                    onPressed: widget.canDelete ? widget.onDelete : null,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                ],
              ),
              if (widget.showOpacitySlider)
                Row(
                  children: [
                    const SizedBox(width: 22),
                    Text(
                      '${(layer.opacity * 100).round()}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: fg.withValues(alpha: 0.7),
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: layer.opacity,
                        min: 0,
                        max: 1,
                        onChanged: widget.onOpacityChanged,
                      ),
                    ),
                  ],
                ),
              if (widget.showBlendModePicker)
                Padding(
                  padding: const EdgeInsets.only(left: 22, right: 4),
                  child:
                      widget.flueraBlendModes != null
                          // Path A — caller opted into the rich
                          // FlueraBlendMode enum (26 modes including the 9
                          // Photoshop-grade extended ones). Used when the
                          // commercial GpuLayerCompositor is registered.
                          ? DropdownButton<FlueraBlendMode>(
                            isDense: true,
                            isExpanded: true,
                            value:
                                widget.flueraBlendModes!.contains(
                                      widget.currentFlueraMode,
                                    )
                                    ? widget.currentFlueraMode
                                    : widget.flueraBlendModes!.first,
                            items: [
                              for (final m in widget.flueraBlendModes!)
                                DropdownMenuItem<FlueraBlendMode>(
                                  value: m,
                                  child: Text(
                                    m.isExtended ? '${m.name} ⚡' : m.name,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                            ],
                            onChanged: (m) {
                              if (m != null) {
                                widget.onFlueraBlendModeChanged(m);
                              }
                            },
                          )
                          // Path B — pub.dev free path with the legacy
                          // ui.BlendMode list.
                          : DropdownButton<BlendMode>(
                            isDense: true,
                            isExpanded: true,
                            value:
                                widget.blendModes.contains(layer.blendMode)
                                    ? layer.blendMode
                                    : widget.blendModes.first,
                            items: [
                              for (final m in widget.blendModes)
                                DropdownMenuItem<BlendMode>(
                                  value: m,
                                  child: Text(
                                    _blendModeLabel(m),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                            ],
                            onChanged: (m) {
                              if (m != null) widget.onBlendModeChanged(m);
                            },
                          ),
                ),
            ],
          ),
        ),
      ),
    );
    // Optional swipe-to-action wrapper. Swipe right (start→end) =
    // duplicate; swipe left (end→start) = delete (only when allowed).
    // We confirm both gestures via `confirmDismiss` returning false so
    // the row never actually disappears under the user's finger —
    // the underlying state callbacks already drive the rebuild.
    Widget content = card;
    if (widget.enableSwipeActions) {
      content = Dismissible(
        key: ValueKey('dismiss-${layer.id.value}'),
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: cs.tertiaryContainer,
          child: Icon(Icons.copy_rounded, color: cs.onTertiaryContainer),
        ),
        secondaryBackground: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          color: widget.canDelete ? cs.errorContainer : cs.surfaceContainerLow,
          child: Icon(
            Icons.delete_outline_rounded,
            color: widget.canDelete ? cs.onErrorContainer : cs.outline,
          ),
        ),
        confirmDismiss: (dir) async {
          if (dir == DismissDirection.startToEnd) {
            widget.onDuplicate();
          } else if (dir == DismissDirection.endToStart && widget.canDelete) {
            widget.onDelete();
          }
          return false;
        },
        child: content,
      );
    }
    return Padding(
      key: ValueKey('row-${layer.id.value}'),
      padding: const EdgeInsets.only(bottom: 6),
      child: content,
    );
  }

  static String _blendModeLabel(BlendMode mode) {
    switch (mode) {
      case BlendMode.srcOver:
        return 'Normal';
      case BlendMode.multiply:
        return 'Multiply';
      case BlendMode.screen:
        return 'Screen';
      case BlendMode.overlay:
        return 'Overlay';
      case BlendMode.darken:
        return 'Darken';
      case BlendMode.lighten:
        return 'Lighten';
      case BlendMode.colorDodge:
        return 'Color Dodge';
      case BlendMode.colorBurn:
        return 'Color Burn';
      case BlendMode.difference:
        return 'Difference';
      case BlendMode.exclusion:
        return 'Exclusion';
      case BlendMode.hardLight:
        return 'Hard Light';
      case BlendMode.softLight:
        return 'Soft Light';
      case BlendMode.hue:
        return 'Hue';
      case BlendMode.saturation:
        return 'Saturation';
      case BlendMode.color:
        return 'Color';
      case BlendMode.luminosity:
        return 'Luminosity';
      default:
        return mode.name;
    }
  }
}

/// Re-export as helper for callers that pass a stable typed reference.
typedef LayerId = NodeId;

/// Compact color-tag chip rendered at the start of every layer row.
/// When [current] is null the chip is an outlined ring (suggestive
/// affordance); otherwise a filled dot of the chosen color. Tapping
/// opens a popup palette with "no tag" + the [palette] colors.
class _ColorTagChip extends StatelessWidget {
  const _ColorTagChip({
    required this.current,
    required this.palette,
    required this.onChanged,
  });

  final Color? current;
  final List<Color> palette;
  final ValueChanged<Color?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<Color?>(
      tooltip: 'Color tag',
      onSelected: onChanged,
      itemBuilder:
          (ctx) => [
            const PopupMenuItem<Color?>(
              value: null,
              child: Row(
                children: [
                  Icon(Icons.do_not_disturb_alt_rounded, size: 16),
                  SizedBox(width: 8),
                  Text('No tag'),
                ],
              ),
            ),
            for (final c in palette)
              PopupMenuItem<Color?>(
                value: c,
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(_labelFor(c)),
                  ],
                ),
              ),
          ],
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: current,
            shape: BoxShape.circle,
            border:
                current == null
                    ? Border.all(
                      color: theme.colorScheme.outline.withValues(alpha: 0.6),
                      width: 1,
                    )
                    : null,
          ),
        ),
      ),
    );
  }

  static String _labelFor(Color c) {
    switch (c.toARGB32()) {
      case 0xFFE53935:
        return 'Red';
      case 0xFFFB8C00:
        return 'Orange';
      case 0xFFFDD835:
        return 'Yellow';
      case 0xFF43A047:
        return 'Green';
      case 0xFF1E88E5:
        return 'Blue';
      case 0xFF8E24AA:
        return 'Purple';
      default:
        return 'Tag';
    }
  }
}
