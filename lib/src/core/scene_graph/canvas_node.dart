import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:fluera_canvas/fluera_canvas.dart';
import '../effects/node_effect.dart';
import '../../systems/accessibility_tree.dart';
import './canvas_node_factory.dart';
import './node_visitor.dart';
import './transform_bridge.dart';
import './frozen_node_view.dart';

/// Base class for all elements in the scene graph.
///
/// Every canvas element (stroke, shape, text, image, group) is a [CanvasNode].
/// Each node carries its own [localTransform] matrix encoding
/// translate/rotate/scale/skew, plus per-node visual properties
/// ([opacity], [blendMode], [isVisible], [isLocked]).
///
/// The scene graph is a tree: each node has a [parent] and leaf nodes
/// represent concrete content, while [GroupNode] subclasses contain children.
abstract class CanvasNode {
  /// Unique identifier for this node.
  final NodeId id;

  /// Human-readable name (shown in layer panel, etc.).
  String name;

  // ---------------------------------------------------------------------------
  // Transform
  // ---------------------------------------------------------------------------

  /// Local transform relative to this node's parent.
  ///
  /// Encodes translate, rotate, scale, and skew in a single 4×4 matrix.
  /// To move/rotate/scale a node, mutate this matrix — the underlying
  /// geometry never changes.
  Matrix4 localTransform;

  /// Whether the [localTransform] is exactly the identity matrix.
  /// Used by renderers to skip `canvas.transform` without allocating `Matrix4.identity()`.
  bool get isIdentityTransform => _isIdentity(localTransform);

  // ---------------------------------------------------------------------------
  // Visual properties
  // ---------------------------------------------------------------------------

  double _opacity;

  /// Node opacity (0.0 = fully transparent, 1.0 = fully opaque).
  ///
  /// Automatically clamped to `[0.0, 1.0]`.
  double get opacity => _opacity;
  set opacity(double value) {
    _opacity = value.clamp(0.0, 1.0);
  }

  /// Field `ui`.
  ui.BlendMode blendMode;
  /// Field `isVisible`.
  bool isVisible;
  /// Field `isLocked`.
  bool isLocked;

  /// Non-destructive effects applied during rendering.
  ///
  /// Effects are processed in order: pre-effects (shadows, glow) before
  /// the node, post-effects (blur, color overlay) after.
  List<NodeEffect> effects;

  /// Accessibility metadata for assistive technologies.
  ///
  /// When non-null, the node is included in the accessibility tree
  /// with the specified role, label, and other semantic properties.
  AccessibilityInfo? accessibilityInfo;

  /// Content provenance tag (A20.3).
  ///
  /// Tracks whether this node was handwritten, imported, or AI-generated.
  /// Defaults to [ContentOrigin.handwriting] (student-authored).
  ContentOrigin contentOrigin;

  /// Baseline offset for text alignment (distance from top of bounds to baseline).
  ///
  /// When non-null, this value is used by [FrameNode] to align children
  /// along their text baseline when [CrossAxisAlignment.baseline] is set.
  /// Only meaningful for nodes that render text (e.g., [TextNode]).
  double? baselineOffset;

  // ---------------------------------------------------------------------------
  // Hierarchy
  // ---------------------------------------------------------------------------

  /// Parent node in the scene graph (null for root).
  CanvasNode? parent;

  /// Back-reference to the owning [SceneGraph], if registered.
  ///
  /// Set by `SceneGraph._registerSubtree()`, cleared by
  /// `SceneGraph._unregisterSubtree()`. Used to bridge transform
  /// invalidation into the invalidation graph and spatial index.
  ///
  /// Uses the [TransformBridge] interface to avoid a circular import
  /// between `canvas_node.dart` and `scene_graph.dart` while keeping
  /// full type safety.
  TransformBridge? ownerGraph;

  // ---------------------------------------------------------------------------
  // Constructor
  // ---------------------------------------------------------------------------

