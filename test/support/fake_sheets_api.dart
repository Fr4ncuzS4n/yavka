import 'package:yavka/services/cloud/cloud_exceptions.dart';
import 'package:yavka/services/cloud/sheets_api.dart';

/// Простая in-memory реализация Sheets API для тестов.
class FakeSheetsApi implements SheetsApi {
  final Map<String, List<List<Object?>>> _rows = {};
  final Set<String> _tabs = {'Sheet1'};
  int _nextTabId = 1;
  bool failAppend = false;
  bool failUpdate = false;

  List<List<Object?>> rowsFor(String tab) => _rows[tab] ?? const [];

  void setRows(String tab, List<List<Object?>> rows) {
    _tabs.add(tab);
    _rows[tab] = [
      for (final row in rows) [...row],
    ];
  }

  @override
  Future<SpreadsheetMeta> getSpreadsheet(String spreadsheetId) async =>
      SpreadsheetMeta(
        id: spreadsheetId,
        title: 'Тестовая таблица',
        url: 'https://docs.google.com/spreadsheets/d/$spreadsheetId/edit',
        tabs: [
          for (final title in _tabs)
            SheetTab(id: title == 'Sheet1' ? 0 : _nextTabId++, title: title),
        ],
      );

  @override
  Future<SpreadsheetMeta> createSpreadsheet(String title) async {
    _tabs.add('Sheet1');
    return getSpreadsheet('created-spreadsheet');
  }

  @override
  Future<void> addSheet(String spreadsheetId, String title) async {
    _tabs.add(title);
  }

  @override
  Future<List<List<Object?>>> getValues(
    String spreadsheetId,
    String range,
  ) async => [
    for (final row in rowsFor(_tabFromRange(range))) [...row],
  ];

  @override
  Future<void> updateValues(
    String spreadsheetId,
    String range,
    List<List<Object?>> values,
  ) async {
    if (failUpdate) throw const GooglePermissionException();
    final tab = _tabFromRange(range);
    final rowNumber = _rowFromRange(range);
    final rows = _rows.putIfAbsent(tab, () => []);
    while (rows.length < rowNumber) {
      rows.add(<Object?>[]);
    }
    rows[rowNumber - 1] = [...values.first];
  }

  @override
  Future<void> batchUpdateValues(
    String spreadsheetId,
    List<SheetValueRange> data,
  ) async {
    if (failUpdate) throw const GooglePermissionException();
    for (final item in data) {
      final tab = _tabFromRange(item.range);
      final rowNumber = _rowFromRange(item.range);
      final rows = _rows.putIfAbsent(tab, () => []);
      while (rows.length < rowNumber) {
        rows.add(<Object?>[]);
      }
      rows[rowNumber - 1] = [...item.values.first];
    }
  }

  @override
  Future<void> appendValues(
    String spreadsheetId,
    String range,
    List<List<Object?>> values,
  ) async {
    if (failAppend) throw const GooglePermissionException();
    final rows = _rows.putIfAbsent(_tabFromRange(range), () => []);
    rows.addAll([
      for (final row in values) [...row],
    ]);
  }

  String _tabFromRange(String range) {
    final match = RegExp(r"^'([^']+)'!").firstMatch(range);
    return match?.group(1) ?? range.split('!').first;
  }

  int _rowFromRange(String range) {
    final match = RegExp(r'!A(\d+):F\d+$').firstMatch(range);
    return int.parse(match?.group(1) ?? '1');
  }
}
