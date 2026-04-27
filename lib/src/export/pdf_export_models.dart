import 'dart:ui' as ui;

// =============================================================================
// PDF EXPORT MODELS — Data classes for PDF export.
//
// Extracted from pdf_export_writer.dart to reduce god-file complexity.
// =============================================================================

// =============================================================================
// IMAGE XOBJECT
// =============================================================================

/// Registered image XObject reference.
class PdfImageXObject {
  /// PDF object ID for this image.
  final int objectId;

  /// Resource name (e.g. /Im1).
  final String resourceName;

  /// Pixel width.
  final int width;

  /// Pixel height.
  final int height;

  /// Optional SMask object ID (for alpha channel).
  final int? smaskId;

  /// API element `PdfImageXObject`.
  const PdfImageXObject({
    required this.objectId,
    required this.resourceName,
    required this.width,
    required this.height,
    this.smaskId,
  });
}

// =============================================================================
// BOOKMARK
// =============================================================================

/// A PDF bookmark (outline) entry.
///
/// Bookmarks appear in the PDF viewer's sidebar and allow quick navigation
/// to specific pages.
class PdfBookmark {
  /// Display title in the bookmark tree.
  final String title;

  /// Zero-based page index to navigate to.
  final int pageIndex;

  /// Child bookmarks (for nested outline hierarchy).
  final List<PdfBookmark> children;

  /// API element `PdfBookmark`.
  const PdfBookmark({
    required this.title,
    required this.pageIndex,
    this.children = const [],
  });
}

// =============================================================================
// WATERMARK
// =============================================================================

/// Watermark position on the page.
enum WatermarkPosition {
  /// Centered diagonally across the page.
  diagonal,

  /// Centered horizontally and vertically.
  center,

  /// Tiled across the entire page.
  tiled,
}

/// A text watermark applied to PDF pages.
class PdfWatermark {
  /// Text to render (e.g. "DRAFT", "CONFIDENTIAL").
  final String text;

  /// Font size in points.
  final double fontSize;

  /// Text color.
  final ui.Color color;

  /// Opacity (0.0 = invisible, 1.0 = fully opaque).
  final double opacity;

  /// Rotation angle in degrees (only used for [WatermarkPosition.diagonal]).
  final double rotation;

  /// Position mode.
  final WatermarkPosition position;

  /// API element `PdfWatermark`.
  const PdfWatermark({
    required this.text,
    this.fontSize = 72,
    this.color = const ui.Color(0xFFCCCCCC),
    this.opacity = 0.3,
    this.rotation = -45,
    this.position = WatermarkPosition.diagonal,
  });
}

// =============================================================================
// LINK ANNOTATION
// =============================================================================

/// A clickable link annotation on a PDF page.
class PdfLinkAnnotation {
  /// Clickable rectangle (in page coordinates, top-left origin).
  final ui.Rect rect;

  /// External URI (e.g. "https://example.com").
  /// If null, this is an internal link using [destPageIndex].
  final String? uri;

  /// Destination page index for internal links.
  final int? destPageIndex;

  /// API element `uri`.
  const PdfLinkAnnotation.uri({required this.rect, required String this.uri})
    : destPageIndex = null;

  /// API element `page`.
  const PdfLinkAnnotation.page({
    required this.rect,
    required int this.destPageIndex,
  }) : uri = null;
}

// =============================================================================
// PAGE LABEL
// =============================================================================

/// Page numbering style for PDF page labels.
enum PageLabelStyle {
  /// Decimal (1, 2, 3, ...)
  decimal,

  /// Uppercase Roman (I, II, III, IV, ...)
  upperRoman,

  /// Lowercase Roman (i, ii, iii, iv, ...)
  lowerRoman,

  /// Uppercase alphabetic (A, B, C, ...)
  upperAlpha,

  /// Lowercase alphabetic (a, b, c, ...)
  lowerAlpha,

  /// No numbering (prefix only).
  none,
}

/// A page label range definition.
///
/// Defines numbering for pages starting at [startPage].
class PdfPageLabel {
  /// Zero-based page index where this label range starts.
  final int startPage;

  /// Numbering style.
  final PageLabelStyle style;

  /// Optional prefix string (e.g. "Chapter ").
  final String prefix;

  /// Starting number (default: 1).
  final int startNumber;

  /// API element `PdfPageLabel`.
  const PdfPageLabel({
    required this.startPage,
    this.style = PageLabelStyle.decimal,
    this.prefix = '',
    this.startNumber = 1,
  });
}

// =============================================================================
// FORM FIELDS
// =============================================================================

/// Base class for PDF interactive form fields.
sealed class PdfFormField {
  /// Field name (unique identifier within the form).
  final String name;

  /// Field position on the page (top-left origin).
  final ui.Rect rect;

  /// Page index where the field appears (0-based).
  final int pageIndex;

  const PdfFormField({
    required this.name,
    required this.rect,
    this.pageIndex = 0,
  });
}

/// Interactive text input field.
class PdfTextField extends PdfFormField {
  /// Field `defaultValue`.
  final String defaultValue;
  /// Field `fontSize`.
  final double fontSize;
  /// Field `multiline`.
  final bool multiline;
  /// Field `maxLength`.
  final int maxLength;

  /// API element `PdfTextField`.
  const PdfTextField({
    required super.name,
    required super.rect,
    super.pageIndex,
    this.defaultValue = '',
    this.fontSize = 12,
    this.multiline = false,
    this.maxLength = 0,
  });
}

/// Checkbox toggle field.
class PdfCheckboxField extends PdfFormField {
  /// Field `defaultChecked`.
  final bool defaultChecked;

  /// API element `PdfCheckboxField`.
  const PdfCheckboxField({
    required super.name,
    required super.rect,
    super.pageIndex,
    this.defaultChecked = false,
  });
}

/// Dropdown / combo-box selection field.
class PdfDropdownField extends PdfFormField {
  /// Field `options`.
  final List<String> options;
  /// Field `defaultValue`.
  final String? defaultValue;
  /// Field `editable`.
  final bool editable;

  /// API element `PdfDropdownField`.
  const PdfDropdownField({
    required super.name,
    required super.rect,
    super.pageIndex,
    required this.options,
    this.defaultValue,
    this.editable = false,
  });
}

// =============================================================================
// REDACTION
// =============================================================================

/// A content redaction area on a PDF page.
class PdfRedaction {
  /// Field `ui`.
  final ui.Rect rect;
  /// Field `ui`.
  final ui.Color overlayColor;
  /// Field `replacementText`.
  final String? replacementText;
  /// Field `pageIndex`.
  final int pageIndex;

  /// API element `PdfRedaction`.
  const PdfRedaction({
    required this.rect,
    this.overlayColor = const ui.Color(0xFF000000),
    this.replacementText,
    this.pageIndex = 0,
  });
}
