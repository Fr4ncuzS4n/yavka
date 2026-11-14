import 'package:yavka/models/attendance_entry.dart';
import 'package:yavka/models/schedule_lesson.dart';
import 'package:yavka/models/student.dart';
import 'package:yavka/services/cloud/journal_cell_codec.dart';
import 'package:yavka/services/cloud/journal_month.dart';

import 'fake_sheets_api.dart';

/// Рисует в фейковой таблице готовый журнал месяца, как его ведёт
/// человек: лист «МЕСЯЦ : ГОД», строка чисел дней, колонка ФИО и блоки
/// колонок под пары. В разные дни блоки разной ширины — приложение
/// подстраивается под такую таблицу.
void seedJournal(
  FakeSheetsApi api, {
  required DateTime month,

  /// Сколько колонок-пар в каждом дне; список циклится по дням месяца.
  required List<int> pairsByDay,
  List<Student> students = const [],

  /// Название листа; по умолчанию «НОЯБРЬ : 2026».
  String? tabTitle,

  /// Строка с числами дней (1-based).
  int dayRow = 2,

  /// Колонка ФИО (0-based).
  int fioColumn = 1,

  /// Первая строка студентов (1-based).
  int firstStudentRow = 4,

  /// Отметки: день → ФИО студента → номер пары → отметка.
  Map<int, Map<String, Map<int, AttendanceEntry>>> marks = const {},
}) {
  final title = tabTitle ?? JournalMonth.displayName(month).toUpperCase()
      .replaceFirst(' ', ' : ');
  final days = JournalCellCodec.daysInMonth(month);

  // Блоки дней начинаются сразу после колонки ФИО.
  final firstBlock = fioColumn + 1;
  final starts = <int>[];
  var cursor = firstBlock;
  for (var day = 1; day <= days; day++) {
    starts.add(cursor);
    cursor += pairsByDay[(day - 1) % pairsByDay.length];
  }
  final totalColumns = cursor;

  List<SeedCell?> empty() => List.generate(totalColumns, (_) => null);

  final weekdayRow = empty();
  final numberRow = empty();
  final pairRow = empty();
  weekdayRow[fioColumn] = api.seedCell(
    value: JournalMonth.monthName(month.month).toUpperCase(),
  );
  numberRow[fioColumn] = api.seedCell(value: '№');
  pairRow[fioColumn] = api.seedCell(value: 'ПАРА');

  for (var day = 1; day <= days; day++) {
    final start = starts[day - 1];
    final date = DateTime(month.year, month.month, day);
    weekdayRow[start] = api.seedCell(value: weekdayFullName(weekdayOf(date)));
    numberRow[start] = api.seedCell(value: day);
    final pairs = pairsByDay[(day - 1) % pairsByDay.length];
    for (var pair = 1; pair <= pairs; pair++) {
      pairRow[start + pair - 1] = api.seedCell(value: pair);
    }
  }

  final rows = <List<SeedCell?>>[];
  // Над строкой чисел — строка с названиями дней недели; сами числа
  // живут на строке dayRow (1-based), как их видит пользователь.
  for (var row = 0; row < dayRow - 2; row++) {
    rows.add(empty());
  }
  rows.add(weekdayRow);
  rows.add(numberRow);
  while (rows.length < firstStudentRow - 2) {
    rows.add(empty());
  }
  rows.add(pairRow);

  for (final student in students) {
    final row = empty();
    row[fioColumn] = api.seedCell(value: student.fullName);
    for (var day = 1; day <= days; day++) {
      final forStudent = marks[day]?[student.fullName];
      if (forStudent == null) continue;
      forStudent.forEach((pair, entry) {
        final start = starts[day - 1];
        if (pair < 1 || pair > pairsByDay[(day - 1) % pairsByDay.length]) {
          return;
        }
        final text = JournalCellCodec.cellTextFor(entry);
        row[start + pair - 1] = api.seedCell(
          value: text,
          background: JournalCellCodec.cellColor(entry.status),
        );
      });
    }
    rows.add(row);
  }

  api.seedSheet(title, rows);
}
