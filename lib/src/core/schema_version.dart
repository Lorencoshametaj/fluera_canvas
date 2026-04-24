import 'package:flutter/foundation.dart';

// =============================================================================
// 📋 SCHEMA VERSIONING — Document-level migration pipeline
// =============================================================================
//
// DESIGN PRINCIPLES:
// - Every serialized document carries a `version` field
// - Migrations are pure JSON→JSON transforms (no object instantiation)
// - Migrations run sequentially: v1→v2→v3→…→current
// - Forward-compatible: documents from newer versions throw a clear error
// - Each migration is a deterministic, idempotent function
// =============================================================================

/// Current document schema version.
///
/// **Increment this** whenever a breaking change is made to the serialization
/// format of any [CanvasNode], [SceneGraph], [NodeEffect], or model class.
///
/// After incrementing, add a corresponding entry in [_migrations] that
/// transforms JSON from the previous version to the new one.
const int kCurrentSchemaVersion = 1;

/// Minimum schema version that this build can load.
///
/// Documents older than this cannot be migrated and will throw
/// [SchemaVersionException].
const int kMinSupportedSchemaVersion = 1;

/// A single migration step: transforms raw JSON from version N to N+1.
///
/// Must be a **pure function** — no side effects, no object instantiation.
/// The input JSON is the full document (top-level, including `'version'`).
/// The returned JSON must have `'version': N+1`.
typedef SchemaMigration =
    Map<String, dynamic> Function(Map<String, dynamic> json);

/// Registry of all migrations, keyed by **source** version.
///
/// The migration at key `N` transforms a document from version `N` to `N+1`.
///
/// Example:
/// ```dart
/// 1: (json) {
///   // Rename 'penType' → 'brushType' in all stroke nodes
///   _walkNodes(json, (node) {
///     if (node['nodeType'] == 'stroke') {
///       final stroke = node['stroke'] as Map<String, dynamic>?;
///       if (stroke != null && stroke.containsKey('penType')) {
///         stroke['brushType'] = stroke.remove('penType');
///       }
///     }
///   });
///   json['version'] = 2;
///   return json;
/// },
/// ```
final Map<int, SchemaMigration> _migrations = {
  // No migrations yet — version 1 is the baseline.
  // When the first breaking change happens, add:
  //   1: (json) { /* transform v1 → v2 */ json['version'] = 2; return json; },
};

// =============================================================================
// Public API
// =============================================================================

/// Migrate a serialized document to the current schema version.
///
/// If the document is already at [kCurrentSchemaVersion], returns it unchanged.
/// If the document is from a **newer** version (future app), throws
/// [SchemaVersionException].
/// If the document has no version field, assumes version 1 (legacy).
///
/// Migrations are applied sequentially: v1 → v2 → v3 → … → current.
///
/// ```dart
/// final json = await loadFromDisk();
/// final migrated = migrateDocument(json);
/// final graph = SceneGraph.fromJson(migrated);
/// ```
Map<String, dynamic> migrateDocument(Map<String, dynamic> json) {
  final int docVersion = (json['version'] as int?) ?? 1;

  // Forward compatibility check: can't load documents from the future
  if (docVersion > kCurrentSchemaVersion) {
    throw SchemaVersionException(
      documentVersion: docVersion,
      currentVersion: kCurrentSchemaVersion,
      message:
          'Document was created with a newer version of the engine '
          '(v$docVersion). This build supports up to v$kCurrentSchemaVersion. '
          'Please update the app.',
    );
  }

  // Too old to migrate
  if (docVersion < kMinSupportedSchemaVersion) {
    throw SchemaVersionException(
      documentVersion: docVersion,
      currentVersion: kCurrentSchemaVersion,
      message:
          'Document schema v$docVersion is too old. '
          'Minimum supported version is v$kMinSupportedSchemaVersion.',
    );
  }

  // Already current — no migration needed
  if (docVersion == kCurrentSchemaVersion) return json;

  // Run migrations sequentially
  var migrated = Map<String, dynamic>.from(json);
  for (int v = docVersion; v < kCurrentSchemaVersion; v++) {
    final migration = _migrations[v];
    if (migration == null) {
      throw SchemaVersionException(
        documentVersion: v,
        currentVersion: kCurrentSchemaVersion,
        message:
            'Missing migration from v$v to v${v + 1}. '
            'This is a bug — please report it.',
      );
    }
    migrated = migration(migrated);
    assert(
      (migrated['version'] as int?) == v + 1,
      'Migration v$v → v${v + 1} did not update the version field.',
    );
  }

  return migrated;
}

/// Check if a document's version is supported without migrating.
///
/// Returns `null` if the version is valid, or a human-readable error message
/// if the document cannot be loaded.
String? validateDocumentVersion(Map<String, dynamic> json) {
  final int docVersion = (json['version'] as int?) ?? 1;

  if (docVersion > kCurrentSchemaVersion) {
    return 'Document requires engine v$docVersion, '
        'but this build only supports v$kCurrentSchemaVersion.';
  }
  if (docVersion < kMinSupportedSchemaVersion) {
    return 'Document v$docVersion is too old. '
        'Minimum supported: v$kMinSupportedSchemaVersion.';
  }
  return null;
}

/// Returns the schema version of a serialized document.
///
/// Legacy documents without a version field default to 1.
int documentVersion(Map<String, dynamic> json) =>
    (json['version'] as int?) ?? 1;

// =============================================================================
// Utility for migrations
// =============================================================================

/// Walk all node JSON objects in a scene graph document.
///
/// Calls [visitor] for every node in the layer tree (depth-first).
/// Useful in migration functions to transform node-level fields.
void walkNodes(
  Map<String, dynamic> json,
  void Function(Map<String, dynamic> node) visitor,
) {
  final sgData = json['sceneGraph'] as Map<String, dynamic>?;
  if (sgData == null) return;

  final layers = sgData['layers'] as List<dynamic>? ?? [];
  for (final layer in layers) {
    if (layer is Map<String, dynamic>) {
      _walkNodeTree(layer, visitor);
    }
  }
}

void _walkNodeTree(
  Map<String, dynamic> node,
  void Function(Map<String, dynamic> node) visitor,
) {
  visitor(node);
  final children = node['children'] as List<dynamic>?;
  if (children != null) {
    for (final child in children) {
      if (child is Map<String, dynamic>) {
        _walkNodeTree(child, visitor);
      }
    }
  }
}

// =============================================================================
// Exception
// =============================================================================

/// Thrown when a document cannot be loaded due to version incompatibility.
class SchemaVersionException implements Exception {
  /// The version found in the document.
  final int documentVersion;

  /// The current engine schema version.
  final int currentVersion;

  /// Human-readable explanation.
  final String message;

  const SchemaVersionException({
    required this.documentVersion,
    required this.currentVersion,
    required this.message,
  });

  @override
  String toString() =>
      'SchemaVersionException: $message '
      '(document: v$documentVersion, engine: v$currentVersion)';
}
