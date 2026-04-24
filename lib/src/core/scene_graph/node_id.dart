/// Strongly-typed scene graph node identifier.
///
/// Wraps a raw `String` as a zero-cost extension type, providing
/// compile-time safety without runtime overhead. Prevents accidental
/// misuse of arbitrary strings as node IDs.
///
/// ```dart
/// final id = NodeId('my-node');
///
/// // Compile error — can't pass a raw String where NodeId is expected:
/// // graph.findNodeById('oops');   // ← error
/// //
/// // Must be explicit:
/// graph.findNodeById(NodeId('my-node'));
/// ```
///
/// At runtime `NodeId` erases to [String] — zero allocation, zero overhead.
extension type const NodeId(String value) implements String {}
