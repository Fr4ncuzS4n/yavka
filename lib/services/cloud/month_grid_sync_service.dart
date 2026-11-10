import 'dart:ui';

import '../../models/attendance_entry.dart';
import '../../models/attendance_session.dart';
import '../../models/attendance_status.dart';
import '../../models/student.dart';
import 'cloud_exceptions.dart';
import 'month_grid_codec.dart';
import 'sheets_api.dart';

/// Результат отправки отметок в лист месяца.
class GridSyncResult {
  const GridSyncResult({
    required this.updatedCells,
    required this.appendedStudents,
    required this.sheetCreated,
  });

  /// Ячеек с отметками записано или очищено.
  final int updatedCells;

  /// Строк студентов, добавленных в конец листа.
  final int appendedStudents;

  /// `true`, если лист месяца создали заново и нарисовали шапку.
  final bool sheetCreated;

  @override
  String toString() =>
      'ячеек: $updatedCells, студентов добавлено: $appendedStudents'
      '${sheetCreated ? ', лист создан' : ''}';
}

/// Разобранное содержимое листа месяца.
class MonthSheetState {
  const MonthSheetState({
    required this.students,
    required this.entries,
    required this.rowsOfStudent,
    this.blocks = const {},
  });

  /// Строки студентов в порядке листа (id — текст из колонки «№»).
  final List<Student> students;

  /// Отметки: день месяца -> id студента -> отметка.
  final Map<int, Map<String, AttendanceEntry>> entries;

  /// Строка листа для каждого id студента.
  final Map<String, int> rowsOfStudent;

  /// Блок колонок каждого дня (если день обозначен в шапке).
  final Map<int, DayBlock> blocks;
}

/// Блок колонок одного дня.
class DayBlock {
  const DayBlock({
    required this.day,
    required this.firstColumn,
    required this.width,
  });

  final int day;
  final int firstColumn;
  final int width;
}

/// Синхронизация посещаемости с журналом месяца в Google Таблице.
///
/// Формат листа повторяет классный журнал: №, ФИО, под каждым днём блок
/// колонок пар; отметка дня пишется в колонку первой пары блока. Отметки
/// держатся в заливках: зелёная — «пришёл», оранжевая с временем —
/// «опоздал», красная с «Н» — «не пришёл», синяя — «по уважительной».
class MonthGridSyncService {
  MonthGridSyncService(this._api);

  final SheetsApi _api;

  /// Заголовок листа для выбранного месяца (с учётом листов без года).
  Future<String?> resolveSheetTitle(
    String spreadsheetId,
    DateTime month,
  ) async {
    final meta = await _api.getSpreadsheet(spreadsheetId);
    return MonthGridCodec.findMonthTab(
      [for (final tab in meta.tabs) tab.title],
      month,
    );
  }