  /// API element `CanvasNode`.
  CanvasNode({
    required this.id,
    this.name = '',
    Matrix4? localTransform,
    double opacity = 1.0,
    this.blendMode = ui.BlendMode.srcOver,
    this.isVisible = true,
    this.isLocked = false,
    this.parent,
    List<NodeEffect>? effects,
    this.contentOrigin = ContentOrigin.handwriting,
  }) : assert(id.isNotEmpty, 'Node ID must not be empty'),
       localTransform = localTransform ?? Matrix4.identity(),
       _opacity = opacity.clamp(0.0, 1.0),
       effects = effects ?? [];

  // ---------------------------------------------------------------------------
  // Content fingerprint
  // ---------------------------------------------------------------------------

  /// A hash that captures node-type-specific content.
  ///
  /// Used by [SceneGraphSnapshot] to detect in-place property changes
  /// (e.g. fill color, text content, stroke data) that the base hash
  /// would miss. Subclasses should override to include their specific data.
  ///
  /// The default returns `runtimeType.hashCode` — enough to detect
  /// type changes but not property-level mutations.
  int get contentFingerprint => runtimeType.hashCode;

  // ---------------------------------------------------------------------------
  // Bounds
  // ---------------------------------------------------------------------------

  /// Bounding box in **local** coordinates (geometry only, no transform).
  Rect get localBounds;

  /// Bounding box in **world** coordinates (with accumulated transforms).
  ///
  /// Cached and invalidated alongside the transform cache to avoid
  /// redundant `MatrixUtils.transformRect` calls (O(1) for static nodes).
  Rect _cachedWorldBounds = Rect.zero;
  bool _worldBoundsDirty = true;

  /// Getter `worldBounds`.
  Rect get worldBounds {
    if (!_worldBoundsDirty) return _cachedWorldBounds;
    final wt = worldTransform;
    _cachedWorldBounds = MatrixUtils.transformRect(wt, localBounds);
    _worldBoundsDirty = false;
    return _cachedWorldBounds;
  }

  // ---------------------------------------------------------------------------
  // World transform
  // ---------------------------------------------------------------------------

  /// Accumulated transform from root to this node.
  ///
  /// Computed by multiplying parent's [worldTransform] × [localTransform].
  /// Cached and invalidated via [invalidateTransformCache].
  late Matrix4 _cachedWorldTransform;
  bool _worldTransformDirty = true;

  /// Getter `worldTransform`.
  Matrix4 get worldTransform {
    if (!_worldTransformDirty) return _cachedWorldTransform;
    if (parent == null) {
      _cachedWorldTransform = localTransform.clone();
    } else {
      _cachedWorldTransform = parent!.worldTransform.multiplied(localTransform);
    }
    _worldTransformDirty = false;
    return _cachedWorldTransform;
  }

  /// Invalidate the cached world transform for this node.
  ///
  /// Also notifies the owning [SceneGraph] (if registered) so that
  /// the invalidation graph and spatial index stay in sync.
  ///
  /// When [propagatingTransform_] is `true`, the call is part of a recursive
  /// parent→child propagation and the [SceneGraph] bridge is skipped
  /// to avoid O(n²) cascade storms.
  ///
  /// **Package-internal** — do not set outside `GroupNode.invalidateTransformCache()`.
  bool propagatingTransform_ = false;

  /// API element `invalidateTransformCache`.
  void invalidateTransformCache() {
    _worldTransformDirty = true;
    _worldBoundsDirty = true;
    // Bridge to SceneGraph only for the TOP-LEVEL invalidation,
    // not during recursive child propagation.
    if (!propagatingTransform_ && ownerGraph != null) {
      ownerGraph!.onNodeTransformInvalidated(this);
    }
  }

  // ---------------------------------------------------------------------------
  // Hit testing
  // ---------------------------------------------------------------------------

