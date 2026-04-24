/// Severity of a system memory-pressure signal forwarded to canvas
/// components (cache managers, GPU renderers) so they can release
/// transient resources on demand.
enum MemoryPressureLevel {
  /// Normal operation — caches may run at full capacity.
  normal,

  /// Warning — shed roughly half of caches / tile buffers.
  warning,

  /// Critical — free as much as possible, keep only the working set.
  critical,
}
