import 'package:flutter/material.dart';

/// 📐 Export preset category
enum ExportPresetCategory {
  paper, // Formati carta (A4, A3, Letter, etc.)
  social, // Formati social media (Instagram, Twitter, etc.)
  custom, // Formato personalizzato
}

/// 📄 Formato pagina standard for export
enum ExportPageFormat {
  a4Portrait,
  a4Landscape,
  a3Portrait,
  a3Landscape,
  letterPortrait,
  letterLandscape,
  custom,
}

/// 🎯 Modello per i preset di esportazione
///
/// Definisce formati predefiniti per esportare il canvas in diverse
/// dimensioni e aspect ratio, ottimizzati per carta o social media.
class ExportPreset {
  final String id;
  final String name;
  final String? subtitle;
  final IconData icon;
  final ExportPresetCategory category;

  /// Aspect ratio (larghezza / altezza).
  /// Es: 1.0 = quadrato, 1.414 = A4 landscape, 0.707 = A4 portrait
  final double? aspectRatio;

  /// Dimensioni fisse in pixel (a 72 DPI base). Se null, usa aspectRatio.
  final Size? fixedSize;

  /// If true, l'utente can ridimensionare liberamente
  final bool isCustom;

  const ExportPreset({
    required this.id,
    required this.name,
    this.subtitle,
    required this.icon,
    required this.category,
    this.aspectRatio,
    this.fixedSize,
    this.isCustom = false,
  });

  /// Calculates le dimensioni in pixel for a dato DPI
  Size getSizeAtDpi(double dpi, {Size? referenceSize}) {
    final scale = dpi / 72.0; // Base 72 DPI

    if (fixedSize != null) {
      return Size(fixedSize!.width * scale, fixedSize!.height * scale);
    }

    if (referenceSize != null && aspectRatio != null) {
      // Adatta alla reference size mantenendo aspect ratio
      final refAspect = referenceSize.width / referenceSize.height;
      if (refAspect > aspectRatio!) {
        // Reference more larga, usa altezza
        return Size(
          referenceSize.height * aspectRatio! * scale,
          referenceSize.height * scale,
        );
      } else {
        // Reference more alta, usa larghezza
        return Size(
          referenceSize.width * scale,
          referenceSize.width / aspectRatio! * scale,
        );
      }
    }

    return Size.zero;
  }

  /// Checks if this preset requires multi-page for aa data area
  bool requiresMultiPage(Rect area, double dpi) {
    final pageSize = getSizeAtDpi(dpi);
    if (pageSize == Size.zero) return false;

    final areaPixels = Size(
      area.width * (dpi / 72.0),
      area.height * (dpi / 72.0),
    );
    return areaPixels.width > pageSize.width ||
        areaPixels.height > pageSize.height;
  }

  /// Calculates il number of pagine necessarie for aa data area
  (int columns, int rows) calculatePageGrid(Rect area, double dpi) {
    final pageSize = getSizeAtDpi(dpi);
    if (pageSize == Size.zero) return (1, 1);

    final areaPixels = Size(
      area.width * (dpi / 72.0),
      area.height * (dpi / 72.0),
    );
    final columns = (areaPixels.width / pageSize.width).ceil();
    final rows = (areaPixels.height / pageSize.height).ceil();

    return (columns.clamp(1, 100), rows.clamp(1, 100));
  }

  // ============================================================
  // PRESET PREDEFINITI
  // ============================================================

  /// 📄 PAPER PRESETS
  static const ExportPreset a4Portrait = ExportPreset(
    id: 'a4_portrait',
    name: 'A4 Portrait',
    subtitle: '210 × 297 mm',
    icon: Icons.description,
    category: ExportPresetCategory.paper,
    aspectRatio: 210 / 297, // ~0.707
    fixedSize: Size(595, 842), // 72 DPI
  );

  static const ExportPreset a4Landscape = ExportPreset(
    id: 'a4_landscape',
    name: 'A4 Landscape',
    subtitle: '297 × 210 mm',
    icon: Icons.description,
    category: ExportPresetCategory.paper,
    aspectRatio: 297 / 210, // ~1.414
    fixedSize: Size(842, 595),
  );

  static const ExportPreset a3Portrait = ExportPreset(
    id: 'a3_portrait',
    name: 'A3 Portrait',
    subtitle: '297 × 420 mm',
    icon: Icons.description,
    category: ExportPresetCategory.paper,
    aspectRatio: 297 / 420,
    fixedSize: Size(842, 1191),
  );

  static const ExportPreset a3Landscape = ExportPreset(
    id: 'a3_landscape',
    name: 'A3 Landscape',
    subtitle: '420 × 297 mm',
    icon: Icons.description,
    category: ExportPresetCategory.paper,
    aspectRatio: 420 / 297,
    fixedSize: Size(1191, 842),
  );