  /// Returns `true` if [worldPoint] falls inside this node's bounds.
  ///
  /// The default implementation inverse-transforms the point into local
  /// space and checks against [localBounds]. Subclasses can override for
  /// more precise hit testing (e.g. path-based).
  bool hitTest(Offset worldPoint) {
    if (!isVisible) return false;
    if (isLocked) return false;

    final inverse = Matrix4.tryInvert(worldTransform);
    if (inverse == null) return false;

    final local = MatrixUtils.transformPoint(inverse, worldPoint);
    return localBounds.contains(local);
  }

  // ---------------------------------------------------------------------------
  // Transform helpers
  // ---------------------------------------------------------------------------

  /// Translate this node by [dx], [dy] (modifies [localTransform] in-place).
  ///
  /// Uses direct storage access — no matrix allocation, no multiply.
  void translate(double dx, double dy) {
    localTransform[12] += dx;
    localTransform[13] += dy;
    invalidateTransformCache();
  }

  /// Set absolute position (replaces translation component).
  void setPosition(double x, double y) {
    localTransform.setTranslationRaw(x, y, 0.0);
    invalidateTransformCache();
  }

  /// Current translation extracted from [localTransform].
  Offset get position {
    final t = localTransform.getTranslation();
    return Offset(t.x, t.y);
  }

  /// Rotate around [pivot] by [radians].
  void rotateAround(double radians, Offset pivot) {
    localTransform = _rotateAroundPivot(localTransform, radians, pivot);
    invalidateTransformCache();
  }

  /// Scale from [anchor] by [sx], [sy].
  void scaleFrom(double sx, double sy, Offset anchor) {
    localTransform = _scaleFromAnchor(localTransform, sx, sy, anchor);
    invalidateTransformCache();
  }

  // ---------------------------------------------------------------------------
  // Cloning
  // ---------------------------------------------------------------------------

  /// Create a deep copy of this node with a new unique ID.
  ///
  /// Delegates to [cloneInternal] which subclasses can override for
  /// zero-serialization cloning. Falls back to JSON roundtrip.
  CanvasNode clone() => cloneInternal();

  /// Subclass-overridable clone implementation.
  ///
  /// The default uses JSON roundtrip. Override in performance-critical
  /// node types for direct field copy.
  CanvasNode cloneInternal() {
    final json = toJson();
    json['id'] = generateUid();
    return CanvasNodeFactory.fromJson(json);
  }

  /// Create a deep, immutable projection of this node.
  ///
  /// Useful for sharing data with plugins or background threads without
  /// exposing the mutable internal graph structure.
  FrozenNodeView freeze() => FrozenNodeView.from(this);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Release resources held by this node.
  ///
  /// Clears effects, accessibility info, and the owner graph reference.
  /// Called when the node is permanently removed from the tree.
  @mustCallSuper
  void dispose() {
    effects.clear();
    accessibilityInfo = null;
    ownerGraph = null;
    parent = null;
  }

  // ---------------------------------------------------------------------------
  // Visitor
  // ---------------------------------------------------------------------------

  /// Accept a [NodeVisitor] for type-safe double-dispatch traversal.
  R accept<R>(NodeVisitor<R> visitor);

  // ---------------------------------------------------------------------------
  // Serialization
  // ---------------------------------------------------------------------------

  /// Serialize this node to JSON.
  ///
  /// Subclasses must override [toJson] and include `'nodeType'` so the
  /// factory deserializer can reconstruct the correct type.
  Map<String, dynamic> toJson();

  /// Serialize the common [CanvasNode] properties shared by all subclasses.
  Map<String, dynamic> baseToJson() {
    final json = <String, dynamic>{'id': id, 'name': name};

    // Only serialize non-default values to keep JSON compact.
    if (!_isIdentity(localTransform)) {
      json['transform'] = localTransform.storage.toList();
    }
    if (_opacity != 1.0) json['opacity'] = _opacity;
    if (blendMode != ui.BlendMode.srcOver) json['blendMode'] = blendMode.name;
    if (!isVisible) json['isVisible'] = false;
    if (isLocked) json['isLocked'] = true;
    if (effects.isNotEmpty) {
      json['effects'] = effects.map((e) => e.toJson()).toList();
    }
    if (accessibilityInfo != null) {
      json['a11y'] = accessibilityInfo!.toJson();
    }
    if (contentOrigin != ContentOrigin.handwriting) {
      json['contentOrigin'] = contentOrigin.name;
    }

    return json;
  }

