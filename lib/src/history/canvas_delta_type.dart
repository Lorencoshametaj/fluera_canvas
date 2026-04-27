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
  strokeAdded,
  strokeRemoved,
  shapeAdded,
  shapeRemoved,
  textAdded,
  textRemoved,
  textUpdated,
  imageAdded,
  imageRemoved,
  imageUpdated,
  layerAdded,
  layerRemoved,
  layerModified,
  layerCleared,
  adjustmentAdded,
  adjustmentRemoved,
  adjustmentUpdated,
}