  static const ExportPreset letterPortrait = ExportPreset(
    id: 'letter_portrait',
    name: 'Letter Portrait',
    subtitle: '8.5 × 11 in',
    icon: Icons.description,
    category: ExportPresetCategory.paper,
    aspectRatio: 8.5 / 11,
    fixedSize: Size(612, 792),
  );

  static const ExportPreset letterLandscape = ExportPreset(
    id: 'letter_landscape',
    name: 'Letter Landscape',
    subtitle: '11 × 8.5 in',
    icon: Icons.description,
    category: ExportPresetCategory.paper,
    aspectRatio: 11 / 8.5,
    fixedSize: Size(792, 612),
  );

  /// 📱 SOCIAL MEDIA PRESETS
  static const ExportPreset instagramSquare = ExportPreset(
    id: 'instagram_square',
    name: 'Instagram',
    subtitle: '1:1 Square',
    icon: Icons.crop_square,
    category: ExportPresetCategory.social,
    aspectRatio: 1.0,
    fixedSize: Size(1080, 1080),
  );

  static const ExportPreset instagramPortrait = ExportPreset(
    id: 'instagram_portrait',
    name: 'Instagram Portrait',
    subtitle: '4:5',
    icon: Icons.crop_portrait,
    category: ExportPresetCategory.social,
    aspectRatio: 4 / 5,
    fixedSize: Size(1080, 1350),
  );

  static const ExportPreset instagramStory = ExportPreset(
    id: 'instagram_story',
    name: 'Story / Reel',
    subtitle: '9:16',
    icon: Icons.smartphone,
    category: ExportPresetCategory.social,
    aspectRatio: 9 / 16,
    fixedSize: Size(1080, 1920),
  );

  static const ExportPreset twitterPost = ExportPreset(
    id: 'twitter_post',
    name: 'Twitter / X',
    subtitle: '16:9',
    icon: Icons.tag,
    category: ExportPresetCategory.social,
    aspectRatio: 16 / 9,
    fixedSize: Size(1200, 675),
  );

  static const ExportPreset youtubeThumbnail = ExportPreset(
    id: 'youtube_thumbnail',
    name: 'YouTube Thumbnail',
    subtitle: '16:9 HD',
    icon: Icons.play_circle_outline,
    category: ExportPresetCategory.social,
    aspectRatio: 16 / 9,
    fixedSize: Size(1280, 720),
  );

  static const ExportPreset linkedInPost = ExportPreset(
    id: 'linkedin_post',
    name: 'LinkedIn',
    subtitle: '1.91:1',
    icon: Icons.work_outline,
    category: ExportPresetCategory.social,
    aspectRatio: 1.91,
    fixedSize: Size(1200, 628),
  );

  static const ExportPreset facebookPost = ExportPreset(
    id: 'facebook_post',
    name: 'Facebook',
    subtitle: '1.91:1',
    icon: Icons.facebook,
    category: ExportPresetCategory.social,
    aspectRatio: 1.91,
    fixedSize: Size(1200, 630),
  );

  /// 🎨 SPECIAL PRESETS
  static const ExportPreset fitContent = ExportPreset(
    id: 'fit_content',
    name: 'Fit Content',
    subtitle: 'Auto-size',
    icon: Icons.fit_screen,
    category: ExportPresetCategory.custom,
    isCustom: true,
  );

  static const ExportPreset custom = ExportPreset(
    id: 'custom',
    name: 'Custom',
    subtitle: 'Free resize',
    icon: Icons.crop_free,
    category: ExportPresetCategory.custom,
    isCustom: true,
  );

  /// Lista of all the preset paper
  static const List<ExportPreset> paperPresets = [
    a4Portrait,
    a4Landscape,
    a3Portrait,
    a3Landscape,
    letterPortrait,
    letterLandscape,
  ];

  /// Lista of all the preset social
  static const List<ExportPreset> socialPresets = [
    instagramSquare,
    instagramPortrait,
    instagramStory,
    twitterPost,
    youtubeThumbnail,
    linkedInPost,
    facebookPost,
  ];

  /// Lista of all the preset speciali
  static const List<ExportPreset> specialPresets = [fitContent, custom];

  /// All i preset disponibili
  static const List<ExportPreset> allPresets = [
    ...specialPresets,
    ...paperPresets,
    ...socialPresets,
  ];

  /// Find un preset per ID
  static ExportPreset? findById(String id) {
    try {
      return allPresets.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }
}

/// 🖼️ Formato di output for export
enum ExportFormat { png, jpeg }

/// ⚙️ Quality DPI for export
enum ExportQuality {
  screen(72, 'Screen', '72 DPI'),
  standard(150, 'Standard', '150 DPI'),
  high(300, 'High Quality', '300 DPI');

