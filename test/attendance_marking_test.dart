// Тесты ключевой логики отметок посещаемости.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yavka/main.dart';
import 'package:yavka/screens/attendance_screen.dart';

void main() {
  testWidgets('Список группы отображается, студент выбран по умолчанию', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AppRoot());
    await tester.pumpAndSettle();

    expect(find.text('Группа БИТ-24-03'), findsOneWidget);
    expect(find.text('Алексей Морозов'), findsOneWidget);
    expect(find.text('Отметить: Алексей Морозов'), findsOneWidget);
  });

  testWidgets('Отметка «Пришёл» применяется к выбранному студенту', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AppRoot());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Пришёл'));
    await tester.pumpAndSettle();

    // Отметка видна в строке первого студента в списке.
    expect(
      find.descendant(
        of: find.byKey(kStudentListKey),
        matching: find.text('Пришёл'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Другой студент выбирается по тапу и получает свою отметку', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AppRoot());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Мария Соколова'));
    await tester.pumpAndSettle();
    expect(find.text('Отметить: Мария Соколова'), findsOneWidget);

    await tester.tap(find.text('Опоздал'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(kStudentListKey),
        matching: find.text('Опоздал'),
      ),
      findsOneWidget,
    );
    // У первого студента отметки нет — его строка не изменилась.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('student-1')),
        matching: find.text('нет отметки'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('«Непришёл» требует подтверждения и выбора времени', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const AppRoot());
    await tester.pumpAndSettle();

    // Первое нажатие — предупреждение.
    await tester.tap(find.text('Непришёл'));
    await tester.pumpAndSettle();
    expect(
      find.text('Второе нажатие: выберите время или используйте текущее.'),
      findsOneWidget,
    );
    expect(find.byType(TimePickerDialog), findsNothing);

    // Второе нажатие — диалог времени.
    await tester.tap(find.text('Непришёл'));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);

    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(find.byType(TimePickerDialog), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(kStudentListKey),
        matching: find.text('Непришёл'),
      ),
      findsOneWidget,
    );
  });
}
