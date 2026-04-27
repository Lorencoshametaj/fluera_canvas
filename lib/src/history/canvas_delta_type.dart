/// Type of incremental canvas mutation.
///
/// Used by both the engine-side [CanvasDeltaTracker] (transient WAL) and the
/// `fluera_canvas_gpu` time-travel recorder (permanent session log). Lives in
/// the free `fluera_canvas` package because the enum index is serialized to
/// disk, so its identity must be stable across the canvas / canvas_gpu /
/// engine boundary.
///
/// Adding new values is a backward-compatible change as long as new entries
/// are appended to the end (existing files use `index` to deserialize).
enum CanvasDeltaType {
  /// Enum value `strokeAdded`.
  strokeAdded,
  /// Enum value `strokeRemoved`.
  strokeRemoved,
  /// Enum value `shapeAdded`.
  shapeAdded,
  /// Enum value `shapeRemoved`.
  shapeRemoved,
  /// Enum value `textAdded`.
  textAdded,
  /// Enum value `textRemoved`.
  textRemoved,
  /// Enum value `textUpdated`.
  textUpdated,
  /// Enum value `imageAdded`.
  imageAdded,
  /// Enum value `imageRemoved`.
  imageRemoved,
  /// Enum value `imageUpdated`.
  imageUpdated,
  /// Enum value `layerAdded`.
  layerAdded,
  /// Enum value `layerRemoved`.
  layerRemoved,
  /// Enum value `layerModified`.
  layerModified,
  /// Enum value `layerCleared`.
  layerCleared,
  /// Enum value `adjustmentAdded`.
  adjustmentAdded,
  /// Enum value `adjustmentRemoved`.
  adjustmentRemoved,
  /// Enum value `adjustmentUpdated`.
  adjustmentUpdated,
}