  final double dpi;
  final String label;
  final String subtitle;

  const ExportQuality(this.dpi, this.label, this.subtitle);
}

/// 🎨 Opzioni di background for export
enum ExportBackground {
  transparent('Transparent', Icons.texture),
  white('White', Icons.crop_square),
  solidColor('Solid Color', Icons.format_color_fill),
  withTemplate('With Template', Icons.grid_on);

  final String label;
  final IconData icon;

  const ExportBackground(this.label, this.icon);
}

/// 📋 Complete configuration for export
class ExportConfig {
  final ExportPreset preset;
  final ExportFormat format;
  final ExportQuality quality;
  final ExportBackground background;
  final Color? backgroundColor;
  final String? paperType; // Paper type per background withTemplate
  final Rect exportArea;
  final bool multiPage;
  final ExportPageFormat pageFormat;
  final String? savedAreaName; // If l'utente vuole salvare quest'area

  // PDF-specific options
  final bool pdfAConformance;
  final String? pdfWatermark;
  final String? pdfPassword;

  const ExportConfig({
    this.preset = ExportPreset.a4Portrait,
    this.format = ExportFormat.png,
    this.quality = ExportQuality.standard,
    this.background = ExportBackground.transparent,
    this.backgroundColor,
    this.paperType,
    this.exportArea = Rect.zero,
    this.multiPage = false,
    this.pageFormat = ExportPageFormat.a4Portrait,
    this.savedAreaName,
    this.pdfAConformance = false,
    this.pdfWatermark,
    this.pdfPassword,
  });

  ExportConfig copyWith({
    ExportPreset? preset,
    ExportFormat? format,
    ExportQuality? quality,
    ExportBackground? background,
    Color? backgroundColor,
    String? paperType,
    Rect? exportArea,
    bool? multiPage,
    ExportPageFormat? pageFormat,
    String? savedAreaName,
    bool? pdfAConformance,
    String? pdfWatermark,
    String? pdfPassword,
  }) {
    return ExportConfig(
      preset: preset ?? this.preset,
      format: format ?? this.format,
      quality: quality ?? this.quality,
      background: background ?? this.background,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      paperType: paperType ?? this.paperType,
      exportArea: exportArea ?? this.exportArea,
      multiPage: multiPage ?? this.multiPage,
      pageFormat: pageFormat ?? this.pageFormat,
      savedAreaName: savedAreaName ?? this.savedAreaName,
      pdfAConformance: pdfAConformance ?? this.pdfAConformance,
      pdfWatermark: pdfWatermark ?? this.pdfWatermark,
      pdfPassword: pdfPassword ?? this.pdfPassword,
    );
  }

  /// Calculates le dimensioni finali in pixel
  Size get finalSizePixels {
    final scale = quality.dpi / 72.0;
    return Size(exportArea.width * scale, exportArea.height * scale);
  }

  /// Checks se supera il limite per immagini singole (8192x8192)
  bool get exceedsImageLimit {
    final size = finalSizePixels;
    return size.width > 8192 || size.height > 8192;
  }

  /// If image exceeds single-page limit, requires multi-page export
  bool get requiresMultiPage {
    return exceedsImageLimit;
  }
}

/// Extension per ExportPageFormat con utility methods
extension ExportPageFormatUtils on ExportPageFormat {
  /// Get the size in points (72 DPI) for this format
  Size get sizeInPoints {
    switch (this) {
      case ExportPageFormat.a4Portrait:
        return const Size(595, 842); // 210 × 297 mm at 72 DPI
      case ExportPageFormat.a4Landscape:
        return const Size(842, 595);
      case ExportPageFormat.a3Portrait:
        return const Size(842, 1191); // 297 × 420 mm at 72 DPI
      case ExportPageFormat.a3Landscape:
        return const Size(1191, 842);
      case ExportPageFormat.letterPortrait:
        return const Size(612, 792); // 8.5 × 11 inches at 72 DPI
      case ExportPageFormat.letterLandscape:
        return const Size(792, 612);
      case ExportPageFormat.custom:
        return const Size(595, 842); // Default to A4
    }
  }

  /// Get the readable label for this format
  String get label {
    switch (this) {
      case ExportPageFormat.a4Portrait:
        return 'A4';
      case ExportPageFormat.a4Landscape:
        return 'A4 Landscape';
      case ExportPageFormat.a3Portrait:
        return 'A3';
      case ExportPageFormat.a3Landscape:
        return 'A3 Landscape';
      case ExportPageFormat.letterPortrait:
        return 'Letter';
      case ExportPageFormat.letterLandscape:
        return 'Letter Landscape';
      case ExportPageFormat.custom:
        return 'Custom';
    }
  }

  /// Get l'aspect ratio del formato
  double get aspectRatio => sizeInPoints.width / sizeInPoints.height;
}
