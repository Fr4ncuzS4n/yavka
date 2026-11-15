// Тесты экрана «Настройки»: сброс локальных данных (отметки,
// расписание, база) с подтверждением и разделы переданных контроллеров.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yavka/data/attendance_controller.dart';
import 'package:yavka/data/attendance_store.dart';
import 'package:yavka/data/catalog_controller.dart';
import 'package:yavka/data/catalog_store.dart';
import 'package:yavka/data/schedule_controller.dart';
import 'package:yavka/data/schedule_store.dart';
import 'package:yavka/data/ui_settings.dart';
import 'package:yavka/models/attendance_entry.dart';
import 'package:yavka/models/attendance_session.dart';
import 'package:yavka/models/attendance_status.dart';
import 'package:yavka/models/schedule_lesson.dart';
import 'package:yavka/models/student.dart';
import 'package:yavka/screens/settings_screen.dart';

void main() {
  const alexey = Student(id: '1', fullName: 'Алексей Морозов');
  final monday = DateTime(2026, 11, 9); // понедельник
  final tuesday = DateTime(2026, 11, 10);

  AttendanceController attendanceWithMarks(AttendanceStore store) {
    final controller = AttendanceController(
      session: AttendanceSession(
        groupName: 'БИТ-24-03',
        date: monday,
        students: const [alexey],
        entries: {
          '1': AttendanceEntry(
            status: AttendanceStatus.came,
            markedAt: DateTime(2026, 11, 9, 9),
          ),
        },
      ),
      store: store,
    );
    // Второй день со своей отметкой.
    controller.selectDate(tuesday);
    controller.mark(
      alexey,
      AttendanceStatus.late,
      DateTime(2026, 11, 10, 9, 40),
    );
    return controller;
  }

  test('сброс стирает отметки всех дней и сохраняет пустоту', () async {
    final store = MemoryAttendanceStore();
    final controller = attendanceWithMarks(store);

    controller.reset();

    // Остаётся один пустой день — выбранный.
    expect(controller.entries, isEmpty);
    expect(controller.students, isEmpty);
    expect(controller.sessions, hasLength(1));
    expect(controller.sessions.single.date.day, tuesday.day);
    // Группа сохраняется как метка, отметок за ней нет.
    expect(controller.sessions.single.groupName, 'БИТ-24-03');

    await pumpEventQueue();
    // Пустые дни не хранятся: в хранилище не осталось отметок.
    expect(await store.loadAll(), isEmpty);
  });

  test('сброс очищает расписание и сохраняет пустоту', () async {
    final store = MemoryScheduleStore();
    final controller = ScheduleController(store: store);
    controller.add(const ScheduleLesson(
      id: 'mon-1',
      weekday: 1,
      startMinutes: 9 * 60,
      subject: 'Математика',
    ));

    controller.clear();

    expect(controller.lessons, isEmpty);
    await pumpEventQueue();
    expect(await store.load(), isEmpty);
  });

  test('сброс очищает базу преподавателей, предметов и кабинетов', () async {
    final store = MemoryCatalogStore();
    final controller = CatalogController(store: store);
    final teacher = controller.addTeacher('Ирина Смирнова');
    controller.addSubject('Математика', teacherId: teacher.id);

    expect(controller.teachers, isNotEmpty);
    expect(controller.subjects, isNotEmpty);

    controller.clear();

    expect(controller.teachers, isEmpty);
    expect(controller.rooms, isEmpty);
    expect(controller.subjects, isEmpty);
    await pumpEventQueue();
    final saved = await store.load();
    expect(saved.teachers, isEmpty);
    expect(saved.subjects, isEmpty);
  });

  testWidgets('настройки показывают разделы переданных контроллеров',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final ui = UiSettingsController(preferences: preferences);

    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        settings: ui,
        schedule: ScheduleController(),
        catalog: CatalogController(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Google Диск'), findsNothing);
    expect(find.text('Уведомления'), findsNothing);
    expect(find.text('База данных'), findsOneWidget);
    // Сброс и «О приложении» — ниже вьюпорта, прокручиваем.
    await tester.scrollUntilVisible(
      find.text('Сбросить локальные данные'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Сбросить локальные данные'), findsOneWidget);
    // О приложении: лого и название — ниже вьюпорта, прокручиваем.
    await tester.scrollUntilVisible(
      find.text('Явка'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Явка'), findsOneWidget);
  });

  testWidgets('сброс данных требует подтверждения и стирает всё',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final ui = UiSettingsController(preferences: preferences);
    final attendance = attendanceWithMarks(MemoryAttendanceStore());
    final schedule = ScheduleController()..add(const ScheduleLesson(
      id: 'mon-1',
      weekday: 1,
      startMinutes: 9 * 60,
      subject: 'Математика',
    ));
    final catalog = CatalogController()..addTeacher('Ирина Смирнова');

    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        settings: ui,
        attendance: attendance,
        schedule: schedule,
        catalog: catalog,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Сбросить локальные данные'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Сбросить локальные данные'));
    await tester.pumpAndSettle();

    // Отмена ничего не стирает.
    await tester.tap(find.text('Сбросить локальные данные'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Отмена'),
    ));
    await tester.pumpAndSettle();
    expect(schedule.lessons, isNotEmpty);
    expect(catalog.teachers, isNotEmpty);
    expect(attendance.entries, isNotEmpty);

    // «Стереть» подтверждает: данные уходят с устройства.
    await tester.tap(find.text('Сбросить локальные данные'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Стереть'),
    ));
    await tester.pumpAndSettle();

    expect(attendance.entries, isEmpty);
    expect(schedule.lessons, isEmpty);
    expect(catalog.teachers, isEmpty);
    expect(find.text('Данные удалены с устройства'), findsOneWidget);
  });
}
