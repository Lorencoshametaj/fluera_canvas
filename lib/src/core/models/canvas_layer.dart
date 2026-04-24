import 'dart:ui' as ui;
import 'package:fluera_canvas/fluera_canvas.dart';

/// Canvas layer — thin adapter around [LayerNode].
///
/// This preserves the existing public API so that all consumers
/// (FlueraLayerController, DrawingPainter, storage services, sync, etc.)
/// continue compiling without changes during the migration.
/// Internally, all data is stored in the [LayerNode] scene graph tree.
class CanvasLayer {
  /// The underlying scene graph node.
  final LayerNode node;

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------

  CanvasLayer({
    required String id,
    required String name,
    List<ProStroke>? strokes,
    List<GeometricShape>? shapes,
    List<DigitalTextElement>? texts,
    List<ImageElement>? images,
    bool isVisible = true,
    bool isLocked = false,
    double opacity = 1.0,
    ui.BlendMode blendMode = ui.BlendMode.srcOver,
  }) : node = LayerNode(
         id: NodeId(id),
         name: name,
         isVisible: isVisible,
         isLocked: isLocked,
         opacity: opacity,
         blendMode: blendMode,
       ) {
    // Populate children from legacy lists
    if (strokes != null) {
      for (final stroke in strokes) {
        node.addStroke(stroke);
      }
    }
    if (shapes != null) {
      for (final shape in shapes) {
        node.addShape(shape);
      }
    }
    if (texts != null) {
      for (final text in texts) {
        node.addText(text);
      }
    }
    if (images != null) {
      for (final image in images) {
        node.addImage(image);
      }
    }
  }

  /// Construct from an existing [LayerNode].
  CanvasLayer.fromNode(this.node);

  // ---------------------------------------------------------------------------
  // Properties (delegated to node)
  // ---------------------------------------------------------------------------

  String get id => node.id;
  String get name => node.name;
  bool get isVisible => node.isVisible;
  bool get isLocked => node.isLocked;
  double get opacity => node.opacity;
  ui.BlendMode get blendMode => node.blendMode;

  // ---------------------------------------------------------------------------
  // Typed element access (read-only views from the node tree)
  // ---------------------------------------------------------------------------

  List<ProStroke> get strokes => node.strokes;
  List<GeometricShape> get shapes => node.shapes;
  List<DigitalTextElement> get texts => node.texts;
  List<ImageElement> get images => node.images;

  // ---------------------------------------------------------------------------
  // Queries
  // ---------------------------------------------------------------------------

  /// Whether the layer has no elements.
  bool get isEmpty => node.isEmpty;

  /// Total number of elements.
  int get elementCount => node.elementCount;

  // ---------------------------------------------------------------------------
  // copyWith
  // ---------------------------------------------------------------------------

  CanvasLayer copyWith({
    String? id,
    String? name,
    List<ProStroke>? strokes,
    List<GeometricShape>? shapes,
    List<DigitalTextElement>? texts,
    List<ImageElement>? images,
    bool? isVisible,
    bool? isLocked,
    double? opacity,
    ui.BlendMode? blendMode,
  }) {
    final copy = CanvasLayer(
      id: id ?? this.id,
      name: name ?? this.name,
      strokes: strokes ?? this.strokes,
      shapes: shapes ?? this.shapes,
      texts: texts ?? this.texts,
      images: images ?? this.images,
      isVisible: isVisible ?? this.isVisible,
      isLocked: isLocked ?? this.isLocked,
      opacity: opacity ?? this.opacity,
      blendMode: blendMode ?? this.blendMode,
    );
    // 🔑 Transfer non-element children (PdfDocumentNode, TabularNode, etc.)
    // that were added directly to the node via node.add(). Without this,
    // copyWith would discard them — causing PDFs/tables to vanish.
    // Generic: transfers ANY non-standard child, not just PdfDocumentNode.
    for (final child in node.children) {
      if (child is! StrokeNode &&
          child is! ShapeNode &&
          child is! TextNode &&
          child is! ImageNode) {
        copy.node.add(child);
      }
    }
    return copy;
  }

