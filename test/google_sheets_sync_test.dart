import 'package:flutter_test/flutter_test.dart';
import 'package:yavka/models/attendance_entry.dart';
import 'package:yavka/models/attendance_session.dart';
import 'package:yavka/models/attendance_status.dart';
import 'package:yavka/models/student.dart';
import 'package:yavka/services/cloud/cloud_exceptions.dart';
import 'package:yavka/services/cloud/google_sheets_sync_service.dart';
import 'package:yavka/services/cloud/sheet_attendance_codec.dart';

import 'support/fake_sheets_api.dart';

void main() {
  const sheetTitle = 'Посещаемость';
  const group = 'БИТ-24-03';
  final date = DateTime(2026, 11, 9);

  const alexey = Student(id: '1', fullName: 'Алексей Морозов');
  const maria = Student(id: '2', fullName: 'Мария Соколова');
  const dmitry = Student(id: '3', fullName: 'Дмитрий Волков');

  AttendanceSession sessionWith(Map<String, AttendanceEntry> entries) =>
      AttendanceSession(
        groupName: group,
        date: date,
        students: const [alexey, maria, dmitry],
        entries: entries,
      );

  test('первая отправка создаёт заголовок и добавляет строки', () async {
    final api = FakeSheetsApi();
    final service = GoogleSheetsSyncService(api);

    final result = await service.push(
      spreadsheetId: 'spreadsheet-id',
      sheetTitle: sheetTitle,
      session: sessionWith({
        '1': AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: DateTime(2026, 11, 9, 9),
        ),
        '2': AttendanceEntry(
          status: AttendanceStatus.late,
          markedAt: DateTime(2026, 11, 9, 9, 15),
        ),
      }),
    );

    expect(result.appended, 2);
    expect(result.updated, 0);
    expect(api.rowsFor(sheetTitle).first, SheetAttendanceCodec.header);
    expect(api.rowsFor(sheetTitle), hasLength(3));
    expect(api.rowsFor(sheetTitle)[1][3], '1');
    expect(api.rowsFor(sheetTitle)[1][5], 'Пришёл');
  });

  test('повторная отправка обновляет строки, а не дублирует их', () async {
    final api = FakeSheetsApi();
    final service = GoogleSheetsSyncService(api);

    await service.push(
      spreadsheetId: 'spreadsheet-id',
      sheetTitle: sheetTitle,
      session: sessionWith({
        '1': AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: DateTime(2026, 11, 9, 9),
        ),
        '2': AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: DateTime(2026, 11, 9, 9),
        ),
      }),
    );

    final result = await service.push(
      spreadsheetId: 'spreadsheet-id',
      sheetTitle: sheetTitle,
      session: sessionWith({
        '1': AttendanceEntry(
          status: AttendanceStatus.excused,
          markedAt: DateTime(2026, 11, 9, 9),
        ),
        '2': AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: DateTime(2026, 11, 9, 9),
        ),
        '3': AttendanceEntry(
          status: AttendanceStatus.absent,
          markedAt: DateTime(2026, 11, 9, 9, 30),
        ),
      }),
    );

    expect(result.updated, 2);
    expect(result.appended, 1);
    expect(api.rowsFor(sheetTitle), hasLength(4));
    final rowForAlexey = api
        .rowsFor(sheetTitle)
        .firstWhere((row) => row.length > 3 && row[3] == '1');
    expect(rowForAlexey[5], 'По уважительной');
  });

  test('загрузка объединяет только строки текущей группы и дня', () async {
    final api = FakeSheetsApi();
    final service = GoogleSheetsSyncService(api);

    api.setRows(sheetTitle, [
      SheetAttendanceCodec.header,
      SheetAttendanceCodec.encode(
        AttendanceRecord(
          groupName: group,
          date: date,
          student: alexey,
          entry: AttendanceEntry(
            status: AttendanceStatus.late,
            markedAt: DateTime(2026, 11, 9, 9, 20),
          ),
        ),
      ),
      SheetAttendanceCodec.encode(
        AttendanceRecord(
          groupName: group,
          date: DateTime(2026, 11, 10),
          student: maria,
          entry: AttendanceEntry(
            status: AttendanceStatus.came,
            markedAt: DateTime(2026, 11, 10, 9),
          ),
        ),
      ),
      SheetAttendanceCodec.encode(
        AttendanceRecord(
          groupName: 'Другая группа',
          date: date,
          student: dmitry,
          entry: AttendanceEntry(
            status: AttendanceStatus.came,
            markedAt: DateTime(2026, 11, 9, 9),
          ),
        ),
      ),
      SheetAttendanceCodec.encode(
        AttendanceRecord(
          groupName: group,
          date: date,
          student: const Student(id: '9', fullName: 'Новый Студент'),
          entry: AttendanceEntry(
            status: AttendanceStatus.excused,
            markedAt: DateTime(2026, 11, 9, 10),
          ),
        ),
      ),
    ]);

    final local = sessionWith({
      '1': AttendanceEntry(
        status: AttendanceStatus.came,
        markedAt: DateTime(2026, 11, 9, 9),
      ),
    });

    final merged = await service.pull(
      spreadsheetId: 'spreadsheet-id',
      sheetTitle: sheetTitle,
      local: local,
    );

    expect(merged.entries['1']?.status, AttendanceStatus.late);
    expect(merged.entries['2'], isNull); // другой день
    expect(merged.entries['3'], isNull); // другая группа
    expect(merged.entries['9']?.status, AttendanceStatus.excused);
    expect(merged.students.map((s) => s.id), contains('9'));
  });

  test('ошибка прав редактора пробрасывается наружу', () async {
    final api = FakeSheetsApi()..failAppend = true;
    final service = GoogleSheetsSyncService(api);

    expect(
      () => service.push(
        spreadsheetId: 'spreadsheet-id',
        sheetTitle: sheetTitle,
        session: sessionWith({
          '1': AttendanceEntry(
            status: AttendanceStatus.came,
            markedAt: DateTime(2026, 11, 9, 9),
          ),
        }),
      ),
      throwsA(isA<GooglePermissionException>()),
    );
  });
}
