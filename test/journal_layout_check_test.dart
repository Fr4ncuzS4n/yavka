// Тесты раскладки журнала: блоки дней по строке чисел и сверка
// с расписанием приложения (пары в дни идут по-разному).

import 'package:flutter_test/flutter_test.dart';
import 'package:yavka/data/schedule_controller.dart';
import 'package:yavka/models/schedule_lesson.dart';
import 'package:yavka/models/student.dart';
import 'package:yavka/services/cloud/journal_check.dart';
import 'package:yavka/services/cloud/journal_layout.dart';
import 'package:yavka/services/cloud/journal_mapping.dart';

import 'support/fake_sheets_api.dart';
import 'support/month_journal_fixture.dart';

void main() {
  final month = DateTime(2026, 11, 1);
  const alexey = Student(id: '1', fullName: 'Алексей Морозов');
  // Блоки по дням недели: вс — 1 колонка, пн — 3, вт — 2 и т.д.
  // Длина цикла 7 — недели совпадают с днями недели.
  const pairsByDay = [1, 3, 2, 1, 2, 1, 1];
  final mapping = const JournalMapping(
    tabTitle: 'НОЯБРЬ : 2026',
    dayRow: 1,
    fioColumn: 1,
    firstStudentRow: 3,
  );

  // Начало блока дня: колонки копятся с первой колонки после ФИО.
  int blockStart(int day) {
    var column = 2;
    for (var d = 1; d < day; d++) {
      column += pairsByDay[(d - 1) % pairsByDay.length];
    }
    return column;
  }

  ScheduleController scheduleWith({int monday = 3, int tuesday = 2}) {
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
    for (var i = 1; i <= tuesday; i++) {
      schedule.add(
        ScheduleLesson(
          id: 'tue-$i',
          weekday: 2,
          startMinutes: 480 + i * 100,
          subject: 'Вторничная пара $i',
        ),
      );
    }
    return schedule;
  }

  test('блоки дней снимаются со строки чисел', () async {
    final api = FakeSheetsApi();
    seedJournal(api, month: month, pairsByDay: pairsByDay, students: [alexey]);
    final grid = (await api.getSheetGrid('sid', 'НОЯБРЬ : 2026'))!;

    final layout = JournalLayout.scan(grid, mapping);

    expect(layout, isNotNull);
    expect(layout!.spanOf(1)!.startColumn, 2);
    // 1 ноября — воскресенье: блок из 1 колонки.
    expect(layout.spanOf(1)!.width, 1);
    // 9 ноября — понедельник: блок из 3 колонок.
    expect(layout.spanOf(9)!.startColumn, blockStart(9));
    expect(layout.spanOf(9)!.width, 3);
    expect(layout.spanOf(10)!.width, 2);
    expect(layout.spanOf(31), isNull);
    // Пара 3 есть в широком дне и нет в узком.
    expect(layout.spanOf(9)!.hasPair(3), isTrue);
    expect(layout.spanOf(10)!.hasPair(3), isFalse);
    expect(layout.spanOf(9)!.columnOfPair(3), blockStart(9) + 2);
  });

  test('номера пар снимаются со строки «ПАРА»', () async {
    final api = FakeSheetsApi();
    seedJournal(api, month: month, pairsByDay: pairsByDay, students: [alexey]);
    final grid = (await api.getSheetGrid('sid', 'НОЯБРЬ : 2026'))!;

    final layout = JournalLayout.scan(
      grid,
      const JournalMapping(
        tabTitle: 'НОЯБРЬ : 2026',
        dayRow: 1,
        fioColumn: 1,
        firstStudentRow: 3,
        pairRow: 2,
      ),
    );

    expect(layout, isNotNull);
    // В блоке дня 9 строка пар говорит 1, 2, 3 — как и в фиксуре.
    final span9 = layout!.spanOf(9)!;
    expect(span9.pairs, [1, 2, 3]);
    expect(span9.columnOfPair(1), blockStart(9));
    expect(span9.columnOfPair(3), blockStart(9) + 2);
    // Колонки без номера в строке пар — уже не колонки пар.
    expect(span9.hasPair(4), isFalse);
  });

  test('пары расписания обязаны найтись в строке пар', () async {
    final api = FakeSheetsApi();
    seedJournal(api, month: month, pairsByDay: pairsByDay, students: [alexey]);
    // У дня 9 стираем номер третьей колонки: пары 3 в таблице нет.
    final override = List<List<SeedCell?>>.generate(3, (_) => <SeedCell?>[]);
    override[2] = List<SeedCell?>.filled(40, null);
    override[2][blockStart(9) + 2] = api.seedCell();
    api.seedSheet('НОЯБРЬ : 2026', override);

    final mapping = const JournalMapping(
      tabTitle: 'НОЯБРЬ : 2026',
      dayRow: 1,
      fioColumn: 1,
      firstStudentRow: 3,
      pairRow: 2,
    );

    final grid = (await api.getSheetGrid('sid', 'НОЯБРЬ : 2026'))!;
    final layout = JournalLayout.scan(grid, mapping)!;

    final report = JournalCheck.check(
      month: month,
      mapping: mapping,
      layout: layout,
      schedule: scheduleWith(monday: 3, tuesday: 2),
    );

    expect(report.ok, isFalse);
    expect(
      report.issues.map((issue) => issue.message).join(' '),
      contains('День 9'),
    );
  });

  test('строка без чисел не разбирается', () async {    final api = FakeSheetsApi();
    api.seedSheet('НОЯБРЬ : 2026', [
      [null, null, null, null],
      [null, null, null, null],
    ]);
    final layout = JournalLayout.scan(
      (await api.getSheetGrid('sid', 'НОЯБРЬ : 2026'))!,
      mapping,
    );
    expect(layout, isNull);
  });

  test('числа не по возрастанию — таблица не разобрана', () async {
    final api = FakeSheetsApi();
    api.seedSheet('НОЯБРЬ : 2026', [
      [null, null, null, null, null, null],
      [
        null,
        null,
        api.seedCell(value: 3),
        api.seedCell(value: 1),
        api.seedCell(value: 2),
        null,
      ],
    ]);
    final layout = JournalLayout.scan(
      (await api.getSheetGrid('sid', 'НОЯБРЬ : 2026'))!,
      mapping,
    );
    expect(layout, isNull);
  });

  test('расписание сходится с таблицей — проверка пройдена', () async {
    final api = FakeSheetsApi();
    seedJournal(api, month: month, pairsByDay: pairsByDay, students: [alexey]);
    final grid = (await api.getSheetGrid('sid', 'НОЯБРЬ : 2026'))!;
    final layout = JournalLayout.scan(grid, mapping)!;

    final report = JournalCheck.check(
      month: month,
      mapping: mapping,
      layout: layout,
      schedule: scheduleWith(monday: 3, tuesday: 2),
    );

    expect(report.ok, isTrue);
    expect(report.issues, isEmpty);
    // В отчёте только дни с парами.
    expect(
      report.rows.map((row) => row.date.day),
      containsAllInOrder([9, 10]),
    );
    final day9 = report.rows.firstWhere((row) => row.date.day == 9);
    expect(day9.pairCount, 3);
    expect(day9.columnCount, 3);
  });

  test('пар больше, чем колонок в блоке, — проверка не пройдена', () async {
    final api = FakeSheetsApi();
    seedJournal(api, month: month, pairsByDay: pairsByDay, students: [alexey]);
    final grid = (await api.getSheetGrid('sid', 'НОЯБРЬ : 2026'))!;
    final layout = JournalLayout.scan(grid, mapping)!;

    final report = JournalCheck.check(
      month: month,
      mapping: mapping,
      layout: layout,
      schedule: scheduleWith(monday: 4, tuesday: 2),
    );

    expect(report.ok, isFalse);
    expect(
      report.issues.map((issue) => issue.message).join(' '),
      contains('День 9'),
    );
  });

  test('дня с парами нет в таблице — проверка это показывает', () {
    final layout = JournalLayout(dayRow: 1, spans: [
      // В таблице только 8-е и 10-е: 9-е пропущено.
      JournalDaySpan(day: 8, startColumn: 2, width: 2),
      JournalDaySpan(day: 10, startColumn: 4, width: 3),
    ]);

    final report = JournalCheck.check(
      month: month,
      mapping: mapping,
      layout: layout,
      schedule: scheduleWith(monday: 3, tuesday: 2),
    );

    expect(report.ok, isFalse);
    expect(
      report.issues.map((issue) => issue.message).join(' '),
      contains('Дня 9 нет'),
    );
  });

  test('пустое расписание — проверять нечего', () async {
    final api = FakeSheetsApi();
    seedJournal(api, month: month, pairsByDay: pairsByDay, students: [alexey]);
    final grid = (await api.getSheetGrid('sid', 'НОЯБРЬ : 2026'))!;
    final layout = JournalLayout.scan(grid, mapping)!;

    final report = JournalCheck.check(
      month: month,
      mapping: mapping,
      layout: layout,
      schedule: ScheduleController.inMemory(),
    );

    expect(report.ok, isTrue);
    expect(report.rows, isEmpty);
  });
}
