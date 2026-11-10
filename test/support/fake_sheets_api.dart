import 'package:yavka/services/cloud/cloud_exceptions.dart';
import 'package:yavka/services/cloud/sheets_api.dart';

/// Простая in-memory реализация Sheets API для тестов.
///
/// Хранит сетку листов: значения, заливки и объединения. Достаточно ума,
/// чтобы применить запросы `batchUpdate`, которыми пишет приложение.
class FakeSheetsApi implements SheetsApi {
  final Map<String, _FakeSheet> _sheets = {};
  final Map<String, String> _ids = {};
  int _nextSheetId = 0;
  String _currentSpreadsheetId = 'fake-spreadsheet';

  /// Флаги ошибок для проверки обработки прав.
  bool failGet = false;
  bool failBatchUpdate = false;

  void reset({String spreadsheetId = 'fake-spreadsheet'}) {
    _sheets.clear();
    _ids.clear();
    _nextSheetId = 0;
    _currentSpreadsheetId = spreadsheetId;
  }

  _FakeSheet _ensure(String title) => _sheets.putIfAbsent(
    title,
    () => _FakeSheet(id: _nextSheetId++, title: title),
  );

  String get spreadsheetId => _currentSpreadsheetId;

  /// Хорошее имя «созданной» таблицы.
  @override
  Future<SpreadsheetMeta> createSpreadsheet(String title) async {
    _currentSpreadsheetId = 'created-spreadsheet';
    _ids[_currentSpreadsheetId] = title;
    return _meta(title);
  }

  SpreadsheetMeta _meta(String title) => SpreadsheetMeta(
    id: _currentSpreadsheetId,
    title: title,
    url: 'https://docs.google.com/spreadsheets/d/$_currentSpreadsheetId/edit',
    tabs: [
      for (final sheet in _sheets.values)
        SheetTab(id: sheet.id, title: sheet.title),
    ],
  );

  SeedCell seedCell({
    Object? value,
    int? background,
    bool bold = false,
    bool merged = false,
    int? mergeRows,
    int? mergeCols,
  }) => SeedCell(
    value: value,
    background: background,
    bold: bold,
    merged: merged,
    mergeRows: mergeRows,
    mergeCols: mergeCols,
  );

  /// Есть ли в фейковой таблице лист с таким названием.
  bool hasSheet(String title) => _sheets.containsKey(title);

  /// Сколько объединений нарисовано на листе.
  int mergeCount(String title) => _sheets[title]?.merges.length ?? 0;

  /// Текущая ширина листа в колонках (после расширения).
  int columnCountOf(String title) => _sheets[title]?.columnCount ?? 0;

  /// Заполняет лист из ресурсных строк: текст, заливка, флаги bold.
  ///
  /// Используется тестами, чтобы воссоздать привычный вид журнала.
  void seedSheet(String title, List<List<SeedCell?>> rows) {
    final sheet = _ensure(title);
    sheet.merges.clear();
    // Явное заполнение может быть шире дефолтных 26 колонок Google.
    final width = rows.fold<int>(
      0,
      (longest, row) => row.length > longest ? row.length : longest,
    );
    if (width > sheet.columnCount) sheet.columnCount = width;
    if (rows.length > sheet.rowCount) sheet.rowCount = rows.length;
    for (var row = 0; row < rows.length; row++) {
      for (var column = 0; column < rows[row].length; column++) {
        final cell = rows[row][column];
        if (cell == null) continue;
        sheet.setCell(
          row,
          column,
          GridCell(value: cell.value, backgroundColor: cell.background),
        );
        if (cell.bold) {
          sheet.boldCells.add('$row:$column');
        }
        if (cell.merged) {
          // Тестовый пример склеивает блок листа вручную.
          final found = sheet.merges.indexWhere(
            (merge) =>
                merge.startRow == row && merge.startColumn == column,
          );
          if (found < 0) {
            sheet.merges.add(GridMerge(
              startRow: row,
              startColumn: column,
              rowCount: cell.mergeRows ?? 1,
              colCount: cell.mergeCols ?? 1,
            ));
          }
        }
      }
    }
  }

