import 'dart:math' as math;

/// Unified telemetry bus for the Fluera Engine.
///
/// Collects performance data from all subsystems via 6 primitives:
/// - **Counter**: monotonic count (e.g. `integrity.repairs`)
/// - **Gauge**: current value (e.g. `memory.rss_mb`)
/// - **Span**: timed operation (e.g. `render.frame`)
/// - **Event**: point-in-time occurrence (e.g. `error.reported`)
/// - **Histogram**: distribution metric with percentiles (e.g. `render.frameMs`)
/// - **AlertRule**: threshold-based monitoring (e.g. p99 > 16ms)
///
/// Advanced features:
/// - **Sampling**: production-safe sampling strategies
/// - **Exporters**: push data to console, callbacks, or external systems
/// - **Hierarchical spans**: parent-child tracing for end-to-end analysis
/// - **Scoped metrics**: tag all data with subsystem scope
///
/// Usage:
/// ```dart
/// final t = EngineScope.current.telemetry;
/// t.counter('integrity.repairs').increment();
/// t.gauge('memory.rss_mb').set(280.5);
/// t.histogram('render.frameMs').record(14.2);
/// final span = t.startSpan('io.save', scope: TelemetryScope.io);
/// await save();
/// span.end();
/// t.flush(); // push to exporters
/// ```
class EngineTelemetry {
  /// Named counters (created on first access).
  final Map<String, TelemetryCounter> _counters = {};

  /// Named gauges (created on first access).
  final Map<String, TelemetryGauge> _gauges = {};

  /// Named histograms (created on first access).
  final Map<String, TelemetryHistogram> _histograms = {};

  /// Completed spans (ring buffer).
  final List<TelemetrySpan> _spans = [];

  /// Point events (ring buffer).
  final List<TelemetryEvent> _events = [];

  /// Registered exporters.
  final List<TelemetryExporter> _exporters = [];

  /// Alert rules.
  final List<AlertRule> _alertRules = [];

  /// Sampling strategy. Default: always sample.
  TelemetrySampler _sampler = const AlwaysSampler();

  /// Maximum number of retained spans.
  static const int maxSpans = 1000;

  /// Maximum number of retained events.
  static const int maxEvents = 500;

  // ---------------------------------------------------------------------------
  // Core API
  // ---------------------------------------------------------------------------

  /// Get or create a named counter.
  TelemetryCounter counter(String name) =>
      _counters.putIfAbsent(name, () => TelemetryCounter(name));

  /// Get or create a named gauge.
  TelemetryGauge gauge(String name) =>
      _gauges.putIfAbsent(name, () => TelemetryGauge(name));

  /// Get or create a named histogram.
  TelemetryHistogram histogram(String name) =>
      _histograms.putIfAbsent(name, () => TelemetryHistogram(name));

  /// Start a timed span. Call [TelemetrySpan.end] when the operation completes.
  ///
  /// Supports optional [parent] for hierarchical tracing and [scope] tagging.
  TelemetrySpan startSpan(
    String name, {
    TelemetrySpan? parent,
    TelemetryScope? scope,
  }) {
    if (!_sampler.shouldSample(name)) {
      return TelemetrySpan._noop(name);
    }
    final span = TelemetrySpan(name, parent: parent, scope: scope)
      .._telemetry = this;
    return span;
  }

  /// Record a completed span.
  void _recordSpan(TelemetrySpan span) {
    _spans.add(span);
    if (_spans.length > maxSpans) {
      _spans.removeAt(0);
    }
  }

  /// Emit a point-in-time event with optional metadata.
  void event(String name, [Map<String, dynamic>? data]) {
    if (!_sampler.shouldSample(name)) return;
    _events.add(TelemetryEvent(name: name, timestampUs: _nowUs(), data: data));
    if (_events.length > maxEvents) {
      _events.removeAt(0);
    }
  }

  // ---------------------------------------------------------------------------
  // Sampling
  // ---------------------------------------------------------------------------

  /// Set the sampling strategy for spans and events.
  void setSampler(TelemetrySampler sampler) => _sampler = sampler;

  /// Get the current sampler.
  TelemetrySampler get sampler => _sampler;

