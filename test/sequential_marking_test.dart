// Тесты поочерёдной отметки: переключатель в настройках и подсветка
// следующего неотмеченного студента после отметки.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yavka/data/attendance_controller.dart';
import 'package:yavka/data/schedule_controller.dart';
import 'package:yavka/data/ui_settings.dart';
import 'package:yavka/main.dart';
import 'package:yavka/models/attendance_entry.dart';
import 'package:yavka/models/attendance_session.dart';
import 'package:yavka/models/attendance_status.dart';
import 'package:yavka/models/schedule_lesson.dart';
import 'package:yavka/models/student.dart';
import 'package:yavka/screens/settings_screen.dart';
import 'support/demo_roster.dart';

/// Фиксированный понедельник: тесты не зависят от дня недели запуска
/// (в выходные отметки запрещены).
final kMonday = DateTime(2026, 11, 9);

Future<UiSettingsController> _settings({bool sequential = false}) async {
  SharedPreferences.setMockInitialValues({
    'yavka.ui.sequential_marking': sequential,
  });
  final preferences = await SharedPreferences.getInstance();
  return UiSettingsController(preferences: preferences);
}

Future<void> _pumpAttendance(
  WidgetTester tester, {
  required UiSettingsController ui,
  AttendanceController? attendance,
  ScheduleController? schedule,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(412, 1300);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(AppRoot(
    attendance:
        attendance ??
        AttendanceController(
          session: AttendanceSession(
            groupName: demoGroupName,
            students: demoStudents,
            date: kMonday,
          ),
        ),
    schedule: schedule,
    settings: ui,
  ));
  await tester.pumpAndSettle();
}

/// Кнопка статуса в панели отметки (в строке отмеченного студента
/// есть чип с тем же текстом — тапать нужно именно кнопку).
Finder _statusButton(AttendanceStatus status) =>
    find.byKey(ValueKey('status-button-${status.name}'));

/// Студенты, оставшиеся без отметки на весь день.
List<Student> unmarkedIn(AttendanceController controller) => [
  for (final student in controller.students)
    if (controller.entryFor(student.id) == null) student,
];

/// Студенты, оставшиеся без отметки на конкретной паре.
List<Student> unmarkedInLesson(
  AttendanceController controller,
  ScheduleLesson lesson,
) => [
  for (final student in controller.students)
    if (controller.entryInLesson(
      student.id,
      lessonKey: lesson.id,
      lessonTitle: lesson.subject,
    ) == null)
      student,
];

void main() {
  group('настройки', () {
    test('по умолчанию поочерёдная отметка выключена', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final settings = UiSettingsController(preferences: preferences);

      expect(settings.sequentialMarking, isFalse);
    });

    test('переключатель сохраняется и восстанавливается', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final settings = UiSettingsController(preferences: preferences);

      await settings.setSequentialMarking(true);
      expect(settings.sequentialMarking, isTrue);

      // Новый контроллер на тех же предпочтениях читает сохранённое.
      final restored = UiSettingsController(preferences: preferences);
      expect(restored.sequentialMarking, isTrue);
    });

    testWidgets('в настройках есть пункт «Поочерёдная отметка»', (tester) async {
      final settings = await _settings();
      await tester.pumpWidget(MaterialApp(
        home: SettingsScreen(settings: settings),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Поочерёдная отметка'), findsOneWidget);
      expect(find.text('Отметка'), findsOneWidget);
    });
  });

  group('экран отметки', () {
    testWidgets('режим включён: баннер и подсветка первого неотмеченного',
        (tester) async {
      // Первый студент уже отмечен — подсветится второй.
      final attendance = AttendanceController(
        session: AttendanceSession(
          groupName: demoGroupName,
          students: demoStudents,
          date: kMonday,
          entries: {
            '1': AttendanceEntry(
              status: AttendanceStatus.came,
              markedAt: DateTime(2026, 11, 9, 9),
            ),
          },
        ),
      );
      final ui = await _settings(sequential: true);

      await _pumpAttendance(tester, ui: ui, attendance: attendance);

      expect(find.byKey(const Key('sequential-banner')), findsOneWidget);
      // Автоподсветка: выбран Мария (первый неотмеченный), а не Алексей.
      expect(find.text('Отметить: Мария Соколова'), findsOneWidget);
    });

    testWidgets('режим выключен: баннера нет, остаётся первый студент',
        (tester) async {
      final attendance = AttendanceController(
        session: AttendanceSession(
          groupName: demoGroupName,
          students: demoStudents,
          date: kMonday,
          entries: {
            '1': AttendanceEntry(
              status: AttendanceStatus.came,
              markedAt: DateTime(2026, 11, 9, 9),
            ),
          },
        ),
      );
      final ui = await _settings();

      await _pumpAttendance(tester, ui: ui, attendance: attendance);

      expect(find.byKey(const Key('sequential-banner')), findsNothing);
      expect(find.text('Отметить: Алексей Морозов'), findsOneWidget);
    });

    testWidgets('после «Пришёл» подсвечивается следующий неотмеченный',
        (tester) async {
      final ui = await _settings(sequential: true);
      final attendance = AttendanceController(
        session: AttendanceSession(
          groupName: demoGroupName,
          students: demoStudents,
          date: kMonday,
        ),
      );
      await _pumpAttendance(tester, ui: ui, attendance: attendance);

      // Первый студент отмечен, продвинулись ко второму.
      await tester.tap(_statusButton(AttendanceStatus.came));
      await tester.pumpAndSettle();

      expect(attendance.entryFor('1')?.status, AttendanceStatus.came);
      expect(find.text('Отметить: Мария Соколова'), findsOneWidget);

      // Второй отмечен — продвинулись к третьему.
      await tester.tap(_statusButton(AttendanceStatus.came));
      await tester.pumpAndSettle();

      expect(attendance.entryFor('2')?.status, AttendanceStatus.came);
      expect(find.text('Отметить: Дмитрий Волков'), findsOneWidget);
    });

    testWidgets('первое нажатие «Непришёл» не продвигает и не отмечает',
        (tester) async {
      final ui = await _settings(sequential: true);
      final attendance = AttendanceController(
        session: AttendanceSession(
          groupName: demoGroupName,
          students: demoStudents,
          date: kMonday,
        ),
      );
      await _pumpAttendance(tester, ui: ui, attendance: attendance);

      await tester.tap(_statusButton(AttendanceStatus.absent));
      await tester.pumpAndSettle();

      // Намерение запомнено, отметки нет, подсветка не сдвинулась.
      expect(attendance.entryFor('1'), isNull);
      expect(find.text('Отметить: Алексей Морозов'), findsOneWidget);

      // Второе нажатие подтверждает: отметка ставится, продвинулись.
      await tester.tap(_statusButton(AttendanceStatus.absent));
      await tester.pumpAndSettle();

      expect(attendance.entryFor('1')?.status, AttendanceStatus.absent);
      expect(find.text('Отметить: Мария Соколова'), findsOneWidget);
    });

    testWidgets('все отмечены — подсветка остаётся на месте', (tester) async {
      final ui = await _settings(sequential: true);
      final attendance = AttendanceController(
        session: AttendanceSession(
          groupName: demoGroupName,
          students: [demoStudents[0], demoStudents[1]],
          date: kMonday,
        ),
      );
      await _pumpAttendance(tester, ui: ui, attendance: attendance);

      await tester.tap(_statusButton(AttendanceStatus.came));
      await tester.pumpAndSettle();
      await tester.tap(_statusButton(AttendanceStatus.came));
      await tester.pumpAndSettle();

      expect(attendance.entryFor('1')?.status, AttendanceStatus.came);
      expect(attendance.entryFor('2')?.status, AttendanceStatus.came);
      // Неотмеченных нет — продвинуться некуда, остаёмся на последнем.
      expect(find.text('Отметить: Мария Соколова'), findsOneWidget);
    });

    testWidgets('режим выключен: отметка не продвигает подсветку',
        (tester) async {
      final ui = await _settings();
      final attendance = AttendanceController(
        session: AttendanceSession(
          groupName: demoGroupName,
          students: demoStudents,
          date: kMonday,
        ),
      );
      await _pumpAttendance(tester, ui: ui, attendance: attendance);

      await tester.tap(_statusButton(AttendanceStatus.came));
      await tester.pumpAndSettle();

      expect(attendance.entryFor('1')?.status, AttendanceStatus.came);
      // Подсветка не двигается — выбранный остаётся на месте.
      expect(find.text('Отметить: Алексей Морозов'), findsOneWidget);
    });

    testWidgets('смена дня подсвечивает первого неотмеченного', (tester) async {
      final ui = await _settings(sequential: true);
      final attendance = AttendanceController(
        session: AttendanceSession(
          groupName: demoGroupName,
          students: demoStudents,
          date: kMonday,
          entries: {
            '1': AttendanceEntry(
              status: AttendanceStatus.came,
              markedAt: DateTime(2026, 11, 9, 9),
            ),
          },
        ),
      );
      await _pumpAttendance(tester, ui: ui, attendance: attendance);

      // Выбран второй день (вторник) — отметок за него нет, подсветится
      // первый студент.
      await tester.tap(find.byKey(const Key('day-next')));
      await tester.pumpAndSettle();

      expect(attendance.selectedDate.day, 10);
      expect(find.text('Отметить: Алексей Морозов'), findsOneWidget);
    });

    testWidgets('на паре подсветка идёт по отметкам этой пары', (tester) async {
      const lesson = ScheduleLesson(
        id: 'mon-1',
        weekday: 1,
        startMinutes: 9 * 60,
        subject: 'Математика',
      );
      final schedule = ScheduleController()..add(lesson);
      final attendance = AttendanceController(
        session: AttendanceSession(
          groupName: demoGroupName,
          students: [demoStudents[0], demoStudents[1], demoStudents[2]],
          date: kMonday,
          // Алексей отмечен на весь день, но не на этой паре:
          // для пары он всё ещё «неотмеченный».
          entries: {
            '1': AttendanceEntry(
              status: AttendanceStatus.came,
              markedAt: DateTime(2026, 11, 9, 9),
            ),
          },
        ),
      );
      final ui = await _settings(sequential: true);
      await _pumpAttendance(tester, ui: ui, attendance: attendance,
          schedule: schedule);

      // Пока «весь день»: Алексей отмечен, подсвечена Мария.
      expect(find.text('Отметить: Мария Соколова'), findsOneWidget);

      // Переключаемся на пару: в scope пары все неотмечены,
      // подсветится первый — Алексей.
      await tester.tap(find.text('09:00 · Математика'));
      await tester.pumpAndSettle();

      expect(find.text('Отметить: Алексей Морозов'), findsOneWidget);

      // Отметили Алексея на паре — подсветится следующий по списку
      // неотмеченный на паре (Мария).
      await tester.tap(_statusButton(AttendanceStatus.came));
      await tester.pumpAndSettle();

      expect(find.text('Отметить: Мария Соколова'), findsOneWidget);
      // Отметка записана как отметка пары.
      final lessonEntry = attendance.entryInLesson(
        '1',
        lessonKey: lesson.id,
        lessonTitle: lesson.subject,
      );
      expect(lessonEntry?.status, AttendanceStatus.came);
      // Отметка на весь день не тронута: в дне без отметки остаются
      // Мария и Дмитрий.
      expect(unmarkedIn(attendance).map((student) => student.id), ['2', '3']);
      // В scope пары после отметки Алексея остаются Мария и Дмитрий.
      expect(
        unmarkedInLesson(attendance, lesson).map((student) => student.id),
        ['2', '3'],
      );
    });
  });
}