  List<GridCell> row(String title, int row) {
    final sheet = _sheets[title];
    if (sheet == null) return const [];
    if (row >= sheet.rows.length) return const [];
    return sheet.rows[row];
  }

  GridCell cell(String title, int row, int column) {
    final cells = this.row(title, row);
    if (column >= cells.length) return const GridCell();
    return cells[column];
  }

  @override
  Future<SheetGrid?> getSheetGrid(
    String spreadsheetId,
    String sheetTitle,
  ) async {
    if (failGet) throw const GooglePermissionException();
    final sheet = _sheets[sheetTitle];
    if (sheet == null) return null;
    final width = sheet.columnCount > sheet.maxColumns
        ? sheet.columnCount
        : sheet.maxColumns;
    return SheetGrid(
      title: sheet.title,
      rowCount: sheet.rowCount,
      colCount: width,
      rows: [
        for (var i = 0; i < sheet.rowCount; i++)
          [
            for (var j = 0; j < width; j++)
              (i < sheet.rows.length && j < sheet.rows[i].length)
                  ? sheet.rows[i][j]
                  : const GridCell(),
          ],
      ],
      merges: [...sheet.merges],
    );
  }

  @override
  Future<void> batchUpdate(
    String spreadsheetId,
    List<Map<String, Object?>> requests,
  ) async {
    if (failBatchUpdate) throw const GooglePermissionException();
    for (final request in requests) {
      final updateSheetProps = request['updateSheetProperties'];
      if (updateSheetProps is Map) {
        _applySheetProperties(updateSheetProps.cast<String, Object?>());
      }
      final dimProps = request['updateDimensionProperties'];
      if (dimProps is Map) {
        _applyDimensionProperties(dimProps.cast<String, Object?>());
      }
      final updateCells = request['updateCells'];
      if (updateCells is Map) {
        _applyUpdateCells(
          updateCells.cast<String, Object?>(),
        );
      }
      final mergeCells = request['mergeCells'];
      if (mergeCells is Map) {
        _applyMergeCells(mergeCells.cast<String, Object?>());
      }
      final unmergeCells = request['unmergeCells'];
      if (unmergeCells is Map) {
        _applyUnmergeCells(unmergeCells.cast<String, Object?>());
      }
    }
  }

  GoogleApiException _invalidArgument(String detail) => GoogleApiException(
    'request contains an invalid argument. $detail',
    statusCode: 400,
  );

  /// Как настоящий Google: уменьшать размеры листа нельзя, только
  /// увеличить.
  void _applySheetProperties(Map<String, Object?> updateSheetProps) {
    final properties = updateSheetProps['properties'];
    if (properties is! Map) return;
    final sheet = _sheetsById(properties['sheetId']);
    if (sheet == null) throw _invalidArgument('нет листа с таким id');

    final grid = properties['gridProperties'];
    if (grid is! Map) return;
    final rowCount = (grid['rowCount'] as num?)?.toInt();
    final columnCount = (grid['columnCount'] as num?)?.toInt();

    if (rowCount != null) {
      if (rowCount < sheet.rowCount) {
        throw _invalidArgument('rowCount уменьшен с ${sheet.rowCount}');
      }
      sheet.rowCount = rowCount;
    }
    if (columnCount != null) {
      if (columnCount < sheet.columnCount) {
        throw _invalidArgument('columnCount уменьшен с ${sheet.columnCount}');
      }
      sheet.columnCount = columnCount;
    }
  }

