// Тесты формата «журнала месяца» — заливок, текстов и шапки листа.

import 'package:flutter_test/flutter_test.dart';

import 'package:yavka/models/attendance_entry.dart';
import 'package:yavka/models/attendance_status.dart';
import 'package:yavka/services/cloud/month_grid_codec.dart';

void main() {
  final month = DateTime(2026, 11); // ноябрь 2026, 30 дней

  group('названия листа и месяца', () {
    test('лист месяца называется «Ноябрь 2026»', () {
      expect(MonthGridCodec.monthSheetTitle(month), 'Ноябрь 2026');
      expect(MonthGridCodec.monthBanner(month), 'НОЯБРЬ');
    });

    test('findMonthTab ищет точное совпадение и лист без года', () {
      expect(
        MonthGridCodec.findMonthTab(['Октябрь 2026', 'Ноябрь 2026'], month),
        'Ноябрь 2026',
      );
      // Старые листы используют только название месяца.
      expect(
        MonthGridCodec.findMonthTab(['НОЯБРЬ', 'Октябрь 2026'], month),
        'НОЯБРЬ',
      );
      expect(
        MonthGridCodec.findMonthTab(['ноябрь'], month),
        'ноябрь',
      );
      expect(
        MonthGridCodec.findMonthTab(['Декабрь 2026'], month),
        isNull,
      );
    });

    test('день недели по-русски с большой буквы', () {
      // 10 ноября 2026 — вторник.
      expect(
        MonthGridCodec.weekdayName(DateTime(2026, 11, 10)),
        'Вторник',
      );
      expect(
        MonthGridCodec.weekdayName(DateTime(2026, 11, 9)),
        'Понедельник',
      );
    });
  });

  group('структура месяца', () {
    test('дней в месяце', () {
      expect(MonthGridCodec.daysInMonth(DateTime(2026, 11)), 30);
      expect(MonthGridCodec.daysInMonth(DateTime(2026, 2)), 28);
      expect(MonthGridCodec.daysInMonth(DateTime(2028, 2)), 29);
      expect(MonthGridCodec.daysInMonth(DateTime(2026, 12)), 31);
    });

    test('первая колонка блока дня растёт по 4 колонки на день', () {
      expect(MonthGridCodec.firstColumnOf(month, 1), 2);
      expect(MonthGridCodec.firstColumnOf(month, 2), 6);
      expect(MonthGridCodec.firstColumnOf(month, 9), 34);
      expect(MonthGridCodec.firstColumnOf(month, 30), 2 + 29 * 4);
    });
  });

  group('цвета статусов', () {
    test('заливки как в бумажном журнале', () {
      expect(
        MonthGridCodec.colorFor(AttendanceStatus.came).toARGB32() & 0xFFFFFF,
        0x00CC00, // зелёная
      );
      expect(
        MonthGridCodec.colorFor(AttendanceStatus.late).toARGB32() & 0xFFFFFF,
        0xFF9900, // оранжевая
      );
      expect(
        MonthGridCodec.colorFor(AttendanceStatus.absent).toARGB32() & 0xFFFFFF,
        0xFF0000, // красная
      );
      expect(
        MonthGridCodec.colorFor(AttendanceStatus.excused).toARGB32() & 0xFFFFFF,
        0x4472C4, // синяя
      );
    });

    test('статус распознаётся по заливке с допуском на округление', () {
      expect(MonthGridCodec.statusFromColor(0x00CC00), AttendanceStatus.came);
      // Google отдаёт цвета с погрешностью ±2 на канал.
      expect(MonthGridCodec.statusFromColor(0x02CA01), AttendanceStatus.came);
      expect(MonthGridCodec.statusFromColor(0xFF9900), AttendanceStatus.late);
      expect(MonthGridCodec.statusFromColor(0xFF0000), AttendanceStatus.absent);
      expect(
        MonthGridCodec.statusFromColor(0x4472C4),
        AttendanceStatus.excused,
      );
      // Чужая заливка (жёлтый маркер) не превращается в статус.
      expect(MonthGridCodec.statusFromColor(0xFFFF00), isNull);
      expect(MonthGridCodec.statusFromColor(0x101010), isNull);
    });

    test('различие каналов больше допуска не распознаётся', () {
      // Красная заливка, но сдвиг 11 > 10 на зелёный канал.
      expect(
        MonthGridCodec.matchesColor(0xFF1100, MonthGridCodec.absentColor),
        isFalse,
      );
      // Сдвиг 2 < 10 (синий канал) — распознаётся.
      expect(
        MonthGridCodec.matchesColor(0xFF0002, MonthGridCodec.absentColor),
        isTrue,
      );
    });
  });

  group('тексты ячеек', () {
    test('опоздал — время отметки', () {
      expect(
        MonthGridCodec.cellTextFor(
          AttendanceEntry(
            status: AttendanceStatus.late,
            markedAt: DateTime(2026, 11, 9, 8, 30),
          ),
        ),
        '8:30',
      );
      // 9:05, а не 9:5.
      expect(
        MonthGridCodec.cellTextFor(
          AttendanceEntry(
            status: AttendanceStatus.late,
            markedAt: DateTime(2026, 11, 9, 9, 5),
          ),
        ),
        '9:05',
      );
    });

    test('не пришёл — буква «Н», остальные — пусто', () {
      expect(
        MonthGridCodec.cellTextFor(
          AttendanceEntry(
            status: AttendanceStatus.absent,
            markedAt: DateTime(2026, 11, 9),
          ),
        ),
        'Н',
      );
      expect(
        MonthGridCodec.cellTextFor(
          AttendanceEntry(
            status: AttendanceStatus.came,
            markedAt: DateTime(2026, 11, 9),
          ),
        ),
        isNull,
      );
      expect(
        MonthGridCodec.cellTextFor(
          AttendanceEntry(
            status: AttendanceStatus.excused,
            markedAt: DateTime(2026, 11, 9),
          ),
        ),
        isNull,
      );
    });
  });

  group('разбор времени из ячейки', () {
    final date = DateTime(2026, 11, 9);

    test('полное время 8:30', () {
      expect(MonthGridCodec.parseMarkedAt(date, '8:30'), DateTime(2026, 11, 9, 8, 30));
    });

    test('почерк журнала 8:3 — это 8:30', () {
      expect(MonthGridCodec.parseMarkedAt(date, '8:3'), DateTime(2026, 11, 9, 8, 30));
    });

    test('9:5 — это 9:50', () {
      expect(MonthGridCodec.parseMarkedAt(date, '9:5'), DateTime(2026, 11, 9, 9, 50));
    });

    test('форматы с точкой и печатное 09:05', () {
      expect(MonthGridCodec.parseMarkedAt(date, '8.30'), DateTime(2026, 11, 9, 8, 30));
      expect(MonthGridCodec.parseMarkedAt(date, '09:05'), DateTime(2026, 11, 9, 9, 5));
    });

    test('без текста остаётся дата', () {
      expect(MonthGridCodec.parseMarkedAt(date, null), date);
      expect(MonthGridCodec.parseMarkedAt(date, ''), date);
      expect(MonthGridCodec.parseMarkedAt(date, 'Н'), date);
      // Нелепое время игнорируется.
      expect(MonthGridCodec.parseMarkedAt(date, '25:00'), date);
      expect(MonthGridCodec.parseMarkedAt(date, '8:75'), date);
    });
  });

  test('декоде ячейки: заливка важнее текста', () {
    final date = DateTime(2026, 11, 9);

    // Зелёная заливка без текста — пришёл.
    final came = MonthGridCodec.decodeCell(0x00CC00, null, date);
    expect(came?.status, AttendanceStatus.came);
    expect(came?.markedAt, date);

    // Красная заливка с «Н» — не пришёл.
    final absent = MonthGridCodec.decodeCell(0xFF0000, 'Н', date);
    expect(absent?.status, AttendanceStatus.absent);

    // Заливка незнакомого цвета, но текст статусный — текст засчитывается
    // (так бывает, если человек исправлял цвет вручную).
    final text = MonthGridCodec.decodeCell(0x123456, 'Пришёл', date);
    expect(text?.status, AttendanceStatus.came);

    // Пустая ячейка — нет отметки.
    expect(MonthGridCodec.decodeCell(null, null, date), isNull);
    expect(MonthGridCodec.decodeCell(null, '', date), isNull);
    // Чужая заливка и чужой текст — не наша отметка.
    expect(MonthGridCodec.decodeCell(0x123456, 'какой-то текст', date), isNull);
  });

  group('шапка листа', () {
    test('структура шапки ноября 2026', () {
      final header = MonthGridCodec.buildHeader(month);

      expect(header, hasLength(3));
      final (weekdayRow, dayRow, pairRow) = (header[0], header[1], header[2]);

      // Баннер месяца и фиксированные подписи.
      expect(weekdayRow[1], 'НОЯБРЬ');
      expect(dayRow[0], '№');
      expect(dayRow[1], 'ФИО');
      expect(pairRow[1], 'ПАРА');

      // 1 ноября 2026 — воскресенье; блоки дней по 4 колонки.
      expect(weekdayRow[2], 'Воскресенье');
      expect(weekdayRow[6], 'Понедельник');
      expect(dayRow[2], 1);
      expect(dayRow[6], 2);
      // Пары пронумерованы внутри каждого блока.
      expect(pairRow[2], 1);
      expect(pairRow[3], 2);
      expect(pairRow[4], 3);
      expect(pairRow[5], 4);
      expect(pairRow[6], 1);

      // Длина строки ровно под 30 дней.
      expect(
        dayRow.length,
        MonthGridCodec.firstDayColumn + 30 * MonthGridCodec.pairsPerDay,
      );
    });

    test('мержи покрывают каждый день в строках 1 и 2', () {
      final merges = MonthGridCodec.buildHeaderMerges(month);

      expect(merges, hasLength(2 * 30));
      expect(merges.first, {
        'startRowIndex': 0,
        'endRowIndex': 1,
        'startColumnIndex': 2,
        'endColumnIndex': 6,
      });
      expect(merges[1], {
        'startRowIndex': 1,
        'endRowIndex': 2,
        'startColumnIndex': 2,
        'endColumnIndex': 6,
      });
      // Последний день.
      expect(merges[58], {
        'startRowIndex': 0,
        'endRowIndex': 1,
        'startColumnIndex': 2 + 29 * 4,
        'endColumnIndex': 2 + 30 * 4,
      });
    });
  });
}
