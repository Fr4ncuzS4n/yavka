import 'attendance_entry.dart';
import 'student.dart';

/// Дата без времени — используется как ключ дня посещаемости.
DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Совпадают ли две даты (без учёта времени).
bool isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Строка таблицы посещаемости: группа + дата + студент + отметка.
class AttendanceRecord {
  const AttendanceRecord({
    required this.groupName,
    required this.date,
    required this.student,
    required this.entry,
  });

  final String groupName;
  final DateTime date;
  final Student student;
  final AttendanceEntry entry;

  /// Ключ, по которому отметка сопоставляется со строкой в таблице.
  String get key =>
      recordKey(groupName: groupName, date: date, studentId: student.id);
}

/// Единый формат ключа отметки для локального хранилища и Google Таблиц.
String recordKey({
  required String groupName,
  required DateTime date,
  required String studentId,
}) =>
    '${dateOnly(date).toIso8601String().substring(0, 10)}|$groupName|$studentId';

/// Состояние посещаемости за один день.
class AttendanceSession {
  const AttendanceSession({
    required this.groupName,
    required this.date,
    required this.students,
    this.entries = const {},
  });

  final String groupName;

  /// День, к которому относятся отметки.
  final DateTime date;

  final List<Student> students;

  /// Отметки по идентификатору студента.
  final Map<String, AttendanceEntry> entries;

  /// Создаёт пустую сессию на сегодня.
  factory AttendanceSession.forToday({
    required String groupName,
    required List<Student> students,
  }) => AttendanceSession(
    groupName: groupName,
    date: dateOnly(DateTime.now()),
    students: List<Student>.unmodifiable(students),
  );

  /// Если сохранённая сессия относится к другому дню — начинаем день заново,
  /// сохраняя список студентов.
  AttendanceSession forToday() {
    final today = dateOnly(DateTime.now());
    if (isSameDate(date, today)) return this;
    return copyWith(date: today, entries: const {});
  }

  AttendanceSession copyWith({
    String? groupName,
    DateTime? date,
    List<Student>? students,
    Map<String, AttendanceEntry>? entries,
  }) => AttendanceSession(
    groupName: groupName ?? this.groupName,
    date: date ?? this.date,
    students: students ?? this.students,
    entries: entries ?? this.entries,
  );

  /// Все отметки в виде строк таблицы.
  Iterable<AttendanceRecord> get records sync* {
    for (final student in students) {
      final entry = entries[student.id];
      if (entry == null) continue;
      yield AttendanceRecord(
        groupName: groupName,
        date: date,
        student: student,
        entry: entry,
      );
    }
  }

  /// Добавляет или заменяет отметку студента.
  AttendanceSession withEntry(Student student, AttendanceEntry entry) {
    final students = this.students.any((s) => s.id == student.id)
        ? this.students
        : List<Student>.unmodifiable([...this.students, student]);
    return copyWith(
      students: students,
      entries: {...entries, student.id: entry},
    );
  }

  /// Синхронизирует список группы с чужим списком (например из листа
  /// месяца): новых добавляет, знакомых обновляет.
  AttendanceSession withRoster(Iterable<Student> roster) {
    var merged = [...students];
    for (final student in roster) {
      if (student.fullName.isEmpty) continue;
      final index = merged.indexWhere(
        (item) => item.id == student.id,
      );
      if (index < 0) {
        merged.add(student);
      } else if (merged[index].fullName != student.fullName) {
        merged[index] = student;
      }
    }
    if (merged.length == students.length &&
        merged.every((student) => students.any(
          (item) => item.id == student.id && item.fullName == student.fullName,
        ))) {
      return this;
    }
    return copyWith(
      students: List<Student>.unmodifiable(merged),
    );
  }

  /// Объединяет удалённые отметки с локальными (удалённые важнее).
  ///
  /// Неизвестные студенты добавляются в список группы — так таблица может
  /// пополняться с другого устройства.
  AttendanceSession mergeRemote(Iterable<AttendanceRecord> remote) {
    final mergedStudents = [...students];
    final mergedEntries = {...entries};

    for (final record in remote) {
      if (!mergedStudents.any((s) => s.id == record.student.id)) {
        mergedStudents.add(record.student);
      } else {
        final index = mergedStudents.indexWhere(
          (s) => s.id == record.student.id,
        );
        if (index >= 0 &&
            mergedStudents[index].fullName != record.student.fullName) {
          mergedStudents[index] = record.student;
        }
      }
      mergedEntries[record.student.id] = record.entry;
    }

    return copyWith(
      students: List<Student>.unmodifiable(mergedStudents),
      entries: mergedEntries,
    );
  }

  Map<String, Object?> toJson() => {
    'groupName': groupName,
    'date': dateOnly(date).toIso8601String().substring(0, 10),
    'students': [for (final student in students) student.toJson()],
    'entries': {
      for (final entry in entries.entries) entry.key: entry.value.toJson(),
    },
  };

  factory AttendanceSession.fromJson(Map<String, Object?> json) {
    final groupName = json['groupName']?.toString() ?? '';
    final date = DateTime.tryParse(json['date']?.toString() ?? '');
    final studentsJson = json['students'];
    if (groupName.isEmpty || date == null || studentsJson is! List) {
      throw const FormatException('Некорректная сессия посещаемости');
    }

    final students = <Student>[];
    for (final item in studentsJson) {
      if (item is Map) {
        students.add(Student.fromJson(Map<String, Object?>.from(item)));
      }
    }

    final entries = <String, AttendanceEntry>{};
    final entriesJson = json['entries'];
    if (entriesJson is Map) {
      for (final item in entriesJson.entries) {
        if (item.value is Map) {
          try {
            entries[item.key.toString()] = AttendanceEntry.fromJson(
              Map<String, Object?>.from(item.value as Map),
            );
          } on FormatException {
            // Повреждённую отметку пропускаем, остальные данные сохраняем.
          }
        }
      }
    }

    return AttendanceSession(
      groupName: groupName,
      date: dateOnly(date),
      students: List<Student>.unmodifiable(students),
      entries: entries,
    );
  }
}
