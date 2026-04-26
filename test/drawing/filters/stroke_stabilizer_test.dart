import 'package:flutter_test/flutter_test.dart';
import 'package:fluera_canvas/fluera_canvas.dart';

void main() {
  group('StrokeStabilizer', () {
    group('level 0 (passthrough)', () {
      test('returns raw point unchanged', () {
        final stabilizer = StrokeStabilizer(level: 0);
        const raw = Offset(100, 200);
        expect(stabilizer.stabilize(raw), raw);
      });

      test('returns every point unchanged for sequence', () {
        final stabilizer = StrokeStabilizer(level: 0);
        final points = [
          const Offset(0, 0),
          const Offset(10, 10),
          const Offset(20, 20),
        ];
        for (final p in points) {
          expect(stabilizer.stabilize(p), p);
        }
      });
    });

    group('level > 0 (stabilized)', () {
      test('first point is returned unchanged', () {
        final stabilizer = StrokeStabilizer(level: 5);
        const first = Offset(100, 100);
        expect(stabilizer.stabilize(first), first);
      });

      test('tremor within string length is filtered out', () {
        final stabilizer = StrokeStabilizer(level: 5);
        // String length for level 5 = 20px
        const anchor = Offset(100, 100);
        stabilizer.stabilize(anchor); // Set anchor

        // Small movement (2px) — within string length of 20px
        // Lazy follow may move slightly toward the raw point
        final result = stabilizer.stabilize(const Offset(102, 100));
        expect(result.dx, closeTo(100.0, 1.0)); // Barely moves
        expect(result.dy, closeTo(100.0, 0.01));
      });

      test('large movement exceeds string length', () {
        final stabilizer = StrokeStabilizer(level: 5);
        // String length for level 5 = 20px
        const anchor = Offset(100, 100);
        stabilizer.stabilize(anchor);

        // Large movement (50px) — well beyond string length of 20px
        final result = stabilizer.stabilize(const Offset(150, 100));
        // Should move towards the target but not reach it
        expect(result.dx, greaterThan(100));
        expect(result.dx, lessThan(150));
        expect(result.dy, 100); // No vertical movement
      });

      test('higher level means more lag/smoothing', () {
        final low = StrokeStabilizer(level: 1);
        final high = StrokeStabilizer(level: 10);
        const anchor = Offset(100, 100);
        const target = Offset(200, 100);

        low.stabilize(anchor);
        high.stabilize(anchor);

        final lowResult = low.stabilize(target);
        final highResult = high.stabilize(target);

        // Low level should move closer to target than high level
        expect(lowResult.dx, greaterThan(highResult.dx));
      });

      test('consecutive close movements smooth out noise', () {
        final stabilizer = StrokeStabilizer(level: 3);
        stabilizer.stabilize(const Offset(100, 100));

        // Zig-zag noise pattern
        final r1 = stabilizer.stabilize(const Offset(120, 105));
        final r2 = stabilizer.stabilize(const Offset(140, 95));
        final r3 = stabilizer.stabilize(const Offset(160, 102));

        // Verify all results are smoothed (between anchor and target)
        expect(r1.dx, greaterThan(100));
        expect(r2.dx, greaterThan(r1.dx));
        expect(r3.dx, greaterThan(r2.dx));
      });
    });

    group('level clamping', () {
      test('negative level clamped to 0', () {
        final stabilizer = StrokeStabilizer(level: -5);
        expect(stabilizer.level, 0);
      });

      test('level > 10 clamped to 10', () {
        final stabilizer = StrokeStabilizer(level: 15);
        expect(stabilizer.level, 10);
      });

      test('level setter clamps', () {
        final stabilizer = StrokeStabilizer(level: 5);
        stabilizer.level = 20;
        expect(stabilizer.level, 10);
        stabilizer.level = -1;
        expect(stabilizer.level, 0);
      });
    });

    group('reset', () {
      test('resets anchor position', () {
        final stabilizer = StrokeStabilizer(level: 5);
        stabilizer.stabilize(const Offset(100, 100));
        stabilizer.stabilize(const Offset(200, 200));

        stabilizer.reset();

        // After reset, next point should be returned as-is (new anchor)
        const newStart = Offset(50, 50);
        expect(stabilizer.stabilize(newStart), newStart);
      });
    });

    group('string length', () {
      test('level 1 has shorter string than level 10', () {
        final low = StrokeStabilizer(level: 1);
        final high = StrokeStabilizer(level: 10);

        // Both anchored at same point
        low.stabilize(const Offset(0, 0));
        high.stabilize(const Offset(0, 0));

        // Move 10px — should be within high's string but may exceed low's
        // Level 1 string = 4px, Level 10 string = 40px
        final lowResult = low.stabilize(const Offset(10, 0));
        final highResult = high.stabilize(const Offset(10, 0));

        // Low level should have moved more than high level
        expect(lowResult.dx, greaterThan(0));
        // High level with lazy follow may move slightly, but much less
        expect(lowResult.dx, greaterThan(highResult.dx));
      });
    });

    group('diagonal movement', () {
      test('stabilizes in both axes', () {
        final stabilizer = StrokeStabilizer(level: 3);
        stabilizer.stabilize(const Offset(0, 0));

        final result = stabilizer.stabilize(const Offset(50, 50));
        expect(result.dx, greaterThan(0));
        expect(result.dy, greaterThan(0));
        // Both should be proportionally smoothed
        expect(result.dx, closeTo(result.dy, 0.001));
      });
    });
  });
}
