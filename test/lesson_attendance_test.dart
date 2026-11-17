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
        session: AttendanceSession(
          groupName: 'БИТ-24-03',
          students: students,
          date: DateTime(2026, 11, 9), // понедельник
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

  test('одинаковый предмет дважды в день: отметка одной пары не видна '
      'на другой', () {
    // Физика стоит в расписании два раза: отметка на первой паре не
    // должна показываться на второй — иначе студент выглядит отмеченным
    // на обеих и поочерёдная отметка его пропускает.
    const fizikaFirst = ScheduleLesson(
      id: 'lesson-fizika-1',
      weekday: 1,
      startMinutes: 9 * 60,
      subject: 'Физика',
    );
    const fizikaSecond = ScheduleLesson(
      id: 'lesson-fizika-2',
      weekday: 1,
      startMinutes: 10 * 60 + 40,
      subject: 'Физика',
    );
    final attendance = controller();
    final now = DateTime.now();
    final alexey = students[0];

    attendance.mark(alexey, AttendanceStatus.came, now,
        lessonKey: fizikaFirst.id, lessonTitle: fizikaFirst.subject);

    expect(
      attendance.entryInLesson(alexey.id,
          lessonKey: fizikaFirst.id, lessonTitle: fizikaFirst.subject),
      isNotNull,
    );
    expect(
      attendance.entryInLesson(alexey.id,
          lessonKey: fizikaSecond.id, lessonTitle: fizikaSecond.subject),
      isNull,
    );
  });

  test('табличная отметка без id пары видна на паре с тем же названием', () {
    // Отметки из журнала бывают только с названием пары — они остаются
    // видны на паре с этим названием.
    final session = AttendanceSession(
      groupName: 'БИТ-24-03',
      date: DateTime(2026, 11, 9),
      students: students,
      entries: {
        '1|Физика': AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: DateTime(2026, 11, 9, 9),
          lessonTitle: 'Физика',
        ),
      },
    );

    expect(
      session.entryInLesson(
        '1',
        lessonKey: 'lesson-fizika-2',
        lessonTitle: 'Физика',
      )?.status,
      AttendanceStatus.came,
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

  test('счётчик пары считает студента один раз: локальная и табличная '
      'отметки одной пары', () {
    // Локальная отметка несёт id пары, табличная — только её название.
    // Записей на студента две, студент отмечен один.
    final session = AttendanceSession(
      groupName: 'БИТ-24-03',
      date: DateTime(2026, 11, 9),
      students: students,
      entries: {
        '1|lesson-math': AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: DateTime(2026, 11, 9, 9),
          lessonKey: 'lesson-math',
          lessonTitle: 'Математика',
        ),
        '1|Математика': AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: DateTime(2026, 11, 9, 9),
          lessonTitle: 'Математика',
        ),
        '2|lesson-math': AttendanceEntry(
          status: AttendanceStatus.late,
          markedAt: DateTime(2026, 11, 9, 9),
          lessonKey: 'lesson-math',
          lessonTitle: 'Математика',
        ),
      },
    );

    expect(
      session.markedCountInLesson(
        lessonKey: 'lesson-math',
        lessonTitle: 'Математика',
      ),
      2, // два студента, а не три записи
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

  test('дневная отметка приложения сильнее отметок пар из таблицы', () {
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

    // Приложение отметило студента на весь день — таблица ему ничего
    // не добавляет, дневная отметка остаётся прежней.
    expect(merged.entryFor('1')?.status, AttendanceStatus.late);
    expect(merged.entryInLesson('1', lessonTitle: 'Математика'), isNull);
  });

  test('отметка пары приложения сильнее отметки той же пары из таблицы',
      () {
    final session = AttendanceSession(
      groupName: 'БИТ-24-03',
      date: DateTime(2026, 11, 13),
      students: students,
      entries: {
        '1|mon-1': AttendanceEntry(
          status: AttendanceStatus.late,
          markedAt: DateTime(2026, 11, 13, 9, 15),
          lessonKey: 'mon-1',
          lessonTitle: 'Математика',
        ),
      },
    );

    final merged = session.mergeRemote([
      AttendanceRecord(
        groupName: 'БИТ-24-03',
        date: DateTime(2026, 11, 13),
        student: students[0],
        entry: AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: DateTime(2026, 11, 13, 9),
          lessonKey: 'mon-1',
          lessonTitle: 'Математика',
        ),
      ),
    ]);

    // Локальное опоздание с временем не затёрлось табличным «пришёл».
    final kept = merged.entryInLesson('1', lessonKey: 'mon-1');
    expect(kept?.status, AttendanceStatus.late);
    expect(kept?.markedAt, DateTime(2026, 11, 13, 9, 15));
  });

  test('таблица дополняет пробелы: незамеченные студенты и пары', () {
    final session = AttendanceSession(
      groupName: 'БИТ-24-03',
      date: DateTime(2026, 11, 13),
      students: students,
      // Алексей отмечен только на первой паре, Мария не отмечена вовсе.
      entries: {
        '1|mon-1': AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: DateTime(2026, 11, 13, 9),
          lessonKey: 'mon-1',
          lessonTitle: 'Математика',
        ),
      },
    );

    AttendanceRecord record(Student student, AttendanceEntry entry) =>
        AttendanceRecord(
          groupName: 'БИТ-24-03',
          date: DateTime(2026, 11, 13),
          student: student,
          entry: entry,
        );

    final merged = session.mergeRemote([
      // Пара 1 Алексея уже отмечена в приложении — таблица не трогает.
      record(
        students[0],
        AttendanceEntry(
          status: AttendanceStatus.absent,
          markedAt: DateTime(2026, 11, 13, 9),
          lessonKey: 'mon-1',
          lessonTitle: 'Математика',
        ),
      ),
      // Пара 2 в приложении пуста — приходит из таблицы.
      record(
        students[0],
        AttendanceEntry(
          status: AttendanceStatus.late,
          markedAt: DateTime(2026, 11, 13, 9, 40),
          lessonKey: 'mon-2',
          lessonTitle: 'История',
        ),
      ),
      // Мария не отмечена вовсе — вся приходит из таблицы.
      record(
        students[1],
        AttendanceEntry(
          status: AttendanceStatus.excused,
          markedAt: DateTime(2026, 11, 13, 9),
          lessonKey: 'mon-1',
          lessonTitle: 'Математика',
        ),
      ),
    ]);

    expect(
      merged.entryInLesson('1', lessonKey: 'mon-1')?.status,
      AttendanceStatus.came,
    );
    final fromTable = merged.entryInLesson('1', lessonKey: 'mon-2');
    expect(fromTable?.status, AttendanceStatus.late);
    expect(fromTable?.markedAt, DateTime(2026, 11, 13, 9, 40));
    expect(
      merged.entryInLesson('2', lessonKey: 'mon-1')?.status,
      AttendanceStatus.excused,
    );
  });

  test('новый студент из таблицы попадает в список вместе с отметками', () {
    final session = AttendanceSession(
      groupName: 'БИТ-24-03',
      date: DateTime(2026, 11, 13),
      students: students,
    );
    const newcomer = Student(id: 'Пётр Новый', fullName: 'Пётр Новый');

    final merged = session.mergeRemote([
      AttendanceRecord(
        groupName: 'БИТ-24-03',
        date: DateTime(2026, 11, 13),
        student: newcomer,
        entry: AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: DateTime(2026, 11, 13, 9),
          lessonTitle: 'Математика',
        ),
      ),
    ]);

    expect(merged.students.map((s) => s.id), contains('Пётр Новый'));
    expect(
      merged.entryInLesson('Пётр Новый', lessonTitle: 'Математика')?.status,
      AttendanceStatus.came,
    );
  });

  test('клавиши времени пары форматируются и разбираются', () {
    expect(formatMinutes(9 * 60 + 5), '09:05');
    expect(parseClockTime('10:30'), 10 * 60 + 30);
    expect(parseClockTime('25:00'), isNull);
    expect(parseClockTime('не время'), isNull);
  });

  test('счётчик «весь день» считает студентов, а не ячейки отметок', () {
    // Алексей с дневной отметкой, Мария отмечена на двух парах,
    // Пётр не отмечен вовсе. Ячеек три, студентов с отметками — два.
    final attendance = AttendanceController(
      session: AttendanceSession(
        groupName: 'БИТ-24-03',
        students: const [
          ...students,
          Student(id: '3', fullName: 'Пётр Ветров'),
        ],
        date: DateTime(2026, 11, 9), // понедельник
      ),
    );
    final now = DateTime.now();
    final alexey = students[0];
    final maria = students[1];

    attendance.mark(alexey, AttendanceStatus.came, now); // дневная отметка
    attendance.mark(
      maria,
      AttendanceStatus.came,
      now,
      lessonKey: lesson.id,
      lessonTitle: lesson.subject,
    );
    attendance.mark(
      maria,
      AttendanceStatus.late,
      now,
      lessonKey: '${lesson.id}-2',
      lessonTitle: 'Физика',
    );

    expect(attendance.entries.length, 3); // три ячейки
    expect(attendance.session.markedCountForDay, 2); // два студента
  });

  test('весь день: все пары заполнены одним статусом — дневная отметка '
      'ставится', () {
    // Физика идёт дважды, История один раз. Алексей на всех парах
    // «Пришёл» — во вкладке «Весь день» он отмечён на весь день, хотя
    // отдельной дневной отметки у него нет.
    const fizika1 = ScheduleLesson(
      id: 'lesson-fizika-1',
      weekday: 1,
      startMinutes: 9 * 60,
      subject: 'Физика',
    );
    const fizika2 = ScheduleLesson(
      id: 'lesson-fizika-2',
      weekday: 1,
      startMinutes: 10 * 60 + 40,
      subject: 'Физика',
    );
    const history = ScheduleLesson(
      id: 'lesson-history',
      weekday: 1,
      startMinutes: 11 * 60 + 50,
      subject: 'История',
    );
    final now = DateTime(2026, 11, 9, 9);
    final attendance = controller();
    final alexey = students[0];

    attendance.mark(alexey, AttendanceStatus.came, now,
        lessonKey: fizika1.id, lessonTitle: fizika1.subject);
    attendance.mark(alexey, AttendanceStatus.came, now,
        lessonKey: fizika2.id, lessonTitle: fizika2.subject);

    // Не все пары заполнены — дневной отметки ещё нет.
    expect(
      attendance.session.wholeDayEntryFor(alexey.id, [
        fizika1,
        fizika2,
        history,
      ]),
      isNull,
    );

    attendance.mark(alexey, AttendanceStatus.came, now,
        lessonKey: history.id, lessonTitle: history.subject);
    final wholeDay = attendance.session.wholeDayEntryFor(alexey.id, [
      fizika1,
      fizika2,
      history,
    ]);
    expect(wholeDay?.status, AttendanceStatus.came);
    expect(attendance.entryFor(alexey.id), isNull); // записи не создано
  });

  test('весь день: разные статусы пар из разных групп не сводятся', () {
    const fizika = ScheduleLesson(
      id: 'lesson-fizika-1',
      weekday: 1,
      startMinutes: 9 * 60,
      subject: 'Физика',
    );
    const history = ScheduleLesson(
      id: 'lesson-history',
      weekday: 1,
      startMinutes: 10 * 60 + 40,
      subject: 'История',
    );
    final now = DateTime(2026, 11, 9, 9);
    final attendance = controller();
    final alexey = students[0];
    final maria = students[1];
    final lessons = [fizika, history];

    // Пришёл на одну, по уважительной на другую — единого статуса нет.
    attendance.mark(alexey, AttendanceStatus.came, now,
        lessonKey: fizika.id, lessonTitle: fizika.subject);
    attendance.mark(alexey, AttendanceStatus.excused, now,
        lessonKey: history.id, lessonTitle: history.subject);
    expect(attendance.session.wholeDayEntryFor(alexey.id, lessons), isNull);

    // Пришёл на одну, не пришёл на другую — тоже.
    attendance.mark(maria, AttendanceStatus.came, now,
        lessonKey: fizika.id, lessonTitle: fizika.subject);
    attendance.mark(maria, AttendanceStatus.absent, now,
        lessonKey: history.id, lessonTitle: history.subject);
    expect(attendance.session.wholeDayEntryFor(maria.id, lessons), isNull);
  });

  test('весь день: «Опоздал» на всех парах считается «Пришёл»', () {
    // Опоздал на все пары — человек был весь день, дневная отметка
    // «Пришёл». Время опозданий остаётся во вкладках пар.
    const fizika = ScheduleLesson(
      id: 'lesson-fizika-1',
      weekday: 1,
      startMinutes: 9 * 60,
      subject: 'Физика',
    );
    const history = ScheduleLesson(
      id: 'lesson-history',
      weekday: 1,
      startMinutes: 10 * 60 + 40,
      subject: 'История',
    );
    final now = DateTime(2026, 11, 9, 9, 10);
    final attendance = controller();
    final alexey = students[0];
    final maria = students[1];
    final lessons = [fizika, history];

    attendance.mark(alexey, AttendanceStatus.late, now,
        lessonKey: fizika.id, lessonTitle: fizika.subject);
    attendance.mark(alexey, AttendanceStatus.late, now,
        lessonKey: history.id, lessonTitle: history.subject);

    // Смешанно «Опоздал» и «Пришёл» — тоже «Пришёл» на весь день.
    attendance.mark(maria, AttendanceStatus.late, now,
        lessonKey: fizika.id, lessonTitle: fizika.subject);
    attendance.mark(maria, AttendanceStatus.came, now,
        lessonKey: history.id, lessonTitle: history.subject);

    final wholeDay = attendance.session.wholeDayEntryFor(alexey.id, lessons);
    expect(wholeDay?.status, AttendanceStatus.came);
    expect(wholeDay?.hasLesson, isFalse);
    expect(attendance.session.wholeDayEntryFor(maria.id, lessons)?.status,
        AttendanceStatus.came);
    // Сами отметки пар не тронуты: опоздание с временем на месте.
    expect(
      attendance.entryInLesson(alexey.id,
              lessonKey: fizika.id, lessonTitle: fizika.subject)?.status,
      AttendanceStatus.late,
    );
  });

  test('весь день: своя дневная отметка важнее отметок пар', () {
    const fizika = ScheduleLesson(
      id: 'lesson-fizika-1',
      weekday: 1,
      startMinutes: 9 * 60,
      subject: 'Физика',
    );
    const history = ScheduleLesson(
      id: 'lesson-history',
      weekday: 1,
      startMinutes: 10 * 60 + 40,
      subject: 'История',
    );
    final now = DateTime(2026, 11, 9, 9);
    final attendance = controller();
    final alexey = students[0];

    attendance.mark(alexey, AttendanceStatus.absent, now); // весь день
    attendance.mark(alexey, AttendanceStatus.came, now,
        lessonKey: fizika.id, lessonTitle: fizika.subject);
    attendance.mark(alexey, AttendanceStatus.came, now,
        lessonKey: history.id, lessonTitle: history.subject);

    final wholeDay = attendance.session.wholeDayEntryFor(alexey.id, [
      fizika,
      history,
    ]);
    expect(wholeDay?.status, AttendanceStatus.absent);
    expect(wholeDay, same(attendance.entryFor(alexey.id)));
  });
}
