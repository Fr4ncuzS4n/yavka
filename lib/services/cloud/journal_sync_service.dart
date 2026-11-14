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
  const JournalSyncResult({
    required this.updatedCells,
    this.skippedDays = const [],
  });

  /// Сколько ячеек перезаписано.
  final int updatedCells;

  /// Дни месяца, отметки которых не расставлены: дня нет в журнале или
  /// блок колонок пар — обрывок, в него посещаемость не поместится.
  /// Выходных здесь нет и не бывает: отметки за них не пишутся молча
  /// (отмечать в выходные запрещено, в журнале их колонок нет).
  final List<int> skippedDays;

  bool get hasSkippedDays => skippedDays.isNotEmpty;

  /// Предупреждение о пропущенных днях для экрана синхронизации.
  String get skippedNote {
    if (skippedDays.isEmpty) return '';
    final za = skippedDays.length == 1 ? 'за день' : 'за дни';
    return 'Посещаемость $za ${skippedDays.join(', ')} расставить '
        'нельзя: в журнале нет дня или колонок пар.';
  }
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
    final skippedDays = <int>[];
    var updatedCells = 0;

    for (final session in sessions) {
      if (!_isSameMonth(session.date, month)) continue;
      if (session.entries.isEmpty) continue;
      // В выходные отметки запрещены и в журнале их колонок нет:
      // такие сессии (например, оставшиеся со старых версий приложения)
      // пропускаются молча — без записи и без предупреждения.
      if (weekdayOf(session.date) >= 6) continue;

      final span = layout.spanOf(session.date.day);
      final schedulePairs =
          schedule?.lessonsFor(weekdayOf(session.date)).length ?? 0;

      // «Обрывок» — дня в журнале нет или блок колонок пар не вмещает
      // все нужные пары (журнал может начинаться не с 1 числа, у дней
      // бывают отрезанные блоки). В такой день посещаемость расставить
      // нельзя: отметки пропускаются, день попадает в предупреждение.
      final missingPairs = span == null || schedulePairs == 0
          ? const <int>[]
          : [
              for (var pair = 1; pair <= schedulePairs; pair++)
                if (!span.hasPair(pair)) pair,
            ];
      final neededPairs = {
        for (final item in session.entries.entries)
          if (!_isWholeDay(item.value))
            _pairNumberOf(item.value, session.date, schedule) ?? 1,
      };
      final unusable =
          span == null ||
          (schedulePairs > 0 && missingPairs.isNotEmpty) ||
          (schedulePairs == 0 && span.pairs.isEmpty) ||
          neededPairs.any((pair) => !span.hasPair(pair));
      if (unusable) {
        skippedDays.add(session.date.day);
        continue;
      }

      // План записи: (строка, колонка) → желаемое состояние ячейки.
      // Сначала раскладываются отметки на весь день, потом конкретные
      // пары переписывают свои колонки — частная отметка важнее общей.
      final plan = <(int, int), (int?, String?)>{};

      // Пары дня для отметки «на весь день»: по расписанию, если оно
      // есть, иначе все колонки пар из строки «ПАРА» таблицы.
      final wholeDayPairs = schedulePairs > 0
          ? [
              for (var pair = 1; pair <= schedulePairs; pair++)
                if (span.hasPair(pair)) pair,
            ]
          : span.pairs;

      for (final item in session.entries.entries) {
        final entry = item.value;
        if (!_isWholeDay(entry)) continue;
        final studentId = item.key.split('|').first;
        final row = _rowOfStudent(session, studentId, rowsOfStudent);
        if (row == null) {
          throw CloudSyncException(
            'Студента «${_displayName(session, studentId)}» нет в журнале. '
            'Добавьте его в таблицу вручную — приложение не меняет список.',
          );
        }
        // Отметка на весь день означает «пришёл/не пришёл на все пары»:
        // она раскладывается в каждую колонку пары этого дня.
        final desired = _desiredCell(entry);
        for (final pair in wholeDayPairs) {
          plan[(row, span.columnOfPair(pair))] = desired;
        }
      }

      for (final item in session.entries.entries) {
        final entry = item.value;
        if (_isWholeDay(entry)) continue;
        final studentId = item.key.split('|').first;
        final row = _rowOfStudent(session, studentId, rowsOfStudent);
        if (row == null) {
          throw CloudSyncException(
            'Студента «${_displayName(session, studentId)}» нет в журнале. '
            'Добавьте его в таблицу вручную — приложение не меняет список.',
          );
        }

        // Пары, отмеченные отдельно, не трогаем общей отметкой.
        final pair = _pairNumberOf(entry, session.date, schedule) ?? 1;
        plan[(row, span.columnOfPair(pair))] = _desiredCell(entry);
      }

      for (final MapEntry(key: (row, column), value: desired)
          in plan.entries) {
        if (column >= grid.colCount) continue;
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
    skippedDays.sort();
    return JournalSyncResult(
      updatedCells: updatedCells,
      skippedDays: List.unmodifiable(skippedDays),
    );
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
    final lastRow = _lastStudentRow(grid, mapping);
    for (var row = mapping.firstStudentRow; row <= lastRow; row++) {
      final fullName =
          grid.cell(row, mapping.fioColumn).value?.toString().trim() ?? '';
      if (fullName.isEmpty || fullName == 'ФИО') continue;

      final student = Student(id: fullName, fullName: fullName);
      students.add(student);

      if (layout == null) continue;
      for (final span in layout.spans) {
        final date = DateTime(month.year, month.month, span.day);
        // Каждая колонка пары — отметка на конкретную пару; номер пары
        // берётся из строки «ПАРА» (или по смещению, если её нет).
        for (final pair in span.pairs) {
          final column = span.columnOfPair(pair);
          final cell = grid.cell(row, column);
          if (cell.isEmpty) continue;
          final parsed = JournalCellCodec.decodeCell(
            cell.backgroundColor,
            cell.value,
            date,
          );
          if (parsed == null) continue;
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

  /// Последняя строка студентов: от настройки, но не дальше конца листа.
  int _lastStudentRow(SheetGrid grid, JournalMapping mapping) {
    final configured = mapping.lastStudentRow;
    if (configured == null) return grid.rows.length - 1;
    return configured.clamp(mapping.firstStudentRow, grid.rows.length - 1);
  }

  /// Ключ пары для колонки с номером [pairNumber].
  ///
  /// Пары берутся из расписания; если расписания для этого дня нет,
  /// колонка подписывается «Пара N» — номер из строки пар таблицы.
  (String?, String?) _lessonOf(
    DateTime date,
    int pairNumber,
    ScheduleController? schedule,
  ) {
    final lessons = schedule == null
        ? const <ScheduleLesson>[]
        : schedule.lessonsFor(weekdayOf(date));
    if (pairNumber >= 1 && pairNumber <= lessons.length) {
      return (lessons[pairNumber - 1].id, lessons[pairNumber - 1].subject);
    }
    return ('pair-$pairNumber', 'Пара $pairNumber');
  }

  /// Отметка на весь день: без ключа и названия пары.
  bool _isWholeDay(AttendanceEntry entry) {
    final key = entry.lessonKey?.trim() ?? '';
    final title = entry.lessonTitle?.trim() ?? '';
    return key.isEmpty && title.isEmpty;
  }

  /// Номер пары для отметки: из расписания по ключу, «pair-N» или названию.
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
  ///
  /// Список читается от первой строки студентов до конечной строки ФИО
  /// (или до конца листа, если конечная строка не задана).
  Map<String, int> _rowsOfStudents(SheetGrid grid, JournalMapping mapping) {
    final rows = <String, int>{};
    final lastRow = _lastStudentRow(grid, mapping);
    for (var row = mapping.firstStudentRow; row <= lastRow; row++) {
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
