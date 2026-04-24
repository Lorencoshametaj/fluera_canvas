import 'package:flutter_test/flutter_test.dart';

import 'package:fluera_canvas_example/main.dart';

void main() {
  testWidgets('example app boots and shows the Clear FAB', (tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('Clear'), findsOneWidget);
  });
}
