import 'attendance_entry.dart';
import 'attendance_status.dart';
import 'schedule_lesson.dart';
import 'student.dart';

/// Дата без времени — используется как ключ дня посещаемости.
DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Совпадают ли две даты (без учёта времени).
bool isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Выходной день (суббота или воскресенье): отметки недоступны.
bool isWeekendDate(DateTime date) =>
    date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;

/// Маркер пары внутри ключа отметки: id пары или её название.
String? lessonMarker(String? lessonKey, String? lessonTitle) {
  final key = lessonKey?.trim();
  if (key != null && key.isNotEmpty) return key;
  final title = lessonTitle?.trim();
  if (title != null && title.isNotEmpty) return title;
  return null;
}

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
  String get key => recordKey(
    groupName: groupName,
    date: date,
    studentId: student.id,
    lesson: lessonMarker(entry.lessonKey, entry.lessonTitle),
  );
}

/// Единый формат ключа отметки для локального хранилища и Google Таблиц.
///
/// [lesson] отличает отметки на разных парах одного дня.
String recordKey({
  required String groupName,
  required DateTime date,
  required String studentId,
  String? lesson,
}) {
  final base =
      '${dateOnly(date).toIso8601String().substring(0, 10)}|$groupName|$studentId';
  final marker = lesson?.trim();
  return marker == null || marker.isEmpty ? base : '$base|$marker';
}

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

  /// Отметки по ключу `entryKey`: студент + (опционально) пара.
  final Map<String, AttendanceEntry> entries;

  /// Ключ отметки в [entries]: студент и (опционально) пара.
  ///
  /// Отметка на весь день — просто идентификатор студента; отметка на
  /// паре — «идентификатор|пара» (id пары или её название).
  static String entryKey({
    required String studentId,
    String? lessonKey,
    String? lessonTitle,
  }) {
    final marker = lessonMarker(lessonKey, lessonTitle);
    return marker == null ? studentId : '$studentId|$marker';
  }

  /// Отметка студента на весь день (без привязки к паре).
  AttendanceEntry? entryFor(String studentId) => entries[studentId];

  /// Отметка студента на конкретной паре.
  ///
  /// Сначала ищем по идентификатору пары (локальные отметки), затем —
  /// по названию (отметки, загруженные из таблицы без id пары).
  ///
  /// Совпадение по названию считается отметкой этой пары, только если
  /// у записи нет своего идентификатора пары: в дне бывает два одинаковых
  /// предмета, и отметка одной из них не должна выдаваться за отметку
  /// другой (иначе студент показывается отмеченным на обеих парах и
  /// поочерёдная отметка его пропускает).
  AttendanceEntry? entryInLesson(
    String studentId, {
    String? lessonKey,
    String? lessonTitle,
  }) {
    final key = lessonKey?.trim();
    if (key != null && key.isNotEmpty) {
      final direct = entries[entryKey(studentId: studentId, lessonKey: key)];
      if (direct != null) return direct;
    }
    final title = lessonTitle?.trim();
    if (title == null || title.isEmpty) return null;
    for (final item in entries.entries) {
      if (!item.key.startsWith('$studentId|')) continue;
      final entry = item.value;
      final entryKey = entry.lessonKey?.trim() ?? '';
      if (key != null &&
          key.isNotEmpty &&
          entryKey.isNotEmpty &&
          entryKey != key) {
        continue;
      }
      if (entry.lessonTitle == title) return entry;
    }
    return null;
  }

  /// Отметка студента для вкладки «Весь день».
  ///
  /// Это собственная дневная отметка студента. Если её нет, но все пары
  /// дня у студента отмечены одним статусом — «Пришёл», «По уважительной»
  /// или «Не пришёл» — дневной считается эта отметка: все ячейки дня
  /// заполнены, и студент не должен выглядеть неотмеченным (иначе
  /// поочерёдная отметка снова его подсвечивает).
  ///
  /// Сходимости нет, если хоть одна пара не отмечена, статусы пар
  /// расходятся или среди отметок есть «Опоздал»: у опоздания время
  /// конкретной пары, ко всему дню оно не сводится.
  AttendanceEntry? wholeDayEntryFor(
    String studentId,
    List<ScheduleLesson> lessons,
  ) {
    final own = entries[studentId];
    if (own != null) return own;
    if (lessons.isEmpty) return null;

    AttendanceEntry? common;
    for (final lesson in lessons) {
      final entry = entryInLesson(
        studentId,
        lessonKey: lesson.id,
        lessonTitle: lesson.subject,
      );
      if (entry == null) return null;
      if (entry.status == AttendanceStatus.late) return null;
      if (common == null) {
        common = entry;
      } else if (common.status != entry.status) {
        return null;
      }
    }
    return common;
  }

  /// Сколько студентов отмечено на паре.
  ///
  /// Считаются разные студенты, а не записи: у одного студента может
  /// оказаться две записи на одну пару — локальная с id пары и пришедшая
  /// из таблицы только с её названием. Такой студент — одна отметка.
  int markedCountInLesson({String? lessonKey, String? lessonTitle}) {
    final title = lessonTitle?.trim();
    return {
      for (final item in entries.entries)
        if ((lessonKey != null && item.value.lessonKey == lessonKey) ||
            (lessonKey != null &&
                title != null &&
                title.isNotEmpty &&
                item.value.lessonKey == null &&
                item.value.lessonTitle == title))
          item.key.split('|').first.trim(),
    }.length;
  }

  /// Сколько разных студентов отмечено за день — на весь день или
  /// хотя бы на одной паре. Ячейки не суммируются: студент, отмеченный
  /// на трёх парах, считается один раз.
  int get markedCountForDay => entries.keys
      .map((key) => key.split('|').first.trim())
      .toSet()
      .length;

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

  /// Убирает студентов, входящих в демо-состав, вместе с их отметками.
  ///
  /// [demoRoster] — отпечаток демонстрационной группы: идентификатор →
  /// ФИО. Студент считается демонстрационным, только если совпали и
  /// ФИО, и идентификатор: у настоящего студента из журнала
  /// идентификатор — его ФИО, демо-номером он быть не может. Отметки
  /// убираются по ключам с этим идентификатором.
  AttendanceSession withoutDemoStudents(Map<String, String> demoRoster) {
    if (demoRoster.isEmpty) return this;
    final demoIdByName = {
      for (final item in demoRoster.entries)
        _normalizeName(item.value): item.key.trim(),
    }..removeWhere((_, id) => id.isEmpty);
    if (demoIdByName.isEmpty) return this;

    final ids = <String>{};
    final keptStudents = <Student>[];
    for (final student in students) {
      final demoId = demoIdByName[_normalizeName(student.fullName)];
      // Идентификатор сравниваем и добавляем в нормализованном виде:
      // в сохранённых данных он мог прийти с лишними пробелами.
      final trimmedId = student.id.trim();
      if (demoId != null && demoId == trimmedId) {
        ids.add(trimmedId);
      } else {
        keptStudents.add(student);
      }
    }
    if (ids.isEmpty) return this;

    final keptEntries = <String, AttendanceEntry>{};
    for (final item in entries.entries) {
      if (ids.contains(item.key.split('|').first.trim())) continue;
      keptEntries[item.key] = item.value;
    }
    return copyWith(
      students: List<Student>.unmodifiable(keptStudents),
      entries: keptEntries,
    );
  }

  /// ФИО без регистра, лишних пробелов и переносов строк — чтобы
  /// «Алексей  Морозов» из хранилища совпал с демо-«Алексей Морозов».
  static String _normalizeName(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

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

  /// Добавляет или заменяет отметку студента (на день или на пару).
  AttendanceSession withEntry(Student student, AttendanceEntry entry) {
    final students = this.students.any((s) => s.id == student.id)
        ? this.students
        : List<Student>.unmodifiable([...this.students, student]);
    final key = entryKey(
      studentId: student.id,
      lessonKey: entry.lessonKey,
      lessonTitle: entry.lessonTitle,
    );
    return copyWith(
      students: students,
      entries: {...entries, key: entry},
    );
  }

  /// Синхронизирует список группы с чужим списком (например из листа
  /// месяца): новых добавляет, знакомых обновляет.
  ///
  /// Знакомый — совпадение по идентификатору или по ФИО. Найденного по
  /// ФИО оставляем как есть: локальные отметки привязаны к его
  /// идентификатору, менять его нельзя.
  AttendanceSession withRoster(Iterable<Student> roster) {
    var merged = [...students];
    var changed = false;
    for (final student in roster) {
      if (student.fullName.isEmpty) continue;
      final byId = merged.indexWhere((item) => item.id == student.id);
      if (byId >= 0) {
        if (merged[byId].fullName != student.fullName) {
          merged[byId] = student;
          changed = true;
        }
        continue;
      }
      final byName = merged.indexWhere(
        (item) =>
            item.fullName.toLowerCase() == student.fullName.toLowerCase(),
      );
      if (byName >= 0) continue;
      merged.add(student);
      changed = true;
    }
    if (!changed) return this;
    return copyWith(students: List<Student>.unmodifiable(merged));
  }

  /// Выравнивает список группы по списку из журнала.
  ///
  /// Работает как [withRoster] — новых добавляет, знакомых обновляет —
  /// и вдобавок убирает студентов, которых в журнале нет, вместе с их
  /// отметками: журнал — источник правды о списке, студент вне его
  /// диапазона строк в список не попадает (например, строка «Итого»).
  /// Пустой [roster] сессию не меняет: пустой журнал — не повод стирать
  /// группу.
  AttendanceSession alignedToRoster(Iterable<Student> roster) {
    final incoming = roster
        .where((student) => student.fullName.trim().isNotEmpty)
        .toList();
    if (incoming.isEmpty) return this;

    // Знакомый — совпадение ФИО или идентификатора с журналом.
    final rosterNames = <String>{
      for (final student in incoming) _normalizeName(student.fullName),
    };
    final rosterIds = <String>{
      for (final student in incoming) _normalizeName(student.id),
    };

    final removedIds = <String>{};
    final keptStudents = <Student>[];
    for (final student in students) {
      final known = rosterNames.contains(_normalizeName(student.fullName)) ||
          rosterIds.contains(_normalizeName(student.id));
      if (known) {
        keptStudents.add(student);
      } else {
        removedIds.add(student.id.trim());
      }
    }

    // Отметки убранных студентов остаются без хозяина — стираем их.
    final session = removedIds.isEmpty
        ? this
        : copyWith(
            students: List<Student>.unmodifiable(keptStudents),
            entries: {
              for (final item in entries.entries)
                if (!removedIds.contains(item.key.split('|').first.trim()))
                  item.key: item.value,
            },
          );
    return session.withRoster(incoming);
  }

  /// Объединяет удалённые отметки с локальными (удалённые важнее).
  ///
  /// Неизвестные студенты добавляются в список группы — так таблица может
  /// пополняться с другого устройства.
  /// Вливает отметки из журнала, не перекрывая отметки приложения.
  ///
  /// Отметка из таблицы применяется только там, где в приложении ещё
  /// ничего нет. Дневная отметка студента закрывает весь день (именно
  /// так она и раскладывается в таблицу при записи), отметка на паре —
  /// свою пару: табличные данные лишь дополняют пробелы. Новых
  /// студентов добавляем, ФИО знакомых обновляем.
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
      if (_coveredByLocalMark(record)) continue;
      mergedEntries[entryKey(
        studentId: record.student.id,
        lessonKey: record.entry.lessonKey,
        lessonTitle: record.entry.lessonTitle,
      )] = record.entry;
    }

    return copyWith(
      students: List<Student>.unmodifiable(mergedStudents),
      entries: mergedEntries,
    );
  }

  /// Закрыт ли слот табличной отметки уже отмеченным студентом.
  ///
  /// Дневная отметка студента означает отметку на все пары дня, поэтому
  /// она закрывает студента целиком; отметка на паре закрывает только
  /// свою пару.
  bool _coveredByLocalMark(AttendanceRecord record) {
    if (entries.containsKey(record.student.id)) return true;
    final key = entryKey(
      studentId: record.student.id,
      lessonKey: record.entry.lessonKey,
      lessonTitle: record.entry.lessonTitle,
    );
    return entries.containsKey(key);
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
