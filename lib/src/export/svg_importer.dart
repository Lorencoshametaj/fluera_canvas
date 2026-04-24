/// 📥 SVG IMPORTER — Parses SVG files into scene graph nodes.
///
/// Supports the 80/20 subset of SVG: `<path>`, `<rect>`, `<circle>`,
/// `<ellipse>`, `<line>`, `<polyline>`, `<polygon>`, `<text>`, `<g>`,
/// with `fill`, `stroke`, `stroke-width`, `opacity`, and `transform`.
///
/// ```dart
/// final importer = SvgImporter();
/// final node = importer.parse(svgString);
/// sceneGraph.addLayer(node);
/// ```
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fluera_canvas/fluera_canvas.dart';

// =============================================================================
// SVG IMPORTER
// =============================================================================

/// Parses SVG markup into a [CanvasNode] tree.
///
/// Returns a [GroupNode] containing all top-level SVG elements as children.
/// Nested `<g>` groups are preserved as nested [GroupNode]s.
class SvgImporter {
  int _idCounter = 0;

  /// Generate a unique node ID.
  String _nextId() => 'svg-import-${_idCounter++}';

  /// Parse an SVG string into a [GroupNode].
  ///
  /// The returned group's children correspond to the SVG's top-level elements.
  GroupNode parse(String svgSource) {
    _idCounter = 0;
    final root = GroupNode(id: NodeId(_nextId()), name: 'SVG Import');

    // Extract content between <svg> and </svg>.
    final svgMatch = RegExp(
      r'<svg[^>]*>(.*?)</svg>',
      dotAll: true,
    ).firstMatch(svgSource);

    if (svgMatch == null) return root;
    final content = svgMatch.group(1)!;

    _parseChildren(content, root);
    return root;
  }

  /// Parse child elements and add them to [parent].
  void _parseChildren(String content, GroupNode parent) {
    // Match self-closing or paired tags.
    final tagPattern = RegExp(
      r'<(\w+)([^>]*?)(/?)>(?:(.*?)</\1>)?',
      dotAll: true,
    );

    for (final match in tagPattern.allMatches(content)) {
      final tagName = match.group(1)!.toLowerCase();
      final attrs = match.group(2) ?? '';
      final selfClosing = match.group(3) == '/';
      final innerContent = match.group(4) ?? '';

      final node = _parseElement(tagName, attrs, innerContent, selfClosing);
      if (node != null) {
        parent.add(node);
      }
    }
  }

  /// Parse a single SVG element into a [CanvasNode].
  CanvasNode? _parseElement(
    String tagName,
    String attrs,
    String innerContent,
    bool selfClosing,
  ) {
    switch (tagName) {
      case 'g':
        return _parseGroup(attrs, innerContent);
      case 'path':
        return _parsePath(attrs);
      case 'rect':
        return _parseRect(attrs);
      case 'circle':
        return _parseCircle(attrs);
      case 'ellipse':
        return _parseEllipse(attrs);
      case 'line':
        return _parseLine(attrs);
      case 'polyline':
        return _parsePolyline(attrs, closed: false);
      case 'polygon':
        return _parsePolyline(attrs, closed: true);
      case 'text':
        return _parseText(attrs, innerContent);
      default:
        return null; // Skip unsupported elements.
    }
  }

  // ---------------------------------------------------------------------------
  // Element parsers
  // ---------------------------------------------------------------------------

  GroupNode _parseGroup(String attrs, String innerContent) {
    final group = GroupNode(
      id: NodeId(_nextId()),
      name: _attr(attrs, 'id') ?? 'group',
    );

    final opacity = _attrDouble(attrs, 'opacity');
    if (opacity != null) group.opacity = opacity;

    _applyTransform(group, attrs);
    _parseChildren(innerContent, group);
    return group;
  }

  PathNode _parsePath(String attrs) {
    final d = _attr(attrs, 'd') ?? '';
    final path = _parseSvgPathData(d);
    return _createPathNode(attrs, path);
  }

