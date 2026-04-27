import 'dart:ui' show Color, Offset;

import 'package:fluera_canvas/fluera_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CanvasStroke makeStroke(int seed) => CanvasStroke(
    points: List<Offset>.unmodifiable([
      Offset(seed.toDouble(), 0),
      Offset(seed.toDouble() + 10, 10),
    ]),
    pressures: const [0.5, 0.7],
    color: Color(0xFF000000 + seed),
    baseWidth: 2.0,
  );

  Widget pump(GlobalKey<FlueraCanvasState> key) => MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 600, height: 400, child: FlueraCanvas(key: key)),
    ),
  );

  group('groupSelection', () {
    testWidgets('returns null on empty / single-node selection', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      expect(
        state.groupSelection(),
        isNull,
        reason: 'empty selection cannot be grouped',
      );
      state.pushStroke(makeStroke(1));
      state.selectInRect(const Rect.fromLTRB(-100, -100, 1000, 1000));
      expect(state.selection.length, 1);
      expect(
        state.groupSelection(),
        isNull,
        reason: 'single-node selection is a no-op',
      );
    });

    testWidgets('wraps 3 strokes into a single GroupNode + selects it', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStrokes([makeStroke(1), makeStroke(2), makeStroke(3)]);
      state.selectInRect(const Rect.fromLTRB(-100, -100, 1000, 1000));
      expect(state.selection.length, 3);

      final groupId = state.groupSelection();
      expect(groupId, isNotNull);
      // Selection swung to the new group; original strokes are no
      // longer in the selectable index (they live inside the group).
      expect(state.selection.ids, {groupId});
      expect(state.selection.length, 1);
      // Layer now has exactly ONE child: the group.
      expect(state.activeLayer.children, hasLength(1));
      expect(state.activeLayer.children.single, isA<GroupNode>());
      final group = state.activeLayer.children.single as GroupNode;
      expect(group.children, hasLength(3));
    });

    testWidgets('undo dissolves the group + restores original selection', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStrokes([makeStroke(1), makeStroke(2), makeStroke(3)]);
      state.selectInRect(const Rect.fromLTRB(-100, -100, 1000, 1000));
      final originalIds = state.selection.ids.toSet();
      state.groupSelection();
      expect(state.activeLayer.children, hasLength(1));

      expect(state.undo(), isTrue);
      expect(state.activeLayer.children, hasLength(3));
      expect(
        state.selection.ids,
        originalIds,
        reason: 'undo restores the original 3-node selection',
      );
    });
  });

  group('ungroupSelection', () {
    testWidgets('flattens a selected group + selects freed children', (
      tester,
    ) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStrokes([makeStroke(1), makeStroke(2)]);
      state.selectInRect(const Rect.fromLTRB(-100, -100, 1000, 1000));
      final originalIds = state.selection.ids.toSet();
      state.groupSelection();
      expect(state.activeLayer.children, hasLength(1));

      final freed = state.ungroupSelection();
      expect(freed, 1, reason: '1 group ungrouped');
      expect(state.activeLayer.children, hasLength(2));
      expect(state.selection.ids, originalIds);
    });

    testWidgets('returns 0 when no group is selected', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStrokes([makeStroke(1), makeStroke(2)]);
      state.selectInRect(const Rect.fromLTRB(-100, -100, 1000, 1000));
      // Selection contains strokes, not groups → 0.
      expect(state.ungroupSelection(), 0);
    });

    testWidgets('undo re-groups dissolved children', (tester) async {
      final key = GlobalKey<FlueraCanvasState>();
      await tester.pumpWidget(pump(key));
      final state = key.currentState!;
      state.pushStrokes([makeStroke(1), makeStroke(2)]);
      state.selectInRect(const Rect.fromLTRB(-100, -100, 1000, 1000));
      final groupId = state.groupSelection();
      state.ungroupSelection();
      expect(state.activeLayer.children, hasLength(2));

      expect(state.undo(), isTrue);
      expect(state.activeLayer.children, hasLength(1));
      expect(state.activeLayer.children.single, isA<GroupNode>());
      expect(state.selection.ids, {groupId});
    });
  });
}
