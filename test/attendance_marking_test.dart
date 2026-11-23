// Тесты ключевой логики отметок посещаемости.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yavka/data/attendance_controller.dart';
import 'support/demo_roster.dart';
import 'package:yavka/main.dart';
import 'package:yavka/models/attendance_session.dart';
import 'package:yavka/screens/attendance_screen.dart';

/// Фиксированный понедельник: тесты не зависят от дня недели запуска
/// (в выходные отметки запрещены).
final kMonday = DateTime(2026, 11, 9);

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(412, 1200);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppRoot(
      attendance: AttendanceController(
        session: AttendanceSession(
          groupName: demoGroupName,
          students: demoStudents,
          date: kMonday,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Список группы отображается, студент выбран по умолчанию', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester);

    expect(find.text('Группа БИТ-24-03'), findsOneWidget);
    expect(find.text('Алексей Морозов'), findsOneWidget);
    expect(find.text('Отметить: Алексей Морозов'), findsOneWidget);
  });

  testWidgets('Отметка «Пришёл» применяется к выбранному студенту', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester);

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
    await _pumpApp(tester);

    await tester.tap(find.text('Мария Соколова'));
    await tester.pumpAndSettle();
    expect(find.text('Отметить: Мария Соколова'), findsOneWidget);

    await tester.tap(find.text('Опоздал'));
    await tester.pumpAndSettle();

    // Первый клик — пустой «опоздал»: времени ещё нет.
    expect(
      find.descendant(
        of: find.byKey(kStudentListKey),
        matching: find.text('без времени'),
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

  testWidgets('Повторный клик по «Опоздал» ставит время', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester);

    await tester.tap(find.text('Опоздал').last);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(kStudentListKey),
        matching: find.text('без времени'),
      ),
      findsOneWidget,
    );

    // Кнопка «Опоздал» и статус-чип в строке называются одинаково —
    // тапаем по кнопке (она последняя в дереве).
    await tester.tap(find.text('Опоздал').last);
    await tester.pumpAndSettle();

    // «Без времени» сменилось на время вида «Ч:ММ».
    expect(
      find.descendant(
        of: find.byKey(kStudentListKey),
        matching: find.text('без времени'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(kStudentListKey),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              RegExp(r'^\d{1,2}:\d{2}$').hasMatch(widget.data ?? ''),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('«Непришёл» требует подтверждения, но времени у него нет', (
    WidgetTester tester,
  ) async {
    await _pumpApp(tester);

    // Первое нажатие — предупреждение.
    await tester.tap(find.text('Непришёл'));
    await tester.pumpAndSettle();
    expect(find.text('Второе нажатие подтвердит отсутствие.'), findsOneWidget);

    // Второе нажатие отмечает сразу: диалога времени у «Непришёл» нет.
    await tester.tap(find.text('Непришёл'));
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
