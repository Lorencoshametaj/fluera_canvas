import 'dart:ui';
import '../core/scene_graph/canvas_node.dart';
import '../core/nodes/group_node.dart';

/// Semantic role for an accessible node.
///
/// Maps to ARIA roles and platform accessibility APIs.
enum AccessibilityRole {
  /// Purely decorative, ignored by assistive technology.
  decorative,

  /// An image or graphic.
  image,

  /// Text content.
  text,

  /// An interactive button.
  button,

  /// A navigational link.
  link,

  /// A structural group/container.
  group,

  /// A section heading.
  heading,

  /// A generic interactive element.
  interactive,

  /// A form input field.
  input,

  /// A list container.
  list,

  /// A list item.
  listItem,

  /// A landmark/region for navigation.
  landmark,

  /// A slider or range control.
  slider,

  /// A checkbox or toggle.
  toggle,
}

/// Accessibility information attached to a [CanvasNode].
///
/// These properties are used to generate the accessibility tree
/// for screen readers and other assistive technologies.
class AccessibilityInfo {
  /// Semantic role of this node.
  AccessibilityRole role;

  /// Short label read by screen readers (equivalent to ARIA label).
  String? label;

  /// Extended description for more context.
  String? description;

  /// Value for interactive elements (e.g., slider value, toggle state).
  String? value;

  /// Hint text describing the result of interacting with this element.
  String? hint;

  /// Whether this node should be included in the accessibility tree.
  /// Nodes marked as [AccessibilityRole.decorative] are excluded by default.
  bool isAccessible;

  /// Reading order index (lower = read first). Null = use visual order.
  int? readingOrder;

  /// Heading level (1-6) if role is [AccessibilityRole.heading].
  int? headingLevel;

  /// Whether this element can receive focus.
  bool isFocusable;

  /// Custom actions available on this element.
  final List<AccessibilityAction> customActions;

  AccessibilityInfo({
    this.role = AccessibilityRole.decorative,
    this.label,
    this.description,
    this.value,
    this.hint,
    this.isAccessible = true,
    this.readingOrder,
    this.headingLevel,
    this.isFocusable = false,
    this.customActions = const [],
  });

  Map<String, dynamic> toJson() => {
    'role': role.name,
    if (label != null) 'label': label,
    if (description != null) 'description': description,
    if (value != null) 'value': value,
    if (hint != null) 'hint': hint,
    'isAccessible': isAccessible,
    if (readingOrder != null) 'readingOrder': readingOrder,
    if (headingLevel != null) 'headingLevel': headingLevel,
    'isFocusable': isFocusable,
    if (customActions.isNotEmpty)
      'customActions': customActions.map((a) => a.toJson()).toList(),
  };

  factory AccessibilityInfo.fromJson(Map<String, dynamic> json) =>
      AccessibilityInfo(
        role: AccessibilityRole.values.byName(
          json['role'] as String? ?? 'decorative',
        ),
        label: json['label'] as String?,
        description: json['description'] as String?,
        value: json['value'] as String?,
        hint: json['hint'] as String?,
        isAccessible: json['isAccessible'] as bool? ?? true,
        readingOrder: json['readingOrder'] as int?,
        headingLevel: json['headingLevel'] as int?,
        isFocusable: json['isFocusable'] as bool? ?? false,
        customActions:
            (json['customActions'] as List<dynamic>?)
                ?.map(
                  (a) =>
                      AccessibilityAction.fromJson(a as Map<String, dynamic>),
                )
                .toList() ??
            [],
      );
}

/// A custom accessibility action available on a node.
class AccessibilityAction {
  final String id;
  final String label;

  const AccessibilityAction({required this.id, required this.label});

  Map<String, dynamic> toJson() => {'id': id, 'label': label};

  factory AccessibilityAction.fromJson(Map<String, dynamic> json) =>
      AccessibilityAction(
        id: json['id'] as String,
        label: json['label'] as String,
      );
}

