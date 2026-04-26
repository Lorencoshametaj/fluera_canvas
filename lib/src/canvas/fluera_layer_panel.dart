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

import 'dart:ui' show BlendMode;

import 'package:flutter/material.dart';

import '../core/nodes/layer_node.dart';
import '../core/scene_graph/node_id.dart';
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
  const FlueraLayerPanel({
    super.key,
    required this.canvasKey,
    this.blendModes = _defaultBlendModes,
    this.showAddButton = true,
    this.showDuplicateButton = true,
    this.showOpacitySlider = true,
    this.showBlendModePicker = true,
    this.padding = const EdgeInsets.all(8),
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
  final List<BlendMode> blendModes;

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
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSubscription());
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
                return _LayerRow(
                  key: ValueKey(layer.id.value),
                  index: i,
                  layer: layer,
                  active: layer.id == activeLayerId,
                  blendModes: widget.blendModes,
                  showOpacitySlider: widget.showOpacitySlider,
                  showBlendModePicker: widget.showBlendModePicker,
                  showDuplicateButton: widget.showDuplicateButton,
                  canDelete: layers.length > 1,
                  onTap: () => state.setActiveLayer(layer.id),
                  onToggleVisible: () =>
                      state.setLayerVisible(layer.id, !layer.isVisible),
                  onToggleLocked: () =>
                      state.setLayerLocked(layer.id, !layer.isLocked),
                  onOpacityChanged: (v) =>
                      state.setLayerOpacity(layer.id, v),
                  onBlendModeChanged: (m) =>
                      state.setLayerBlendMode(layer.id, m),
                  onRename: (newName) =>
                      state.setLayerName(layer.id, newName),
                  onDuplicate: () => state.duplicateLayer(layer.id),
                  onDelete: () => state.removeLayer(layer.id),
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
    required this.showOpacitySlider,
    required this.showBlendModePicker,
    required this.showDuplicateButton,
    required this.canDelete,
    required this.onTap,
    required this.onToggleVisible,
    required this.onToggleLocked,
    required this.onOpacityChanged,
    required this.onBlendModeChanged,
    required this.onRename,
    required this.onDuplicate,
    required this.onDelete,
  });

  final int index;
  final LayerNode layer;
  final bool active;
  final List<BlendMode> blendModes;
  final bool showOpacitySlider;
  final bool showBlendModePicker;
  final bool showDuplicateButton;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback onToggleVisible;
  final VoidCallback onToggleLocked;
  final ValueChanged<double> onOpacityChanged;
  final ValueChanged<BlendMode> onBlendModeChanged;
  final ValueChanged<String> onRename;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;

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
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
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
    return Padding(
      key: ValueKey('row-${layer.id.value}'),
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
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
                      child: _editingName
                          ? TextField(
                              controller: _nameCtrl,
                              autofocus: true,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: fg,
                              ),
                              decoration: const InputDecoration(
                                isDense: true,
                                contentPadding:
                                    EdgeInsets.symmetric(vertical: 4),
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => _commitRename(),
                              onTapOutside: (_) => _commitRename(),
                            )
                          : GestureDetector(
                              onDoubleTap: () =>
                                  setState(() => _editingName = true),
                              child: Text(
                                layer.name,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: fg,
                                  fontWeight: widget.active
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
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
                      tooltip: widget.canDelete
                          ? 'Delete'
                          : 'Cannot delete the last layer',
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        size: 16,
                        color: widget.canDelete
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
                    child: DropdownButton<BlendMode>(
                      isDense: true,
                      isExpanded: true,
                      value: widget.blendModes.contains(layer.blendMode)
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
      ),
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
