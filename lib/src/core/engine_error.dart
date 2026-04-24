/// 🏷️ ENGINE ERROR — Classified error model for structured recovery.
///
/// Every error flowing through the recovery system is wrapped in an
/// [EngineError] with severity, domain, and source metadata. This enables:
///
/// - Retry decisions based on [severity] (transient → retry, fatal → propagate)
/// - Domain-scoped dashboarding (storage errors vs rendering errors)
/// - Source-level traceability (which method, which service)
///
/// ```dart
/// final error = EngineError(
///   severity: ErrorSeverity.transient,
///   domain: ErrorDomain.storage,
///   source: 'DiskStrokeManager._loadIndex',
///   original: e,
///   stack: stackTrace,
/// );
/// ```
library;

/// How severe is the error, and what action should be taken.
enum ErrorSeverity {
  /// Temporary failure — retry will likely succeed (I/O hiccup, timeout).
  transient,

  /// Service is impaired but the engine can continue with reduced functionality.
  /// Example: native metrics unavailable → fall back to internal budget tracking.
  degraded,

  /// Unrecoverable — the operation cannot succeed regardless of retries.
  /// Example: corrupt database schema, invalid binary format.
  fatal,
}

/// Which subsystem produced the error.
enum ErrorDomain {
  /// Disk I/O, SQLite, file system operations.
  storage,

  /// Native platform channels (stylus, vibration, performance monitor).
  platform,

  /// Tile rasterization, shader compilation, isolate pool.
  rendering,

  /// Real-time sync, cloud operations.
  network,

  /// Scene graph structural integrity violations.
  sceneGraph,
}

/// A classified engine error with full context for recovery and telemetry.
class EngineError {
  /// Severity classification — drives retry/fallback decisions.
  final ErrorSeverity severity;

  /// Domain classification — for scoped dashboarding.
  final ErrorDomain domain;

  /// Human-readable source identifier (e.g. `'DiskStrokeManager._loadIndex'`).
  final String source;

  /// The original exception or error.
  final Object original;

  /// Stack trace at the point of failure, if available.
  final StackTrace? stack;

  /// When the error occurred.
  final DateTime timestamp;

  /// Optional context map for additional diagnostic data.
  final Map<String, dynamic>? context;

  EngineError({
    required this.severity,
    required this.domain,
    required this.source,
    required this.original,
    this.stack,
    this.context,
  }) : timestamp = DateTime.now();

  @override
  String toString() =>
      'EngineError(${severity.name}/${domain.name}) in $source: $original';
}
