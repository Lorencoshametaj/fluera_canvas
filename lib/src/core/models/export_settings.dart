/// Image export parameters stored on an [ImageElement].
///
/// Minimal canvas-core model — advanced export presets (colour profiles,
/// chroma subsampling, DPI scaling) are layered on top by consumer
/// packages.
class ExportSettings {
  /// Output format identifier — typically "png", "jpeg", "webp".
  final String format;

  /// Quality 0..100 for lossy formats. Ignored for lossless.
  final int quality;

  const ExportSettings({this.format = 'png', this.quality = 90});

  ExportSettings copyWith({String? format, int? quality}) => ExportSettings(
    format: format ?? this.format,
    quality: quality ?? this.quality,
  );

  Map<String, dynamic> toJson() => {'format': format, 'quality': quality};

  factory ExportSettings.fromJson(Map<String, dynamic> json) => ExportSettings(
    format: json['format'] as String? ?? 'png',
    quality: (json['quality'] as num?)?.toInt() ?? 90,
  );
}
