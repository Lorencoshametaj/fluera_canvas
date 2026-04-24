import 'canvas_node.dart';

// ---------------------------------------------------------------------------
// InterceptorResult
// ---------------------------------------------------------------------------

/// Result of a pre-mutation interceptor check.
sealed class InterceptorResult {
  const InterceptorResult();

  /// Allow the mutation to proceed.
  const factory InterceptorResult.allow() = _AllowResult;

  /// Reject the mutation with a reason.
  const factory InterceptorResult.reject(String reason) = _RejectResult;

  /// Allow with a transformed node (e.g., auto-rename).
  const factory InterceptorResult.transform(CanvasNode transformedNode) =
      _TransformResult;

  /// Whether this result allows the mutation.
  bool get isAllowed;

  /// Rejection reason, if any.
  String? get reason;

  /// Transformed node, if any.
  CanvasNode? get transformedNode;
}

class _AllowResult extends InterceptorResult {
  const _AllowResult();

  @override
  bool get isAllowed => true;

  @override
  String? get reason => null;

  @override
  CanvasNode? get transformedNode => null;
}

class _RejectResult extends InterceptorResult {
  final String _reason;
  const _RejectResult(this._reason);

  @override
  bool get isAllowed => false;

  @override
  String? get reason => _reason;

  @override
  CanvasNode? get transformedNode => null;
}

class _TransformResult extends InterceptorResult {
  final CanvasNode _node;
  const _TransformResult(this._node);

  @override
  bool get isAllowed => true;

  @override
  String? get reason => null;

  @override
  CanvasNode? get transformedNode => _node;
}

// ---------------------------------------------------------------------------
// MutationRejectedError
// ---------------------------------------------------------------------------

/// Thrown when a scene graph mutation is rejected by an interceptor.
class MutationRejectedError extends Error {
  /// Human-readable reason for rejection.
  final String reason;

  /// The interceptor that rejected the mutation.
  final String interceptorName;

  MutationRejectedError({required this.reason, required this.interceptorName});

  @override
  String toString() => 'MutationRejectedError: $reason (by $interceptorName)';
}

// ---------------------------------------------------------------------------
// SceneGraphInterceptor
// ---------------------------------------------------------------------------

/// Abstract pre-mutation hook for the scene graph.
///
/// Interceptors are called **before** a mutation is applied.
/// They can:
/// - **Allow** it (default)
/// - **Reject** it (throws [MutationRejectedError])
/// - **Transform** the node being mutated
///
/// ```dart
/// class NamingConventionInterceptor extends SceneGraphInterceptor {
///   @override
///   String get name => 'NamingConvention';
///
///   @override
///   InterceptorResult beforeAdd(CanvasNode node, String parentId) {
///     if (node.name.isEmpty) {
///       final renamed = node.clone()..name = 'Untitled ${node.runtimeType}';
///       return InterceptorResult.transform(renamed);
///     }
///     return const InterceptorResult.allow();
///   }
/// }
/// ```
abstract class SceneGraphInterceptor {
  /// Human-readable name (for error messages).
  String get name;

  /// Priority (lower = earlier in chain). Default: 100.
  int get priority => 100;

  /// Whether this interceptor is currently active.
  bool enabled = true;

  /// Called before a node is added to the tree.
  InterceptorResult beforeAdd(CanvasNode node, String parentId) =>
      const InterceptorResult.allow();

  /// Called before a node is removed from the tree.
  InterceptorResult beforeRemove(CanvasNode node, String parentId) =>
      const InterceptorResult.allow();

  /// Called before a node's property is changed.
  InterceptorResult beforePropertyChange(
    CanvasNode node,
    String property,
    dynamic newValue,
  ) => const InterceptorResult.allow();

  /// Called before children are reordered within a group.
  InterceptorResult beforeReorder(
    String parentId,
    int oldIndex,
    int newIndex,
  ) => const InterceptorResult.allow();
}

// ---------------------------------------------------------------------------
// InterceptorChain
// ---------------------------------------------------------------------------

