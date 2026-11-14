// Тесты синхронизации с существующим журналом: приложение только
// отмечает ячейки пар, структуру таблицы не трогает, месяц берёт из
// названия «МЕСЯЦ : ГОД», а пары сверяет с расписанием.

import 'package:flutter_test/flutter_test.dart';
import 'package:yavka/data/schedule_controller.dart';
import 'package:yavka/models/attendance_entry.dart';
import 'package:yavka/models/attendance_session.dart';
import 'package:yavka/models/attendance_status.dart';
import 'package:yavka/models/schedule_lesson.dart';
import 'package:yavka/models/student.dart';
import 'package:yavka/services/cloud/cloud_exceptions.dart';
import 'package:yavka/services/cloud/journal_mapping.dart';
import 'package:yavka/services/cloud/journal_sync_service.dart';

import 'support/fake_sheets_api.dart';
import 'support/month_journal_fixture.dart';

void main() {
  final month = DateTime(2026, 11, 1);
  final date = DateTime(2026, 11, 9); // понедельник 9 ноября
  const alexey = Student(id: '1', fullName: 'Алексей Морозов');
  const maria = Student(id: '2', fullName: 'Мария Соколова');
  const tabTitle = 'НОЯБРЬ : 2026';

  // Блоки по дням недели (7 колонок цикла): пн — 3, вт — 2.
  const pairsByDay = [1, 3, 2, 1, 2, 1, 1];
  final mapping = const JournalMapping(
    tabTitle: tabTitle,
    dayRow: 1,
    fioColumn: 1,
    firstStudentRow: 3,
  );

  int blockStart(int day) {
    var column = 2;
    for (var d = 1; d < day; d++) {
      column += pairsByDay[(d - 1) % pairsByDay.length];
    }
    return column;
  }

  ScheduleController scheduleWith({int monday = 3}) {
    final schedule = ScheduleController.inMemory();
    for (var i = 1; i <= monday; i++) {
      schedule.add(
        ScheduleLesson(
          id: 'mon-$i',
          weekday: 1,
          startMinutes: 480 + i * 100,
          subject: 'Понедельничная пара $i',
        ),
      );
    }
    return schedule;
  }

  AttendanceSession session(Map<String, AttendanceEntry> entries) =>
      AttendanceSession(
        groupName: 'БИТ-24-03',
        date: date,
        students: const [alexey, maria],
        entries: entries,
      );

  test('отметка «пришёл» ложится цветом в колонку первой пары', () async {
    final api = FakeSheetsApi();
    seedJournal(api, month: month, pairsByDay: pairsByDay, students: const [
      alexey,
      maria,
    ]);
    final service = JournalSyncService(api);

    final result = await service.push(
      spreadsheetId: 'sid',
      mapping: mapping,
      sessions: [
        session({
          '1': AttendanceEntry(
            status: AttendanceStatus.came,
            markedAt: DateTime(2026, 11, 9, 9),
          ),
        }),
      ],
      schedule: scheduleWith(),
    );

    // Отметка на весь день живёт в первой колонке блока дня.
    expect(api.cell(tabTitle, 3, blockStart(9)).backgroundColor, 0x00CC00);
    expect(api.cell(tabTitle, 3, blockStart(9)).value, isNull);
    expect(result.updatedCells, 1);
    // Одна посылка, в ней только updateCells — структуру не трогаем.
    expect(api.batchRequestLog, [
      ['updateCells'],
    ]);
  });

  test('опоздание пишется во вторую пару цветом и временем', () async {
    final api = FakeSheetsApi();
    seedJournal(api, month: month, pairsByDay: pairsByDay, students: const [
      alexey,
      maria,
    ]);
    final service = JournalSyncService(api);

    await service.push(
      spreadsheetId: 'sid',
      mapping: mapping,
      sessions: [
        session({
          '1|mon-2': AttendanceEntry(
            status: AttendanceStatus.late,
            markedAt: DateTime(2026, 11, 9, 9, 40),
            lessonKey: 'mon-2',
            lessonTitle: 'Понедельничная пара 2',
          ),
        }),
      ],
      schedule: scheduleWith(),
    );

    final cell = api.cell(tabTitle, 3, blockStart(9) + 1);
    expect(cell.backgroundColor, 0xFF9900);
    expect(cell.value, '9:40');
  });

  test('опоздание без расписания попадает в пару из «Пара N»', () async {
    final api = FakeSheetsApi();
    seedJournal(api, month: month, pairsByDay: pairsByDay, students: const [
      alexey,
      maria,
    ]);
    final service = JournalSyncService(api);

    await service.push(
      spreadsheetId: 'sid',
      mapping: mapping,
      sessions: [
        session({
          '1|Пара 2': AttendanceEntry(
            status: AttendanceStatus.late,
            markedAt: DateTime(2026, 11, 9, 9, 40),
            lessonKey: 'pair-2',
            lessonTitle: 'Пара 2',
          ),
        }),
      ],
    );

    final cell = api.cell(tabTitle, 3, blockStart(9) + 1);
    expect(cell.backgroundColor, 0xFF9900);
    expect(cell.value, '9:40');
  });

  test('отметки другого студента ложатся в его строку', () async {
    final api = FakeSheetsApi();
    seedJournal(api, month: month, pairsByDay: pairsByDay, students: const [
      alexey,
      maria,
    ]);
    final service = JournalSyncService(api);

    await service.push(
      spreadsheetId: 'sid',
      mapping: mapping,
      sessions: [
        session({
          '2': AttendanceEntry(
            status: AttendanceStatus.absent,
            markedAt: DateTime(2026, 11, 9, 9),
          ),
        }),
      ],
      schedule: scheduleWith(),
    );

    final cell = api.cell(tabTitle, 4, blockStart(9));
    expect(cell.backgroundColor, 0xFF0000);
    expect(cell.value, 'Н');
    // Строка Алексея не тронута.
    expect(api.cell(tabTitle, 3, blockStart(9)).backgroundColor, isNull);
  });

  test('чужие отметки не затираются, если локальных нет', () async {
    final api = FakeSheetsApi();
    seedJournal(
      api,
      month: month,
      pairsByDay: pairsByDay,
      students: const [alexey, maria],
      marks: {
        9: {
          'Алексей Морозов': {
            3: AttendanceEntry(
              status: AttendanceStatus.excused,
              markedAt: DateTime(2026, 11, 9, 9),
            ),
          },
        },
      },
    );
    final service = JournalSyncService(api);

    await service.push(
      spreadsheetId: 'sid',
      mapping: mapping,
      sessions: [session(const {})],
      schedule: scheduleWith(),
    );

    // Синяя отметка «по уважительной» осталась на месте.
    final cell = api.cell(tabTitle, 3, blockStart(9) + 2);
    expect(cell.backgroundColor, 0x4472C4);
    expect(api.batchUpdateCalls, 0);
  });

  test('пары нет в блоке дня — таблица не согласована с расписанием',
      () async {
    final api = FakeSheetsApi();
    seedJournal(api, month: month, pairsByDay: pairsByDay, students: const [
      alexey,
      maria,
    ]);
    final service = JournalSyncService(api);

    // День 9 — понедельник, блок 3 колонки; по расписанию четырнадцатая
    // пара не влезает: блок шире расписания не становится.
    await expectLater(
      service.push(
        spreadsheetId: 'sid',
        mapping: mapping,
        sessions: [
          session({
            '1|mon-4': AttendanceEntry(
              status: AttendanceStatus.came,
              markedAt: DateTime(2026, 11, 9, 9),
              lessonKey: 'mon-4',
            ),
          }),
        ],
        schedule: scheduleWith(monday: 4),
      ),
      throwsA(
        isA<CloudSyncException>().having(
          (error) => error.message,
          'message',
          contains('Пары 4 нет в дне 9'),
        ),
      ),
    );
  });

  test('дня нет в таблице — отправка останавливается с подсказкой',
      () async {
    final api = FakeSheetsApi();
    // Журнал, где 9-е пропущено: числа 1…8, 10…30. Числа — на строке 2
    // (0-based 1), студент — на строке 4 (0-based 3).
    final numbers = List<SeedCell?>.filled(100, null);
    var column = 2;
    for (var day = 1; day <= 30; day++) {
      if (day == 9) continue;
      numbers[column] = api.seedCell(value: day);
      column += 3;
    }
    final student = List<SeedCell?>.filled(100, null)
      ..[1] = api.seedCell(value: 'Алексей Морозов');
    api.seedSheet(tabTitle, [
      List<SeedCell?>.filled(100, null),
      numbers,
      List<SeedCell?>.filled(100, null),
      student,
    ]);
    final service = JournalSyncService(api);

    await expectLater(
      service.push(
        spreadsheetId: 'sid',
        mapping: mapping,
        sessions: [
          session({
            '1': AttendanceEntry(
              status: AttendanceStatus.came,
              markedAt: DateTime(2026, 11, 9, 9),
            ),
          }),
        ],
        schedule: scheduleWith(),
      ),
      throwsA(
        isA<CloudSyncException>().having(
          (error) => error.message,
          'message',
          contains('нет дня 9'),
        ),
      ),
    );
  });

  test('студента нет в журнале — приложение не добавляет его само',
      () async {
    final api = FakeSheetsApi();
    seedJournal(api, month: month, pairsByDay: pairsByDay, students: const [
      alexey,
    ]);
    final service = JournalSyncService(api);

    await expectLater(
      service.push(
        spreadsheetId: 'sid',
        mapping: mapping,
        sessions: [
          session({
            '2': AttendanceEntry(
              status: AttendanceStatus.came,
              markedAt: DateTime(2026, 11, 9, 9),
            ),
          }),
        ],
        schedule: scheduleWith(),
      ),
      throwsA(
        isA<CloudSyncException>().having(
          (error) => error.message,
          'message',
          contains('Мария Соколова'),
        ),
      ),
    );
  });

  test('загрузка читает список по ФИО и отметки по парам', () async {
    final api = FakeSheetsApi();
    seedJournal(
      api,
      month: month,
      pairsByDay: pairsByDay,
      students: const [alexey, maria],
      marks: {
        9: {
          'Алексей Морозов': {
            1: AttendanceEntry(
              status: AttendanceStatus.late,
              markedAt: DateTime(2026, 11, 9, 9, 40),
            ),
          },
          'Мария Соколова': {
            2: AttendanceEntry(
              status: AttendanceStatus.came,
              markedAt: DateTime(2026, 11, 9, 9),
            ),
          },
        },
      },
    );
    final service = JournalSyncService(api);

    final roster = await service.read(
      spreadsheetId: 'sid',
      mapping: mapping,
      month: month,
      schedule: scheduleWith(),
    );

    expect(
      roster.students.map((student) => student.fullName),
      ['Алексей Морозов', 'Мария Соколова'],
    );
    // Первая колонка блока — отметка на весь день.
    final alexeyEntries = roster.entries[9]!;
    expect(alexeyEntries['Алексей Морозов']!.status, AttendanceStatus.late);
    expect(alexeyEntries['Алексей Морозов']!.markedAt, DateTime(2026, 11, 9, 9, 40));
    expect(alexeyEntries['Алексей Морозов']!.lessonKey, isNull);
    // Вторая колонка — пара из расписания.
    final mariaEntry = alexeyEntries['Мария Соколова|mon-2'];
    expect(mariaEntry, isNotNull);
    expect(mariaEntry!.status, AttendanceStatus.came);
    expect(mariaEntry.lessonKey, 'mon-2');
    expect(mariaEntry.lessonTitle, 'Понедельничная пара 2');
  });

  test('месяц подбирается из названия листа «МЕСЯЦ : ГОД»', () async {
    final api = FakeSheetsApi();
    seedJournal(api, month: month, pairsByDay: pairsByDay, students: const [
      alexey,
      maria,
    ]);
    final service = JournalSyncService(api);

    final snapshot = await service.snapshot(
      spreadsheetId: 'sid',
      mapping: mapping,
      schedule: scheduleWith(),
    );
    expect(snapshot.month, DateTime(2026, 11));
    expect(snapshot.check.ok, isTrue);

    // Октябрьские отметки в ноябрьский журнал не пишутся.
    final result = await service.push(
      spreadsheetId: 'sid',
      mapping: mapping,
      sessions: [
        AttendanceSession(
          groupName: 'БИТ-24-03',
          date: DateTime(2026, 10, 5),
          students: const [alexey],
          entries: {
            '1': AttendanceEntry(
              status: AttendanceStatus.came,
              markedAt: DateTime(2026, 10, 5, 9),
            ),
          },
        ),
      ],
      schedule: scheduleWith(),
    );
    expect(result.updatedCells, 0);
    expect(api.batchUpdateCalls, 0);
  });

  test('название не похоже на месяц — нужна подсказка', () async {
    final api = FakeSheetsApi();
    seedJournal(
      api,
      month: month,
      pairsByDay: pairsByDay,
      students: const [alexey],
      tabTitle: 'Посещаемость',
    );
    final service = JournalSyncService(api);

    final snapshot = await service.snapshot(
      spreadsheetId: 'sid',
      mapping: const JournalMapping(
        tabTitle: 'Посещаемость',
        dayRow: 1,
        fioColumn: 1,
        firstStudentRow: 3,
      ),
      schedule: scheduleWith(),
    );
    expect(snapshot.month, isNull);

    await expectLater(
      service.push(
        spreadsheetId: 'sid',
        mapping: const JournalMapping(
          tabTitle: 'Посещаемость',
          dayRow: 1,
          fioColumn: 1,
          firstStudentRow: 3,
        ),
        sessions: [
          session({
            '1': AttendanceEntry(
              status: AttendanceStatus.came,
              markedAt: DateTime(2026, 11, 9, 9),
            ),
          }),
        ],
        schedule: scheduleWith(),
      ),
      throwsA(isA<CloudSyncException>()),
    );
  });

  test('листа журнала нет — понятная ошибка', () async {
    final api = FakeSheetsApi();
    seedJournal(api, month: month, pairsByDay: pairsByDay, students: const [
      alexey,
    ]);
    final service = JournalSyncService(api);

    await expectLater(
      service.snapshot(
        spreadsheetId: 'sid',
        mapping: const JournalMapping(
          tabTitle: 'Декабрь : 2026',
          dayRow: 1,
          fioColumn: 1,
          firstStudentRow: 3,
        ),
        schedule: scheduleWith(),
      ),
      throwsA(
        isA<CloudSyncException>().having(
          (error) => error.message,
          'message',
          contains('Декабрь : 2026'),
        ),
      ),
    );
  });
}
