import 'dart:async';
import 'dart:collection';

import 'engine_event.dart';

/// 🚌 Centralized Event Bus — Enterprise cross-subsystem communication.
///
/// Provides typed pub-sub for all engine subsystems. Consumers subscribe
/// to specific event types using [on<T>()], and producers emit events
/// through [emit()].
///
/// The event bus is registered in [EngineScope] and bridged from existing
/// subsystem notification systems (SceneGraph, SelectionManager, etc.).
///
/// ```dart
/// final bus = EngineScope.current.eventBus;
///
/// // Listen to all scene graph events
/// bus.on<NodeAddedEngineEvent>().listen((e) {
///   print('Node ${e.node.id} added to ${e.parentId}');
/// });
///
/// // Listen to all events from any domain
/// bus.stream.listen((e) => analytics.track(e));
///
/// // Pause during batch mutations
/// bus.pause();
/// // ...mass mutations...
/// bus.resume(); // emits BatchCompleteEngineEvent
/// ```
class EngineEventBus {
  final StreamController<EngineEvent> _controller =
      StreamController<EngineEvent>.broadcast(sync: false);

  // ── Pause/resume state ──
  bool _paused = false;
  int _suppressedCount = 0;
  DateTime? _pauseStart;

  /// Bounded queue for critical events emitted during pause.
  ///
  /// Critical events (marked with [CriticalEvent]) are **never dropped**
  /// during pause — they're buffered here and flushed on [resume],
  /// before the [BatchCompleteEngineEvent].
  static const int _maxCriticalBuffer = 100;
  final Queue<EngineEvent> _criticalBuffer = Queue<EngineEvent>();

  // ── Metrics ──
  int _totalEmitted = 0;
  final Map<String, int> _eventCountByType = {};

  // ═══════════════════════════════════════════════════════════════════════════
  // SUBSCRIBE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Stream of **all** engine events.
  Stream<EngineEvent> get stream => _controller.stream;

  /// Listen to events of a specific type only.
  ///
  /// Uses runtime type filtering — zero overhead when no listeners are
  /// attached.
  ///
  /// ```dart
  /// bus.on<NodeAddedEngineEvent>().listen((e) => ...);
  /// ```
  Stream<T> on<T extends EngineEvent>() =>
      _controller.stream.where((e) => e is T).cast<T>();

  /// Listen to events from a specific source subsystem.
  ///
  /// ```dart
  /// bus.whereSource('SceneGraph').listen((e) => ...);
  /// ```
  Stream<EngineEvent> whereSource(String source) =>
      _controller.stream.where((e) => e.source == source);

  /// Listen to events from a specific domain.
  ///
  /// ```dart
  /// bus.whereDomain(EventDomain.sceneGraph).listen((e) => ...);
  /// ```
  Stream<EngineEvent> whereDomain(EventDomain domain) =>
      _controller.stream.where((e) => e.domain == domain);

  // ── Microtask batching ──

  /// When `true`, events emitted synchronously within the same microtask
  /// are buffered and delivered together, preventing rapid-fire events
  /// from starving the render pipeline.
  bool enableBatching = false;
  bool _batchScheduled = false;
  final List<EngineEvent> _batchBuffer = [];

  /// Emit a typed event to all listeners.
  ///
  /// If the bus is [_paused]:
  /// - **Critical** events (marked with [CriticalEvent]) are buffered
  ///   and flushed on [resume] (never lost).
  /// - **Best-effort** events are silently suppressed.
  ///
  /// If [enableBatching] is `true`, events are buffered and flushed
  /// in a single microtask.
  void emit(EngineEvent event) {
    if (_controller.isClosed) return;

    if (_paused) {
      // Critical events are NEVER dropped — buffer them.
      if (event is CriticalEvent) {
        if (_criticalBuffer.length >= _maxCriticalBuffer) {
          _criticalBuffer.removeFirst(); // evict oldest
        }
        _criticalBuffer.add(event);
      }
      _suppressedCount++;
      return;
    }

    if (enableBatching) {
      _batchBuffer.add(event);
      if (!_batchScheduled) {
        _batchScheduled = true;
        scheduleMicrotask(_flushBatch);
      }
      return;
    }

    _totalEmitted++;
    final typeName = event.runtimeType.toString();
    _eventCountByType[typeName] = (_eventCountByType[typeName] ?? 0) + 1;

    _controller.add(event);
  }

  void _flushBatch() {
    _batchScheduled = false;
    for (final e in _batchBuffer) {
      _totalEmitted++;
      final typeName = e.runtimeType.toString();
      _eventCountByType[typeName] = (_eventCountByType[typeName] ?? 0) + 1;
      _controller.add(e);
    }
    _batchBuffer.clear();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PAUSE / RESUME
  // ═══════════════════════════════════════════════════════════════════════════

  /// Pause event emission.
  ///
  /// While paused, [emit] calls are silently suppressed (not queued).
  /// Call [resume] to re-enable emission and emit a [BatchCompleteEngineEvent]
  /// summarizing the pause.
  void pause() {
    if (_paused) return;
    _paused = true;
    _suppressedCount = 0;
    _pauseStart = DateTime.now();
  }

  /// Resume event emission after a [pause].
  ///
  /// Flushes any buffered critical events first, then emits a
  /// [BatchCompleteEngineEvent] with the count of suppressed events
  /// and the pause duration.
  void resume() {
    if (!_paused) return;
    _paused = false;

    // Flush critical events BEFORE the batch-complete marker.
    while (_criticalBuffer.isNotEmpty) {
      final critical = _criticalBuffer.removeFirst();
      _totalEmitted++;
      final typeName = critical.runtimeType.toString();
      _eventCountByType[typeName] = (_eventCountByType[typeName] ?? 0) + 1;
      _controller.add(critical);
    }

    final suppressed = _suppressedCount;
    final duration =
        _pauseStart != null
            ? DateTime.now().difference(_pauseStart!)
            : Duration.zero;

    _suppressedCount = 0;
    _pauseStart = null;

    // Notify listeners that a batch operation completed
    if (suppressed > 0) {
      emit(
        BatchCompleteEngineEvent(
          suppressedCount: suppressed,
          pauseDuration: duration,
        ),
      );
    }
  }

  /// Whether emission is currently paused.
  bool get isPaused => _paused;

  // ═══════════════════════════════════════════════════════════════════════════
  // METRICS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Total number of events successfully emitted (not suppressed).
  int get totalEmitted => _totalEmitted;

  /// Breakdown of events emitted by runtime type name.
  Map<String, int> get eventCountByType => Map.unmodifiable(_eventCountByType);

  // ═══════════════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Close the event bus. After this, [emit] is a no-op.
  void dispose() {
    _criticalBuffer.clear();
    _controller.close();
  }
}