  // ---------------------------------------------------------------------------
  // Exporters
  // ---------------------------------------------------------------------------

  /// Add a telemetry exporter.
  void addExporter(TelemetryExporter exporter) => _exporters.add(exporter);

  /// Remove a telemetry exporter.
  void removeExporter(TelemetryExporter exporter) =>
      _exporters.remove(exporter);

  /// Flush all data to registered exporters.
  void flush() {
    if (_exporters.isEmpty) return;
    final data = snapshot();
    for (final exporter in _exporters) {
      exporter.export(data);
    }
  }

  // ---------------------------------------------------------------------------
  // Alert Rules
  // ---------------------------------------------------------------------------

  /// Add an alert rule.
  void addAlertRule(AlertRule rule) => _alertRules.add(rule);

  /// Remove an alert rule.
  void removeAlertRule(AlertRule rule) => _alertRules.remove(rule);

  /// Check all alert rules and return triggered alerts.
  List<TriggeredAlert> checkAlerts() {
    final alerts = <TriggeredAlert>[];
    for (final rule in _alertRules) {
      final hist = _histograms[rule.metricName];
      if (hist == null || hist.count == 0) continue;

      final value = hist.percentile(rule.percentile);
      if (value > rule.thresholdUs) {
        alerts.add(
          TriggeredAlert(
            rule: rule,
            actualValue: value,
            sampleCount: hist.count,
          ),
        );
      }
    }
    return alerts;
  }

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  /// Export all telemetry data as a JSON-serializable map.
  Map<String, dynamic> snapshot() {
    return {
      'timestampUs': _nowUs(),
      'counters': {for (final c in _counters.values) c.name: c.value},
      'gauges': {for (final g in _gauges.values) g.name: g.value},
      'histograms': {for (final h in _histograms.values) h.name: h.toJson()},
      'spans': _spans.map((s) => s.toJson()).toList(),
      'events': _events.map((e) => e.toJson()).toList(),
    };
  }

  /// Reset all telemetry data.
  void reset() {
    _counters.clear();
    _gauges.clear();
    _histograms.clear();
    _spans.clear();
    _events.clear();
  }

  static int _nowUs() => DateTime.now().microsecondsSinceEpoch;
}

// =============================================================================
// Core Primitives
// =============================================================================

/// Monotonically-increasing counter.
class TelemetryCounter {
  /// Name used as the key in snapshots.
  final String name;

  /// Current count.
  int value = 0;

  TelemetryCounter(this.name);

  /// Increment by [n] (default 1).
  void increment([int n = 1]) => value += n;

  /// Reset to zero.
  void reset() => value = 0;
}

/// Current-value gauge (can go up or down).
class TelemetryGauge {
  /// Name used as the key in snapshots.
  final String name;

  /// Current value.
  double value = 0;

  TelemetryGauge(this.name);

  /// Set the gauge to [v].
  void set(double v) => value = v;
}

/// Timed operation span with optional parent and scope.
class TelemetrySpan {
  /// Operation name.
  final String name;

  /// Start timestamp in microseconds since epoch.
  int startUs;

  /// End timestamp in microseconds since epoch. Null if still running.
  int? endUs;

  /// Parent span for hierarchical tracing.
  final TelemetrySpan? parent;

  /// Subsystem scope tag.
  final TelemetryScope? scope;

  /// Whether this is a no-op span (sampling rejected it).
  final bool _noop;

  /// Reference to the telemetry bus (set when span is recorded).
  EngineTelemetry? _telemetry;

  TelemetrySpan(this.name, {this.parent, this.scope})
    : startUs = EngineTelemetry._nowUs(),
      _noop = false;

  /// Create a no-op span that records nothing (used when sampling rejects).
  TelemetrySpan._noop(this.name)
    : startUs = 0,
      parent = null,
      scope = null,
      _noop = true;

  /// Parent span name for tracing.
  String? get parentName => parent?.name;

  /// Duration in microseconds, or null if not yet ended.
  int? get durationUs => endUs != null ? endUs! - startUs : null;

