// Тесты отметок посещаемости на каждой паре.

import 'package:flutter_test/flutter_test.dart';
import 'package:yavka/data/attendance_controller.dart';
import 'package:yavka/data/attendance_store.dart';
import 'package:yavka/models/attendance_entry.dart';
import 'package:yavka/models/attendance_session.dart';
import 'package:yavka/models/attendance_status.dart';
import 'package:yavka/models/schedule_lesson.dart';
import 'package:yavka/models/student.dart';

void main() {
  const students = [
    Student(id: '1', fullName: 'Алексей Морозов'),
    Student(id: '2', fullName: 'Мария Соколова'),
  ];
  const lesson = ScheduleLesson(
    id: 'lesson-math',
    weekday: 1,
    startMinutes: 9 * 60,
    endMinutes: 10 * 60 + 30,
    subject: 'Математика',
    room: '201',
  );

  AttendanceController controller({AttendanceStore? store}) =>
      AttendanceController(
        session: AttendanceSession.forToday(
          groupName: 'БИТ-24-03',
          students: students,
        ),
        store: store,
      );

  test('отметка на паре не смешивается с отметкой на весь день', () {
    final attendance = controller();
    final now = DateTime.now();
    final alexey = students[0];

    attendance.mark(
      alexey,
      AttendanceStatus.came,
      now,
      lessonKey: lesson.id,
      lessonTitle: lesson.subject,
    );

    // На паре — «Пришёл», на весь день отметки нет.
    expect(
      attendance.entryInLesson(alexey.id,
          lessonKey: lesson.id, lessonTitle: lesson.subject)?.status,
      AttendanceStatus.came,
    );
    expect(attendance.entryFor(alexey.id), isNull);

    // Общая отметка на весь день пишется отдельно.
    attendance.mark(alexey, AttendanceStatus.late, now);
    expect(attendance.entryFor(alexey.id)?.status, AttendanceStatus.late);
    expect(
      attendance.entryInLesson(alexey.id,
          lessonKey: lesson.id, lessonTitle: lesson.subject)?.status,
      AttendanceStatus.came,
    );
  });

  test('отметки на разных парах одного дня раздельны', () {
    final attendance = controller();
    const second = ScheduleLesson(
      id: 'lesson-history',
      weekday: 1,
      startMinutes: 10 * 60 + 40,
      subject: 'История',
    );
    final now = DateTime.now();
    final alexey = students[0];

    attendance.mark(alexey, AttendanceStatus.came, now,
        lessonKey: lesson.id, lessonTitle: lesson.subject);
    attendance.mark(alexey, AttendanceStatus.absent, now,
        lessonKey: second.id, lessonTitle: second.subject);

    expect(
      attendance.entryInLesson(alexey.id, lessonKey: lesson.id)?.status,
      AttendanceStatus.came,
    );
    expect(
      attendance.entryInLesson(alexey.id, lessonKey: second.id)?.status,
      AttendanceStatus.absent,
    );
  });

  test('повторная отметка на той же паре заменяет предыдущую', () {
    final attendance = controller();
    final now = DateTime.now();
    final alexey = students[0];

    attendance.mark(alexey, AttendanceStatus.came, now,
        lessonKey: lesson.id, lessonTitle: lesson.subject);
    attendance.mark(alexey, AttendanceStatus.late, now,
        lessonKey: lesson.id, lessonTitle: lesson.subject);

    expect(
      attendance.entryInLesson(alexey.id, lessonKey: lesson.id)?.status,
      AttendanceStatus.late,
    );
    expect(
      attendance.session.markedCountInLesson(
        lessonKey: lesson.id,
        lessonTitle: lesson.subject,
      ),
      1,
    );
  });

  test('счётчик отметок на паре считает только её студентов', () {
    final attendance = controller();
    final now = DateTime.now();

    attendance.mark(students[0], AttendanceStatus.came, now,
        lessonKey: lesson.id, lessonTitle: lesson.subject);
    attendance.mark(students[1], AttendanceStatus.came, now); // весь день

    expect(
      attendance.session.markedCountInLesson(
        lessonKey: lesson.id,
        lessonTitle: lesson.subject,
      ),
      1,
    );
  });

  test('отметки на парах переживают сохранение и загрузку', () async {
    final store = MemoryAttendanceStore();
    final attendance = controller(store: store);
    final now = DateTime(2026, 11, 13, 9, 5);

    attendance.mark(students[0], AttendanceStatus.came, now,
        lessonKey: lesson.id, lessonTitle: lesson.subject);

    final restored = controller(store: store);
    await restored.load();

    final entry = restored.entryInLesson(
      students[0].id,
      lessonKey: lesson.id,
      lessonTitle: lesson.subject,
    );
    expect(entry?.status, AttendanceStatus.came);
    expect(entry?.lessonKey, lesson.id);
    expect(entry?.lessonTitle, 'Математика');
  });

  test('сессия без пар читается из старого формата JSON', () {
    final session = AttendanceSession.fromJson({
      'groupName': 'БИТ-24-03',
      'date': '2026-11-13',
      'students': [
        {'id': '1', 'fullName': 'Алексей Морозов'},
      ],
      'entries': {
        '1': {
          'status': 'came',
          'markedAt': '2026-11-13T09:00:00.000',
        },
      },
    });

    expect(session.entryFor('1')?.status, AttendanceStatus.came);
    expect(session.entries.keys, contains('1'));
  });

  test('отметки с парами, загруженные из таблицы, не затирают отметки дня',
      () {
    final session = AttendanceSession(
      groupName: 'БИТ-24-03',
      date: DateTime(2026, 11, 13),
      students: students,
      entries: {
        '1': AttendanceEntry(
          status: AttendanceStatus.late,
          markedAt: DateTime(2026, 11, 13, 9),
        ),
      },
    );

    final merged = session.mergeRemote([
      AttendanceRecord(
        groupName: 'БИТ-24-03',
        date: DateTime(2026, 11, 13),
        student: students[0],
        // Из таблицы приходит только название пары, без её id.
        entry: AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: DateTime(2026, 11, 13, 9, 10),
          lessonTitle: 'Математика',
        ),
      ),
    ]);

    // Отметка на весь день и отметка на паре живут в одной сессии.
    expect(merged.entryFor('1')?.status, AttendanceStatus.late);
    expect(
      merged
          .entryInLesson('1', lessonTitle: 'Математика')
          ?.status,
      AttendanceStatus.came,
    );
  });

  test('клавиши времени пары форматируются и разбираются', () {
    expect(formatMinutes(9 * 60 + 5), '09:05');
    expect(parseClockTime('10:30'), 10 * 60 + 30);
    expect(parseClockTime('25:00'), isNull);
    expect(parseClockTime('не время'), isNull);
  });
}
