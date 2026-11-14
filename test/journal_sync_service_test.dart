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
import 'package:yavka/services/cloud/journal_cell_codec.dart';
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

  // Блоки по рабочим дням (5 колонок цикла): пн — 3, вт — 2, ср — 1,
  // чт — 2, пт — 1. Выходных в журнале нет.
  const pairsByDay = [3, 2, 1, 2, 1];
  final mapping = const JournalMapping(
    tabTitle: tabTitle,
    dayRow: 1,
    fioColumn: 1,
    firstStudentRow: 3,
  );

  // Начало блока дня: колонки копятся с первой колонки после ФИО,
  // выходные (суббота и воскресенье) колонок не занимают.
  int blockStart(int day) {
    var column = 2;
    var working = 0;
    for (var d = 1; d < day; d++) {
      if (DateTime(2026, 11, d).weekday >= 6) continue;
      column += pairsByDay[working % pairsByDay.length];
      working++;
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

  test('отметка на весь день раскладывается на все пары дня', () async {
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

    // Отметка на весь день стоит в каждой колонке пары дня: у 9 ноября
    // их три, все три покрашены.
    for (var offset = 0; offset < 3; offset++) {
      final cell = api.cell(tabTitle, 3, blockStart(9) + offset);
      expect(cell.backgroundColor, 0x00FF00, reason: 'колонка $offset');
      expect(cell.value, isNull);
    }
    expect(result.updatedCells, 3);
    // Одна посылка updateCells — структуру не трогаем.
    expect(api.batchRequestLog, hasLength(1));
    expect(api.batchRequestLog.single, everyElement('updateCells'));
  });

  test('отдельная отметка пары не тронута отметкой на весь день', () async {
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
          // Весь день: пришёл на все пары.
          '1': AttendanceEntry(
            status: AttendanceStatus.came,
            markedAt: DateTime(2026, 11, 9, 9),
          ),
          // Но на второй паре — опоздал: время важнее общей отметки.
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

    final first = api.cell(tabTitle, 3, blockStart(9));
    expect(first.backgroundColor, 0x00FF00); // пришёл
    final second = api.cell(tabTitle, 3, blockStart(9) + 1);
    expect(second.backgroundColor, 0xFF9900); // опоздал, время сохранилось
    expect(second.value, '9:40');
    final third = api.cell(tabTitle, 3, blockStart(9) + 2);
    expect(third.backgroundColor, 0x00FF00); // пришёл
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
    // «Н» стоит в каждой колонке пары дня.
    expect(api.cell(tabTitle, 4, blockStart(9) + 1).value, 'Н');
    expect(api.cell(tabTitle, 4, blockStart(9) + 2).value, 'Н');
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

  test('пары нет в блоке дня — день пропускается как обрывок', () async {
    final api = FakeSheetsApi();
    seedJournal(api, month: month, pairsByDay: pairsByDay, students: const [
      alexey,
      maria,
    ]);
    final service = JournalSyncService(api);

    // День 9 — понедельник, блок 3 колонки; по расписанию четыре пары,
    // четвёртой колонки нет: день — обрывок.
    final result = await service.push(
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
    );

    // Ничего не записано, день попал в предупреждение.
    expect(result.updatedCells, 0);
    expect(result.skippedDays, [9]);
    expect(api.batchUpdateCalls, 0);
  });

  test('дня нет в таблице — отметки за него пропускаются', () async {
    final api = FakeSheetsApi();
    // Журнал без выходных, где 9-е пропущено: числа рабочих дней
    // 1…8, 10…30. Числа — на строке 2 (0-based 1), студент — на строке
    // 4 (0-based 3).
    final numbers = List<SeedCell?>.filled(100, null);
    var column = 2;
    for (var day = 1; day <= 30; day++) {
      if (day == 9) continue;
      if (DateTime(2026, 11, day).weekday >= 6) continue;
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

    // Ошибки нет: день пропущен, посещаемость в него не расставить.
    expect(result.updatedCells, 0);
    expect(result.skippedDays, [9]);
    expect(result.skippedNote, contains('9'));
    expect(api.batchUpdateCalls, 0);
  });

  test('журнал начинается не с 1 числа — пропущенные дни игнорируются',
      () async {
    final api = FakeSheetsApi();
    // Журнал начинается с 3 ноября: чисел дней 1 и 2 в таблице нет.
    final numbers = List<SeedCell?>.filled(100, null);
    var column = 2;
    for (var day = 3; day <= 30; day++) {
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

    final result = await service.push(
      spreadsheetId: 'sid',
      mapping: mapping,
      sessions: [
        AttendanceSession(
          groupName: 'БИТ-24-03',
          date: DateTime(2026, 11, 1),
          students: const [alexey, maria],
          entries: {
            '1': AttendanceEntry(
              status: AttendanceStatus.came,
              markedAt: DateTime(2026, 11, 1, 9),
            ),
          },
        ),
        AttendanceSession(
          groupName: 'БИТ-24-03',
          date: DateTime(2026, 11, 2),
          students: const [alexey, maria],
          entries: {
            '1': AttendanceEntry(
              status: AttendanceStatus.came,
              markedAt: DateTime(2026, 11, 2, 9),
            ),
          },
        ),
      ],
      schedule: scheduleWith(),
    );

    // Дней 1 и 2 нет в журнале: отметки не расставить, об ошибках
    // речи нет — дни попадают в предупреждение.
    expect(result.updatedCells, 0);
    expect(result.skippedDays, [1, 2]);
    expect(api.batchUpdateCalls, 0);

    // Зато день 3, который в журнале есть, пишется как обычно.
    final written = await service.push(
      spreadsheetId: 'sid',
      mapping: mapping,
      sessions: [
        AttendanceSession(
          groupName: 'БИТ-24-03',
          date: DateTime(2026, 11, 3),
          students: const [alexey, maria],
          entries: {
            '1': AttendanceEntry(
              status: AttendanceStatus.came,
              markedAt: DateTime(2026, 11, 3, 9),
            ),
          },
        ),
      ],
      schedule: scheduleWith(),
    );
    expect(written.updatedCells, 3);
    expect(written.skippedDays, isEmpty);
    expect(api.cell(tabTitle, 3, 2).backgroundColor, 0x00FF00);
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

  test('пары нет в строке пар — день пропускается как обрывок', () async {
    final api = FakeSheetsApi();
    seedJournal(api, month: month, pairsByDay: pairsByDay, students: const [
      alexey,
      maria,
    ]);
    // У дня 9 в строке пар стираем номер третьей колонки: пары 3 в
    // таблице больше нет, хотя по расписанию она есть.
    final override = List<List<SeedCell?>>.generate(3, (_) => <SeedCell?>[]);
    override[2] = List<SeedCell?>.filled(40, null);
    override[2][blockStart(9) + 2] = api.seedCell();
    api.seedSheet(tabTitle, override);

    final service = JournalSyncService(api);
    final result = await service.push(
      spreadsheetId: 'sid',
      mapping: const JournalMapping(
        tabTitle: tabTitle,
        dayRow: 1,
        fioColumn: 1,
        firstStudentRow: 3,
        pairRow: 2,
      ),
      sessions: [
        session({
          '1|mon-3': AttendanceEntry(
            status: AttendanceStatus.came,
            markedAt: DateTime(2026, 11, 9, 9),
            lessonKey: 'mon-3',
          ),
        }),
      ],
      schedule: scheduleWith(),
    );

    // Ничего не записано, день попал в предупреждение об обрывке.
    expect(result.updatedCells, 0);
    expect(result.skippedDays, [9]);
    expect(api.batchUpdateCalls, 0);
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
    // Первая колонка блока — пара 1 из расписания.
    final alexeyEntries = roster.entries[9]!;
    final alexeyFirst = alexeyEntries['Алексей Морозов|mon-1'];
    expect(alexeyFirst, isNotNull);
    expect(alexeyFirst!.status, AttendanceStatus.late);
    expect(alexeyFirst.markedAt, DateTime(2026, 11, 9, 9, 40));
    expect(alexeyFirst.lessonKey, 'mon-1');
    expect(alexeyFirst.lessonTitle, 'Понедельничная пара 1');
    // Вторая колонка — пара 2 из расписания.
    final mariaEntry = alexeyEntries['Мария Соколова|mon-2'];
    expect(mariaEntry, isNotNull);
    expect(mariaEntry!.status, AttendanceStatus.came);
    expect(mariaEntry.lessonKey, 'mon-2');
    expect(mariaEntry.lessonTitle, 'Понедельничная пара 2');
  });

  test('без расписания ключи пар берутся из строки пар таблицы', () async {
    final api = FakeSheetsApi();
    seedJournal(
      api,
      month: month,
      pairsByDay: pairsByDay,
      students: const [alexey, maria],
      marks: {
        9: {
          'Алексей Морозов': {
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
      mapping: const JournalMapping(
        tabTitle: tabTitle,
        dayRow: 1,
        fioColumn: 1,
        firstStudentRow: 3,
        pairRow: 2,
      ),
      month: month,
      // Расписания нет — номера пар берутся из строки «ПАРА».
    );

    final alexeyEntries = roster.entries[9]!;
    expect(alexeyEntries.keys, ['Алексей Морозов|pair-2']);
    expect(alexeyEntries['Алексей Морозов|pair-2']!.lessonTitle, 'Пара 2');
  });

  test('номера пар читаются из строки «ПАРА» даже со сдвигом', () async {
    final api = FakeSheetsApi();
    seedJournal(
      api,
      month: month,
      pairsByDay: pairsByDay,
      students: const [alexey],
      marks: {
        9: {
          'Алексей Морозов': {
            2: AttendanceEntry(
              status: AttendanceStatus.late,
              markedAt: DateTime(2026, 11, 9, 9, 30),
            ),
          },
        },
      },
    );
    // Строка пар дня 9: первая колонка блока без номера (колонка «на
    // весь день»), пары 2 и 3 — во второй и третьей колонках.
    final override = List<List<SeedCell?>>.generate(3, (_) => <SeedCell?>[]);
    override[2] = [
      ...List<SeedCell?>.filled(40, null),
    ];
    override[2][blockStart(9)] = api.seedCell(); // стираем номер первой
    override[2][blockStart(9) + 1] = api.seedCell(value: 2);
    override[2][blockStart(9) + 2] = api.seedCell(value: 3);
    api.seedSheet(tabTitle, override);

    final service = JournalSyncService(api);
    final roster = await service.read(
      spreadsheetId: 'sid',
      mapping: const JournalMapping(
        tabTitle: tabTitle,
        dayRow: 1,
        fioColumn: 1,
        firstStudentRow: 3,
        pairRow: 2,
      ),
      month: month,
    );

    final alexeyEntries = roster.entries[9]!;
    // Отметка стоит во второй колонке блока — строка пар говорит, что
    // это пара 2; колонка без номера парами не считается.
    expect(alexeyEntries.keys, ['Алексей Морозов|pair-2']);
    expect(
      alexeyEntries['Алексей Морозов|pair-2']!.markedAt,
      DateTime(2026, 11, 9, 9, 30),
    );
  });

  test('отметка на весь день раскладывается по парам из строки «ПАРА»',
      () async {
    final api = FakeSheetsApi();
    seedJournal(api, month: month, pairsByDay: pairsByDay, students: const [
      alexey,
    ]);
    // У дня 9 в строке пар только числа 1 и 2: третья колонка блока —
    // не пара, и отметка на весь день её не трогает.
    final override = List<List<SeedCell?>>.generate(3, (_) => <SeedCell?>[]);
    override[2] = List<SeedCell?>.filled(40, null);
    override[2][blockStart(9) + 2] = api.seedCell(); // стираем номер
    api.seedSheet(tabTitle, override);

    final service = JournalSyncService(api);
    await service.push(
      spreadsheetId: 'sid',
      mapping: const JournalMapping(
        tabTitle: tabTitle,
        dayRow: 1,
        fioColumn: 1,
        firstStudentRow: 3,
        pairRow: 2,
      ),
      sessions: [
        session({
          '1': AttendanceEntry(
            status: AttendanceStatus.came,
            markedAt: DateTime(2026, 11, 9, 9),
          ),
        }),
      ],
    );

    // Пары дня — колонки с номерами в строке пар: их две.
    expect(
      api.cell(tabTitle, 3, blockStart(9)).backgroundColor,
      0x00FF00,
    );
    expect(
      api.cell(tabTitle, 3, blockStart(9) + 1).backgroundColor,
      0x00FF00,
    );
    // Третья колонка не пара — осталась пустой.
    expect(
      api.cell(tabTitle, 3, blockStart(9) + 2).backgroundColor,
      isNull,
    );
  });

  test('отметка на весь день не разливается на колонки за блоком',
      () async {
    final api = FakeSheetsApi();
    // Маленький журнал: день 1 — 1 колонка, день 2 — 2 колонки, но сам
    // лист шириной 10: справа от последнего блока пустые колонки.
    final empty = List<SeedCell?>.filled(10, null);
    final numbers = [...empty];
    numbers[1] = api.seedCell(value: '№');
    numbers[2] = api.seedCell(value: 1);
    numbers[3] = api.seedCell(value: 2);
    final pairs = [...empty];
    pairs[1] = api.seedCell(value: 'ПАРА');
    pairs[2] = api.seedCell(value: 1);
    pairs[3] = api.seedCell(value: 1);
    pairs[4] = api.seedCell(value: 2);
    final student = [...empty];
    student[1] = api.seedCell(value: 'Алексей Морозов');
    api.seedSheet(tabTitle, [empty, numbers, pairs, student]);

    final service = JournalSyncService(api);
    final result = await service.push(
      spreadsheetId: 'sid',
      mapping: const JournalMapping(
        tabTitle: tabTitle,
        dayRow: 1,
        fioColumn: 1,
        firstStudentRow: 3,
        pairRow: 2,
      ),
      sessions: [
        AttendanceSession(
          groupName: 'БИТ-24-03',
          date: DateTime(2026, 11, 2),
          students: const [alexey],
          entries: {
            '1': AttendanceEntry(
              status: AttendanceStatus.came,
              markedAt: DateTime(2026, 11, 2, 9),
            ),
          },
        ),
      ],
      // Расписания нет: пары дня — по строке «ПАРА».
    );

    // У дня 2 две колонки пар, зелёная отметка ровно в них.
    expect(result.updatedCells, 2);
    expect(api.cell(tabTitle, 3, 3).backgroundColor, 0x00FF00);
    expect(api.cell(tabTitle, 3, 4).backgroundColor, 0x00FF00);
    // Пустые колонки за блоком не тронуты.
    expect(api.cell(tabTitle, 3, 5).backgroundColor, isNull);
    expect(api.cell(tabTitle, 3, 9).backgroundColor, isNull);
  });

  test('конечная строка студентов ограничивает список группы', () async {
    final api = FakeSheetsApi();
    seedJournal(api, month: month, pairsByDay: pairsByDay, students: const [
      alexey,
      maria,
    ]);
    // Под списком группы в таблице живут итоги и примечания — конечная
    // строка ФИО отсекает их от списка.
    final junk = List<List<SeedCell?>>.generate(7, (_) => <SeedCell?>[]);
    junk[5] = [null, api.seedCell(value: 'Итого')];
    junk[6] = [null, api.seedCell(value: 'Примечания')];
    api.seedSheet(tabTitle, junk);

    final service = JournalSyncService(api);
    final roster = await service.read(
      spreadsheetId: 'sid',
      mapping: const JournalMapping(
        tabTitle: tabTitle,
        dayRow: 1,
        fioColumn: 1,
        firstStudentRow: 3,
        pairRow: 2,
        lastStudentRow: 4, // Мария на строке 0-based 4 — последняя.
      ),
      month: month,
    );

    expect(
      roster.students.map((student) => student.fullName),
      ['Алексей Морозов', 'Мария Соколова'],
    );

    // Без конечной строки «Итого» попал бы в список.
    final unbounded = await service.read(
      spreadsheetId: 'sid',
      mapping: const JournalMapping(
        tabTitle: tabTitle,
        dayRow: 1,
        fioColumn: 1,
        firstStudentRow: 3,
        pairRow: 2,
      ),
      month: month,
    );
    expect(
      unbounded.students.map((student) => student.fullName),
      contains('Итого'),
    );
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

  test('зелёный «пришёл» — зелёный из палитры Google', () {
    // В заливку идёт RGB без альфа-канала — как его хранит таблица.
    expect(JournalCellCodec.cellColor(AttendanceStatus.came), 0x00FF00);
    // Зелёный, который даёт Google при выборе «Зелёного», читается.
    expect(JournalCellCodec.statusFromColor(0x00FF00), AttendanceStatus.came);
    // Зелёный ранних версий приложения тоже читается: старые отметки
    // журнала не пропадут, а при следующей отправке перезапишутся.
    expect(JournalCellCodec.statusFromColor(0x00CC00), AttendanceStatus.came);
    // Другие цвета палитры Google «пришедшим» не считаются.
    expect(JournalCellCodec.statusFromColor(0x00FFFF), isNull);
  });
}
