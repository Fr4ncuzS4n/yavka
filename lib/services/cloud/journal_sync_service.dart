import '../../data/schedule_controller.dart';
import '../../models/attendance_entry.dart';
import '../../models/attendance_session.dart';
import '../../models/schedule_lesson.dart';
import '../../models/student.dart';
import 'cloud_exceptions.dart';
import 'journal_cell_codec.dart';
import 'journal_check.dart';
import 'journal_layout.dart';
import 'journal_mapping.dart';
import 'journal_month.dart';
import 'sheets_api.dart';

/// Итог отправки отметок в журнал.
class JournalSyncResult {
  const JournalSyncResult({required this.updatedCells});

  /// Сколько ячеек перезаписано.
  final int updatedCells;
}

/// Список группы, снятый с листа журнала.
class JournalRoster {
  const JournalRoster({required this.students, required this.entries});

  /// Студенты из колонки ФИО: идентификатор — ФИО, как в таблице.
  final List<Student> students;

  /// Отметки: день месяца → ключ отметки → отметка.
  ///
  /// Ключ — «ФИО» (отметка на весь день) или «ФИО|ключ пары».
  final Map<int, Map<String, AttendanceEntry>> entries;
}

/// Всё, что приложение сняло с листа журнала за один раз.
class JournalSnapshot {
  const JournalSnapshot({
    required this.month,
    required this.layout,
    required this.check,
  });

  /// Месяц из названия таблицы (или листа); `null`, если не разобрать.
  final DateTime? month;

  /// Раскладка журнала: где какой день и сколько у него колонок.
  final JournalLayout? layout;

  /// Сверка раскладки с расписанием приложения.
  final JournalCheckReport check;
}

/// Синхронизация с существующим журналом Google Таблицы.
///
/// Приложение только отмечает ячейку пары цветом (и временем, если это
/// опоздание). Структуру таблицы оно не меняет: ни шапки, ни объединений,
/// ни ширин колонок, ни листов. Раскладку журнал берёт из настроек и со
/// строки чисел, а месяц — из названия таблицы «МЕСЯЦ : ГОД».
class JournalSyncService {
  JournalSyncService(this._api);

  final SheetsApi _api;

  /// Снимает журнал: месяц, раскладку и сверку с расписанием.
  ///
  /// [schedule] нужен, чтобы знать, сколько пар в каждый день.
  Future<JournalSnapshot> snapshot({
    required String spreadsheetId,
    required JournalMapping mapping,
    ScheduleController? schedule,
  }) async {
    final meta = await _api.getSpreadsheet(spreadsheetId);
    // Месяц — из названия таблицы; если там его нет — из названия листа.
    final month =
        JournalMonth.parseTitle(meta.title) ??
        JournalMonth.parseTitle(mapping.tabTitle);

    final grid = await _api.getSheetGrid(spreadsheetId, mapping.tabTitle);
    if (grid == null) {
      throw CloudSyncException(
        'Листа «${mapping.tabTitle}» в таблице нет. Откройте настройку '
        'журнала и выберите существующий лист.',
      );
    }

    final layout = JournalLayout.scan(grid, mapping);
    final check = JournalCheck.check(
      month: month ?? DateTime.now(),
      mapping: mapping,
      layout: layout,
      schedule: schedule ?? ScheduleController.inMemory(),
    );
    return JournalSnapshot(month: month, layout: layout, check: check);
  }

