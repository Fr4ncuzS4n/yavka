// Тесты скелета экрана отметки посещаемости.

import 'package:flutter_test/flutter_test.dart';

import 'package:yavka/main.dart';

void main() {
  testWidgets('Attendance screen renders marking buttons', (
    WidgetTester tester,
  ) async {
    // Build the app and trigger a frame.
    await tester.pumpWidget(const AppRoot());

    // Verify that all four marking buttons are present.
    expect(find.text('Пришёл'), findsOneWidget);
    expect(find.text('Непришёл'), findsOneWidget);
    expect(find.text('Опоздал'), findsOneWidget);
    expect(find.text('По уважительной'), findsOneWidget);
  });
}
