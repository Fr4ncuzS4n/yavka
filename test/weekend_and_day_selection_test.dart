// Тесты выходных и выбора дня и пары на экране отметки.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yavka/data/attendance_controller.dart';
import 'package:yavka/data/attendance_store.dart';
import 'package:yavka/data/schedule_controller.dart';
import 'package:yavka/main.dart';
import 'package:yavka/models/attendance_session.dart';
import 'package:yavka/models/attendance_status.dart';
import 'package:yavka/models/schedule_lesson.dart';
import 'package:yavka/models/student.dart';
import 'package:yavka/screens/attendance_screen.dart';

const students = [
  Student(id: '1', fullName: 'Алексей Морозов'),
  Student(id: '2', fullName: 'Мария Соколова'),
];

const mathLesson = ScheduleLesson(
  id: 'lesson-math',
  weekday: 1,
  startMinutes: 9 * 60,
  subject: 'Математика',
);

/// Понедельник, за который можно отмечать (дата фиксированная).
final monday = DateTime(2026, 11, 9);

AttendanceController weekdayController() => AttendanceController(
  session: AttendanceSession(
    groupName: 'БИТ-24-03',
    students: students,
    date: monday,
  ),
);

ScheduleController scheduleWithLessons() =>
    ScheduleController(lessons: [mathLesson]);

/// Контроллер экрана из дерева виджетов.
AttendanceController _screenAttendance(WidgetTester tester) =>
    tester.widget<AttendanceScreen>(find.byType(AttendanceScreen)).attendance!;

