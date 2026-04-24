import 'dart:async';
import 'dart:collection';
import 'package:fluera_canvas/fluera_canvas.dart';
import '../engine_event_bus.dart';
import '../engine_event.dart';

// ---------------------------------------------------------------------------
// Scene Graph Events
// ---------------------------------------------------------------------------

/// Base class for all scene graph events.
abstract class SceneGraphEvent {
  /// Timestamp when the event was created.
  final DateTime timestamp = DateTime.now();
}

/// A node was added to the tree.
class NodeAddedEvent extends SceneGraphEvent {
  final CanvasNode node;
  final String parentId;
  NodeAddedEvent(this.node, this.parentId);
}

/// A node was removed from the tree.
class NodeRemovedEvent extends SceneGraphEvent {
  final CanvasNode node;
  final String parentId;
  NodeRemovedEvent(this.node, this.parentId);
}

/// A node's properties changed.
class NodeChangedEvent extends SceneGraphEvent {
  final CanvasNode node;
  final String property;
  NodeChangedEvent(this.node, this.property);
}

/// Children were reordered within a group.
class NodeReorderedEvent extends SceneGraphEvent {
  final String parentId;
  final int oldIndex;
  final int newIndex;
  NodeReorderedEvent(this.parentId, this.oldIndex, this.newIndex);
}

// ---------------------------------------------------------------------------
// Observer interface
// ---------------------------------------------------------------------------

/// Observer interface for scene graph structural changes.
///
/// Implement this to react to additions, removals, property changes,
/// and reorderings in the scene graph.
///
/// ```dart
/// class UndoTracker implements SceneGraphObserver {
///   @override
///   void onNodeAdded(CanvasNode node, String parentId) {
///     recordCommand(AddNodeCommand(node, parentId));
///   }
///   // ...
/// }
/// ```
abstract class SceneGraphObserver {
  /// Called when a node is added to the tree.
  void onNodeAdded(CanvasNode node, String parentId) {}

  /// Called when a node is removed from the tree.
  void onNodeRemoved(CanvasNode node, String parentId) {}

  /// Called when a node's property changes.
  void onNodeChanged(CanvasNode node, String property) {}

  /// Called when children are reordered.
  void onNodeReordered(String parentId, int oldIndex, int newIndex) {}
}

// ---------------------------------------------------------------------------
// Observer manager mixin
// ---------------------------------------------------------------------------

