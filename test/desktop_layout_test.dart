// Тесты десктопной раскладки экрана отметки: кнопки слева, список справа.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yavka/main.dart';
import 'package:yavka/screens/attendance_screen.dart';

/// variant: TargetPlatformVariant.desktop() запускает каждый тест
/// на Windows, Linux и macOS — то есть ровно на десктопных ОС.
void main() {
  testWidgets('На десктопе панель отметки слева, список справа', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AppRoot());
    await tester.pumpAndSettle();

    final panel = tester.getRect(find.byKey(kMarkingPanelKey));
    final list = tester.getRect(find.byKey(kStudentListKey));
    final windowWidth =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;

    expect(panel.right, lessThanOrEqualTo(list.left));
    // Панель фиксированной ширины, список занимает остальное окно.
    expect(panel.width, 320);
    expect(list.right, windowWidth);
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('На десктопе отметка «Пришёл» работает как обычно', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AppRoot());
    await tester.pumpAndSettle();

    expect(find.text('Отметить: Алексей Морозов'), findsOneWidget);

    await tester.tap(find.text('Пришёл'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(kStudentListKey),
        matching: find.text('Пришёл'),
      ),
      findsOneWidget,
    );
  }, variant: TargetPlatformVariant.desktop());

  testWidgets('На десктопе «Непришёл» требует подтверждения', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AppRoot());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Непришёл'));
    await tester.pumpAndSettle();
    expect(
      find.text('Второе нажатие: выберите время или используйте текущее.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Непришёл'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
  }, variant: TargetPlatformVariant.desktop());
}
