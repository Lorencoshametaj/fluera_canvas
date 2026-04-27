/// Engine-wide event hierarchy for the centralized [EngineEventBus].
///
/// All events that flow through the bus extend [EngineEvent] and carry
/// a timestamp, source identifier, and domain classification.
///
/// Subsystem-specific events are grouped by [EventDomain]:
/// - [sceneGraph] — node additions, removals, property changes
/// - [selection]  — selection changes
/// - [variable]   — design variable value changes
/// - [memory]     — memory pressure and eviction
/// - [error]      — error reports
/// - [custom]     — plugin-emitted events
/// - [bus]        — internal bus control events
/// - [command]    — command history execute/undo/redo
library;

import 'package:fluera_canvas/fluera_canvas.dart';

// =============================================================================
// EVENT DOMAIN
// =============================================================================

/// Classification of an event's origin subsystem.
enum EventDomain {
  /// Scene graph structural changes (add, remove, reorder, property change).
  sceneGraph,

  /// Selection manager changes.
  selection,

  /// Design variable / token value changes.
  variable,

  /// Memory pressure, eviction, and budget events.
  memory,

  /// Error reports funnelled through [ErrorRecoveryService].
  error,

  /// Plugin-emitted custom events.
  custom,

  /// Internal bus control events (e.g. batch complete).
  bus,

  /// Command history events (execute, undo, redo).
  command,

  /// Accessibility tree changes.
  accessibility,

  /// Animation playback events.
  animation,

  /// Intelligence subsystem events (Conscious Architecture cross-layer).
  intelligence,
}

// =============================================================================
// BASE EVENT
// =============================================================================

/// Base class for all events flowing through [EngineEventBus].
///
/// Every event carries:
/// - [timestamp] — when it was created
/// - [source]    — human-readable origin (e.g. `'SceneGraph'`)
/// - [domain]    — which subsystem produced it
abstract class EngineEvent {
  /// When the event was created.
  final DateTime timestamp;

  /// Human-readable source identifier.
  final String source;

  /// Which subsystem produced this event.
  final EventDomain domain;

  /// API element `source`.
  EngineEvent({required this.source, required this.domain})
    : timestamp = DateTime.now();
}

/// Marker mixin for events that must **never** be silently dropped.
///
/// During an [EngineEventBus] pause, best-effort events are suppressed,
/// but events marked with [CriticalEvent] are buffered and flushed
/// on resume. Use this for error reports, integrity violations,
/// and other non-lossy diagnostics.
mixin CriticalEvent on EngineEvent {}

// =============================================================================
// SCENE GRAPH EVENTS
// =============================================================================

/// A node was added to the scene graph.
class NodeAddedEngineEvent extends EngineEvent {
  /// Field `node`.
  final CanvasNode node;
  /// Field `parentId`.
  final String parentId;

  /// API element `node`.
  NodeAddedEngineEvent({required this.node, required this.parentId})
    : super(source: 'SceneGraph', domain: EventDomain.sceneGraph);
}

/// A node was removed from the scene graph.
class NodeRemovedEngineEvent extends EngineEvent {
  /// Field `node`.
  final CanvasNode node;
  /// Field `parentId`.
  final String parentId;

  /// API element `node`.
  NodeRemovedEngineEvent({required this.node, required this.parentId})
    : super(source: 'SceneGraph', domain: EventDomain.sceneGraph);
}

/// A node's property changed.
class NodePropertyChangedEngineEvent extends EngineEvent {
  /// Field `node`.
  final CanvasNode node;
  /// Field `property`.
  final String property;

  /// API element `node`.
  NodePropertyChangedEngineEvent({required this.node, required this.property})
    : super(source: 'SceneGraph', domain: EventDomain.sceneGraph);
}

/// Children were reordered within a group.
class NodeReorderedEngineEvent extends EngineEvent {
  /// Field `parentId`.
  final String parentId;
  /// Field `oldIndex`.
  final int oldIndex;
  /// Field `newIndex`.
  final int newIndex;