  /// End this span and record it in the telemetry bus.
  void end() {
    if (_noop || endUs != null) return; // no-op or idempotent
    endUs = EngineTelemetry._nowUs();
    _telemetry?._recordSpan(this);
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'startUs': startUs,
    if (endUs != null) 'endUs': endUs,
    if (durationUs != null) 'durationUs': durationUs,
    if (parentName != null) 'parent': parentName,
    if (scope != null) 'scope': scope!.name,
  };
}

/// Point-in-time event with optional metadata.
class TelemetryEvent {
  final String name;
  final int timestampUs;
  final Map<String, dynamic>? data;

  const TelemetryEvent({
    required this.name,
    required this.timestampUs,
    this.data,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'timestampUs': timestampUs,
    if (data != null) 'data': data,
  };
}

// =============================================================================
// Histogram (Distribution Metric)
// =============================================================================

/// Rolling distribution metric with percentile computation.
///
/// Records values and computes p50, p95, p99, min, max, average.
/// Uses a fixed-size ring buffer to bound memory usage.
///
/// ```dart
/// final hist = telemetry.histogram('render.frameMs');
/// hist.record(14.2);
/// hist.record(16.8);
/// print(hist.p50); // median
/// print(hist.p99); // 99th percentile
/// ```
class TelemetryHistogram {
  final String name;
  final List<double> _values = [];
  bool _sorted = false;

  /// Maximum number of retained values.
  static const int maxValues = 2048;

  TelemetryHistogram(this.name);

  /// Record a value.
  void record(double value) {
    _values.add(value);
    _sorted = false;
    if (_values.length > maxValues) {
      _values.removeAt(0);
    }
  }

  /// Number of recorded values.
  int get count => _values.length;

  /// Minimum recorded value.
  double get min {
    if (_values.isEmpty) return 0;
    _ensureSorted();
    return _values.first;
  }

  /// Maximum recorded value.
  double get max {
    if (_values.isEmpty) return 0;
    _ensureSorted();
    return _values.last;
  }

  /// Average of all recorded values.
  double get avg {
    if (_values.isEmpty) return 0;
    return _values.fold<double>(0, (sum, v) => sum + v) / _values.length;
  }

  /// 50th percentile (median).
  double get p50 => percentile(50);

  /// 95th percentile.
  double get p95 => percentile(95);

  /// 99th percentile.
  double get p99 => percentile(99);

  /// Compute the [p]-th percentile (0–100).
  double percentile(int p) {
    if (_values.isEmpty) return 0;
    _ensureSorted();
    final idx = ((p / 100) * (_values.length - 1)).round().clamp(
      0,
      _values.length - 1,
    );
    return _values[idx];
  }

  void _ensureSorted() {
    if (_sorted) return;
    _values.sort();
    _sorted = true;
  }

  /// Reset all recorded values.
  void reset() {
    _values.clear();
    _sorted = false;
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'count': count,
    'min': min,
    'max': max,
    'avg': avg,
    'p50': p50,
    'p95': p95,
    'p99': p99,
  };
}

// =============================================================================
// Telemetry Scope
// =============================================================================

/// Subsystem scope for tagged metrics.
enum TelemetryScope {
  rendering,
  history,
  layout,
  io,
  network,
  sceneGraph,
  selection,
  plugin,
  theme,
}

// =============================================================================
// Sampling Strategies
// =============================================================================

/// Interface for controlling which spans/events are recorded.
abstract class TelemetrySampler {
  const TelemetrySampler();

  /// Whether to sample (record) a span or event with the given [name].
  bool shouldSample(String name);
}

/// Always sample (debug/development mode).
class AlwaysSampler extends TelemetrySampler {
  const AlwaysSampler();

  @override
  bool shouldSample(String name) => true;
}

/// Sample at a fixed rate (production mode).
///
/// ```dart
/// telemetry.setSampler(RateSampler(0.01)); // 1% sampling
/// ```
class RateSampler extends TelemetrySampler {
  /// Sampling rate between 0.0 (nothing) and 1.0 (everything).
  final double rate;

  /// Deterministic counter-based sampling.
  int _counter = 0;
  final int _interval;

