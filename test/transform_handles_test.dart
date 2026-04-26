import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'package:fluera_canvas/src/canvas/selection/transform_handles.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' show Matrix4;

void main() {
  // ── Translation ─────────────────────────────────────────────────────
  group('TransformMath.translation', () {
    test('translates by (dx, dy) in matrix [12]/[13]', () {
      final m = TransformMath.translation(10, -7);
      expect(m.storage[12], 10);
      expect(m.storage[13], -7);
    });

    test('axis-lock collapses the smaller axis', () {
      final mx = TransformMath.translation(20, 5, axisLock: true);
      expect(mx.storage[12], 20);
      expect(mx.storage[13], 0);
      final my = TransformMath.translation(3, -15, axisLock: true);
      expect(my.storage[12], 0);
      expect(my.storage[13], -15);
    });
  });

  // ── Corner scale ────────────────────────────────────────────────────
  group('TransformMath.cornerScale', () {
    final bounds = const Rect.fromLTRB(0, 0, 100, 50);

    test('uniform corner drag picks the dominant magnitude per axis', () {
      // bottom-right anchor = topLeft (0,0). Drag bottom-right from
      // (100, 50) to (200, 60) — sx would be 2, sy would be 1.2.
      // Uniform = both become ±2, signs preserved.
      final r = TransformMath.cornerScale(
        originalBounds: bounds,
        grabbed: SelectionHandle.bottomRight,
        pointer: const Offset(200, 60),
        uniform: true,
      );
      expect(r.sx, closeTo(2.0, 1e-6));
      expect(r.sy, closeTo(2.0, 1e-6));
      expect(r.anchor, const Offset(0, 0));
    });

    test('non-uniform corner drag respects each axis independently', () {
      final r = TransformMath.cornerScale(
        originalBounds: bounds,
        grabbed: SelectionHandle.bottomRight,
        pointer: const Offset(150, 75),
        uniform: false,
      );
      expect(r.sx, closeTo(1.5, 1e-6));
      expect(r.sy, closeTo(1.5, 1e-6));
    });

    test('topLeft drag flips signs when crossing the opposite corner', () {
      final r = TransformMath.cornerScale(
        originalBounds: bounds,
        grabbed: SelectionHandle.topLeft,
        pointer: const Offset(150, 75),
        uniform: false,
      );
      // topLeft anchor = bottomRight (100, 50). dx_orig = 0-100=-100,
      // dx_new = 150-100=50. sx = -0.5. sy similarly = -0.5.
      expect(r.sx, closeTo(-0.5, 1e-6));
      expect(r.sy, closeTo(-0.5, 1e-6));
      expect(r.anchor, const Offset(100, 50));
    });
  });

  // ── Edge scale ──────────────────────────────────────────────────────
  group('TransformMath.edgeScale', () {
    final bounds = const Rect.fromLTRB(0, 0, 100, 50);

    test('topMid drag: only sy changes, anchor at bottom-mid', () {
      final r = TransformMath.edgeScale(
        originalBounds: bounds,
        grabbed: SelectionHandle.topMid,
        pointer: const Offset(50, -25),
      );
      expect(r.sx, 1.0);
      expect(r.sy, closeTo(1.5, 1e-6));
      expect(r.anchor, const Offset(50, 50));
    });

    test('midRight drag: only sx changes, anchor at mid-left', () {
      final r = TransformMath.edgeScale(
        originalBounds: bounds,
        grabbed: SelectionHandle.midRight,
        pointer: const Offset(150, 25),
      );
      expect(r.sx, closeTo(1.5, 1e-6));
      expect(r.sy, 1.0);
      expect(r.anchor, const Offset(0, 25));
    });
  });

  // ── Rotation ────────────────────────────────────────────────────────
  group('TransformMath.rotationDelta', () {
    test('quarter turn from east to north → +π/2 (CCW in math, CW visually)',
        () {
      final delta = TransformMath.rotationDelta(
        center: Offset.zero,
        anchor: const Offset(10, 0),
        pointer: const Offset(0, 10),
      );
      expect(delta, closeTo(math.pi / 2, 1e-9));
    });

    test('snap15 quantises to 15° steps', () {
      // 22° actual -> snaps to 15°.
      final raw = TransformMath.rotationDelta(
        center: Offset.zero,
        anchor: const Offset(10, 0),
        pointer: Offset(
          10 * math.cos(22 * math.pi / 180),
          10 * math.sin(22 * math.pi / 180),
        ),
      );
      final snapped = TransformMath.rotationDelta(
        center: Offset.zero,
        anchor: const Offset(10, 0),
        pointer: Offset(
          10 * math.cos(22 * math.pi / 180),
          10 * math.sin(22 * math.pi / 180),
        ),
        snap15: true,
      );
      expect(raw, isNot(closeTo(15 * math.pi / 180, 1e-3)));
      expect(snapped, closeTo(15 * math.pi / 180, 1e-9));
    });
  });

  // ── Mirror ──────────────────────────────────────────────────────────
  group('TransformMath.mirror', () {
    test('mirrorH around x=50 reflects (10,?) to (90,?)', () {
      final m = TransformMath.mirrorH(50);
      final out = _applyTo(m, const Offset(10, 7));
      expect(out.dx, closeTo(90, 1e-6));
      expect(out.dy, closeTo(7, 1e-6));
    });

    test('mirrorV around y=20 reflects (?, 5) to (?, 35)', () {
      final m = TransformMath.mirrorV(20);
      final out = _applyTo(m, const Offset(13, 5));
      expect(out.dy, closeTo(35, 1e-6));
      expect(out.dx, closeTo(13, 1e-6));
    });
  });

  // ── Handle hit-test ─────────────────────────────────────────────────
  group('TransformMath.hitTestHandle', () {
    final bounds = const Rect.fromLTRB(0, 0, 100, 50);

    test('exact handle center hits the corresponding handle', () {
      expect(
        TransformMath.hitTestHandle(bounds, const Offset(0, 0), 1.0),
        SelectionHandle.topLeft,
      );
      expect(
        TransformMath.hitTestHandle(bounds, const Offset(50, 0), 1.0),
        SelectionHandle.topMid,
      );
      expect(
        TransformMath.hitTestHandle(bounds, const Offset(100, 50), 1.0),
        SelectionHandle.bottomRight,
      );
    });

    test('point well outside any handle returns null', () {
      expect(
        TransformMath.hitTestHandle(bounds, const Offset(50, 25), 1.0),
        isNull,
      );
    });

    test('rotate handle sits 24 / scale above topMid', () {
      // At scale=1 → 24 px above top-mid (50, -24). Sample exactly there.
      expect(
        TransformMath.hitTestHandle(bounds, const Offset(50, -24), 1.0),
        SelectionHandle.rotate,
      );
    });

    test('hit zone scales inversely with camera scale', () {
      // At zoom-in (scale=4), the handle pickup zone shrinks to
      // 12/4 = 3 world units. A 5-world-unit offset misses now even
      // though it would have hit at scale=1.
      expect(
        TransformMath.hitTestHandle(bounds, const Offset(5, 0), 1.0),
        SelectionHandle.topLeft,
      );
      expect(
        TransformMath.hitTestHandle(bounds, const Offset(5, 0), 4.0),
        isNull,
      );
    });
  });

  // ── Mode lookup ─────────────────────────────────────────────────────
  group('TransformMath.modeForHandle', () {
    test('corners → scaleCorner, edges → scaleEdge, rotate → rotate', () {
      expect(
        TransformMath.modeForHandle(SelectionHandle.topRight),
        TransformMode.scaleCorner,
      );
      expect(
        TransformMath.modeForHandle(SelectionHandle.midRight),
        TransformMode.scaleEdge,
      );
      expect(
        TransformMath.modeForHandle(SelectionHandle.rotate),
        TransformMode.rotate,
      );
    });
  });
}

Offset _applyTo(Matrix4 m, Offset p) {
  final s = m.storage;
  // 4x4 column-major homogeneous transform on (x, y, 0, 1).
  final x = s[0] * p.dx + s[4] * p.dy + s[12];
  final y = s[1] * p.dx + s[5] * p.dy + s[13];
  return Offset(x, y);
}
