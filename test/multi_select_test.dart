// Тесты отмены отметки и множественного выбора.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yavka/data/attendance_controller.dart';
import 'support/demo_roster.dart';
import 'package:yavka/main.dart';
import 'package:yavka/models/attendance_session.dart';
import 'package:yavka/screens/attendance_screen.dart';

Future<void> _pumpTall(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(412, 1300);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppRoot(
      // Фиксированный понедельник: в выходные отметки запрещены.
      attendance: AttendanceController(
        session: AttendanceSession(
          groupName: demoGroupName,
          students: demoStudents,
          date: DateTime(2026, 11, 9),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _inList(Finder matching) =>
    find.descendant(of: find.byKey(kStudentListKey), matching: matching);

void main() {
  testWidgets('Кнопка «Отменить отметку» снимает отметку', (tester) async {
    await _pumpTall(tester);

    await tester.tap(find.text('Пришёл'));
    await tester.pumpAndSettle();
    expect(_inList(find.text('Пришёл')), findsOneWidget);
    expect(find.text('Отменить отметку'), findsOneWidget);

    await tester.tap(find.text('Отменить отметку'));
    await tester.pumpAndSettle();

    expect(_inList(find.text('Пришёл')), findsNothing);
    expect(find.text('Отменить отметку'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('student-1')),
        matching: find.text('нет отметки'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Множественный выбор: «Выбрать всех» и общая отметка', (
    tester,
  ) async {
    await _pumpTall(tester);

    await tester.tap(find.byIcon(Icons.library_add_check_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Выбрано: 1'), findsOneWidget);

    await tester.tap(find.text('Выбрать всех'));
    await tester.pumpAndSettle();
    expect(find.text('Выбрано: 10'), findsOneWidget);

    await tester.tap(find.text('Пришёл'));
    await tester.pumpAndSettle();

    // Все 10 строк построены (высокий экран) и отмечены.
    // В этом режиме статус виден в подписи строки: «Пришёл» — без
    // времени, время есть только у опоздания.
    expect(_inList(find.textContaining('Пришёл')), findsNWidgets(10));
    expect(_inList(find.text('нет отметки')), findsNothing);
    expect(find.text('10 из 10'), findsOneWidget);
  });

  testWidgets('Множественный выбор: ручной выбор нескольких', (tester) async {
    await _pumpTall(tester);

    await tester.tap(find.byIcon(Icons.library_add_check_outlined));
    await tester.pumpAndSettle();
    // Первый студент уже выбран при входе в режим.
    expect(find.text('Выбрано: 1'), findsOneWidget);

    await tester.tap(find.text('Дмитрий Волков'));
    await tester.pumpAndSettle();
    expect(find.text('Выбрано: 2'), findsOneWidget);

    await tester.tap(find.text('Опоздал'));
    await tester.pumpAndSettle();

    expect(_inList(find.textContaining('Опоздал')), findsNWidgets(2));
    // Второй студент (Мария) не был выбран — у него отметки нет.
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('student-2')),
        matching: find.text('нет отметки'),
      ),
      findsOneWidget,
    );
    expect(find.text('2 из 10'), findsOneWidget);

    // Выход из режима возвращает одиночный выбор.
    await tester.tap(find.byTooltip('Выйти из множественного выбора'));
    await tester.pumpAndSettle();
    expect(find.text('Выбрано: 2'), findsNothing);
  });
}