  RateSampler(this.rate) : _interval = rate > 0 ? (1 / rate).ceil() : 0;

  @override
  bool shouldSample(String name) {
    if (rate <= 0) return false;
    if (rate >= 1) return true;
    _counter++;
    return _counter % _interval == 0;
  }
}

/// Adaptive sampler that backs off under load.
///
/// Starts at [baseRate] and drops to [minRate] when the number
/// of samples per window exceeds [maxPerWindow].
class AdaptiveSampler extends TelemetrySampler {
  final double baseRate;
  final double minRate;
  final int maxPerWindow;
  final Duration window;

  int _windowCount = 0;
  DateTime _windowStart = DateTime.now();

  AdaptiveSampler({
    this.baseRate = 1.0,
    this.minRate = 0.01,
    this.maxPerWindow = 100,
    this.window = const Duration(seconds: 1),
  });

  @override
  bool shouldSample(String name) {
    final now = DateTime.now();
    if (now.difference(_windowStart) > window) {
      _windowStart = now;
      _windowCount = 0;
    }
    _windowCount++;

    if (_windowCount <= maxPerWindow) return true;

    // Back off to minimum rate.
    final backoffInterval = math.max(1, (1 / minRate).ceil());
    return (_windowCount % backoffInterval) == 0;
  }
}

// =============================================================================
// Exporters
// =============================================================================

/// Interface for pushing telemetry data to external systems.
abstract class TelemetryExporter {
  const TelemetryExporter();

  /// Export a telemetry snapshot.
  void export(Map<String, dynamic> snapshot);
}

/// Exporter that prints a summary to the debug console.
class ConsoleTelemetryExporter extends TelemetryExporter {
  const ConsoleTelemetryExporter();

  @override
  void export(Map<String, dynamic> snapshot) {
    final buf = StringBuffer('[Telemetry] ');
    final counters = snapshot['counters'] as Map<String, dynamic>?;
    if (counters != null && counters.isNotEmpty) {
      buf.write('counters=${counters.length} ');
    }
    final histograms = snapshot['histograms'] as Map<String, dynamic>?;
    if (histograms != null) {
      for (final entry in histograms.entries) {
        final h = entry.value as Map<String, dynamic>;
        buf.write('${entry.key}(p50=${h['p50']}, p99=${h['p99']}) ');
      }
    }
    // ignore: avoid_print
  }
}

/// Exporter that invokes a callback with the snapshot data.
///
/// ```dart
/// telemetry.addExporter(CallbackTelemetryExporter((data) {
///   myBackend.push(data);
/// }));
/// ```
class CallbackTelemetryExporter extends TelemetryExporter {
  final void Function(Map<String, dynamic> snapshot) onExport;

  const CallbackTelemetryExporter(this.onExport);

  @override
  void export(Map<String, dynamic> snapshot) => onExport(snapshot);
}

// =============================================================================
// Alert Rules
// =============================================================================

/// Severity level for triggered alerts.
enum AlertSeverity { info, warning, critical }

/// A threshold-based alert rule on a histogram metric.
///
/// ```dart
/// telemetry.addAlertRule(AlertRule(
///   name: 'slow_render',
///   metricName: 'render.frameMs',
///   percentile: 99,
///   thresholdUs: 16667, // 60fps budget
///   severity: AlertSeverity.warning,
/// ));
/// ```
class AlertRule {
  final String name;
  final String metricName;
  final int percentile;
  final double thresholdUs;
  final AlertSeverity severity;

  const AlertRule({
    required this.name,
    required this.metricName,
    this.percentile = 99,
    required this.thresholdUs,
    this.severity = AlertSeverity.warning,
  });
}

/// A triggered alert containing the rule and actual measured value.
class TriggeredAlert {
  final AlertRule rule;
  final double actualValue;
  final int sampleCount;

  const TriggeredAlert({
    required this.rule,
    required this.actualValue,
    required this.sampleCount,
  });

  @override
  String toString() =>
      'TriggeredAlert(${rule.name}: ${rule.metricName} '
      'p${rule.percentile}=$actualValue > ${rule.thresholdUs}, '
      'severity=${rule.severity.name}, samples=$sampleCount)';
}