/// Manages an ordered chain of [SceneGraphInterceptor]s.
///
/// Interceptors are run in priority order (lowest first).
/// The chain short-circuits on the first rejection.
class InterceptorChain {
  final List<SceneGraphInterceptor> _interceptors = [];

  /// Add an interceptor to the chain.
  void add(SceneGraphInterceptor interceptor) {
    _interceptors.add(interceptor);
    _interceptors.sort((a, b) => a.priority.compareTo(b.priority));
  }

  /// Remove an interceptor from the chain.
  void remove(SceneGraphInterceptor interceptor) {
    _interceptors.remove(interceptor);
  }

  /// All registered interceptors (read-only).
  List<SceneGraphInterceptor> get interceptors =>
      List.unmodifiable(_interceptors);

  /// Run `beforeAdd` through the chain.
  ///
  /// Returns the (possibly transformed) node, or throws
  /// [MutationRejectedError] if any interceptor rejects.
  CanvasNode runBeforeAdd(CanvasNode node, String parentId) {
    var current = node;
    for (final i in _interceptors) {
      if (!i.enabled) continue;
      final result = i.beforeAdd(current, parentId);
      if (!result.isAllowed) {
        throw MutationRejectedError(
          reason: result.reason ?? 'Rejected by ${i.name}',
          interceptorName: i.name,
        );
      }
      if (result.transformedNode != null) {
        current = result.transformedNode!;
      }
    }
    return current;
  }

  /// Run `beforeRemove` through the chain.
  void runBeforeRemove(CanvasNode node, String parentId) {
    for (final i in _interceptors) {
      if (!i.enabled) continue;
      final result = i.beforeRemove(node, parentId);
      if (!result.isAllowed) {
        throw MutationRejectedError(
          reason: result.reason ?? 'Rejected by ${i.name}',
          interceptorName: i.name,
        );
      }
    }
  }

  /// Run `beforePropertyChange` through the chain.
  void runBeforePropertyChange(
    CanvasNode node,
    String property,
    dynamic newValue,
  ) {
    for (final i in _interceptors) {
      if (!i.enabled) continue;
      final result = i.beforePropertyChange(node, property, newValue);
      if (!result.isAllowed) {
        throw MutationRejectedError(
          reason: result.reason ?? 'Rejected by ${i.name}',
          interceptorName: i.name,
        );
      }
    }
  }

  /// Run `beforeReorder` through the chain.
  void runBeforeReorder(String parentId, int oldIndex, int newIndex) {
    for (final i in _interceptors) {
      if (!i.enabled) continue;
      final result = i.beforeReorder(parentId, oldIndex, newIndex);
      if (!result.isAllowed) {
        throw MutationRejectedError(
          reason: result.reason ?? 'Rejected by ${i.name}',
          interceptorName: i.name,
        );
      }
    }
  }

  /// Clear all interceptors.
  void clear() => _interceptors.clear();
}

// ---------------------------------------------------------------------------
// Built-in: LockInterceptor
// ---------------------------------------------------------------------------

/// Prevents modification of locked nodes.
///
/// Blocks `remove` and `propertyChange` on nodes where
/// [CanvasNode.isLocked] is `true`.
class LockInterceptor extends SceneGraphInterceptor {
  @override
  String get name => 'LockInterceptor';

  @override
  int get priority => 0; // Run first — locks override everything.

  @override
  InterceptorResult beforeRemove(CanvasNode node, String parentId) {
    if (node.isLocked) {
      return InterceptorResult.reject(
        'Cannot remove locked node "${node.name}" (${node.id})',
      );
    }
    return const InterceptorResult.allow();
  }

  @override
  InterceptorResult beforePropertyChange(
    CanvasNode node,
    String property,
    dynamic newValue,
  ) {
    // Allow unlocking even on locked nodes.
    if (property == 'isLocked') return const InterceptorResult.allow();

    if (node.isLocked) {
      return InterceptorResult.reject(
        'Cannot modify "$property" on locked node "${node.name}" (${node.id})',
      );
    }
    return const InterceptorResult.allow();
  }
}