/// A node in the accessibility tree.
///
/// Mirrors the scene graph structure but only includes accessible nodes.
class AccessibilityTreeNode {
  final String nodeId;
  final AccessibilityInfo info;
  final Rect worldBounds;
  final List<AccessibilityTreeNode> children;

  AccessibilityTreeNode({
    required this.nodeId,
    required this.info,
    required this.worldBounds,
    this.children = const [],
  });

  /// Flatten the tree into reading order.
  List<AccessibilityTreeNode> flatten() {
    final result = <AccessibilityTreeNode>[];
    _flattenInto(result);
    return result;
  }

  void _flattenInto(List<AccessibilityTreeNode> result) {
    if (info.role != AccessibilityRole.decorative && info.isAccessible) {
      result.add(this);
    }
    for (final child in children) {
      child._flattenInto(result);
    }
  }
}

/// Builds an accessibility tree from the scene graph.
///
/// Traverses the scene graph and creates a parallel tree containing
/// only nodes with accessibility information. Decorative nodes are
/// excluded, and nodes are sorted by reading order.
///
/// ```dart
/// final builder = AccessibilityTreeBuilder();
/// final tree = builder.buildTree(sceneGraphRoot);
/// final ordered = tree.flatten();
/// // ordered contains accessible nodes in reading order
/// ```
class AccessibilityTreeBuilder {
  /// Build the accessibility tree from a scene graph root.
  AccessibilityTreeNode? buildTree(CanvasNode root) {
    return _buildNode(root);
  }

  AccessibilityTreeNode? _buildNode(CanvasNode node) {
    // Skip invisible or locked-invisible nodes.
    if (!node.isVisible) return null;

    final info = node.accessibilityInfo;
    final children = <AccessibilityTreeNode>[];

    // Recurse into children.
    if (node is GroupNode) {
      for (final child in node.children) {
        final childNode = _buildNode(child);
        if (childNode != null) {
          children.add(childNode);
        }
      }
    }

    // Sort children by reading order (if specified), then by position.
    children.sort((a, b) {
      final orderA = a.info.readingOrder ?? 99999;
      final orderB = b.info.readingOrder ?? 99999;
      if (orderA != orderB) return orderA.compareTo(orderB);
      // Fall back to top-to-bottom, left-to-right visual order.
      final dy = a.worldBounds.top.compareTo(b.worldBounds.top);
      if (dy != 0) return dy;
      return a.worldBounds.left.compareTo(b.worldBounds.left);
    });

    // Skip purely decorative nodes with no accessible children.
    if (info == null || info.role == AccessibilityRole.decorative) {
      if (children.isEmpty) return null;
      // If decorative but has accessible children, create a group wrapper.
      return AccessibilityTreeNode(
        nodeId: node.id,
        info: AccessibilityInfo(role: AccessibilityRole.group),
        worldBounds: node.worldBounds,
        children: children,
      );
    }

    return AccessibilityTreeNode(
      nodeId: node.id,
      info: info,
      worldBounds: node.worldBounds,
      children: children,
    );
  }

  /// Get a flat, ordered list of all focusable nodes.
  List<AccessibilityTreeNode> getFocusOrder(CanvasNode root) {
    final tree = buildTree(root);
    if (tree == null) return [];

    return tree.flatten().where((n) => n.info.isFocusable).toList();
  }

  /// Generate an accessibility summary for debugging/export.
  String generateSummary(CanvasNode root) {
    final tree = buildTree(root);
    if (tree == null) return 'No accessible content.';

    final buffer = StringBuffer();
    _summarizeNode(tree, buffer, 0);
    return buffer.toString();
  }

  void _summarizeNode(
    AccessibilityTreeNode node,
    StringBuffer buffer,
    int depth,
  ) {
    final indent = '  ' * depth;
    final role = node.info.role.name.toUpperCase();
    final label = node.info.label ?? '(no label)';
    buffer.writeln('$indent[$role] $label');

    if (node.info.description != null) {
      buffer.writeln('$indent  desc: ${node.info.description}');
    }

    for (final child in node.children) {
      _summarizeNode(child, buffer, depth + 1);
    }
  }
}
