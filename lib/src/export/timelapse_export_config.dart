import 'package:flutter/material.dart';

/// 🎬 Risoluzione video per timelapse export
enum TimelapseResolution {
  hd720(1280, 'HD 720p', '1280×720'),
  fullHd1080(1920, 'Full HD 1080p', '1920×1080'),
  uhd4k(3840, '4K UHD', '3840×2160');

  final int width;
  final String label;
  final String description;

  const TimelapseResolution(this.width, this.label, this.description);

  /// Calculates altezza dal aspect ratio of the canvas
  int heightForAspectRatio(double aspectRatio) =>
      (width / aspectRatio).round().clamp(2, 4096);

  /// Stima size file in MB (approssimativa)
  double estimatedFileSizeMb({
    required int totalFrames,
    required TimelapseFormat format,
  }) {
    // Stima bitrate per risoluzione (H.264, quality media)
    final bitrateKbps = switch (this) {
      TimelapseResolution.hd720 => 4000,
      TimelapseResolution.fullHd1080 => 8000,
      TimelapseResolution.uhd4k => 20000,
    };

    if (format == TimelapseFormat.gif) {
      // GIF: molto more pesante (~4x rispetto a MP4)
      return totalFrames * width * 720 * 3 / (1024 * 1024 * 8);
    }

    final durationSec = totalFrames / 30.0;
    return bitrateKbps * durationSec / 8 / 1024;
  }
}

/// 🎬 Formato output video
enum TimelapseFormat {
  mp4('MP4', 'H.264', Icons.movie_outlined),
  gif('GIF', 'Animato', Icons.gif_box_outlined);

  final String label;
  final String codec;
  final IconData icon;

  const TimelapseFormat(this.label, this.codec, this.icon);

  String get extension => switch (this) {
    TimelapseFormat.mp4 => 'mp4',
    TimelapseFormat.gif => 'gif',
  };
}

/// 🎬 Speed timelapse
enum TimelapseSpeed {
  x2(2, '2×'),
  x4(4, '4×'),
  x8(8, '8×'),
  x16(16, '16×'),
  x32(32, '32×');

  final int multiplier;
  final String label;

  const TimelapseSpeed(this.multiplier, this.label);
}

/// 🎬 Complete configuration for timelapse export
///
/// Combine risoluzione, speed, formato e opzioni cosmetiche
/// per produrre un video timelapse del processo creativo.
class TimelapseExportConfig {
  /// Risoluzione output
  final TimelapseResolution resolution;

  /// Speed di riproduzione (multiplier)
  final TimelapseSpeed speed;

  /// Formato output (MP4/GIF)
  final TimelapseFormat format;

  /// Frame per secondo (30 o 60)
  final int fps;

  /// Canvas background color
  final Color backgroundColor;

  /// If true, aggiunge watermark "Made with Looponia" in basso a destra
  final bool showWatermark;

  /// Frame skip: per sessioni molto lunghe (>5000 eventi), renderizza
  /// only every Nth frame to maintain reasonable times.
  /// Calculateto automaticamente da [calculateFramePlan].
  final int frameSkip;

  const TimelapseExportConfig({
    this.resolution = TimelapseResolution.fullHd1080,
    this.speed = TimelapseSpeed.x8,
    this.format = TimelapseFormat.mp4,
    this.fps = 30,
    this.backgroundColor = Colors.white,
    this.showWatermark = true,
    this.frameSkip = 1,
  });

  /// Calculates il numero totale di frame nel video output
  int totalFrames(int eventCount) {
    final effectiveEvents = (eventCount / frameSkip).ceil();
    return (effectiveEvents / speed.multiplier).ceil().clamp(1, 99999);
  }

  /// Estimated video duration in seconds
  double estimatedDurationSec(int eventCount) => totalFrames(eventCount) / fps;

  /// Estimated file size in MB
  double estimatedFileSizeMb(int eventCount) => resolution.estimatedFileSizeMb(
    totalFrames: totalFrames(eventCount),
    format: format,
  );

  /// Factory: calcola automaticamente frameSkip per sessioni lunghe
  ///
  /// Obiettivo: video tra 15s e 120s. Se troppo lungo, aumenta frameSkip.
  factory TimelapseExportConfig.auto({
    required int eventCount,
    TimelapseResolution resolution = TimelapseResolution.fullHd1080,
    TimelapseSpeed speed = TimelapseSpeed.x8,
    TimelapseFormat format = TimelapseFormat.mp4,
    Color backgroundColor = Colors.white,
    bool showWatermark = true,
  }) {
    int frameSkip = 1;
    final maxDurationSec = 120.0;
    final fps = 30;

    // Calculate frameSkip to remain under maxDuration
    while (true) {
      final effectiveEvents = (eventCount / frameSkip).ceil();
      final totalFrames = (effectiveEvents / speed.multiplier).ceil();
      final duration = totalFrames / fps;

      if (duration <= maxDurationSec || frameSkip > 100) break;
      frameSkip++;
    }

    return TimelapseExportConfig(
      resolution: resolution,
      speed: speed,
      format: format,
      fps: fps,
      backgroundColor: backgroundColor,
      showWatermark: showWatermark,
      frameSkip: frameSkip,
    );
  }

  TimelapseExportConfig copyWith({
    TimelapseResolution? resolution,
    TimelapseSpeed? speed,
    TimelapseFormat? format,
    int? fps,
    Color? backgroundColor,
    bool? showWatermark,
    int? frameSkip,
  }) {
    return TimelapseExportConfig(
      resolution: resolution ?? this.resolution,
      speed: speed ?? this.speed,
      format: format ?? this.format,
      fps: fps ?? this.fps,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      showWatermark: showWatermark ?? this.showWatermark,
      frameSkip: frameSkip ?? this.frameSkip,
    );
  }
}