  /// Отправляет отметки в журнал: только заливка и текст ячейки пары.
  Future<JournalSyncResult> push({
    required String spreadsheetId,
    required JournalMapping mapping,
    required List<AttendanceSession> sessions,
    ScheduleController? schedule,
  }) async {
    final meta = await _api.getSpreadsheet(spreadsheetId);
    final month =
        JournalMonth.parseTitle(meta.title) ??
        JournalMonth.parseTitle(mapping.tabTitle);
    if (month == null) {
      throw CloudSyncException(
        'Не удалось определить месяц: назовите таблицу или лист '
        '«МЕСЯЦ : ГОД», например «Ноябрь : 2026».',
      );
    }

    final grid = await _api.getSheetGrid(spreadsheetId, mapping.tabTitle);
    if (grid == null) {
      throw CloudSyncException(
        'Листа «${mapping.tabTitle}» в таблице нет. Откройте настройку '
        'журнала и выберите существующий лист.',
      );
    }
    final layout = JournalLayout.scan(grid, mapping);
    if (layout == null) {
      throw CloudSyncException(
        'В строке ${mapping.dayRow + 1} не нашлись числа дней. Проверьте '
        'настройку журнала.',
      );
    }

    final sheetId = _tabId(meta.tabs, mapping.tabTitle);
    final rowsOfStudent = _rowsOfStudents(grid, mapping);
    final requests = <Map<String, Object?>>[];
    var updatedCells = 0;

    for (final session in sessions) {
      if (!_isSameMonth(session.date, month)) continue;
      final span = layout.spanOf(session.date.day);
      if (span == null) {
        throw CloudSyncException(
          'В журнале нет дня ${session.date.day}, хотя есть отметки за '
          '${session.date.day}.${session.date.month}. Проверьте таблицу.',
        );
      }

      for (final item in session.entries.entries) {
        final studentId = item.key.split('|').first;
        final row = _rowOfStudent(session, studentId, rowsOfStudent);
        if (row == null) {
          throw CloudSyncException(
            'Студента «${_displayName(session, studentId)}» нет в журнале. '
            'Добавьте его в таблицу вручную — приложение не меняет список.',
          );
        }

        final pair = _pairNumberOf(item.value, session.date, schedule) ?? 1;
        if (!span.hasPair(pair)) {
          throw CloudSyncException(
            'Пары $pair нет в дне ${session.date.day}: в блоке только '
            '${span.width} колонок. Проверьте таблицу или расписание.',
          );
        }
        final column = span.columnOfPair(pair);
        if (column >= grid.colCount) continue;

        final desired = _desiredCell(item.value);
        if (_sameCell(grid.cell(row, column), desired)) continue;
        updatedCells++;
        requests.add(
          _updateCells(
            sheetId: sheetId,
            row: row,
            column: column,
            color: desired.$1,
            text: desired.$2,
          ),
        );
      }
    }

    if (requests.isNotEmpty) {
      await _api.batchUpdate(spreadsheetId, requests);
    }
    return JournalSyncResult(updatedCells: updatedCells);
  }

  /// Читает список группы и отметки из журнала.
  Future<JournalRoster> read({
    required String spreadsheetId,
    required JournalMapping mapping,
    required DateTime month,
    ScheduleController? schedule,
  }) async {
    final grid = await _api.getSheetGrid(spreadsheetId, mapping.tabTitle);
    if (grid == null) {
      throw CloudSyncException(
        'Листа «${mapping.tabTitle}» в таблице нет. Откройте настройку '
        'журнала и выберите существующий лист.',
      );
    }
    final layout = JournalLayout.scan(grid, mapping);

    final students = <Student>[];
    final entries = <int, Map<String, AttendanceEntry>>{};
    for (
      var row = mapping.firstStudentRow;
      row < grid.rows.length;
      row++
    ) {
      final fullName =
          grid.cell(row, mapping.fioColumn).value?.toString().trim() ?? '';
      if (fullName.isEmpty || fullName == 'ФИО') continue;

      final student = Student(id: fullName, fullName: fullName);
      students.add(student);

      if (layout == null) continue;
      for (final span in layout.spans) {
        final date = DateTime(month.year, month.month, span.day);
        for (var pair = 1; pair <= span.width; pair++) {
          final cell = grid.cell(row, span.columnOfPair(pair));
          if (cell.isEmpty) continue;
          final parsed = JournalCellCodec.decodeCell(
            cell.backgroundColor,
            cell.value,
            date,
          );
          if (parsed == null) continue;
          // Первая колонка блока — отметка на весь день; остальные —
          // конкретные пары: ключ пары берём из расписания.
          final lesson = _lessonOf(date, pair, schedule);
          final entry = AttendanceEntry(
            status: parsed.status,
            markedAt: parsed.markedAt,
            lessonKey: lesson.$1,
            lessonTitle: lesson.$2,
          );
          final key = AttendanceSession.entryKey(
            studentId: student.id,
            lessonKey: entry.lessonKey,
            lessonTitle: entry.lessonTitle,
          );
          entries.putIfAbsent(span.day, () => {})[key] = entry;
        }
      }
    }
    return JournalRoster(students: students, entries: entries);
  }

  // -- Детали ----------------------------------------------------------------

  /// Ключ пары для отметки из колонки.
  ///
  /// Первая колонка блока — отметка на весь день (без ключа пары);
  /// остальные — пары по расписанию, а за их пределами — «Пара N».
  (String?, String?) _lessonOf(
    DateTime date,
    int pair,
    ScheduleController? schedule,
  ) {
    if (pair <= 1) return (null, null);
    if (schedule == null) return ('pair-$pair', 'Пара $pair');
    final lessons = schedule.lessonsFor(weekdayOf(date));
    if (pair <= lessons.length) {
      return (lessons[pair - 1].id, lessons[pair - 1].subject);
    }
    return ('pair-$pair', 'Пара $pair');
  }

