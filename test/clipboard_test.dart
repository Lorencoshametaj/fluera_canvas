// Tests for the 0.13.0 clipboard API on FlueraCanvasState.
//
// We mock the platform Clipboard channel so the tests are
// deterministic + work in `flutter test` (which has no real OS
// clipboard wired by default).

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // In-memory clipboard backing the platform channel mock.
  String? _clipboardText;

  setUp(() {
    _clipboardText = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<dynamic, dynamic>;
        _clipboardText = args['text'] as String?;
        return null;
      }
      if (call.method == 'Clipboard.getData') {
        // Match real platform semantics: return null when nothing is
        // on the clipboard rather than a Map with a null `text` field.
        if (_clipboardText == null) return null;
        return <String, dynamic>{'text': _clipboardText};
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<FlueraCanvasState> _pumpCanvas(WidgetTester tester) async {
    final canvasKey = GlobalKey<FlueraCanvasState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: FlueraCanvas(key: canvasKey),
          ),
        ),
      ),
    );
    await tester.pump();
    return canvasKey.currentState!;
  }

  testWidgets('copySelection no-op when selection is empty', (tester) async {
    final state = await _pumpCanvas(tester);
    await state.copySelection();
    expect(_clipboardText, isNull);
  });

  testWidgets('copy → paste round-trips a stroke into the canvas', (
    tester,
  ) async {
    final state = await _pumpCanvas(tester);
    state.pushStroke(
      CanvasStroke(
        points: const [Offset(10, 10), Offset(60, 60)],
        pressures: const [0.5, 0.7],
        color: const Color(0xFFE53935),
        baseWidth: 3,
      ),
    );
    await tester.pump();
    final beforeCount = state.strokes.length;

    // Select everything, copy, then paste at world (0, 0).
    state.selectInRect(const Rect.fromLTWH(-1000, -1000, 2000, 2000));
    await tester.pump();
    await state.copySelection();
    expect(_clipboardText, startsWith('FLUERA_CLIPBOARD_V1:'));

    final newIds = await state.pasteFromClipboard(
      worldPosition: const Offset(0, 0),
    );
    await tester.pump();
    expect(newIds, isNotEmpty);
    expect(state.strokes.length, beforeCount + 1);
  });

  testWidgets('paste with empty / non-fluera clipboard returns []', (
    tester,
  ) async {
    final state = await _pumpCanvas(tester);
    // Empty clipboard.
    expect(await state.pasteFromClipboard(), isEmpty);
    // Foreign content.
    _clipboardText = 'just some random copied text from another app';
    expect(await state.pasteFromClipboard(), isEmpty);
  });

  // Regression: 0.16.2 fix — pasted strokes must preserve the
  // tilts / twists / metadata channels added in 0.14.0. Pre-fix the
  // paste path silently dropped them, mutating calligraphy strokes
  // round-tripped through the clipboard.
  testWidgets('paste preserves tilts / twists / metadata channels', (
    tester,
  ) async {
    final state = await _pumpCanvas(tester);
    state.pushStroke(
      CanvasStroke(
        points: const [Offset(10, 10), Offset(60, 60)],
        pressures: const [0.5, 0.7],
        color: const Color(0xFF1A1A1A),
        baseWidth: 3,
        tilts: const [Offset(0.1, 0.2), Offset(0.3, 0.4)],
        twists: const [0.5, 0.6],
        metadata: const {'author': 'lorenzo', 'replay-ms': 1234},
      ),
    );
    await tester.pump();

    state.selectInRect(const Rect.fromLTWH(-1000, -1000, 2000, 2000));
    await tester.pump();
    await state.copySelection();

    final newIds = await state.pasteFromClipboard(
      worldPosition: const Offset(0, 0),
    );
    await tester.pump();
    expect(newIds, hasLength(1));

    final pasted = state.strokes.last;
    expect(pasted.tilts, isNotNull);
    expect(pasted.tilts, hasLength(2));
    expect(pasted.tilts![0].dx, closeTo(0.1, 1e-6));
    expect(pasted.tilts![0].dy, closeTo(0.2, 1e-6));
    // FCV0 serialises twists as float32 — assert with tolerance.
    expect(pasted.twists, hasLength(2));
    expect(pasted.twists![0], closeTo(0.5, 1e-5));
    expect(pasted.twists![1], closeTo(0.6, 1e-5));
    expect(pasted.metadata?['author'], 'lorenzo');
    expect(pasted.metadata?['replay-ms'], 1234);
  });
}
