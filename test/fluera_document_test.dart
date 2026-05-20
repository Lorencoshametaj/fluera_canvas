// Tests for the 0.14.0 FlueraDocument model — dirty flag, autosave
// debounce, save/load round-trip, metadata copyWith / fromJson.

import 'dart:typed_data';
import 'dart:ui';

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlueraDocumentMeta', () {
    test('copyWith preserves unspecified fields', () {
      const base = FlueraDocumentMeta(
        id: 'note-42',
        title: 'Original',
        tags: ['draft'],
      );
      final updated = base.copyWith(title: 'Renamed');
      expect(updated.id, 'note-42');
      expect(updated.title, 'Renamed');
      expect(updated.tags, ['draft']);
    });

    test('toJson / fromJson round-trip', () {
      final original = FlueraDocumentMeta(
        id: 'doc-1',
        title: 'Hello',
        createdAt: DateTime.utc(2026, 4, 28, 12, 0, 0),
        modifiedAt: DateTime.utc(2026, 4, 28, 12, 5, 0),
        tags: const ['important', 'shared'],
      );
      final restored = FlueraDocumentMeta.fromJson(original.toJson());
      expect(restored, original);
    });
  });

  group('FlueraDocument', () {
    testWidgets('dirty flag flips on first stroke commit', (tester) async {
      final canvasKey = GlobalKey<FlueraCanvasState>();
      // Long debounce ensures the autosave Timer never fires during the
      // test body — the dispose() at the end cancels it cleanly so the
      // framework's "no pending timers" invariant stays green.
      final doc = FlueraDocument(
        canvasKey: canvasKey,
        meta: const FlueraDocumentMeta(id: 'test-doc'),
        autosaveDebounce: const Duration(seconds: 60),
        onAutoSave: (_, __) async {},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: FlueraCanvas(key: canvasKey),
            ),
          ),
        ),
      );
      await tester.pump();
      doc.wire();
      expect(doc.isDirty, isFalse);
      canvasKey.currentState!.pushStroke(
        CanvasStroke(
          points: const [Offset(10, 10), Offset(20, 20)],
          pressures: const [0.5, 0.5],
          color: const Color(0xFF000000),
          baseWidth: 2,
        ),
      );
      await tester.pump();
      expect(doc.isDirty, isTrue);
      doc.dispose();
    });

    testWidgets('save() writes bytes via callback and clears dirty', (
      tester,
    ) async {
      final canvasKey = GlobalKey<FlueraCanvasState>();
      Uint8List? captured;
      FlueraDocumentMeta? capturedMeta;
      final doc = FlueraDocument(
        canvasKey: canvasKey,
        meta: const FlueraDocumentMeta(id: 'doc-x', title: 'X'),
        autosaveDebounce: const Duration(seconds: 60), // never trips
        onAutoSave: (bytes, meta) async {
          captured = bytes;
          capturedMeta = meta;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: FlueraCanvas(key: canvasKey),
            ),
          ),
        ),
      );
      await tester.pump();
      doc.wire();
      canvasKey.currentState!.pushStroke(
        CanvasStroke(
          points: const [Offset(0, 0), Offset(50, 50)],
          pressures: const [0.5, 0.5],
          color: const Color(0xFF1A1A1A),
          baseWidth: 3,
        ),
      );
      await tester.pump();
      expect(doc.isDirty, isTrue);
      await doc.save();
      expect(captured, isNotNull);
      expect(captured!.length, greaterThan(8)); // FCV0 magic + version
      expect(capturedMeta?.id, 'doc-x');
      expect(capturedMeta?.modifiedAt, isNotNull);
      expect(doc.isDirty, isFalse);
      doc.dispose();
    });

    testWidgets('load() hydrates the canvas and clears dirty', (tester) async {
      // Two documents: docA writes, docB loads back.
      final keyA = GlobalKey<FlueraCanvasState>();
      Uint8List? blob;
      FlueraDocumentMeta savedMeta = const FlueraDocumentMeta(id: 'hello');
      final docA = FlueraDocument(
        canvasKey: keyA,
        meta: savedMeta,
        autosaveDebounce: const Duration(seconds: 60),
        onAutoSave: (bytes, meta) async {
          blob = bytes;
          savedMeta = meta;
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: FlueraCanvas(key: keyA),
            ),
          ),
        ),
      );
      await tester.pump();
      docA.wire();
      keyA.currentState!.pushStroke(
        CanvasStroke(
          points: const [Offset(0, 0), Offset(40, 40)],
          pressures: const [0.5, 0.5],
          color: const Color(0xFFE53935),
          baseWidth: 2,
        ),
      );
      await tester.pump();
      await docA.save();
      expect(blob, isNotNull);

      // Now mount docB pointing at a fresh canvas, hand over the blob.
      final keyB = GlobalKey<FlueraCanvasState>();
      final docB = FlueraDocument(
        canvasKey: keyB,
        onAutoLoad: () async => (bytes: blob!, meta: savedMeta),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: FlueraCanvas(key: keyB),
            ),
          ),
        ),
      );
      await tester.pump();
      await docB.load();
      expect(docB.meta.id, 'hello');
      expect(docB.isDirty, isFalse);
      expect(keyB.currentState!.strokes.length, 1);
      docA.dispose();
      docB.dispose();
    });
  });
}