  /// Отправляет отметки в лист месяца (создаёт лист и шапку при
  /// необходимости).
  Future<GridSyncResult> push({
    required String spreadsheetId,
    required DateTime month,
    required AttendanceSession session,
  }) async {
    final monthDate = DateTime(month.year, month.month, 1);
    final canonicalTitle = MonthGridCodec.monthSheetTitle(month);

    final meta = await _api.getSpreadsheet(spreadsheetId);
    final found = MonthGridCodec.findMonthTab(
      [for (final tab in meta.tabs) tab.title],
      monthDate,
    );

    var sheetCreated = false;
    var actualTitle = canonicalTitle;
    var sheetId = _tabId(meta.tabs, actualTitle);
    if (found == null) {
      sheetId = await _api.addSheet(spreadsheetId, canonicalTitle);
      meta.tabs.add(SheetTab(id: sheetId, title: canonicalTitle));
      sheetCreated = true;
    } else {
      actualTitle = found;
    }

    var grid = await _api.getSheetGrid(spreadsheetId, actualTitle);
    if (grid == null || !_hasHeader(grid)) {
      await _createHeader(
        spreadsheetId: spreadsheetId,
        month: monthDate,
        sheetId: _tabId(meta.tabs, actualTitle),
        columnCount: grid?.colCount ?? 0,
      );
      // Перечитываем сетку, чтобы поверх шапки ничего не затирать.
      grid = await _api.getSheetGrid(spreadsheetId, actualTitle);
      if (grid == null) {
        throw const GoogleApiException(
          'Создан лист месяца, но не удалось прочитать его обратно.',
        );
      }
    }
    final currentGrid = grid;

    final state = decode(grid, monthDate);
    final requests = <Map<String, Object?>>[];

    // Студенты, которых на листе нет, — добавляем строками вниз.
    var appendedStudents = 0;
    final knownRows = Map.of(state.rowsOfStudent);
    var nextRow = MonthGridCodec.firstStudentRow + state.students.length;
    for (final student in session.students) {
      if (knownRows.containsKey(student.id) ||
          state.students.any(
            (sheet) => sheet.fullName == student.fullName,
          )) {
        continue;
      }
      final number = state.students.length + appendedStudents + 1;
      requests.add(
        _updateCells(
          sheetId: sheetId,
          rowIndex: nextRow,
          columnIndex: 0,
          rows: [
            {
              'values': [
                {
                  'userEnteredValue': {'numberValue': number},
                },
                {
                  'userEnteredValue': {'stringValue': student.fullName},
                },
              ],
            },
          ],
          fields: 'userEnteredValue',
        ),
      );
      knownRows[student.id] = nextRow;
      nextRow++;
      appendedStudents++;
    }

    // Отметки: содержимое листа месяца; сегодняшний день поверх — локальные
    // отметки всегда свежее.
    final desired = {
      for (final entry in state.entries.entries)
        entry.key: {...entry.value},
    };
    if (_isSameMonth(session.date, monthDate)) {
      final day = session.date.day;
      desired[day] = {
        ...?desired[day],
        for (final record in session.records) record.student.id: record.entry,
      };
    }

    var updatedCells = 0;
    desired.forEach((day, byStudent) {
      final block = state.blocks[day];
      if (block == null) return;
      byStudent.forEach((studentId, entry) {
        final row = knownRows[studentId];
        if (row == null) return;

        for (
          var column = block.firstColumn;
          column < block.firstColumn + block.width &&
              column < currentGrid.colCount;
          column++
        ) {
          final isMainColumn = column == block.firstColumn;
          if (!_cellDiffers(
            currentGrid,
            row,
            column,
            entry,
            mainColumn: isMainColumn,
          )) {
            continue;
          }
          updatedCells++;
          requests.add(
            _cellUpdateCells(
              sheetId: sheetId,
              rowIndex: row,
              columnIndex: column,
              entry: entry,
              isMainColumn: isMainColumn,
            ),
          );
        }
      });
    });

    if (requests.isNotEmpty) {
      await _api.batchUpdate(spreadsheetId, requests);
    }

    return GridSyncResult(
      updatedCells: updatedCells,
      appendedStudents: appendedStudents,
      sheetCreated: sheetCreated,
    );
  }

  /// Читает список студентов и отметки месяца из листа.
  ///
  /// Возвращает `null`, если листа месяца ещё нет.
  Future<MonthSheetState?> read(String spreadsheetId, DateTime month) async {
    final meta = await _api.getSpreadsheet(spreadsheetId);
    final title = MonthGridCodec.findMonthTab(
      [for (final tab in meta.tabs) tab.title],
      month,
    );
    if (title == null) return null;

    final grid = await _api.getSheetGrid(spreadsheetId, title);
    if (grid == null) return null;
    return decode(grid, month);
  }

  /// Разбирает сетку листа в студентов, отметки и блоки дней.
  MonthSheetState decode(SheetGrid grid, DateTime month) {
    final view = grid.mergedView();
    final blocks = dayBlocksOf(grid, month);

    final students = <Student>[];
    final rowsOfStudent = <String, int>{};
    final entries = <int, Map<String, AttendanceEntry>>{};

    for (
      var row = MonthGridCodec.firstStudentRow;
      row < view.length;
      row++
    ) {
      final rowCells = view[row];
      final numberCell = rowCells.isNotEmpty ? rowCells[0] : const GridCell();
      final fioCell = rowCells.length > 1 ? rowCells[1] : const GridCell();

      final fullName = fioCell.value?.toString().trim() ?? '';
      if (fullName.isEmpty || fullName == 'ФИО') continue;

      final number = numberCell.value?.toString().trim() ?? '';
      // Без номера строка списка не опознаётся в отметках.
      if (number.isEmpty) continue;

      final student = Student(id: number, fullName: fullName);
      students.add(student);
      rowsOfStudent[student.id] = row;

      for (final block in blocks.values) {
        AttendanceEntry? entry;
        for (
          var column = block.firstColumn;
          column < block.firstColumn + block.width && column < rowCells.length;
          column++
        ) {
          final cell = rowCells[column];
          if (cell.isEmpty) continue;
          final date = DateTime(month.year, month.month, block.day);
          final parsed = MonthGridCodec.decodeCell(
            cell.backgroundColor,
            cell.value,
            date,
          );
          if (parsed == null) continue;
          entry = parsed;
          break;
        }
        if (entry == null) continue;
        entries.putIfAbsent(block.day, () => {})[student.id] = entry;
      }
    }

    return MonthSheetState(
      students: students,
      entries: entries,
      rowsOfStudent: rowsOfStudent,
      blocks: blocks,
    );
  }