  /// Номер пары для отметки: из расписания по ключу, «pair-N» или названию.
  ///
  /// Отметка на весь день попадает в первую пару дня.
  int? _pairNumberOf(
    AttendanceEntry entry,
    DateTime date,
    ScheduleController? schedule,
  ) {
    final lessons = schedule == null
        ? const <ScheduleLesson>[]
        : schedule.lessonsFor(weekdayOf(date));
    final key = entry.lessonKey?.trim();
    if (key != null && key.isNotEmpty) {
      for (var i = 0; i < lessons.length; i++) {
        if (lessons[i].id == key) return i + 1;
      }
      final synthetic = RegExp(r'^pair-(\d+)$').firstMatch(key);
      if (synthetic != null) return int.tryParse(synthetic.group(1)!);
    }
    final title = entry.lessonTitle?.trim();
    if (title != null && title.isNotEmpty) {
      for (var i = 0; i < lessons.length; i++) {
        if (lessons[i].subject == title) return i + 1;
      }
      final synthetic = RegExp(r'^Пара (\d+)$').firstMatch(title);
      if (synthetic != null) return int.tryParse(synthetic.group(1)!);
    }
    return null;
  }

  /// (цвет, текст) желаемого состояния ячейки для отметки.
  (int?, String?) _desiredCell(AttendanceEntry entry) => (
    JournalCellCodec.cellColor(entry.status),
    JournalCellCodec.cellTextFor(entry),
  );

  /// Одинакова ли ячейка с желаемым состоянием.
  bool _sameCell(GridCell cell, (int?, String?) desired) {
    final (color, text) = desired;
    final actualText = cell.value?.toString().trim() ?? '';
    final actualColor = cell.backgroundColor == null
        ? null
        : cell.backgroundColor! & 0xFFFFFF;
    return actualText == (text ?? '') && actualColor == color;
  }

  /// Имя студента для сообщения об ошибке: ФИО из списка группы,
  /// если идентификатор там нашёлся.
  String _displayName(AttendanceSession session, String studentId) {
    for (final student in session.students) {
      if (student.id == studentId) return student.fullName;
    }
    for (final student in session.students) {
      if (student.fullName.toLowerCase() == studentId.toLowerCase()) {
        return student.fullName;
      }
    }
    return studentId;
  }

  /// Строка студента в журнале: ключ отметки может быть и локальным
  /// идентификатором, и ФИО из таблицы — сопоставляем через список
  /// группы сессии, а ФИО ищем в колонке ФИО.
  int? _rowOfStudent(
    AttendanceSession session,
    String studentId,
    Map<String, int> rowsOfStudent,
  ) {
    final direct = rowsOfStudent[studentId];
    if (direct != null) return direct;

    for (final student in session.students) {
      if (student.id != studentId) continue;
      final row = rowsOfStudent[student.fullName];
      if (row != null) return row;
    }
    for (final student in session.students) {
      if (student.fullName.toLowerCase() != studentId.toLowerCase()) continue;
      final row = rowsOfStudent[student.fullName];
      if (row != null) return row;
    }
    return null;
  }

  /// Строки студентов по ФИО из колонки ФИО.
  Map<String, int> _rowsOfStudents(SheetGrid grid, JournalMapping mapping) {
    final rows = <String, int>{};
    for (var row = mapping.firstStudentRow; row < grid.rows.length; row++) {
      final fullName =
          grid.cell(row, mapping.fioColumn).value?.toString().trim() ?? '';
      if (fullName.isEmpty || fullName == 'ФИО') continue;
      rows.putIfAbsent(fullName, () => row);
    }
    return rows;
  }

  Map<String, Object?> _updateCells({
    required int sheetId,
    required int row,
    required int column,
    required int? color,
    required String? text,
  }) => {
    'updateCells': {
      'start': {
        'sheetId': sheetId,
        'rowIndex': row,
        'columnIndex': column,
      },
      'rows': [
        {
          'values': [
            {
              if (text != null)
                'userEnteredValue': {'stringValue': text},
              if (color != null)
                'userEnteredFormat': {
                  'backgroundColor': {
                    'red': ((color >> 16) & 0xFF) / 255,
                    'green': ((color >> 8) & 0xFF) / 255,
                    'blue': (color & 0xFF) / 255,
                  },
                },
            },
          ],
        },
      ],
      // Отсутствие поля в JSON очищает его: так стираем и текст, и
      // заливку, если отметка отменена.
      'fields': 'userEnteredValue,userEnteredFormat.backgroundColor',
    },
  };

  int _tabId(List<SheetTab> tabs, String title) {
    for (final tab in tabs) {
      if (tab.title.toLowerCase() == title.toLowerCase()) return tab.id;
    }
    return 0;
  }

  bool _isSameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;
}