  /// Restore common [CanvasNode] properties from [json].
  static void applyBaseFromJson(CanvasNode node, Map<String, dynamic> json) {
    node.name = (json['name'] as String?) ?? '';

    if (json['transform'] != null) {
      final storage = (json['transform'] as List).cast<num>();
      node.localTransform = Matrix4.fromList(
        storage.map((n) => n.toDouble()).toList(),
      );
    }

    if (json['opacity'] != null) {
      node.opacity = (json['opacity'] as num).toDouble();
    }
    if (json['blendMode'] != null) {
      node.blendMode =
          _blendModeByName[json['blendMode']] ?? ui.BlendMode.srcOver;
    }
    if (json['isVisible'] != null) {
      node.isVisible = json['isVisible'] as bool;
    }
    if (json['isLocked'] != null) {
      node.isLocked = json['isLocked'] as bool;
    }
    if (json['effects'] != null) {
      node.effects =
          (json['effects'] as List<dynamic>)
              .map((e) => NodeEffect.fromJson(e as Map<String, dynamic>))
              .toList();
    }
    if (json['a11y'] != null) {
      node.accessibilityInfo = AccessibilityInfo.fromJson(
        json['a11y'] as Map<String, dynamic>,
      );
    }
    if (json['contentOrigin'] != null) {
      node.contentOrigin = ContentOrigin.values.firstWhere(
        (e) => e.name == json['contentOrigin'],
        orElse: () => ContentOrigin.handwriting,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Equality
  // ---------------------------------------------------------------------------

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CanvasNode && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => '$runtimeType(id: $id, name: "$name")';

  // ---------------------------------------------------------------------------
  // Private helpers & static caches
  // ---------------------------------------------------------------------------

  /// O(1) BlendMode lookup by name (avoids O(n) `firstWhere` per node).
  static final Map<String, ui.BlendMode> _blendModeByName = {
    for (final m in ui.BlendMode.values) m.name: m,
  };

  static bool _isIdentity(Matrix4 m) {
    final s = m.storage;
    return s[0] == 1 &&
        s[1] == 0 &&
        s[2] == 0 &&
        s[3] == 0 &&
        s[4] == 0 &&
        s[5] == 1 &&
        s[6] == 0 &&
        s[7] == 0 &&
        s[8] == 0 &&
        s[9] == 0 &&
        s[10] == 1 &&
        s[11] == 0 &&
        s[12] == 0 &&
        s[13] == 0 &&
        s[14] == 0 &&
        s[15] == 1;
  }

  static Matrix4 _rotateAroundPivot(
    Matrix4 current,
    double radians,
    Offset pivot,
  ) {
    // T(pivot) · R(radians) · T(-pivot) · current
    final pre = Matrix4.translationValues(pivot.dx, pivot.dy, 0.0);
    final rot = Matrix4.rotationZ(radians);
    final post = Matrix4.translationValues(-pivot.dx, -pivot.dy, 0.0);
    return pre
      ..multiply(rot)
      ..multiply(post)
      ..multiply(current);
  }

  static Matrix4 _scaleFromAnchor(
    Matrix4 current,
    double sx,
    double sy,
    Offset anchor,
  ) {
    // T(anchor) · S(sx,sy) · T(-anchor) · current
    final pre = Matrix4.translationValues(anchor.dx, anchor.dy, 0.0);
    final scl = Matrix4.diagonal3Values(sx, sy, 1.0);
    final post = Matrix4.translationValues(-anchor.dx, -anchor.dy, 0.0);
    return pre
      ..multiply(scl)
      ..multiply(post)
      ..multiply(current);
  }
}
