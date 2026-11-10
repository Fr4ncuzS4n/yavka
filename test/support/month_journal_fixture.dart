import 'package:yavka/models/attendance_entry.dart';
import 'package:yavka/models/student.dart';
import 'package:yavka/services/cloud/month_grid_codec.dart';

import 'fake_sheets_api.dart';

/// Рисует в фейковой таблице журнал одного месяца: три строки шапки
/// с мержами и строки студентов с отметками в заливках.
void seedJournal(
  FakeSheetsApi api, {
  required DateTime month,
  required List<Student> students,
  Map<int, Map<String, AttendanceEntry>> marks = const {},
  String? tabTitle,
}) {
  final canonicalTitle = MonthGridCodec.monthSheetTitle(month);
  final title = tabTitle ?? canonicalTitle;
  final days = MonthGridCodec.daysInMonth(month);
  final totalColumns = MonthGridCodec.firstDayColumn + days * 4;

  List<SeedCell?> emptyRow() => List.generate(totalColumns, (_) => null);

  final weekRow = emptyRow();
  final numberRow = emptyRow();
  final pairRow = emptyRow();

  weekRow[1] = api.seedCell(
    value: MonthGridCodec.monthBanner(month),
    merged: true,
    mergeCols: 4,
  );
  numberRow[0] = api.seedCell(value: '№');
  numberRow[1] = api.seedCell(value: 'ФИО');
  pairRow[1] = api.seedCell(value: 'ПАРА');

  for (var day = 1; day <= days; day++) {
    final first = MonthGridCodec.firstColumnOf(month, day);
    weekRow[first] = api.seedCell(
      value: MonthGridCodec.weekdayName(DateTime(month.year, month.month, day)),
      merged: true,
      mergeCols: 4,
    );
    numberRow[first] = api.seedCell(value: day, merged: true, mergeCols: 4);
    for (var pair = 1; pair <= 4; pair++) {
      pairRow[first + pair - 1] = api.seedCell(value: pair);
    }
  }

  final rows = <List<SeedCell?>>[weekRow, numberRow, pairRow];
  for (final student in students) {
    final row = emptyRow();
    row[0] = api.seedCell(value: student.id);
    row[1] = api.seedCell(value: student.fullName);
    marks.forEach((day, byStudent) {
      final entry = byStudent[student.id];
      if (entry == null) return;
      final column = MonthGridCodec.firstColumnOf(month, day);
      row[column] = api.seedCell(
        value: MonthGridCodec.cellTextFor(entry),
        background: MonthGridCodec.colorFor(entry.status).toARGB32() & 0xFFFFFF,
      );
    });
    rows.add(row);
  }

  api.seedSheet(title, rows);
}