  // ---------------------------------------------------------------------------
  // Serialization — scene graph format
  // ---------------------------------------------------------------------------

  /// Serialize to JSON using the scene graph node format.
  Map<String, dynamic> toJson() => node.toJson();

  /// 🚀 PERF: Serialize metadata only (no strokes) for sharded cloud save.
  Map<String, dynamic> toJsonMetadataOnly() => node.toJsonMetadataOnly();

  /// Deserialize from JSON.
  ///
  /// Supports the new scene graph format (with `children` array)
  /// and falls back to legacy format (separate `strokes`/`shapes`/etc. arrays).
  factory CanvasLayer.fromJson(Map<String, dynamic> json) {
    // New scene graph format: has 'children' or 'nodeType'
    if (json.containsKey('children') || json['nodeType'] == 'layer') {
      final layerNode = CanvasNodeFactory.layerFromJson(json);
      return CanvasLayer.fromNode(layerNode);
    }

    // Legacy format: separate typed arrays
    return CanvasLayer(
      id: json['id'] as String,
      name: json['name'] as String,
      strokes:
          (json['strokes'] as List<dynamic>?)
              ?.map((s) => ProStroke.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      shapes:
          (json['shapes'] as List<dynamic>?)
              ?.map((s) => GeometricShape.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      texts:
          (json['texts'] as List<dynamic>?)
              ?.map(
                (t) => DigitalTextElement.fromJson(t as Map<String, dynamic>),
              )
              .toList() ??
          [],
      images:
          (json['images'] as List<dynamic>?)
              ?.map((i) => ImageElement.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
      isVisible: json['isVisible'] as bool? ?? true,
      isLocked: json['isLocked'] as bool? ?? false,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      blendMode: _blendModeFromName(json['blendMode'] as String?),
    );
  }

  /// 🚀 LAZY DECODE: Deserialize from JSON WITHOUT stroke data.
  ///
  /// Loads layer metadata (id, name, visibility, opacity, blendMode) and
  /// non-stroke children (shapes, texts, images, PDFs) but skips stroke
  /// deserialization entirely. This eliminates the transient ~750MB memory
  /// peak when loading 100K+ strokes that are already indexed in SQLite.
  ///
  /// Stubs are injected separately via [StrokePagingManager.loadStubsFromIndex].
  factory CanvasLayer.fromJsonMetadataOnly(Map<String, dynamic> json) {
    // Scene graph format: use metadata-only layer factory
    if (json.containsKey('children') || json['nodeType'] == 'layer') {
      final layerNode = CanvasNodeFactory.layerFromJsonMetadataOnly(json);
      return CanvasLayer.fromNode(layerNode);
    }

    // Legacy format: load everything except strokes
    return CanvasLayer(
      id: json['id'] as String,
      name: json['name'] as String,
      strokes: [], // Skip stroke deserialization
      shapes:
          (json['shapes'] as List<dynamic>?)
              ?.map((s) => GeometricShape.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
      texts:
          (json['texts'] as List<dynamic>?)
              ?.map(
                (t) => DigitalTextElement.fromJson(t as Map<String, dynamic>),
              )
              .toList() ??
          [],
      images:
          (json['images'] as List<dynamic>?)
              ?.map((i) => ImageElement.fromJson(i as Map<String, dynamic>))
              .toList() ??
          [],
      isVisible: json['isVisible'] as bool? ?? true,
      isLocked: json['isLocked'] as bool? ?? false,
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      blendMode: _blendModeFromName(json['blendMode'] as String?),
    );
  }

  /// Helper: convert string name → BlendMode (backward compatible).
  static ui.BlendMode _blendModeFromName(String? name) {
    if (name == null) return ui.BlendMode.srcOver;
    return ui.BlendMode.values.firstWhere(
      (m) => m.name == name,
      orElse: () => ui.BlendMode.srcOver,
    );
  }
}