  /// Блоки колонок дней по строке чисел месяца.
  ///
  /// Работает и с нашими листами (4 колонки на день), и с журналом,
  /// нарисованным вручную (3–4 колонки, разная ширина блоков).
  Map<int, DayBlock> dayBlocksOf(SheetGrid grid, DateTime month) {
    final view = grid.mergedView();
    final blocks = <int, DayBlock>{};
    if (view.length <= 1) return blocks;

    final dayRow = view[1];
    final starts = <int, int>{};
    for (
      var column = MonthGridCodec.firstDayColumn;
      column < dayRow.length;
      column++
    ) {
      final value = int.tryParse(dayRow[column].value?.toString().trim() ?? '');
      if (value == null || value < 1 || value > 31) continue;
      // Один и тот же «номер» не может открывать два блока.
      if (starts.containsKey(value)) continue;
      starts[value] = column;
    }
    if (starts.isEmpty) return blocks;

    final orderedDays = starts.keys.toList()..sort();
    final orderedColumns = starts.values.toList()..sort();

    for (final day in orderedDays) {
      final start = starts[day]!;
      final dayIndex = orderedDays.indexOf(day);
      final columnIndex = orderedColumns.indexOf(start);
      int width;
      if (columnIndex + 1 < orderedColumns.length) {
        width = orderedColumns[columnIndex + 1] - start;
      } else {
        width = MonthGridCodec.pairsPerDay;
      }
      blocks[day] = DayBlock(
        day: day,
        firstColumn: start,
        width: width.clamp(1, 12),
      );
      // Дни читаются по порядку следования, если совпали номера.
      if (orderedDays.indexOf(day) != dayIndex) break;
    }
    return blocks;
  }

  // -- Проверки и подготовка ячеек ------------------------------------------

  bool _isSameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  bool _hasHeader(SheetGrid grid) {
    if (grid.rows.length < 3) return false;
    final firstDayCell = grid.cell(1, MonthGridCodec.firstDayColumn);
    return firstDayCell.value?.toString().trim() == '1';
  }

  bool _cellDiffers(
    SheetGrid grid,
    int row,
    int column,
    AttendanceEntry entry, {
    required bool mainColumn,
  }) {
    final cell = grid.cell(row, column);
    if (!mainColumn) {
      // Побочные колонки блока нужно очистить, если там нарисованы наши
      // заливки — отметка дня живёт в одной ячейке.
      return cell.backgroundColor != null && _isOurColor(cell.backgroundColor);
    }
    final expectedText = MonthGridCodec.cellTextFor(entry) ?? '';
    final actualText = cell.value?.toString().trim() ?? '';
    final expectedColor = MonthGridCodec.colorFor(entry.status).toARGB32()
        & 0xFFFFFF;
    return actualText != expectedText ||
        cell.backgroundColor != expectedColor;
  }

  bool _isOurColor(int? color) {
    if (color == null) return false;
    return AttendanceStatus.values.any(
      (status) =>
          MonthGridCodec.matchesColor(color, MonthGridCodec.colorFor(status)),
    );
  }

  // -- Конструкторы запросов к Google API -----------------------------------

  /// Один updateCells на одну ячейку с отметкой.
  Map<String, Object?> _cellUpdateCells({
    required int sheetId,
    required int rowIndex,
    required int columnIndex,
    required AttendanceEntry entry,
    required bool isMainColumn,
  }) {
    final color = MonthGridCodec.colorFor(entry.status).toARGB32();
    final cellJson = <String, Object?>{
      'userEnteredFormat': {
        'backgroundColor': _colorJson(color),
      },
      if (isMainColumn && MonthGridCodec.cellTextFor(entry) != null)
        'userEnteredValue': {
          'stringValue': MonthGridCodec.cellTextFor(entry),
        },
    };
    return _updateCells(
      sheetId: sheetId,
      rowIndex: rowIndex,
      columnIndex: columnIndex,
      rows: [
        {
          'values': [cellJson],
        },
      ],
      // Отсутствие поля в JSON очищает его: так стираем и текст, и
      // лишние заливки в побочных колонках.
      fields: 'userEnteredValue,userEnteredFormat.backgroundColor',
    );
  }