  /// Как настоящий Google: свойства размеров можно менять только внутри
  /// текущей сетки листа, иначе запрос целиком отклоняется (400).
  void _applyDimensionProperties(Map<String, Object?> dimProps) {
    final range = dimProps['range'];
    if (range is! Map) return;
    final sheet = _sheetsById(range['sheetId']);
    if (sheet == null) throw _invalidArgument('нет листа с таким id');

    final endIndex = (range['endIndex'] as num?)?.toInt();
    if (endIndex == null) return;
    switch (range['dimension']?.toString()) {
      case 'COLUMNS':
        if (endIndex > sheet.columnCount) {
          throw _invalidArgument(
            'колонки $endIndex вне ширины ${sheet.columnCount}',
          );
        }
      case 'ROWS':
        if (endIndex > sheet.rowCount) {
          throw _invalidArgument(
            'строки $endIndex вне высоты ${sheet.rowCount}',
          );
        }
    }
    // Значения width (pixelSize) fake не хранит.
  }

  void _applyUpdateCells(Map<String, Object?> updateCells) {
    final start = updateCells['start'];
    final rows = updateCells['rows'];
    if (start is! Map || rows is! List) return;
    final rowIndex = (start['rowIndex'] as num?)?.toInt() ?? 0;
    final columnIndex = (start['columnIndex'] as num?)?.toInt() ?? 0;
    final fields = updateCells['fields']?.toString() ?? '';
    final clearsValue = fields.contains('userEnteredValue');
    final clearsFormat = fields.contains('userEnteredFormat');

    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      if (row is! Map) continue;
      final values = row['values'];
      if (values is! List) continue;
      for (var c = 0; c < values.length; c++) {
        final cell = values[c];
        if (cell is! Map) continue;
        final sheet = _sheets.values
            .where((item) => item.id == (start['sheetId'] as num?)?.toInt())
            .toList();
        final target = sheet.isEmpty ? null : sheet.first;
        // В тестах лист ищем по id, при отсутствии — любой (один лист).
        final holder =
            target ?? (_sheets.values.isEmpty ? null : _sheets.values.first);
        if (holder == null) continue;
        holder.applyCellPatch(
          row: rowIndex + r,
          column: columnIndex + c,
          cell: cell.cast<String, Object?>(),
          clearsValue: clearsValue,
          clearsFormat: clearsFormat,
        );
      }
    }
  }

  void _applyMergeCells(Map<String, Object?> mergeCells) {
    final range = mergeCells['range'];
    if (range is! Map) return;
    final sheet = _sheetsById(range['sheetId']);
    if (sheet == null) throw _invalidArgument('нет листа с таким id');
    final endRowIndex = (range['endRowIndex'] as num?)?.toInt() ?? 0;
    final endColumnIndex = (range['endColumnIndex'] as num?)?.toInt() ?? 0;
    if (endRowIndex > sheet.rowCount || endColumnIndex > sheet.columnCount) {
      throw _invalidArgument('мерж вне сетки листа');
    }
    final merge = GridMerge(
      startRow: (range['startRowIndex'] as num?)?.toInt() ?? 0,
      startColumn: (range['startColumnIndex'] as num?)?.toInt() ?? 0,
      rowCount: ((range['endRowIndex'] as num?)?.toInt() ?? 0) -
          ((range['startRowIndex'] as num?)?.toInt() ?? 0),
      colCount: ((range['endColumnIndex'] as num?)?.toInt() ?? 0) -
          ((range['startColumnIndex'] as num?)?.toInt() ?? 0),
    );
    sheet.merges
      ..removeWhere(
        (item) => item.startRow == merge.startRow && item.startColumn == merge.startColumn,
      )
      ..add(merge);
  }

  void _applyUnmergeCells(Map<String, Object?> unmergeCells) {
    final range = unmergeCells['range'];
    if (range is! Map) return;
    final sheet = _sheetsById(range['sheetId']);
    if (sheet == null) return;
    final startRow = (range['startRowIndex'] as num?)?.toInt() ?? 0;
    final startColumn = (range['startColumnIndex'] as num?)?.toInt() ?? 0;
    sheet.merges.removeWhere(
      (item) => item.startRow == startRow && item.startColumn == startColumn,
    );
  }

  _FakeSheet? _sheetsById(Object? id) {
    if (id == null) {
      return _sheets.values.isEmpty ? null : _sheets.values.first;
    }
    final wanted = (id as num).toInt();
    for (final sheet in _sheets.values) {
      if (sheet.id == wanted) return sheet;
    }
    return null;
  }

  @override
  Future<SpreadsheetMeta> getSpreadsheet(String spreadsheetId) async {
    if (failGet) throw const GooglePermissionException();
    return _meta(_ids[spreadsheetId] ?? 'Тестовая таблица');
  }

  @override
  Future<int> addSheet(String spreadsheetId, String title) {
    return Future<int>.value(_ensure(title).id);
  }

  /// Имя единственного листа — удобно в тестах.
  String get onlyTitle => _sheets.keys.isEmpty ? '' : _sheets.keys.first;
}