  PathNode _parseRect(String attrs) {
    final x = _attrDouble(attrs, 'x') ?? 0;
    final y = _attrDouble(attrs, 'y') ?? 0;
    final w = _attrDouble(attrs, 'width') ?? 0;
    final h = _attrDouble(attrs, 'height') ?? 0;
    final rx = _attrDouble(attrs, 'rx') ?? 0;
    final ry = _attrDouble(attrs, 'ry') ?? rx;

    final path = VectorPath(segments: []);
    if (rx > 0 || ry > 0) {
      // Rounded rect as path segments.
      final cr = math.min(rx, w / 2);
      final cy = math.min(ry, h / 2);
      path.segments.add(MoveSegment(endPoint: ui.Offset(x + cr, y)));
      path.lineTo(x + w - cr, y);
      path.segments.add(
        CubicSegment(
          controlPoint1: ui.Offset(x + w, y),
          controlPoint2: ui.Offset(x + w, y),
          endPoint: ui.Offset(x + w, y + cy),
        ),
      );
      path.lineTo(x + w, y + h - cy);
      path.segments.add(
        CubicSegment(
          controlPoint1: ui.Offset(x + w, y + h),
          controlPoint2: ui.Offset(x + w, y + h),
          endPoint: ui.Offset(x + w - cr, y + h),
        ),
      );
      path.lineTo(x + cr, y + h);
      path.segments.add(
        CubicSegment(
          controlPoint1: ui.Offset(x, y + h),
          controlPoint2: ui.Offset(x, y + h),
          endPoint: ui.Offset(x, y + h - cy),
        ),
      );
      path.lineTo(x, y + cy);
      path.segments.add(
        CubicSegment(
          controlPoint1: ui.Offset(x, y),
          controlPoint2: ui.Offset(x, y),
          endPoint: ui.Offset(x + cr, y),
        ),
      );
      path.close();
    } else {
      path.segments.add(MoveSegment(endPoint: ui.Offset(x, y)));
      path.lineTo(x + w, y);
      path.lineTo(x + w, y + h);
      path.lineTo(x, y + h);
      path.close();
    }

    return _createPathNode(attrs, path);
  }

  PathNode _parseCircle(String attrs) {
    final cx = _attrDouble(attrs, 'cx') ?? 0;
    final cy = _attrDouble(attrs, 'cy') ?? 0;
    final r = _attrDouble(attrs, 'r') ?? 0;
    return _createPathNode(attrs, _ellipsePath(cx, cy, r, r));
  }

  PathNode _parseEllipse(String attrs) {
    final cx = _attrDouble(attrs, 'cx') ?? 0;
    final cy = _attrDouble(attrs, 'cy') ?? 0;
    final rx = _attrDouble(attrs, 'rx') ?? 0;
    final ry = _attrDouble(attrs, 'ry') ?? 0;
    return _createPathNode(attrs, _ellipsePath(cx, cy, rx, ry));
  }

  PathNode _parseLine(String attrs) {
    final x1 = _attrDouble(attrs, 'x1') ?? 0;
    final y1 = _attrDouble(attrs, 'y1') ?? 0;
    final x2 = _attrDouble(attrs, 'x2') ?? 0;
    final y2 = _attrDouble(attrs, 'y2') ?? 0;

    final path = VectorPath(
      segments: [
        MoveSegment(endPoint: ui.Offset(x1, y1)),
        LineSegment(endPoint: ui.Offset(x2, y2)),
      ],
    );

    return _createPathNode(attrs, path);
  }

  PathNode _parsePolyline(String attrs, {required bool closed}) {
    final pointsStr = _attr(attrs, 'points') ?? '';
    final nums =
        RegExp(
          r'[-+]?\d*\.?\d+',
        ).allMatches(pointsStr).map((m) => double.parse(m.group(0)!)).toList();

    final path = VectorPath(segments: []);
    for (int i = 0; i < nums.length - 1; i += 2) {
      if (i == 0) {
        path.segments.add(
          MoveSegment(endPoint: ui.Offset(nums[i], nums[i + 1])),
        );
      } else {
        path.lineTo(nums[i], nums[i + 1]);
      }
    }
    if (closed) path.close();

    return _createPathNode(attrs, path);
  }

  TextNode? _parseText(String attrs, String innerContent) {
    // Strip inner tags (tspan etc) and get plain text.
    final plainText = innerContent.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    if (plainText.isEmpty) return null;

    final x = _attrDouble(attrs, 'x') ?? 0;
    final y = _attrDouble(attrs, 'y') ?? 0;

    final node = TextNode(
      id: NodeId(_nextId()),
      textElement: DigitalTextElement(
        id: _nextId(),
        text: plainText,
        position: ui.Offset(x, y),
        color: const ui.Color(0xFF000000),
        createdAt: DateTime.now(),
      ),
      name: _attr(attrs, 'id') ?? 'text',
    );
    node.setPosition(x, y);

    final opacity = _attrDouble(attrs, 'opacity');
    if (opacity != null) node.opacity = opacity;

    return node;
  }

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  /// Create a [PathNode] from parsed attributes and a path.
  PathNode _createPathNode(String attrs, VectorPath path) {
    final fillStr = _attr(attrs, 'fill');
    final strokeStr = _attr(attrs, 'stroke');
    final strokeWidth = _attrDouble(attrs, 'stroke-width');
    final opacity = _attrDouble(attrs, 'opacity');

    final node = PathNode(
      id: NodeId(_nextId()),
      path: path,
      name: _attr(attrs, 'id') ?? 'path',
      // ignore: deprecated_member_use
      fillColor:
          fillStr != null && fillStr != 'none' ? _parseColor(fillStr) : null,
      // ignore: deprecated_member_use
      strokeColor:
          strokeStr != null && strokeStr != 'none'
              ? _parseColor(strokeStr)
              : null,
      strokeWidth: strokeWidth ?? 1.0,
    );

    if (opacity != null) node.opacity = opacity;
    _applyTransform(node, attrs);
    return node;
  }

