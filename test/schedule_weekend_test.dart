// Тесты расписания: отметки пар недоступны в выходные.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yavka/data/attendance_controller.dart';
import 'package:yavka/data/schedule_controller.dart';
import 'package:yavka/models/attendance_session.dart';
import 'package:yavka/models/schedule_lesson.dart';
import 'package:yavka/screens/schedule_screen.dart';

const kWeekendNotice = 'Сегодня выходной — отметки посещаемости недоступны.';

ScheduleController scheduleEveryDay() => ScheduleController(
  lessons: [
    for (var weekday = 1; weekday <= 7; weekday++)
      ScheduleLesson(
        id: 'lesson-$weekday',
        weekday: weekday,
        startMinutes: 9 * 60,
        subject: 'Пара $weekday',
      ),
  ],
);

Future<void> _pump(WidgetTester tester) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(412, 1300);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: ScheduleScreen(
        schedule: scheduleEveryDay(),
        attendance: AttendanceController(
          session: AttendanceSession(
            groupName: 'БИТ-24-03',
            date: DateTime(2026, 11, 9), // понедельник
            students: const [],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('вкладки воскресенья нет, на вкладке субботы нет кнопки «Отметить»', (
    tester,
  ) async {
    await _pump(tester);

    // Воскресенье не показывается вовсе — пары 7 не видно нигде.
    expect(find.text('вс'), findsNothing);
    expect(find.text('Пара 7'), findsNothing);

    await _openTab(tester, 'сб');
    expect(find.text('Отметить'), findsNothing);
    expect(find.text('Пара 6'), findsOneWidget);
  });

  testWidgets('на вкладке «сегодня»: чип отметки в будни, баннер в выходные', (
    tester,
  ) async {
    await _pump(tester);

    // Начальная вкладка — сегодняшний день недели (в воскресенье —
    // суббота, потому что вкладки воскресенья больше нет).
    final today = DateTime.now().weekday;
    if (today == DateTime.saturday) {
      expect(find.text(kWeekendNotice), findsOneWidget);
      expect(find.text('Отметить'), findsNothing);
    } else if (today == DateTime.sunday) {
      // Показана суббота, а не «сегодня»: баннера выходного нет.
      expect(find.text(kWeekendNotice), findsNothing);
      expect(find.text('Отметить'), findsNothing);
    } else {
      expect(find.text(kWeekendNotice), findsNothing);
      expect(find.text('Отметить'), findsOneWidget);
    }
  });

  testWidgets('в будний день, который не сегодня, отметки тоже недоступны', (
    tester,
  ) async {
    await _pump(tester);

    final today = DateTime.now().weekday;
    // Открываем первый будний день, который не сегодня.
    final otherWeekday = today == 1 ? 2 : 1;
    await _openTab(tester, otherWeekday == 1 ? 'пн' : 'вт');

    expect(find.text('Отметить'), findsNothing);
    // Баннера выходного быть не должно: это не выходной, а «не сегодня».
    expect(find.text(kWeekendNotice), findsNothing);
  });
}
