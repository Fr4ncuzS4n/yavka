// Тесты подбора месяца из названия таблицы «МЕСЯЦ : ГОД».

import 'package:flutter_test/flutter_test.dart';
import 'package:yavka/services/cloud/journal_month.dart';

void main() {
  test('«МЕСЯЦ : ГОД» разбирается в месяц', () {
    expect(JournalMonth.parseTitle('НОЯБРЬ : 2026'), DateTime(2026, 11));
    expect(JournalMonth.parseTitle('Ноябрь : 2026'), DateTime(2026, 11));
    expect(JournalMonth.parseTitle('ноябрь:2026'), DateTime(2026, 11));
    expect(JournalMonth.parseTitle('Ноябрь 2026'), DateTime(2026, 11));
    expect(JournalMonth.parseTitle('Ноябрь :2026'), DateTime(2026, 11));
  });

  test('месяц без года — текущий год', () {
    final now = DateTime.now();
    expect(
      JournalMonth.parseTitle('НОЯБРЬ'),
      DateTime(now.year, 11),
    );
    expect(
      JournalMonth.parseTitle('ноябрь'),
      DateTime(now.year, 11),
    );
  });

  test('понимаются родительные формы («ноября»)', () {
    expect(JournalMonth.parseTitle('ноября : 2026'), DateTime(2026, 11));
    expect(JournalMonth.parseTitle('Марта : 2027'), DateTime(2027, 3));
  });

  test('посторонние названия не разбираются', () {
    expect(JournalMonth.parseTitle('Посещаемость'), isNull);
    expect(JournalMonth.parseTitle('НОЯБРЬ : 26'), isNull);
    expect(JournalMonth.parseTitle(''), isNull);
    expect(JournalMonth.parseTitle('13-й месяц : 2026'), isNull);
    expect(JournalMonth.parseTitle('2026'), isNull);
  });

  test('имя месяца и отображаемое название', () {
    expect(JournalMonth.monthName(11), 'Ноябрь');
    expect(
      JournalMonth.displayName(DateTime(2026, 11)),
      'Ноябрь 2026',
    );
  });
}
