import 'package:flutter_test/flutter_test.dart';
import 'package:yavka/models/attendance_entry.dart';
import 'package:yavka/models/attendance_session.dart';
import 'package:yavka/models/attendance_status.dart';
import 'package:yavka/models/student.dart';
import 'package:yavka/services/cloud/sheet_attendance_codec.dart';

void main() {
  group('SheetAttendanceCodec', () {
    const student = Student(id: '1', fullName: 'Алексей Морозов');

    AttendanceRecord record({
      String group = 'БИТ-24-03',
      DateTime? date,
      AttendanceStatus status = AttendanceStatus.came,
      DateTime? markedAt,
    }) => AttendanceRecord(
      groupName: group,
      date: date ?? DateTime(2026, 11, 9),
      student: student,
      entry: AttendanceEntry(
        status: status,
        markedAt: markedAt ?? DateTime(2026, 11, 9, 9, 5),
      ),
    );

    test('заголовок распознаётся', () {
      expect(
        SheetAttendanceCodec.isHeader(SheetAttendanceCodec.header),
        isTrue,
      );
      expect(
        SheetAttendanceCodec.isHeader(['Дата', '', '', '', '', '']),
        isTrue,
      );
      expect(
        SheetAttendanceCodec.isHeader(['2026-11-09', '09:05', 'Группа']),
        isFalse,
      );
    });

    test('строка кодируется и декодируется без потерь', () {
      final source = record();
      final row = SheetAttendanceCodec.encode(source);

      expect(row, [
        '2026-11-09',
        '09:05',
        'БИТ-24-03',
        '1',
        'Алексей Морозов',
        'Пришёл',
      ]);

      final decoded = SheetAttendanceCodec.decode(row);
      expect(decoded, isNotNull);
      expect(decoded!.key, source.key);
      expect(decoded.entry.status, AttendanceStatus.came);
      expect(decoded.entry.markedAt, DateTime(2026, 11, 9, 9, 5));
      expect(decoded.student.fullName, student.fullName);
    });

    test('статус читается и по коду, и по подписи', () {
      final byCode = SheetAttendanceCodec.decode([
        '2026-11-09',
        '09:05',
        'БИТ-24-03',
        '1',
        'Алексей Морозов',
        'late',
      ]);
      final byLabel = SheetAttendanceCodec.decode([
        '2026-11-09',
        '09:05',
        'БИТ-24-03',
        '1',
        'Алексей Морозов',
        'Опоздал',
      ]);

      expect(byCode?.entry.status, AttendanceStatus.late);
      expect(byLabel?.entry.status, AttendanceStatus.late);
    });

    test('дата в формате 09.11.2026 и кривое время', () {
      final decoded = SheetAttendanceCodec.decode([
        '09.11.2026',
        'не время',
        'БИТ-24-03',
        '1',
        'Алексей Морозов',
        'Пришёл',
      ]);

      expect(decoded, isNotNull);
      expect(decoded!.date, DateTime(2026, 11, 9));
      expect(decoded.entry.markedAt, DateTime(2026, 11, 9));
    });

    test('испорченные строки пропускаются', () {
      expect(
        SheetAttendanceCodec.decode([
          '2026-11-09',
          '09:05',
          'БИТ-24-03',
          '1',
          'Алексей Морозов',
          'Неизвестно',
        ]),
        isNull,
      );
      expect(
        SheetAttendanceCodec.decode([
          'не дата',
          '09:05',
          'БИТ-24-03',
          '1',
          'Алексей Морозов',
          'Пришёл',
        ]),
        isNull,
      );
      expect(SheetAttendanceCodec.decode(['2026-11-09']), isNull);
      expect(SheetAttendanceCodec.decode(SheetAttendanceCodec.header), isNull);
    });

    test('удалённые отметки важнее локальных, новые студенты добавляются', () {
      final session = AttendanceSession(
        groupName: 'БИТ-24-03',
        date: DateTime(2026, 11, 9),
        students: const [student],
        entries: {
          '1': AttendanceEntry(
            status: AttendanceStatus.came,
            markedAt: DateTime(2026, 11, 9, 9),
          ),
        },
      );

      final merged = session.mergeRemote([
        AttendanceRecord(
          groupName: 'БИТ-24-03',
          date: DateTime(2026, 11, 9),
          student: student,
          entry: AttendanceEntry(
            status: AttendanceStatus.late,
            markedAt: DateTime(2026, 11, 9, 9, 30),
          ),
        ),
        AttendanceRecord(
          groupName: 'БИТ-24-03',
          date: DateTime(2026, 11, 9),
          student: const Student(id: '2', fullName: 'Мария Соколова'),
          entry: AttendanceEntry(
            status: AttendanceStatus.excused,
            markedAt: DateTime(2026, 11, 9),
          ),
        ),
      ]);

      expect(merged.entries['1']?.status, AttendanceStatus.late);
      expect(merged.entries['2']?.status, AttendanceStatus.excused);
      expect(merged.students.map((s) => s.id), containsAll(['1', '2']));
    });
  });

  test('сессия другого дня начинается без отметок', () {
    final old = AttendanceSession(
      groupName: 'БИТ-24-03',
      date: DateTime(2020, 1, 1),
      students: const [Student(id: '1', fullName: 'Алексей Морозов')],
      entries: {
        '1': AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: DateTime(2020, 1, 1, 9),
        ),
      },
    );

    final today = old.forToday();
    expect(today.entries, isEmpty);
    expect(today.students, old.students);
    expect(
      today.date,
      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day),
    );
  });
}