/// Ячейка для засева фейкового листа в тестах.
class SeedCell {
  SeedCell({
    this.value,
    this.background,
    this.bold = false,
    this.merged = false,
    this.mergeRows,
    this.mergeCols,
  });

  final Object? value;
  final int? background;
  final bool bold;
  final bool merged;
  final int? mergeRows;
  final int? mergeCols;
}

class _FakeSheet {
  _FakeSheet({required this.id, required this.title});

  final int id;
  final String title;

  // Как в Google: новый лист создаётся дефолтным 1000x26.
  int rowCount = 1000;
  int columnCount = 26;

  final List<List<GridCell>> rows = [];
  final List<GridMerge> merges = [];
  final Set<String> boldCells = {};

  int get maxColumns =>
      rows.fold(0, (longest, row) => row.length > longest ? row.length : longest);

  void setCell(int row, int column, GridCell cell) {
    while (rows.length <= row) {
      rows.add(const []);
    }
    final cells = rows[row];
    final updated = [...cells];
    while (updated.length <= column) {
      updated.add(const GridCell());
    }
    updated[column] = cell;
    rows[row] = updated;
  }

  /// Разбор запроса updateCells для одной ячейки: значение и заливка.
  void applyCellPatch({
    required int row,
    required int column,
    required Map<String, Object?> cell,
    required bool clearsValue,
    required bool clearsFormat,
  }) {
    final existing = cell2(row, column);
    Object? value = existing.value;
    int? background = existing.backgroundColor;

    if (clearsValue) {
      final entered = cell['userEnteredValue'];
      if (entered is Map) {
        value = entered['stringValue'] ??
            entered['numberValue'] ??
            entered['boolValue'];
      } else {
        value = null; // поля нет — Google стирает значение
      }
    }
    if (clearsFormat) {
      final format = cell['userEnteredFormat'];
      if (format is Map) {
        background = colorToIntOrNull(format['backgroundColor']);
      } else {
        background = null;
      }
    }
    setCell(row, column, GridCell(value: value, backgroundColor: background));
  }

  GridCell cell2(int row, int column) {
    if (row >= rows.length) return const GridCell();
    final cells = rows[row];
    if (column >= cells.length) return const GridCell();
    return cells[column];
  }

  /// Цвет Google `{red, green, blue}` — числа от 0 до 1 — в `0xRRGGBB`.
  ///
  /// Белый и прозрачный фон заливкой не считается, как и в реальном
  /// читателе `GoogleSheetsApi`.
  static int? colorToIntOrNull(Object? raw) {
    if (raw is! Map) return null;
    final alpha = raw['alpha'];
    if (alpha is num && alpha < 0.05) return null;

    int channel(Object? value) =>
        (((value as num?) ?? 0).clamp(0.0, 1.0) * 255).round();
    final red = channel(raw['red']);
    final green = channel(raw['green']);
    final blue = channel(raw['blue']);
    if (red > 245 && green > 245 && blue > 245) return null;
    return red << 16 | green << 8 | blue;
  }
}