/// Mixin providing observer management and event stream capabilities.
///
/// Applied to [SceneGraph] to centralize notification dispatch.
mixin SceneGraphObservable {
  final List<SceneGraphObserver> _observers = [];

  /// Cached snapshot of observers, rebuilt on add/remove.
  ///
  /// Avoids allocating `List.of(_observers)` on every notification dispatch.
  List<SceneGraphObserver> _observerSnapshot = [];

  final StreamController<SceneGraphEvent> _eventController =
      StreamController<SceneGraphEvent>.broadcast();

  /// Optional reference to the centralized event bus.
  EngineEventBus? _engineEventBus;

  /// Optional reference to the telemetry bus.
  EngineTelemetry? _telemetry;

  /// Provides access to the event bus for transaction management.
  EngineEventBus? get engineEventBus => _engineEventBus;

  /// Provides access to telemetry for transaction span tracking.
  EngineTelemetry? get telemetryBus => _telemetry;

  // ---------------------------------------------------------------------------
  // Transaction-aware deferred notifications
  // ---------------------------------------------------------------------------

  /// When true, notifications are buffered instead of dispatched immediately.
  ///
  /// Used by [SceneGraphTransaction] to defer observer/event/bus
  /// notifications until commit, or discard them on rollback.
  bool _deferNotifications = false;

  /// Buffered notification callbacks, flushed on commit.
  final List<void Function()> _deferredCallbacks = [];

  /// Dedup keys for deferred property-change notifications.
  /// Prevents N changes to the same node+property from queuing N callbacks.
  final Set<String> _deferredChangeKeys = {};

  /// Whether notifications are currently being deferred.
  bool get isDeferringNotifications => _deferNotifications;

  // ---------------------------------------------------------------------------
  // Per-frame property-change coalescing
  // ---------------------------------------------------------------------------

  /// Whether automatic per-frame coalescing is enabled.
  ///
  /// When true, `notifyNodeChanged` calls outside a transaction are
  /// coalesced into a single microtask flush, eliminating observer storms
  /// from bulk property edits (e.g. apply-style-to-50-nodes).
  ///
  /// Structural changes (add/remove/reorder) are always dispatched
  /// immediately regardless of this flag.
  bool coalescingEnabled = true;

  /// Pending property changes keyed by node, coalesced until microtask flush.
  final Map<CanvasNode, Set<String>> _pendingChanges =
      LinkedHashMap<CanvasNode, Set<String>>();

  /// Whether a microtask flush has already been scheduled.
  bool _flushScheduled = false;

  /// Begin deferring all notifications.
  void beginDeferNotifications() => _deferNotifications = true;

  /// Flush all deferred notifications in order, then stop deferring.
  void flushDeferredNotifications() {
    _deferNotifications = false;
    for (final cb in _deferredCallbacks) {
      cb();
    }
    _deferredCallbacks.clear();
    _deferredChangeKeys.clear();
  }

  /// Discard all deferred notifications and stop deferring.
  void clearDeferredNotifications() {
    _deferNotifications = false;
    _deferredCallbacks.clear();
    _deferredChangeKeys.clear();
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Connect this observable to the centralized event bus.
  ///
  /// Once connected, all scene graph notifications are also emitted
  /// as typed [EngineEvent]s on the bus.
  void connectEventBus(EngineEventBus bus) => _engineEventBus = bus;

  /// Connect telemetry for transaction span tracking.
  void connectTelemetry(EngineTelemetry telemetry) => _telemetry = telemetry;

  /// Stream of all scene graph events (reactive alternative to observers).
  Stream<SceneGraphEvent> get events => _eventController.stream;

  /// Register an observer.
  void addObserver(SceneGraphObserver observer) {
    _observers.add(observer);
    _observerSnapshot = List.of(_observers);
  }

  /// Remove a previously registered observer.
  void removeObserver(SceneGraphObserver observer) {
    _observers.remove(observer);
    _observerSnapshot = List.of(_observers);
  }

  /// Notify all observers that a node was added.
  void notifyNodeAdded(CanvasNode node, String parentId) {
    if (_deferNotifications) {
      _deferredCallbacks.add(() => _dispatchNodeAdded(node, parentId));
      return;
    }
    _dispatchNodeAdded(node, parentId);
  }

  /// Notify all observers that a node was removed.
  void notifyNodeRemoved(CanvasNode node, String parentId) {
    if (_deferNotifications) {
      _deferredCallbacks.add(() => _dispatchNodeRemoved(node, parentId));
      return;
    }
    _dispatchNodeRemoved(node, parentId);
  }

  /// Notify all observers that a node's property changed.
  ///
  /// During a transaction, dedup is applied: only the **first** change
  /// to a given (nodeId, property) pair queues a callback.
  ///
  /// Outside a transaction with [coalescingEnabled], changes are coalesced
  /// and dispatched in a single microtask, eliminating observer storms.
  void notifyNodeChanged(CanvasNode node, String property) {
    if (_deferNotifications) {
      final key = '${node.id}:$property';
      if (_deferredChangeKeys.contains(key)) return; // dedup
      _deferredChangeKeys.add(key);
      _deferredCallbacks.add(() => _dispatchNodeChanged(node, property));
      return;
    }
    if (coalescingEnabled) {
      _pendingChanges.putIfAbsent(node, () => <String>{}).add(property);
      if (!_flushScheduled) {
        _flushScheduled = true;
        scheduleMicrotask(_flushPendingChanges);
      }
      return;
    }
    _dispatchNodeChanged(node, property);
  }

  /// Force-flush all coalesced property-change notifications immediately.
  ///
  /// Call this when you need observers to see changes synchronously
  /// (e.g. before reading derived state that depends on observer updates).
  void flushPendingChanges() {
    if (_pendingChanges.isEmpty) return;
    _flushPendingChanges();
  }

  /// Internal: dispatches all coalesced property changes.
  void _flushPendingChanges() {
    _flushScheduled = false;
    // Snapshot to allow re-entrant notifications during dispatch.
    final snapshot = Map<CanvasNode, Set<String>>.of(_pendingChanges);
    _pendingChanges.clear();
    for (final entry in snapshot.entries) {
      for (final prop in entry.value) {
        _dispatchNodeChanged(entry.key, prop);
      }
    }
  }

  /// Notify all observers that children were reordered.
  void notifyNodeReordered(String parentId, int oldIndex, int newIndex) {
    if (_deferNotifications) {
      _deferredCallbacks.add(
        () => _dispatchNodeReordered(parentId, oldIndex, newIndex),
      );
      return;
    }
    _dispatchNodeReordered(parentId, oldIndex, newIndex);
  }

  // ---------------------------------------------------------------------------
  // Private dispatch helpers
  // ---------------------------------------------------------------------------

  void _dispatchNodeAdded(CanvasNode node, String parentId) {
    for (final o in _observerSnapshot) {
      o.onNodeAdded(node, parentId);
    }
    _eventController.add(NodeAddedEvent(node, parentId));
    _engineEventBus?.emit(NodeAddedEngineEvent(node: node, parentId: parentId));
  }

  void _dispatchNodeRemoved(CanvasNode node, String parentId) {
    for (final o in _observerSnapshot) {
      o.onNodeRemoved(node, parentId);
    }
    _eventController.add(NodeRemovedEvent(node, parentId));
    _engineEventBus?.emit(
      NodeRemovedEngineEvent(node: node, parentId: parentId),
    );
  }

  void _dispatchNodeChanged(CanvasNode node, String property) {
    for (final o in _observerSnapshot) {
      o.onNodeChanged(node, property);
    }
    _eventController.add(NodeChangedEvent(node, property));
    _engineEventBus?.emit(
      NodePropertyChangedEngineEvent(node: node, property: property),
    );
  }

  void _dispatchNodeReordered(String parentId, int oldIndex, int newIndex) {
    for (final o in _observerSnapshot) {
      o.onNodeReordered(parentId, oldIndex, newIndex);
    }
    _eventController.add(NodeReorderedEvent(parentId, oldIndex, newIndex));
    _engineEventBus?.emit(
      NodeReorderedEngineEvent(
        parentId: parentId,
        oldIndex: oldIndex,
        newIndex: newIndex,
      ),
    );
  }

  /// Close the event stream and clear observers.
  void disposeObservable() {
    _deferredCallbacks.clear();
    _deferNotifications = false;
    _pendingChanges.clear();
    _flushScheduled = false;
    _eventController.close();
    _observers.clear();
  }
}
