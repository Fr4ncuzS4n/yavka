// Тесты месячного синхронизатора: создание листа-журнала, запись и
// чтение отметок в заливках.

import 'package:flutter_test/flutter_test.dart';

import 'package:yavka/models/attendance_entry.dart';
import 'package:yavka/models/attendance_session.dart';
import 'package:yavka/models/attendance_status.dart';
import 'package:yavka/models/student.dart';
import 'package:yavka/services/cloud/month_grid_codec.dart';
import 'package:yavka/services/cloud/month_grid_sync_service.dart';

import 'support/fake_sheets_api.dart';
import 'support/month_journal_fixture.dart';

void main() {
  final month = DateTime(2026, 11, 1);
  final sessionDate = DateTime(2026, 11, 9); // 9 ноября, понедельник
  const alexey = Student(id: '1', fullName: 'Алексей Морозов');
  const maria = Student(id: '2', fullName: 'Мария Соколова');
  const title = 'Ноябрь 2026';

  // Колонка блока 9 ноября.
  final day9Column = MonthGridCodec.firstColumnOf(month, 9);

  AttendanceSession sessionWith(Map<String, AttendanceEntry> entries) =>
      AttendanceSession(
        groupName: 'БИТ-24-03',
        date: sessionDate,
        students: const [alexey, maria],
        entries: entries,
      );

  MonthGridSyncService service(FakeSheetsApi api) => MonthGridSyncService(api);

  test('push создаёт лист месяца и рисует шапку-журнал', () async {
    final api = FakeSheetsApi();
    final sync = service(api);

    final result = await sync.push(
      spreadsheetId: 'sid',
      month: month,
      sessions: [sessionWith({
        '1': AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: DateTime(2026, 11, 9, 8),
        ),
        '2': AttendanceEntry(
          status: AttendanceStatus.late,
          markedAt: DateTime(2026, 11, 9, 9, 40),
        ),
      })],
    );

    expect(result.sheetCreated, isTrue);
    expect(api.hasSheet(title), isTrue);

    // Шапка: баннер месяца, №, ФИО, ПАРА, розовый уголок.
    expect(api.cell(title, 0, 1).value, 'НОЯБРЬ');
    expect(api.cell(title, 1, 0).value, '№');
    expect(api.cell(title, 1, 1).value, 'ФИО');
    expect(api.cell(title, 2, 1).value, 'ПАРА');
    expect(api.cell(title, 0, 0).backgroundColor, 0xFF00FF);
    expect(api.cell(title, 0, 1).backgroundColor, isNull);

    // Дни недели и числа в шапке поверх блоков.
    // 9 ноября 2026 — понедельник.
    expect(api.cell(title, 0, day9Column).value, 'Понедельник');
    expect(api.cell(title, 1, day9Column).value.toString(), '9');

    // Мержи шапки: по два на каждый день.
    expect(api.mergeCount(title), 2 * 30);

    // Новые студенты добавлены строками с номерами.
    expect(result.appendedStudents, 2);
    expect(api.cell(title, 3, 0).value, isA<num>());
    expect(api.cell(title, 3, 1).value, 'Алексей Морозов');
    expect(api.cell(title, 4, 1).value, 'Мария Соколова');

    // Отметки в заливках колonoки первой пары блока дня.
    expect(result.updatedCells, 2);
    expect(api.cell(title, 3, day9Column).backgroundColor, 0x00CC00);
    expect(api.cell(title, 3, day9Column + 3).backgroundColor, isNull);
    final lateCell = api.cell(title, 4, day9Column);
    expect(lateCell.backgroundColor, 0xFF9900);
    expect(lateCell.value, '9:40');
  });

  test('повторная отправка не переставляет ячейки', () async {
    final api = FakeSheetsApi();
    final sync = service(api);
    final session = sessionWith({
      '1': AttendanceEntry(
        status: AttendanceStatus.came,
        markedAt: DateTime(2026, 11, 9, 8),
      ),
    });

    final first = await sync.push(spreadsheetId: 'sid', month: month, sessions: [session]);
    expect(first.sheetCreated, isTrue);

    final second = await sync.push(spreadsheetId: 'sid', month: month, sessions: [session]);

    expect(second.sheetCreated, isFalse);
    expect(second.appendedStudents, 0);
    expect(second.updatedCells, 0);
  });

  test('новый лист расширяется с 26 колонок до ширины журнала', () async {
    // Репродукция пользовательской ошибки: Google создаёт новый лист
    // дефолтным 1000x26, а шапка журнала требует 2 + 30·4 = 122 колонки.
    // Валидация Google отклоняла такой пакет с 400 INVALID_ARGUMENT —
    // теперь лист сначала расширяется, и ошибка невозможна.
    final api = FakeSheetsApi();
    final sync = service(api);

    final result = await sync.push(
      spreadsheetId: 'sid',
      month: month, // НОЯБРЬ 2026: 2 + 30·4 = 122 колонки
      sessions: [sessionWith({
        '1': AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: DateTime(2026, 11, 9, 8),
        ),
      })],
    );

    expect(result.sheetCreated, isTrue);
    // Дефолт 26 колонок вырос до ширины журнала.
    expect(api.columnCountOf(title), 122);
    // Шапка нарисована целиком: у последнего (30-го) дня последний блок
    // пары — колонка 121, в строке «ПАРА» там «4».
    expect(api.cell(title, 2, 121).value, '4');
  });

  test('расширение листа и рисование шапки — разные пакеты', () async {
    // Google может валидировать каждый batchUpdate против состояния до
    // пакета: расширение и рисование в одном пакете рискованно. Расширение
    // уходит отдельным вызовом, шапка — следующим.
    final api = FakeSheetsApi();
    final sync = service(api);

    await sync.push(
      spreadsheetId: 'sid',
      month: month,
      sessions: [sessionWith({
        '1': AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: DateTime(2026, 11, 9, 8),
        ),
      })],
    );

    // Первый batchUpdate расширяет сетку, второй рисует шапку, третий
    // пишет саму отметку — расширение никогда не смешано с рисованием.
    expect(api.batchUpdateCalls, 3);
    // После обоих пакетов лист нужной ширины со шапкой.
    expect(api.columnCountOf(title), 122);
    expect(api.cell(title, 1, MonthGridCodec.firstDayColumn).value, '1');
  });

  test('чужие отметки на листе не затираются, если локальных нет', () async {
    final api = FakeSheetsApi();
    seedJournal(
      api,
      month: month,
      students: const [alexey, maria],
      marks: {
        8: {
          '1': AttendanceEntry(
            status: AttendanceStatus.excused,
            markedAt: DateTime(2026, 11, 8),
          ),
          '2': AttendanceEntry(
            status: AttendanceStatus.absent,
            markedAt: DateTime(2026, 11, 8),
          ),
        },
        9: {
          '1': AttendanceEntry(
            status: AttendanceStatus.came,
            markedAt: DateTime(2026, 11, 9),
          ),
        },
      },
    );
    final sync = service(api);

    // Локальных отметок пока нет — приложение только читает журнал.
    final result = await sync.push(
      spreadsheetId: 'sid',
      month: month,
      sessions: [sessionWith({})],
    );

    expect(result.sheetCreated, isFalse);
    expect(result.updatedCells, 0);
    expect(api.cell(title, 3, day9Column).backgroundColor, 0x00CC00);
  });

  test('локальная отметка за день сильнее листа', () async {
    final api = FakeSheetsApi();
    seedJournal(
      api,
      month: month,
      students: const [alexey],
      marks: {
        9: {
          '1': AttendanceEntry(
            status: AttendanceStatus.came,
            markedAt: DateTime(2026, 11, 9, 8),
          ),
        },
      },
    );
    final sync = service(api);

    final result = await sync.push(
      spreadsheetId: 'sid',
      month: month,
      sessions: [sessionWith({
        '1': AttendanceEntry(
          status: AttendanceStatus.late,
          markedAt: DateTime(2026, 11, 9, 9, 40),
        ),
      })],
    );

    expect(result.updatedCells, 1);
    final cell = api.cell(title, 3, day9Column);
    expect(cell.backgroundColor, 0xFF9900);
    expect(cell.value, '9:40');
  });

  test('read разбирает все четыре статуса и время опоздания', () async {
    final api = FakeSheetsApi();
    const ivan = Student(id: '3', fullName: 'Иван Петров');
    const olga = Student(id: '4', fullName: 'Ольга Белова');
    seedJournal(
      api,
      month: month,
      students: const [alexey, maria, ivan, olga],
      marks: {
        9: {
          '1': AttendanceEntry(
            status: AttendanceStatus.came,
            markedAt: DateTime(2026, 11, 9, 8),
          ),
          '2': AttendanceEntry(
            status: AttendanceStatus.late,
            markedAt: DateTime(2026, 11, 9, 9, 40),
          ),
          '3': AttendanceEntry(
            status: AttendanceStatus.absent,
            markedAt: DateTime(2026, 11, 9),
          ),
          '4': AttendanceEntry(
            status: AttendanceStatus.excused,
            markedAt: DateTime(2026, 11, 9),
          ),
        },
      },
    );
    final sync = service(api);

    final state = await sync.read('sid', month);
    expect(state, isNotNull);
    expect(state!.students.map((s) => s.id), ['1', '2', '3', '4']);
    expect(state.students.first.fullName, 'Алексей Морозов');

    final day9 = state.entries[9]!;
    expect(day9['1']?.status, AttendanceStatus.came);
    // Для «пришёл» времени на листе нет — остаётся дата.
    expect(day9['1']?.markedAt, DateTime(2026, 11, 9));
    expect(day9['2']?.status, AttendanceStatus.late);
    expect(day9['2']?.markedAt, DateTime(2026, 11, 9, 9, 40));
    expect(day9['3']?.status, AttendanceStatus.absent);
    expect(day9['3']?.markedAt, DateTime(2026, 11, 9));
    expect(day9['4']?.status, AttendanceStatus.excused);
  });

  test('read несуществующего листа — null', () async {
    final api = FakeSheetsApi();
    final sync = service(api);

    final state = await sync.read('sid', month);
    expect(state, isNull);
  });

  test('push для листа без года («НОЯБРЬ») использует его', () async {
    final api = FakeSheetsApi();
    seedJournal(
      api,
      month: month,
      students: const [alexey],
      tabTitle: 'НОЯБРЬ',
    );
    final sync = service(api);

    final result = await sync.push(
      spreadsheetId: 'sid',
      month: month,
      sessions: [sessionWith({
        '1': AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: DateTime(2026, 11, 9, 8),
        ),
      })],
    );

    expect(result.sheetCreated, isFalse);
    expect(api.hasSheet('НОЯБРЬ'), isTrue);
    expect(api.hasSheet(title), isFalse);
    // Марии на листе нет — она добавляется строкой, Алексей уже есть.
    expect(result.appendedStudents, 1);
    expect(api.cell('НОЯБРЬ', 3, day9Column).backgroundColor, 0x00CC00);
  });

  test('push пишет отметки и в листах с блоками другой ширины', () async {
    // Журнал, нарисованный человеком: блоки по 3 колонки.
    final api = FakeSheetsApi();
    final days = 30;
    final total = MonthGridCodec.firstDayColumn + days * 3;
    List<SeedCell?> empty() => List.generate(total, (_) => null);

    final numberRow = empty();
    numberRow[1] = api.seedCell(value: 'ФИО');
    for (var day = 1; day <= days; day++) {
      numberRow[MonthGridCodec.firstDayColumn + (day - 1) * 3] = api.seedCell(
        value: day,
      );
    }
    final studentRow = empty()
      ..[0] = api.seedCell(value: '1')
      ..[1] = api.seedCell(value: 'Алексей Морозов');
    api.seedSheet(
      title,
      [empty(), numberRow, empty(), studentRow],
    );

    final sync = service(api);
    final result = await sync.push(
      spreadsheetId: 'sid',
      month: month,
      sessions: [sessionWith({
        '1': AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: DateTime(2026, 11, 9, 8),
        ),
      })],
    );

    // Блоки по 3 колонки: 9 ноября начинается с колонки 2 + 8·3.
    final day9Column3 = MonthGridCodec.firstDayColumn + 8 * 3;
    expect(result.appendedStudents, 1);
    expect(api.cell(title, 3, day9Column3).backgroundColor, 0x00CC00);
  });
}
