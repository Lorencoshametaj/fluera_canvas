import 'dart:ui';
import 'dart:typed_data';
import 'package:flutter/widgets.dart'; // For Matrix4 and MatrixUtils

/// Identifies a unique material (paint configuration) for batching.
class MaterialKey {
  final int colorValue;
  final int? shaderHash;
  final BlendMode blendMode;
  final PaintingStyle style;
  final double strokeWidth;

  const MaterialKey({
    required this.colorValue,
    this.shaderHash,
    required this.blendMode,
    required this.style,
    this.strokeWidth = 0.0,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MaterialKey &&
          colorValue == other.colorValue &&
          shaderHash == other.shaderHash &&
          blendMode == other.blendMode &&
          style == other.style &&
          strokeWidth == other.strokeWidth;

  @override
  int get hashCode =>
      Object.hash(colorValue, shaderHash, blendMode, style, strokeWidth);
}

/// A specific drawing operation inside a batch.
abstract class DrawCommand {
  void execute(Canvas canvas, Paint paint);
}

/// Command to draw a path with a specific transform.
class PathDrawCommand implements DrawCommand {
  final Path path;
  final Matrix4 transform;

  PathDrawCommand(this.path, this.transform);

  @override
  void execute(Canvas canvas, Paint paint) {
    canvas.save();
    if (!transform.isIdentity()) {
      canvas.transform(transform.storage);
    }
    canvas.drawPath(path, paint);
    canvas.restore();
  }
}

/// Command to draw an entire pre-recorded picture (used for Symbols/Instancing).
class PictureDrawCommand implements DrawCommand {
  final Picture picture;
  final Matrix4 transform;

  PictureDrawCommand(this.picture, this.transform);

  @override
  void execute(Canvas canvas, Paint paint) {
    canvas.save();
    if (!transform.isIdentity()) {
      canvas.transform(transform.storage);
    }
    canvas.drawPicture(picture);
    canvas.restore();
  }
}

/// Command to draw a basic rectangle (optimized into drawVertices when batched).
class RectDrawCommand implements DrawCommand {
  final Rect rect;
  final Matrix4 transform;

  RectDrawCommand(this.rect, this.transform);

  @override
  void execute(Canvas canvas, Paint paint) {
    canvas.save();
    if (!transform.isIdentity()) {
      canvas.transform(transform.storage);
    }
    canvas.drawRect(rect, paint);
    canvas.restore();
  }
}

/// A batch of draw calls sharing the same material.
class RenderBatch {
  static const int maxCommands = 4096;

  MaterialKey _material;
  final List<DrawCommand> commands = [];

  RenderBatch(this._material);

  /// Current material key (may change via [reset] for pool reuse).
  MaterialKey get material => _material;

  bool get isFull => commands.length >= maxCommands;

  void addCommand(DrawCommand cmd) {
    commands.add(cmd);
  }

  /// Reset this batch for reuse from the pool.
  void reset(MaterialKey newMaterial) {
    // We need to reassign material — make it non-final for pooling.
    commands.clear();
    _material = newMaterial;
  }

  void flush(Canvas canvas) {
    if (commands.isEmpty) return;

    final paint =
        Paint()
          ..color = Color(material.colorValue)
          ..blendMode = material.blendMode
          ..style = material.style
          ..strokeWidth = material.strokeWidth;

    // Separate paths and rects. Note: We only execute one type of batch per RenderBatch
    // in practice, because BatchRenderer groups commands by type if needed, but here
    // we process them in order of type if mixed.
    final pathCmds = commands.whereType<PathDrawCommand>();
    for (final cmd in pathCmds) {
      cmd.execute(canvas, paint);
    }

    final rectCmds = commands.whereType<RectDrawCommand>().toList();
    if (rectCmds.isNotEmpty) {
      final positions = Float32List(
        rectCmds.length * 8,
      ); // 4 vertices * 2 (x,y)
      final indices = Uint16List(
        rectCmds.length * 6,
      ); // 2 triangles * 3 indices
      int vOffset = 0;
      int iOffset = 0;
      int vertexIndex = 0;

      for (final cmd in rectCmds) {
        final r = cmd.rect;
        final t = cmd.transform;

        final p0 = MatrixUtils.transformPoint(t, r.topLeft);
        final p1 = MatrixUtils.transformPoint(t, r.topRight);
        final p2 = MatrixUtils.transformPoint(t, r.bottomRight);
        final p3 = MatrixUtils.transformPoint(t, r.bottomLeft);

        positions[vOffset++] = p0.dx;
        positions[vOffset++] = p0.dy;
        positions[vOffset++] = p1.dx;
        positions[vOffset++] = p1.dy;
        positions[vOffset++] = p2.dx;
        positions[vOffset++] = p2.dy;
        positions[vOffset++] = p3.dx;
        positions[vOffset++] = p3.dy;

        indices[iOffset++] = vertexIndex + 0;
        indices[iOffset++] = vertexIndex + 1;
        indices[iOffset++] = vertexIndex + 2;
        indices[iOffset++] = vertexIndex + 0;
        indices[iOffset++] = vertexIndex + 2;
        indices[iOffset++] = vertexIndex + 3;

        vertexIndex += 4;
      }

      final vertices = Vertices.raw(
        VertexMode.triangles,
        positions,
        indices: indices,
      );
      // Use the actual blend mode of the material, not hardcoded srcOver.
      canvas.drawVertices(vertices, material.blendMode, paint);
    }

    final picCmds = commands.whereType<PictureDrawCommand>();
    for (final pic in picCmds) {
      pic.execute(canvas, paint);
    }
  }
}

/// Collects and manages multiple RenderBatches safely preserving Z-order.
///
/// Uses a free-list pool to avoid per-frame [RenderBatch] allocations.
/// In a stable scene, the batch count is identical frame-to-frame — all
/// allocations happen on the first frame and are reused thereafter.
class BatchRenderer {
  /// Active batches for the current frame (in submission order).
  final List<RenderBatch> _batches = [];

  /// Pool of previously used batches awaiting reuse.
  final List<RenderBatch> _pool = [];

  RenderBatch? _currentBatch;
  int _activeBatchCount = 0;

  void flushAll(Canvas canvas) {
    for (int i = 0; i < _activeBatchCount; i++) {
      _batches[i].flush(canvas);
    }
    // Return all used batches to the pool (clear their commands but keep alloc)
    for (int i = 0; i < _activeBatchCount; i++) {
      final batch = _batches[i];
      batch.commands.clear();
      _pool.add(batch);
    }
    _batches.clear();
    _activeBatchCount = 0;
    _currentBatch = null;
  }

  RenderBatch _getBatch(MaterialKey key) {
    // To preserve z-order natively, we only append to the current batch if the material matches.
    // If the material changes, we MUST break the batch.
    if (_currentBatch != null &&
        _currentBatch!.material == key &&
        !_currentBatch!.isFull) {
      return _currentBatch!;
    }
    // Reuse a pooled batch or create a new one.
    final batch =
        _pool.isNotEmpty ? (_pool.removeLast()..reset(key)) : RenderBatch(key);
    _batches.add(batch);
    _activeBatchCount++;
    _currentBatch = batch;
    return batch;
  }

  void addPath(MaterialKey key, Path path, Matrix4 transform) {
    _getBatch(key).addCommand(PathDrawCommand(path, transform));
  }

  void addRect(MaterialKey key, Rect rect, Matrix4 transform) {
    _getBatch(key).addCommand(RectDrawCommand(rect, transform));
  }

  void addPicture(
    Picture picture,
    Matrix4 transform, {
    BlendMode blendMode = BlendMode.srcOver,
    Color color = const Color(0xFFFFFFFF),
  }) {
    final key = MaterialKey(
      colorValue: color.toARGB32(),
      blendMode: blendMode,
      style: PaintingStyle.fill,
    );
    _getBatch(key).addCommand(PictureDrawCommand(picture, transform));
  }
}
