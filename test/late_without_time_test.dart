// «Опоздал» без времени: первый клик ставит пустую отметку,
// повторный — добавляет время. Пустой «опоздал» хранится как дата
// без времени и в журнал идёт заливкой без текста.

import 'package:flutter_test/flutter_test.dart';

import 'package:yavka/models/attendance_entry.dart';
import 'package:yavka/models/attendance_session.dart';
import 'package:yavka/models/attendance_status.dart';
import 'package:yavka/models/student.dart';
import 'package:yavka/services/cloud/journal_cell_codec.dart';

void main() {
  final monday = DateTime(2026, 11, 9);
  final alexey = Student(id: 'Алексей Морозов', fullName: 'Алексей Морозов');

  AttendanceEntry lateMark({required bool withTime}) => AttendanceEntry(
    status: AttendanceStatus.late,
    markedAt: withTime ? DateTime(2026, 11, 9, 10, 20) : monday,
  );

  test('Пустой «опоздал» — дата без времени, hasTime false', () {
    final empty = lateMark(withTime: false);
    expect(empty.status, AttendanceStatus.late);
    expect(empty.hasTime, isFalse);

    final timed = lateMark(withTime: true);
    expect(timed.hasTime, isTrue);
  });

  test('В журнал пустой «опоздал» пишется заливкой без текста', () {
    expect(JournalCellCodec.cellTextFor(lateMark(withTime: false)), isNull);
    expect(JournalCellCodec.cellTextFor(lateMark(withTime: true)), '10:20');
  });

  test('Из журнала оранжевая ячейка без текста читается без времени', () {
    final parsed = JournalCellCodec.decodeCell(
      JournalCellCodec.lateColor.toARGB32() & 0xFFFFFF,
      '',
      monday,
    );
    expect(parsed, isNotNull);
    expect(parsed!.status, AttendanceStatus.late);
    expect(parsed.hasTime, isFalse);
    // Время не потерялось: «10:20» читается обратно с временем.
    final timed = JournalCellCodec.decodeCell(
      JournalCellCodec.lateColor.toARGB32() & 0xFFFFFF,
      '10:20',
      monday,
    );
    expect(timed!.hasTime, isTrue);
  });

  test('Пустой «опоздал» переживает сохранение сессии без времени', () {
    final session = AttendanceSession(
      groupName: 'БИТ-24-03',
      date: monday,
      students: [alexey],
    ).withEntry(alexey, lateMark(withTime: false));

    final restored = AttendanceSession.fromJson(session.toJson());
    final entry = restored.entryFor(alexey.id);
    expect(entry, isNotNull);
    expect(entry!.status, AttendanceStatus.late);
    expect(entry.hasTime, isFalse);
  });
}
