// ════════════════════════════════════════════════════════════════════════════
// 📄 FlueraDocument — opt-in document wrapper around FlueraCanvasState.
//
// Adds the production-grade plumbing every notes / whiteboard app
// ends up reinventing: stable id, title, created/modified timestamps,
// dirty flag, autosave debounce, single load entry-point. Lossless —
// the canvas state remains the source of truth (every byte goes
// through `state.toBytes()` / `state.loadFromBytes(...)`); this class
// just mediates *when* save is called and lets the consumer attach
// metadata that round-trips with the binary blob.
//
// Opt-in: not required. The pre-0.14 pattern (write FCV0 bytes
// yourself on stroke commit) keeps working. Use this when you want
// to skip writing the dirty-flag + debounce plumbing.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show GlobalKey;

import '../canvas/fluera_canvas_widget.dart';

/// Immutable document metadata — id, title, timestamps, tags. Stored
/// alongside the FCV0 binary blob via the autosave / load callbacks.
///
/// Added in 0.14.0.
@immutable
class FlueraDocumentMeta {
  /// Build new metadata. [id] is required and must be stable across
  /// loads — typically a UUID generated at document creation.
  const FlueraDocumentMeta({
    required this.id,
    this.title = '',
    this.createdAt,
    this.modifiedAt,
    this.tags = const [],
  });

  /// Stable identifier (UUID, slug, etc.). Cannot be empty.
  final String id;

  /// Human-readable title displayed in app chrome. May be empty for
  /// untitled documents — the consumer decides the placeholder.
  final String title;

  /// First-creation timestamp (UTC recommended). Persists through
  /// `toJson` / `fromJson`. `null` for legacy documents that were
  /// created before this metadata existed.
  final DateTime? createdAt;

  /// Last-modified timestamp; updated on every successful autosave.
  /// `null` until the first save.
  final DateTime? modifiedAt;

  /// Free-form labels for organisation / search. Round-trips as a
  /// JSON array.
  final List<String> tags;