  /// API element `NodeReorderedEngineEvent`.
  NodeReorderedEngineEvent({
    required this.parentId,
    required this.oldIndex,
    required this.newIndex,
  }) : super(source: 'SceneGraph', domain: EventDomain.sceneGraph);
}

// =============================================================================
// SELECTION EVENTS
// =============================================================================

/// The selection changed.
class SelectionChangedEngineEvent extends EngineEvent {
  /// Kind of change (selected, deselected, cleared, replaced).
  final String changeType;

  /// IDs of nodes affected by this change.
  final List<String> affectedIds;

  /// Total number of selected nodes after this change.
  final int totalSelected;

  /// API element `SelectionChangedEngineEvent`.
  SelectionChangedEngineEvent({
    required this.changeType,
    required this.affectedIds,
    required this.totalSelected,
  }) : super(source: 'SelectionManager', domain: EventDomain.selection);
}

// =============================================================================
// DESIGN VARIABLE EVENTS
// =============================================================================

/// A design variable value changed.
class VariableChangedEngineEvent extends EngineEvent {
  /// ID of the variable that changed.
  final String variableId;

  /// Mode that was affected (or `null` for variable-level changes).
  final String? modeId;

  /// The property that changed (e.g. 'value', 'name', 'alias').
  final String property;

  /// The old value.
  final dynamic oldValue;

  /// The new value.
  final dynamic newValue;

  /// API element `VariableChangedEngineEvent`.
  VariableChangedEngineEvent({
    required this.variableId,
    this.modeId,
    required this.property,
    this.oldValue,
    this.newValue,
  }) : super(source: 'DesignVariable', domain: EventDomain.variable);
}

// =============================================================================
// MEMORY EVENTS
// =============================================================================

/// Memory pressure level changed or eviction was performed.
class MemoryPressureEngineEvent extends EngineEvent {
  /// Current pressure level name (normal, warning, critical).
  final String level;

  /// Total estimated memory usage in MB.
  final double totalEstimatedMB;

  /// Budget cap in MB.
  final int budgetCapMB;

  /// API element `MemoryPressureEngineEvent`.
  MemoryPressureEngineEvent({
    required this.level,
    required this.totalEstimatedMB,
    required this.budgetCapMB,
  }) : super(source: 'MemoryBudgetController', domain: EventDomain.memory);
}

// =============================================================================
// ERROR EVENTS
// =============================================================================

/// An error was reported through [ErrorRecoveryService].
///
/// Marked as [CriticalEvent] — never silently dropped during bus pause.
class ErrorReportedEngineEvent extends EngineEvent with CriticalEvent {
  /// The classified engine error.
  final EngineError error;

  /// API element `error`.
  ErrorReportedEngineEvent({required this.error})
    : super(source: 'ErrorRecoveryService', domain: EventDomain.error);
}

// =============================================================================
// CUSTOM / PLUGIN EVENTS
// =============================================================================

/// A custom event emitted by a plugin.
class CustomPluginEngineEvent extends EngineEvent {
  /// The emitting plugin's ID.
  final String pluginId;

  /// Plugin-defined event name.
  final String name;

  /// Optional payload data.
  final Map<String, dynamic>? data;

  /// API element `CustomPluginEngineEvent`.
  CustomPluginEngineEvent({
    required this.pluginId,
    required this.name,
    this.data,
  }) : super(source: 'Plugin:$pluginId', domain: EventDomain.custom);
}

// =============================================================================
// BUS CONTROL EVENTS
// =============================================================================

/// Emitted when a paused event bus resumes.
class BatchCompleteEngineEvent extends EngineEvent {
  /// Number of events that were suppressed during the pause.
  final int suppressedCount;

  /// How long the pause lasted.
  final Duration pauseDuration;

  /// API element `BatchCompleteEngineEvent`.
  BatchCompleteEngineEvent({
    required this.suppressedCount,
    required this.pauseDuration,
  }) : super(source: 'EngineEventBus', domain: EventDomain.bus);
}