  /// Approximate an ellipse as 4 cubic Bézier segments.
  VectorPath _ellipsePath(double cx, double cy, double rx, double ry) {
    // Magic number for cubic Bézier circle approximation.
    const k = 0.5522847498;
    final kx = rx * k;
    final ky = ry * k;

    return VectorPath(
      segments: [
        MoveSegment(endPoint: ui.Offset(cx, cy - ry)),
        CubicSegment(
          controlPoint1: ui.Offset(cx + kx, cy - ry),
          controlPoint2: ui.Offset(cx + rx, cy - ky),
          endPoint: ui.Offset(cx + rx, cy),
        ),
        CubicSegment(
          controlPoint1: ui.Offset(cx + rx, cy + ky),
          controlPoint2: ui.Offset(cx + kx, cy + ry),
          endPoint: ui.Offset(cx, cy + ry),
        ),
        CubicSegment(
          controlPoint1: ui.Offset(cx - kx, cy + ry),
          controlPoint2: ui.Offset(cx - rx, cy + ky),
          endPoint: ui.Offset(cx - rx, cy),
        ),
        CubicSegment(
          controlPoint1: ui.Offset(cx - rx, cy - ky),
          controlPoint2: ui.Offset(cx - kx, cy - ry),
          endPoint: ui.Offset(cx, cy - ry),
        ),
      ],
      isClosed: true,
    );
  }

  /// Parse SVG path `d` attribute into a [VectorPath].
  VectorPath _parseSvgPathData(String d) {
    final path = VectorPath(segments: []);
    final tokens = _tokenize(d);
    int pos = 0;
    double cx = 0, cy = 0; // Current point.
    double mx = 0, my = 0; // Move-to point (for Z).

    while (pos < tokens.length) {
      final cmd = tokens[pos];
      if (RegExp(r'[A-Za-z]').hasMatch(cmd)) {
        pos++;
      } else {
        break;
      }

      switch (cmd) {
        case 'M':
          cx = double.parse(tokens[pos++]);
          cy = double.parse(tokens[pos++]);
          mx = cx;
          my = cy;
          path.segments.add(MoveSegment(endPoint: ui.Offset(cx, cy)));
          // Implicit line-to after M.
          while (pos < tokens.length && _isNumber(tokens[pos])) {
            cx = double.parse(tokens[pos++]);
            cy = double.parse(tokens[pos++]);
            path.lineTo(cx, cy);
          }
        case 'm':
          cx += double.parse(tokens[pos++]);
          cy += double.parse(tokens[pos++]);
          mx = cx;
          my = cy;
          path.segments.add(MoveSegment(endPoint: ui.Offset(cx, cy)));
          while (pos < tokens.length && _isNumber(tokens[pos])) {
            cx += double.parse(tokens[pos++]);
            cy += double.parse(tokens[pos++]);
            path.lineTo(cx, cy);
          }
        case 'L':
          while (pos < tokens.length && _isNumber(tokens[pos])) {
            cx = double.parse(tokens[pos++]);
            cy = double.parse(tokens[pos++]);
            path.lineTo(cx, cy);
          }
        case 'l':
          while (pos < tokens.length && _isNumber(tokens[pos])) {
            cx += double.parse(tokens[pos++]);
            cy += double.parse(tokens[pos++]);
            path.lineTo(cx, cy);
          }
        case 'H':
          cx = double.parse(tokens[pos++]);
          path.lineTo(cx, cy);
        case 'h':
          cx += double.parse(tokens[pos++]);
          path.lineTo(cx, cy);
        case 'V':
          cy = double.parse(tokens[pos++]);
          path.lineTo(cx, cy);
        case 'v':
          cy += double.parse(tokens[pos++]);
          path.lineTo(cx, cy);
        case 'C':
          while (pos < tokens.length && _isNumber(tokens[pos])) {
            final c1x = double.parse(tokens[pos++]);
            final c1y = double.parse(tokens[pos++]);
            final c2x = double.parse(tokens[pos++]);
            final c2y = double.parse(tokens[pos++]);
            cx = double.parse(tokens[pos++]);
            cy = double.parse(tokens[pos++]);
            path.cubicTo(c1x, c1y, c2x, c2y, cx, cy);
          }
        case 'c':
          while (pos < tokens.length && _isNumber(tokens[pos])) {
            final c1x = cx + double.parse(tokens[pos++]);
            final c1y = cy + double.parse(tokens[pos++]);
            final c2x = cx + double.parse(tokens[pos++]);
            final c2y = cy + double.parse(tokens[pos++]);
            cx += double.parse(tokens[pos++]);
            cy += double.parse(tokens[pos++]);
            path.cubicTo(c1x, c1y, c2x, c2y, cx, cy);
          }
        case 'Q':
          while (pos < tokens.length && _isNumber(tokens[pos])) {
            final cpx = double.parse(tokens[pos++]);
            final cpy = double.parse(tokens[pos++]);
            cx = double.parse(tokens[pos++]);
            cy = double.parse(tokens[pos++]);
            path.quadTo(cpx, cpy, cx, cy);
          }
        case 'q':
          while (pos < tokens.length && _isNumber(tokens[pos])) {
            final cpx = cx + double.parse(tokens[pos++]);
            final cpy = cy + double.parse(tokens[pos++]);
            cx += double.parse(tokens[pos++]);
            cy += double.parse(tokens[pos++]);
            path.quadTo(cpx, cpy, cx, cy);
          }
        case 'Z':
        case 'z':
          path.close();
          cx = mx;
          cy = my;
      }
    }

    return path;
  }