  /// Returns a copy with the given fields replaced. Pass `null` to
  /// leave a field unchanged; use `const FlueraDocumentMeta(id: ...)`
  /// for a full reset.
  FlueraDocumentMeta copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? modifiedAt,
    List<String>? tags,
  }) {
    return FlueraDocumentMeta(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      tags: tags ?? this.tags,
    );
  }

  /// JSON-encodable representation. Use it as a sidecar file or fold
  /// into the host app's database row.
  Map<String, dynamic> toJson() => {
        'id': id,
        if (title.isNotEmpty) 'title': title,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (modifiedAt != null) 'modifiedAt': modifiedAt!.toIso8601String(),
        if (tags.isNotEmpty) 'tags': tags,
      };

  /// Inverse of [toJson]. Tolerant to missing optional keys.
  factory FlueraDocumentMeta.fromJson(Map<String, dynamic> j) {
    return FlueraDocumentMeta(
      id: j['id'] as String? ?? '',
      title: j['title'] as String? ?? '',
      createdAt: j['createdAt'] is String
          ? DateTime.tryParse(j['createdAt'] as String)
          : null,
      modifiedAt: j['modifiedAt'] is String
          ? DateTime.tryParse(j['modifiedAt'] as String)
          : null,
      tags: (j['tags'] as List?)?.cast<String>() ?? const [],
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FlueraDocumentMeta &&
      other.id == id &&
      other.title == title &&
      other.createdAt == createdAt &&
      other.modifiedAt == modifiedAt &&
      _listEquals(other.tags, tags);

  @override
  int get hashCode => Object.hash(
        id,
        title,
        createdAt,
        modifiedAt,
        Object.hashAll(tags),
      );

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Callback invoked when the document needs to persist itself. Given
/// the current [FCV0] bytes + metadata, the consumer chooses where /
/// how to store them (file system, cloud, IndexedDB on web, …).
typedef FlueraDocumentSaveCallback = Future<void> Function(
  Uint8List bytes,
  FlueraDocumentMeta meta,
);

/// Callback invoked at load time. Returns `null` if there's nothing
/// to load (first-time launch, deleted file, etc.). Otherwise must
/// return both the binary blob and the matching metadata.
typedef FlueraDocumentLoadCallback = Future<({
  Uint8List bytes,
  FlueraDocumentMeta meta,
})?> Function();

/// Document-aware wrapper around a [FlueraCanvas] mounted via
/// [GlobalKey]. Subscribes to the canvas's `historyListenable` so
/// every committed stroke flips the [isDirty] flag and starts /
/// resets the autosave debounce timer.
///
/// Typical wiring:
///
/// ```dart
/// final canvasKey = GlobalKey<FlueraCanvasState>();
/// final doc = FlueraDocument(
///   canvasKey: canvasKey,
///   meta: FlueraDocumentMeta(id: 'note-42', title: 'Meeting notes'),
///   onAutoSave: (bytes, meta) async {
///     final dir = await getApplicationDocumentsDirectory();
///     await File('${dir.path}/${meta.id}.fcv').writeAsBytes(bytes);
///   },
///   onAutoLoad: () async {
///     final dir = await getApplicationDocumentsDirectory();
///     final f = File('${dir.path}/note-42.fcv');
///     if (!f.existsSync()) return null;
///     return (bytes: await f.readAsBytes(), meta: doc.meta);
///   },
/// );
/// ```
///
/// Added in 0.14.0.
class FlueraDocument extends ChangeNotifier {
  /// Build a document bound to [canvasKey]. The canvas widget itself
  /// must be mounted before calling [load] — typically that's done
  /// inside a `addPostFrameCallback` from the host widget's `initState`.
  FlueraDocument({
    required this.canvasKey,
    FlueraDocumentMeta meta = const FlueraDocumentMeta(id: ''),
    Duration autosaveDebounce = const Duration(seconds: 2),
    FlueraDocumentSaveCallback? onAutoSave,
    FlueraDocumentLoadCallback? onAutoLoad,
  })  : _meta = meta,
        _autosaveDebounce = autosaveDebounce,
        _onAutoSave = onAutoSave,
        _onAutoLoad = onAutoLoad;

  /// Key of the [FlueraCanvas] this document mediates.
  final GlobalKey<FlueraCanvasState> canvasKey;

  FlueraDocumentMeta _meta;
  final Duration _autosaveDebounce;
  final FlueraDocumentSaveCallback? _onAutoSave;
  final FlueraDocumentLoadCallback? _onAutoLoad;

  bool _dirty = false;
  Timer? _autosaveTimer;
  bool _wired = false;

  /// Current document metadata.
  FlueraDocumentMeta get meta => _meta;

  /// `true` since the last successful save / load. Cleared by [save].
  bool get isDirty => _dirty;

  /// Replace the metadata. Notifies listeners; does NOT mark the
  /// document dirty (metadata is sidecar — only canvas content
  /// changes the binary blob).
  void setMeta(FlueraDocumentMeta next) {
    if (next == _meta) return;
    _meta = next;
    notifyListeners();
  }

  /// Force a save now. Cancels any pending debounced autosave and
  /// invokes [_onAutoSave] synchronously with the current canvas
  /// bytes + a meta whose `modifiedAt` is bumped to `DateTime.now()`.
  /// No-op if [_onAutoSave] wasn't provided.
  Future<void> save() async {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    final state = canvasKey.currentState;
    final cb = _onAutoSave;
    if (state == null || cb == null) return;
    final bytes = state.toBytes();
    final updated = _meta.copyWith(modifiedAt: DateTime.now());
    setMeta(updated);
    await cb(bytes, updated);
    _dirty = false;
    notifyListeners();
  }

  /// Run the consumer-provided [_onAutoLoad]. When it returns a
  /// payload, the canvas is hydrated via `loadFromBytes` and the
  /// document's metadata is replaced. No-op when [_onAutoLoad] wasn't
  /// provided or the callback returns `null`.
  Future<void> load() async {
    final cb = _onAutoLoad;
    if (cb == null) return;
    final result = await cb();
    if (result == null) return;
    final state = canvasKey.currentState;
    if (state == null) return;
    state.loadFromBytes(result.bytes);
    _meta = result.meta;
    _dirty = false;
    _ensureWired();
    notifyListeners();
  }

  /// Subscribes to the canvas's `historyListenable` (idempotent).
  /// Call this once after the canvas is mounted — typically inside
  /// the host widget's `initState`'s `addPostFrameCallback`.
  void wire() => _ensureWired();

  void _ensureWired() {
    if (_wired) return;
    final state = canvasKey.currentState;
    if (state == null) return;
    state.historyListenable.addListener(_onCanvasChanged);
    _wired = true;
  }

  void _onCanvasChanged() {
    if (!_dirty) {
      _dirty = true;
      notifyListeners();
    }
    _autosaveTimer?.cancel();
    if (_onAutoSave == null) return;
    _autosaveTimer = Timer(_autosaveDebounce, () {
      // Fire-and-forget — consumers handle their own errors inside
      // the callback. We can't usefully propagate exceptions from
      // a Timer callback.
      save();
    });
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    if (_wired) {
      final state = canvasKey.currentState;
      state?.historyListenable.removeListener(_onCanvasChanged);
    }
    super.dispose();
  }
}