// =============================================================================
// COMMAND EVENTS
// =============================================================================

/// A command was executed through [CommandHistory].
class CommandExecutedEngineEvent extends EngineEvent {
  /// Human-readable label of the executed command.
  final String commandLabel;

  /// Runtime type name of the command (for telemetry).
  final String commandType;

  /// API element `CommandExecutedEngineEvent`.
  CommandExecutedEngineEvent({
    required this.commandLabel,
    required this.commandType,
  }) : super(source: 'CommandHistory', domain: EventDomain.command);
}

/// A command was undone through [CommandHistory].
class CommandUndoneEngineEvent extends EngineEvent {
  /// Human-readable label of the undone command.
  final String commandLabel;

  /// Runtime type name of the command (for telemetry).
  final String commandType;

  /// API element `CommandUndoneEngineEvent`.
  CommandUndoneEngineEvent({
    required this.commandLabel,
    required this.commandType,
  }) : super(source: 'CommandHistory', domain: EventDomain.command);
}

// =============================================================================
// ACCESSIBILITY EVENTS
// =============================================================================

/// The accessibility tree was rebuilt after a scene graph change.
class AccessibilityTreeChangedEvent extends EngineEvent {
  /// Number of accessible nodes in the new tree.
  final int nodeCount;

  /// API element `nodeCount`.
  AccessibilityTreeChangedEvent({required this.nodeCount})
    : super(source: 'AccessibilityBridge', domain: EventDomain.accessibility);
}

// =============================================================================
// ANIMATION EVENTS
// =============================================================================

/// Animation playback started.
class AnimationPlaybackStartedEvent extends EngineEvent {
  /// Method `AnimationPlaybackStartedEvent`.
  AnimationPlaybackStartedEvent()
    : super(source: 'AnimationPlayer', domain: EventDomain.animation);
}

/// Animation playback stopped (either completed or explicitly stopped).
class AnimationPlaybackStoppedEvent extends EngineEvent {
  /// Whether playback completed naturally (reached end) vs. was stopped.
  final bool completed;

  /// API element `completed`.
  AnimationPlaybackStoppedEvent({required this.completed})
    : super(source: 'AnimationPlayer', domain: EventDomain.animation);
}

/// An animation frame was applied to the scene graph.
class AnimationFrameEvent extends EngineEvent {
  /// Current playback time.
  final Duration time;

  /// API element `time`.
  AnimationFrameEvent({required this.time})
    : super(source: 'AnimationPlayer', domain: EventDomain.animation);
}

// =============================================================================
// INTELLIGENCE EVENTS (Conscious Architecture)
// =============================================================================

/// AdaptiveProfile recommendations changed after context updates.
class ProfileRecommendationsChangedEvent extends EngineEvent {
  /// Current stabilizer level recommendation (0-3).
  final int stabilizerLevel;

  /// Current tile prefetch bias.
  final double prefetchBias;

  /// API element `ProfileRecommendationsChangedEvent`.
  ProfileRecommendationsChangedEvent({
    required this.stabilizerLevel,
    required this.prefetchBias,
  }) : super(source: 'ConsciousArchitecture', domain: EventDomain.intelligence);
}

/// DesignLinter completed a lint pass and found violations.
class LintCompletedEvent extends EngineEvent {
  /// Number of violations found.
  final int violationCount;

  /// API element `violationCount`.
  LintCompletedEvent({required this.violationCount})
    : super(source: 'ConsciousArchitecture', domain: EventDomain.intelligence);
}

/// SmartSnap threshold was adapted by the Conscious Architecture.
class SnapThresholdChangedEvent extends EngineEvent {
  /// New threshold in canvas pixels.
  final double threshold;

  /// API element `threshold`.
  SnapThresholdChangedEvent({required this.threshold})
    : super(source: 'ConsciousArchitecture', domain: EventDomain.intelligence);
}
