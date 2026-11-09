/// Минимальный интерфейс Google Sheets API, нужный приложению.
///
/// Абстракция позволяет тестировать синхронизацию без сети.
abstract interface class SheetsApi {
  Future<SpreadsheetMeta> getSpreadsheet(String spreadsheetId);

  Future<SpreadsheetMeta> createSpreadsheet(String title);

  Future<void> addSheet(String spreadsheetId, String title);

  Future<List<List<Object?>>> getValues(String spreadsheetId, String range);

  Future<void> updateValues(
    String spreadsheetId,
    String range,
    List<List<Object?>> values,
  );

  Future<void> batchUpdateValues(
    String spreadsheetId,
    List<SheetValueRange> data,
  );

  Future<void> appendValues(
    String spreadsheetId,
    String range,
    List<List<Object?>> values,
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

  bool hasTab(String title) => tabs.any((tab) => tab.title == title);

  int? tabId(String title) {
    for (final tab in tabs) {
      if (tab.title == title) return tab.id;
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