void main() {
  group('Контроллер: выходные', () {
    test('отметка в субботу не ставится', () {
      final attendance = AttendanceController(
        session: AttendanceSession(
          groupName: 'БИТ-24-03',
          students: students,
          date: DateTime(2026, 11, 14), // суббота
        ),
      );

      attendance.mark(
        students[0],
        AttendanceStatus.came,
        DateTime(2026, 11, 14, 9),
      );

      expect(attendance.entryFor(students[0].id), isNull);
    });

    test('отметка в воскресенье не ставится', () {
      final attendance = AttendanceController(
        session: AttendanceSession(
          groupName: 'БИТ-24-03',
          students: students,
          date: DateTime(2026, 11, 15), // воскресенье
        ),
      );

      attendance.mark(
        students[0],
        AttendanceStatus.came,
        DateTime(2026, 11, 15, 9),
      );

      expect(attendance.entryFor(students[0].id), isNull);
    });

    test('в будний день отметка ставится как обычно', () {
      final attendance = weekdayController();

      attendance.mark(
        students[0],
        AttendanceStatus.came,
        DateTime(2026, 11, 9, 9),
      );

      expect(
        attendance.entryFor(students[0].id)?.status,
        AttendanceStatus.came,
      );
    });

    test('после выходных переключение на будний день разрешает отметку', () {
      final attendance = AttendanceController(
        session: AttendanceSession(
          groupName: 'БИТ-24-03',
          students: students,
          date: DateTime(2026, 11, 14), // суббота
        ),
      );
      attendance.mark(
        students[0],
        AttendanceStatus.came,
        DateTime(2026, 11, 14, 9),
      );
      expect(attendance.entryFor(students[0].id), isNull);

      attendance.selectDate(DateTime(2026, 11, 13)); // пятница
      attendance.mark(
        students[0],
        AttendanceStatus.came,
        DateTime(2026, 11, 13, 9),
      );
      expect(
        attendance.entryFor(students[0].id)?.status,
        AttendanceStatus.came,
      );
    });
  });

  group('Контроллер: выбор дня', () {
    test('отметки разных дней раздельны и сохраняются при переключении', () {
      final attendance = weekdayController();
      final tuesday = DateTime(2026, 11, 10);

      attendance.mark(
        students[0],
        AttendanceStatus.came,
        DateTime(2026, 11, 9, 9),
      );
      attendance.selectDate(tuesday);
      attendance.mark(
        students[1],
        AttendanceStatus.late,
        DateTime(2026, 11, 10, 9, 30),
      );

      // Во вторник отметки понедельника нет.
      expect(attendance.selectedDate, dateOnly(tuesday));
      expect(attendance.entryFor(students[0].id), isNull);
      expect(
        attendance.entryFor(students[1].id)?.status,
        AttendanceStatus.late,
      );

      // В понедельник отметка на месте, вторничной нет.
      attendance.selectDate(monday);
      expect(
        attendance.entryFor(students[0].id)?.status,
        AttendanceStatus.came,
      );
      expect(attendance.entryFor(students[1].id), isNull);
    });

    test('список группы переносится на новый день', () {
      final attendance = weekdayController();

      attendance.selectDate(DateTime(2026, 11, 10));

      expect(
        attendance.students.map((s) => s.fullName),
        students.map((s) => s.fullName),
      );
    });

    test('дни переживают сохранение и загрузку', () async {
      final store = MemoryAttendanceStore();
      AttendanceController build() => AttendanceController(
        session: AttendanceSession(
          groupName: 'БИТ-24-03',
          students: students,
          date: monday,
        ),
        store: store,
      );
      final attendance = build();

      attendance.mark(
        students[0],
        AttendanceStatus.came,
        DateTime(2026, 11, 9, 9),
      );
      attendance.selectDate(DateTime(2026, 11, 10));
      attendance.mark(
        students[1],
        AttendanceStatus.absent,
        DateTime(2026, 11, 10, 10),
      );

      final restored = build();
      await restored.load();

      restored.selectDate(monday);
      expect(restored.entryFor(students[0].id)?.status, AttendanceStatus.came);
      expect(restored.entryFor(students[1].id), isNull);

      restored.selectDate(DateTime(2026, 11, 10));
      expect(
        restored.entryFor(students[1].id)?.status,
        AttendanceStatus.absent,
      );
      expect(restored.entryFor(students[0].id), isNull);
    });

    test('состав группы подтягивается во все дни', () {
      final attendance = weekdayController();
      const newcomer = Student(id: '3', fullName: 'Иван Петров');

      attendance.mergeRoster([students[0], students[1], newcomer]);

      expect(attendance.students, contains(newcomer));
      attendance.selectDate(DateTime(2026, 11, 10));
      expect(attendance.students, contains(newcomer));
    });

    test('sessionsInMonth возвращает дни выбранного месяца', () {
      final attendance = weekdayController();
      attendance.selectDate(DateTime(2026, 12, 1)); // следующий месяц
      attendance.mark(
        students[0],
        AttendanceStatus.came,
        DateTime(2026, 12, 1, 9),
      );

      final november = attendance.sessionsInMonth(DateTime(2026, 11));
      final december = attendance.sessionsInMonth(DateTime(2026, 12));

      expect(november, hasLength(0));
      expect(december, hasLength(1));
      expect(december.single.date, dateOnly(DateTime(2026, 12, 1)));
    });
  });

  group('Экран отметки: выбор дня и пары', () {
    /// Последний будний день ≤ сегодня: «вперёд» отмечать нельзя.
    AttendanceController upToTodayController() {
      var day = dateOnly(DateTime.now());
      while (isWeekendDate(day)) {
        day = day.subtract(const Duration(days: 1));
      }
      return AttendanceController(
        session: AttendanceSession(
          groupName: 'БИТ-24-03',
          students: students,
          date: day,
        ),
      );
    }

    Future<void> pumpApp(WidgetTester tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 1300);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        AppRoot(
          attendance: weekdayController(),
          schedule: scheduleWithLessons(),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('стрелка «назад» перепрыгивает выходные, «вперёд» нет', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 1300);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(AppRoot(attendance: upToTodayController()));
      await tester.pumpAndSettle();

      final next = find.byKey(const Key('day-next'));
      final prev = find.byKey(const Key('day-prev'));

      // Вперёд отметить нельзя: дальше — только будущие дни.
      expect(tester.widget<IconButton>(next).onPressed, isNull);

      // Назад — работает и перепрыгивает выходные.
      expect(tester.widget<IconButton>(prev).onPressed, isNotNull);
      final initial = _screenAttendance(tester).selectedDate;
      await tester.tap(prev);
      await tester.pumpAndSettle();

      var expected = initial.subtract(const Duration(days: 1));
      while (isWeekendDate(expected)) {
        expected = expected.subtract(const Duration(days: 1));
      }
      expect(_screenAttendance(tester).selectedDate, expected);
    });

    testWidgets('выбранная пара отделяет свои отметки от отметок дня', (
      tester,
    ) async {
      await pumpApp(tester);

      // Выбираем пару из расписания.
      await tester.tap(find.text('09:00 · Математика'));
      await tester.pumpAndSettle();
      // Заголовок пары — и в шапке экрана, и в заголовке списка.
      expect(find.text('Пара «Математика»'), findsNWidgets(2));

      await tester.tap(find.text('Пришёл'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(kStudentListKey),
          matching: find.textContaining('Пришёл'),
        ),
        findsOneWidget,
      );

      // Возвращаемся к «весь день». Пара в дне одна, все ячейки дня у
      // Алексея заполнены «Пришёл» — его дневная отметка выводится из
      // отметок пар. Мария не отмечена.
      await tester.tap(find.text('Весь день'));
      await tester.pumpAndSettle();
      expect(find.text('Пара «Математика»'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(kStudentListKey),
          matching: find.textContaining('Пришёл'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(kStudentListKey),
          matching: find.text('нет отметки'),
        ),
        findsOneWidget,
      );

      // Отметка на паре на месте.
      final entry = _screenAttendance(tester).entryInLesson(
        students[0].id,
        lessonKey: mathLesson.id,
        lessonTitle: mathLesson.subject,
      );
      expect(entry?.status, AttendanceStatus.came);
    });
  });

  group('Экран отметки: выходной', () {
    testWidgets('в выходной кнопки отметки выключены и виден баннер', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 1300);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        AppRoot(
          attendance: AttendanceController(
            session: AttendanceSession(
              groupName: 'БИТ-24-03',
              students: students,
              date: DateTime(2026, 11, 14), // суббота
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Выходной — в субботу и воскресенье отметки недоступны.'),
        findsOneWidget,
      );
      expect(find.text('Отменить отметку'), findsNothing);

      // Кнопки есть, но нажатие не отмечает.
      await tester.tap(find.text('Пришёл'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(kStudentListKey),
          matching: find.textContaining('Пришёл'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(kStudentListKey),
          matching: find.text('нет отметки'),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('стрелки перепрыгивают выходные и баннер исчезает', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(412, 1300);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        AppRoot(
          attendance: AttendanceController(
            session: AttendanceSession(
              groupName: 'БИТ-24-03',
              students: students,
              date: DateTime(2026, 11, 14), // суббота
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Выходной — в субботу и воскресенье отметки недоступны.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('day-prev')));
      await tester.pumpAndSettle();

      // Пятница: баннера нет, отметка ставится.
      expect(
        find.text('Выходной — в субботу и воскресенье отметки недоступны.'),
        findsNothing,
      );
      await tester.tap(find.text('Пришёл'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(kStudentListKey),
          matching: find.textContaining('Пришёл'),
        ),
        findsOneWidget,
      );
      expect(find.text('Отменить отметку'), findsOneWidget);
    });
  });
}
