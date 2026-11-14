// Тесты вычищения демонстрационных студентов из хранилища приложения.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yavka/data/attendance_store.dart';
import 'package:yavka/models/attendance_entry.dart';
import 'package:yavka/models/attendance_session.dart';
import 'package:yavka/models/attendance_status.dart';
import 'package:yavka/models/student.dart';

/// Отпечаток демонстрационной группы: идентификатор → ФИО.
const demoRoster = {
  '1': 'Алексей Морозов',
  '2': 'Мария Соколова',
  '3': 'Дмитрий Волков',
  '4': 'Анна Кузнецова',
  '5': 'Никита Попов',
  '6': 'София Лебедева',
  '7': 'Артём Новиков',
  '8': 'Екатерина Фёдорова',
  '9': 'Максим Егоров',
  '10': 'Полина Павлова',
};

void main() {
  final day = DateTime(2026, 11, 9);
  const demo = Student(id: '1', fullName: 'Алексей Морозов');
  const real = Student(id: '20', fullName: 'Иван Настоящий');
  const storageKey = 'yavka.attendance.days.v1';

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
  });

  Future<SharedPreferencesAttendanceStore> store() async =>
      SharedPreferencesAttendanceStore(
        await SharedPreferences.getInstance(),
      );

  test('записанные дни читаются обратно (круговорот хранилища)', () async {
    final attendance = await store();
    final session = AttendanceSession(
      groupName: 'Группа',
      date: day,
      students: const [real],
      entries: {
        '20': AttendanceEntry(status: AttendanceStatus.came, markedAt: day),
        '20|mon-2': AttendanceEntry(
          status: AttendanceStatus.late,
          markedAt: day,
        ),
      },
    );

    await attendance.saveAll([session]);
    final days = await attendance.loadAll();

    expect(days[day]!.groupName, 'Группа');
    expect(
      days[day]!.students.map((student) => student.fullName),
      [real.fullName],
    );
    expect(days[day]!.entries.keys, ['20', '20|mon-2']);
  });

  test('без демо-студентов сессия возвращается как есть', () {
    final session = AttendanceSession(
      groupName: 'Группа',
      date: day,
      students: const [real],
      entries: {
        '20': AttendanceEntry(status: AttendanceStatus.came, markedAt: day),
      },
    );

    expect(identical(session.withoutDemoStudents(demoRoster), session), isTrue);
    expect(identical(session.withoutDemoStudents(const {}), session), isTrue);
  });

  test('демо-студент убирается вместе со своими отметками', () {
    final session = AttendanceSession(
      groupName: 'БИТ-24-03',
      date: day,
      students: const [demo, real],
      entries: {
        // Отметки демо-студента: на весь день и на паре.
        '1': AttendanceEntry(status: AttendanceStatus.came, markedAt: day),
        '1|mon-2': AttendanceEntry(
          status: AttendanceStatus.late,
          markedAt: day,
        ),
        // Настоящие отметки остаются.
        '20': AttendanceEntry(status: AttendanceStatus.excused, markedAt: day),
        '20|mon-2': AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: day,
        ),
      },
    );

    final cleaned = session.withoutDemoStudents(demoRoster);

    expect(
      cleaned.students.map((student) => student.fullName),
      [real.fullName],
    );
    expect(cleaned.entries.keys, ['20', '20|mon-2']);
  });

  test('регистр и лишние пробелы не спасают демо-студента', () {
    final session = AttendanceSession(
      groupName: '',
      date: day,
      students: const [
        Student(id: ' 1 ', fullName: 'алексей  морозов'),
        real,
      ],
      entries: {
        '1': AttendanceEntry(status: AttendanceStatus.came, markedAt: day),
      },
    );

    final cleaned = session.withoutDemoStudents(demoRoster);
    expect(
      cleaned.students.map((student) => student.fullName),
      [real.fullName],
    );
    expect(cleaned.entries, isEmpty);
  });

  test('настоящий студент из журнала с тем же ФИО не вычищается', () {
    // У отметок из журнала идентификатор студента — его ФИО, поэтому
    // совпадает только имя, но не демо-номер.
    final journalStudent = Student(
      id: 'Алексей Морозов',
      fullName: 'Алексей Морозов',
    );
    final session = AttendanceSession(
      groupName: '',
      date: day,
      students: [journalStudent],
      entries: {
        'Алексей Морозов': AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: day,
        ),
      },
    );

    final cleaned = session.withoutDemoStudents(demoRoster);

    expect(identical(cleaned, session), isTrue);
    expect(cleaned.students, [journalStudent]);
    expect(cleaned.entries.keys, ['Алексей Морозов']);
  });

  test('хранилище при чтении вычищает демо-студентов и переписывается',
      () async {
    final preferences = await SharedPreferences.getInstance();
    final attendance = await store();
    await attendance.saveAll([
      AttendanceSession(
        groupName: 'БИТ-24-03',
        date: day,
        students: const [demo, real],
        entries: {
          '1': AttendanceEntry(status: AttendanceStatus.came, markedAt: day),
          '20': AttendanceEntry(status: AttendanceStatus.came, markedAt: day),
        },
      ),
    ]);

    final days = await attendance.loadAll();

    // В памяти остался только настоящий студент с его отметкой.
    final loaded = days[day]!;
    expect(
      loaded.students.map((student) => student.fullName),
      [real.fullName],
    );
    expect(loaded.entries.keys, ['20']);

    // Хранилище переписано без демо-студентов.
    final raw = preferences.getString(storageKey)!;
    expect(raw, isNot(contains('Алексей Морозов')));
    final reread = await attendance.loadAll();
    expect(
      reread[day]!.students.map((student) => student.fullName),
      [real.fullName],
    );
  });

  test('день с одними демо-отметками из хранилища исчезает', () async {
    final preferences = await SharedPreferences.getInstance();
    final attendance = await store();
    await attendance.saveAll([
      AttendanceSession(
        groupName: 'БИТ-24-03',
        date: day,
        students: const [demo],
        entries: {
          '1': AttendanceEntry(status: AttendanceStatus.came, markedAt: day),
        },
      ),
    ]);

    expect(await attendance.loadAll(), isEmpty);
    // В JSON хранилища дня больше нет.
    final raw = jsonDecode(preferences.getString(storageKey)!) as Map;
    expect(raw['days'], isEmpty);
  });
}