  Map<String, Object?> _updateCells({
    required int sheetId,
    required int rowIndex,
    required int columnIndex,
    required List<Map<String, Object?>> rows,
    required String fields,
  }) => {
    'updateCells': {
      'start': {
        'sheetId': sheetId,
        'rowIndex': rowIndex,
        'columnIndex': columnIndex,
      },
      'rows': rows,
      'fields': fields,
    },
  };

  Map<String, Object?> _colorJson(int rgb) => {
    'red': ((rgb >> 16) & 0xFF) / 255,
    'green': ((rgb >> 8) & 0xFF) / 255,
    'blue': (rgb & 0xFF) / 255,
  };

  // -- Создание шапки нового листа ------------------------------------------

  Future<void> _createHeader({
    required String spreadsheetId,
    required DateTime month,
    required int sheetId,
    required int columnCount,
  }) async {
    final header = MonthGridCodec.buildHeader(month);
    final totalColumns = header.first.length;

    final rows = <Map<String, Object?>>[];
    for (var rowIndex = 0; rowIndex < header.length; rowIndex++) {
      final row = header[rowIndex];
      final cells = <Map<String, Object?>>[];
      for (var column = 0; column < row.length; column++) {
        final value = row[column];
        final bold = value != null && rowIndex <= 1;
        final isPinkCorner = rowIndex == 0 && column == 0;
        cells.add({
          if (value != null)
            'userEnteredValue': {
              'stringValue': value.toString(),
            },
          'userEnteredFormat': {
            if (value != null) 'textFormat': {'bold': bold},
            if (value != null && rowIndex < 3)
              'horizontalAlignment': 'CENTER',
            // Розовый уголок A1 — как в журнале; B1 без заливки.
            if (isPinkCorner)
              'backgroundColor': _colorJson(
                const Color(0xFFFF00FF).toARGB32(),
              ),
          },
        });
      }
      rows.add({'values': cells});
    }

    final requests = <Map<String, Object?>>[
      // Новый лист Google создаётся дефолтным 1000×26, а журналу ноября
      // нужны 2 + 30·4 = 122 колонки. Google строго проверяет границы:
      // запросы за пределами сетки отклоняются целиком (400 INVALID
      // ARGUMENT), поэтому сначала расширяем лист. Уменьшать размеры
      // нельзя — растим только когда реально не хватает.
      if (columnCount < totalColumns)
        {
          'updateSheetProperties': {
            'properties': {
              'sheetId': sheetId,
              'gridProperties': {'columnCount': totalColumns},
            },
            'fields': 'gridProperties.columnCount',
          },
        },
      _updateCells(
        sheetId: sheetId,
        rowIndex: 0,
        columnIndex: 0,
        rows: rows,
        fields:
            'userEnteredValue,userEnteredFormat.backgroundColor,'
            'userEnteredFormat.horizontalAlignment,'
            'userEnteredFormat.textFormat.bold',
      ),
      {
        'updateDimensionProperties': {
          'range': {
            'sheetId': sheetId,
            'dimension': 'COLUMNS',
            'startIndex': 0,
            'endIndex': 2,
          },
          'properties': {'pixelSize': 110},
          'fields': 'pixelSize',
        },
      },
      {
        'updateDimensionProperties': {
          'range': {
            'sheetId': sheetId,
            'dimension': 'COLUMNS',
            'startIndex': MonthGridCodec.firstDayColumn,
            'endIndex': totalColumns,
          },
          'properties': {'pixelSize': 34},
          'fields': 'pixelSize',
        },
      },
      for (final merge in MonthGridCodec.buildHeaderMerges(month))
        {
          'mergeCells': {
            'range': {
              'sheetId': sheetId,
              'startRowIndex': merge['startRowIndex'],
              'endRowIndex': merge['endRowIndex'],
              'startColumnIndex': merge['startColumnIndex'],
              'endColumnIndex': merge['endColumnIndex'],
            },
            'mergeType': 'MERGE_ALL',
          },
        },
    ];

    await _api.batchUpdate(spreadsheetId, requests);
  }

  int _tabId(List<SheetTab> tabs, String title) {
    for (final tab in tabs) {
      if (tab.title.toLowerCase() == title.toLowerCase()) return tab.id;
    }
    return 0;
  }
}
