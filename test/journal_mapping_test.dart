// Тесты настройки журнала: буквы колонок и сохранение настройки.

import 'package:flutter_test/flutter_test.dart';
import 'package:yavka/services/cloud/journal_mapping.dart';

void main() {
  test('буквенная ссылка колонки в индекс и обратно', () {
    expect(JournalMapping.parseColumnLetter('A'), 0);
    expect(JournalMapping.parseColumnLetter('B'), 1);
    expect(JournalMapping.parseColumnLetter('b'), 1);
    expect(JournalMapping.parseColumnLetter('B2'), 1);
    expect(JournalMapping.parseColumnLetter('AA'), 26);
    expect(JournalMapping.parseColumnLetter('CZ'), 103);
    expect(JournalMapping.columnLetter(0), 'A');
    expect(JournalMapping.columnLetter(1), 'B');
    expect(JournalMapping.columnLetter(26), 'AA');
    expect(JournalMapping.columnLetter(103), 'CZ');
  });

  test('некорректные ссылки не разбираются', () {
    expect(JournalMapping.parseColumnLetter(''), isNull);
    expect(JournalMapping.parseColumnLetter('123'), isNull);
    expect(JournalMapping.parseColumnLetter('АБВ'), isNull); // кириллица
  });

  test('настройка сохраняется в JSON и восстанавливается', () {
    const mapping = JournalMapping(
      tabTitle: 'НОЯБРЬ : 2026',
      dayRow: 1,
      fioColumn: 1,
      firstStudentRow: 3,
    );
    final restored = JournalMapping.tryDecode(mapping.encode());
    expect(restored, isNotNull);
    expect(restored!.tabTitle, 'НОЯБРЬ : 2026');
    expect(restored.dayRow, 1);
    expect(restored.fioColumn, 1);
    expect(restored.firstStudentRow, 3);
  });

  test('битая или пустая настройка — не настройка', () {
    expect(JournalMapping.tryDecode(''), isNull);
    expect(JournalMapping.tryDecode('не json'), isNull);
    expect(
      JournalMapping.tryDecode('{"tabTitle":"","dayRow":1}'),
      isNull,
    );
    expect(
      JournalMapping.tryDecode('{"tabTitle":"Лист","dayRow":-1}'),
      isNull,
    );
  });
}