  /// Apply SVG transform attribute to a node.
  void _applyTransform(CanvasNode node, String attrs) {
    final transformStr = _attr(attrs, 'transform');
    if (transformStr == null) return;

    // Parse translate(x, y).
    final translateMatch = RegExp(
      r'translate\(\s*([-\d.]+)[\s,]+([-\d.]+)\s*\)',
    ).firstMatch(transformStr);
    if (translateMatch != null) {
      final tx = double.parse(translateMatch.group(1)!);
      final ty = double.parse(translateMatch.group(2)!);
      node.setPosition(tx, ty);
    }
  }

  // ---------------------------------------------------------------------------
  // SVG attribute parsing
  // ---------------------------------------------------------------------------

  /// Extract an attribute value from an attribute string.
  static String? _attr(String attrs, String name) {
    final match = RegExp('$name\\s*=\\s*["\']([^"\']*)["\']').firstMatch(attrs);
    return match?.group(1);
  }

  /// Extract a double attribute.
  static double? _attrDouble(String attrs, String name) {
    final val = _attr(attrs, name);
    return val != null ? double.tryParse(val) : null;
  }

  /// Parse an SVG color string to a [ui.Color].
  static ui.Color _parseColor(String color) {
    final trimmed = color.trim().toLowerCase();

    // Hex: #RGB, #RRGGBB
    if (trimmed.startsWith('#')) {
      final hex = trimmed.substring(1);
      if (hex.length == 3) {
        final r = int.parse('${hex[0]}${hex[0]}', radix: 16);
        final g = int.parse('${hex[1]}${hex[1]}', radix: 16);
        final b = int.parse('${hex[2]}${hex[2]}', radix: 16);
        return ui.Color.fromARGB(255, r, g, b);
      }
      if (hex.length == 6) {
        return ui.Color(0xFF000000 | int.parse(hex, radix: 16));
      }
    }

    // Named colors (common subset).
    const namedColors = <String, int>{
      'black': 0xFF000000,
      'white': 0xFFFFFFFF,
      'red': 0xFFFF0000,
      'green': 0xFF008000,
      'blue': 0xFF0000FF,
      'yellow': 0xFFFFFF00,
      'cyan': 0xFF00FFFF,
      'magenta': 0xFFFF00FF,
      'gray': 0xFF808080,
      'grey': 0xFF808080,
      'orange': 0xFFFFA500,
      'purple': 0xFF800080,
      'transparent': 0x00000000,
    };
    if (namedColors.containsKey(trimmed)) {
      return ui.Color(namedColors[trimmed]!);
    }

    // rgb(r, g, b)
    final rgbMatch = RegExp(
      r'rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)',
    ).firstMatch(trimmed);
    if (rgbMatch != null) {
      return ui.Color.fromARGB(
        255,
        int.parse(rgbMatch.group(1)!),
        int.parse(rgbMatch.group(2)!),
        int.parse(rgbMatch.group(3)!),
      );
    }

    return const ui.Color(0xFF000000); // Default to black.
  }

  /// Tokenize SVG path data.
  static List<String> _tokenize(String d) {
    return RegExp(
      r'[MmLlHhVvCcSsQqTtAaZz]|[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?',
    ).allMatches(d).map((m) => m.group(0)!).toList();
  }

  static bool _isNumber(String token) =>
      RegExp(r'^[-+]?(?:\d+\.?\d*|\.\d+)').hasMatch(token);
}
