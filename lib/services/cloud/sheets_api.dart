/// Минимальный интерфейс Google Sheets API, нужный приложению.
///
/// Абстракция позволяет тестировать синхронизацию без сети.
abstract interface class SheetsApi {
  Future<SpreadsheetMeta> getSpreadsheet(String spreadsheetId);

  Future<SpreadsheetMeta> createSpreadsheet(String title);

  /// Создаёт лист и возвращает его sheetId.
  Future<int> addSheet(String spreadsheetId, String title);

  /// Сетка листа: значения, заливки и объединения. `null`, если листа нет.
  Future<SheetGrid?> getSheetGrid(String spreadsheetId, String sheetTitle);

  /// Значения ячеек в A1-нотации (лист «Уведомления» и подобные).
  Future<List<List<Object?>>> getValues(String spreadsheetId, String range);

  /// Записывает значения в начало диапазона в A1-нотации.
  Future<void> updateValues(
    String spreadsheetId,
    String range,
    List<List<Object?>> values,
  );

  /// Дописывает строки в конец диапазона в A1-нотации.
  Future<void> appendValues(
    String spreadsheetId,
    String range,
    List<List<Object?>> values,
  );

  /// Пакетно записывает значения по нескольким диапазонам.
  Future<void> batchUpdateValues(
    String spreadsheetId,
    List<SheetValueRange> data,
  );

  /// Прямые запросы к `spreadsheets/{id}:batchUpdate` — заливки,
  /// объединения, ширины колонок, значения ячеек.
  Future<void> batchUpdate(
    String spreadsheetId,
    List<Map<String, Object?>> requests,
  );
}

/// Диапазон и значения для пакетного обновления.
class SheetValueRange {
  const SheetValueRange({required this.range, required this.values});

  final String range;
  final List<List<Object?>> values;

  Map<String, Object?> toJson() => {'range': range, 'values': values};
}

/// Метаданные таблицы.
class SpreadsheetMeta {
  const SpreadsheetMeta({
    required this.id,
    required this.title,
    required this.url,
    required this.tabs,
  });

  final String id;
  final String title;
  final String url;
  final List<SheetTab> tabs;

  bool hasTab(String title) =>
      tabs.any((tab) => tab.title.toLowerCase() == title.toLowerCase());

  int? tabId(String title) {
    for (final tab in tabs) {
      if (tab.title.toLowerCase() == title.toLowerCase()) return tab.id;
    }
    return null;
  }
}

/// Лист внутри таблицы.
class SheetTab {
  const SheetTab({required this.id, required this.title});

  final int id;
  final String title;
}

/// Ячейка сетки листа: показываемое значение и заливка.
class GridCell {
  const GridCell({this.value, this.backgroundColor});

  /// Показываемое значение ячейки (например `8:30`, `Н`, `2`).
  final Object? value;

  /// Заливка `0xRRGGBB` или `null`, если ячейка без заливки.
  final int? backgroundColor;

  bool get isEmpty => value == null && backgroundColor == null;
}

/// Сравнение ячеек по значению и заливке — для поиска отличий.
bool sameCell(GridCell a, GridCell b) {
  final aValue = a.value?.toString() ?? '';
  final bValue = b.value?.toString() ?? '';
  return aValue == bValue && a.backgroundColor == b.backgroundColor;
}

/// Объединённый диапазон ячеек (индексы 0-based, полуинтервалы).
class GridMerge {
  const GridMerge({
    required this.startRow,
    required this.startColumn,
    required this.rowCount,
    required this.colCount,
  });

  final int startRow;
  final int startColumn;
  final int rowCount;
  final int colCount;

  bool contains(int row, int column) =>
      row >= startRow &&
      row < startRow + rowCount &&
      column >= startColumn &&
      column < startColumn + colCount;
}

/// Сетка одного листа с заливками и объединениями.
class SheetGrid {
  const SheetGrid({
    required this.title,
    required this.rowCount,
    required this.colCount,
    required this.rows,
    this.merges = const [],
  });

  final String title;
  final int rowCount;
  final int colCount;

  /// Строки сетки; короткие строки добиты пустыми ячейками.
  final List<List<GridCell>> rows;

  final List<GridMerge> merges;

  /// Ячейка или пустая, если за пределами сетки.
  GridCell cell(int row, int column) {
    if (row < 0 || row >= rows.length) return const GridCell();
    final cells = rows[row];
    if (column < 0 || column >= cells.length) return const GridCell();
    return cells[column];
  }

  /// Разворачивает merge: объединённые ячейки принимают значение
  /// и цвет первой ячейки объединения — так проще сравнивать и читать.
  List<List<GridCell>> mergedView() {
    final view = [
      for (var row = 0; row < rows.length; row++)
        [for (var column = 0; column < colCount; column++) cell(row, column)],
    ];
    for (final merge in merges) {
      for (
        var row = merge.startRow;
        row < merge.startRow + merge.rowCount;
        row++
      ) {
        for (
          var column = merge.startColumn;
          column < merge.startColumn + merge.colCount;
          column++
        ) {
          if (row == merge.startRow && column == merge.startColumn) continue;
          if (row < 0 || row >= view.length) continue;
          if (column < 0 || column >= (view[row].length)) continue;
          view[row][column] = view[merge.startRow][merge.startColumn];
        }
      }
    }
    return view;
  }
}
