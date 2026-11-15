// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/catalog.dart';
import '../models/schedule_lesson.dart';
import 'catalog_store.dart';

/// Локальная база данных: преподаватели, кабинеты и предметы.
///
/// Пары расписания выбирают предмет, преподавателя и кабинет селектами
/// из этой базы. База живёт на устройстве, переживает перезапуск и
/// переносится файлом: [exportJson] и [importJson].
class CatalogController extends ChangeNotifier {
  CatalogController({CatalogStore? store, CatalogData? data})
    : _store = store,
      _teachers = _copy(data?.teachers),
      _rooms = _copy(data?.rooms),
      _subjects = _copy(data?.subjects);

  /// Пустая база — удобно для тестов и первого запуска.
  factory CatalogController.inMemory() => CatalogController();

  static List<T> _copy<T>(Iterable<T>? items) =>
      items == null ? <T>[] : List<T>.of(items);

  final CatalogStore? _store;
  List<Teacher> _teachers;
  List<Room> _rooms;
  List<Subject> _subjects;
  bool _loaded = false;
  int _sequence = 0;

  /// Преподаватели по алфавиту.
  List<Teacher> get teachers => _sorted(_teachers, (item) => item.name);

  /// Кабинеты по алфавиту.
  List<Room> get rooms => _sorted(_rooms, (item) => item.name);

  /// Предметы по алфавиту.
  List<Subject> get subjects => _sorted(_subjects, (item) => item.name);

  static List<T> _sorted<T>(List<T> items, String Function(T) keyOf) {
    final result = [...items]
      ..sort(
        (a, b) => keyOf(a).toLowerCase().compareTo(keyOf(b).toLowerCase()),
      );
    return List.unmodifiable(result);
  }

  /// Снимок базы для хранилища и экспорта.
  CatalogData get snapshot => CatalogData(
    teachers: List.of(_teachers),
    rooms: List.of(_rooms),
    subjects: List.of(_subjects),
  );

  /// Загружает сохранённую базу.
  Future<void> load() async {
    final store = _store;
    if (store == null || _loaded) return;
    _loaded = true;
    try {
      final saved = await store.load();
      _teachers = _copy(saved.teachers);
      _rooms = _copy(saved.rooms);
      _subjects = _copy(saved.subjects);
      notifyListeners();
    } catch (_) {
      // Повреждённое хранилище не должно мешать работе приложения.
    }
  }

  // --- Преподаватели ---

  Teacher? teacherById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final item in _teachers) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Преподаватель по имени без учёта регистра и лишних пробелов.
  Teacher? teacherByName(String name) {
    final key = normalizeCatalogName(name);
    if (key.isEmpty) return null;
    for (final item in _teachers) {
      if (item.normalizedKey == key) return item;
    }
    return null;
  }

  /// Добавляет преподавателя. Повторный вызов с тем же именем не
  /// создаёт дубликат — возвращает уже имеющегося.
  Teacher addTeacher(String name) {
    final (teacher, added) = _ensureTeacher(name);
    if (added) _changed();
    return teacher;
  }

  /// Переименовывает преподавателя; предметы не трогает — они ссылаются
  /// по идентификатору. false — имя пустое или уже занято другим.
  bool updateTeacher(String id, String name) {
    final newName = name.trim();
    if (newName.isEmpty) return false;
    final clash = teacherByName(newName);
    if (clash != null && clash.id != id) return false;
    var replaced = false;
    final updated = <Teacher>[];
    for (final item in _teachers) {
      if (item.id == id) {
        replaced = true;
        updated.add(item.copyWithName(newName));
      } else {
        updated.add(item);
      }
    }
    if (!replaced) return false;
    _teachers = updated;
    _changed();
    return true;
  }

  /// Удаляет преподавателя; предметы остаются без него.
  /// Возвращает, сколько предметов потеряло ссылку.
  int removeTeacher(String id) {
    final kept = [
      for (final item in _teachers)
        if (item.id != id) item,
    ];
    if (kept.length == _teachers.length) return 0;
    var cleared = 0;
    final subjects = <Subject>[];
    for (final subject in _subjects) {
      if (subject.teacherId == id) {
        cleared++;
        subjects.add(
          Subject(id: subject.id, name: subject.name, roomId: subject.roomId),
        );
      } else {
        subjects.add(subject);
      }
    }
    _teachers = kept;
    _subjects = subjects;
    _changed();
    return cleared;
  }

  // --- Кабинеты ---

  Room? roomById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final item in _rooms) {
      if (item.id == id) return item;
    }
    return null;
  }

  Room? roomByName(String name) {
    final key = normalizeCatalogName(name);
    if (key.isEmpty) return null;
    for (final item in _rooms) {
      if (item.normalizedKey == key) return item;
    }
    return null;
  }

  /// Добавляет кабинет; повтор с тем же именем возвращает имеющийся.
  Room addRoom(String name) {
    final (room, added) = _ensureRoom(name);
    if (added) _changed();
    return room;
  }

  /// Переименовывает кабинет; false — имя пустое или уже занято другим.
  bool updateRoom(String id, String name) {
    final newName = name.trim();
    if (newName.isEmpty) return false;
    final clash = roomByName(newName);
    if (clash != null && clash.id != id) return false;
    var replaced = false;
    final updated = <Room>[];
    for (final item in _rooms) {
      if (item.id == id) {
        replaced = true;
        updated.add(item.copyWithName(newName));
      } else {
        updated.add(item);
      }
    }
    if (!replaced) return false;
    _rooms = updated;
    _changed();
    return true;
  }

  /// Удаляет кабинет; предметы остаются без него.
  /// Возвращает, сколько предметов потеряло ссылку.
  int removeRoom(String id) {
    final kept = [
      for (final item in _rooms)
        if (item.id != id) item,
    ];
    if (kept.length == _rooms.length) return 0;
    var cleared = 0;
    final subjects = <Subject>[];
    for (final subject in _subjects) {
      if (subject.roomId == id) {
        cleared++;
        subjects.add(
          Subject(
            id: subject.id,
            name: subject.name,
            teacherId: subject.teacherId,
          ),
        );
      } else {
        subjects.add(subject);
      }
    }
    _rooms = kept;
    _subjects = subjects;
    _changed();
    return cleared;
  }

  // --- Предметы ---

  Subject? subjectById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final item in _subjects) {
      if (item.id == id) return item;
    }
    return null;
  }

  Subject? subjectByName(String name) {
    final key = normalizeCatalogName(name);
    if (key.isEmpty) return null;
    for (final item in _subjects) {
      if (item.normalizedKey == key) return item;
    }
    return null;
  }

  /// Добавляет предмет со ссылками на преподавателя и кабинет.
  /// Повторное имя не создаёт дубликат — возвращается имеющийся предмет.
  Subject addSubject(String name, {String? teacherId, String? roomId}) {
    final title = name.trim();
    if (title.isEmpty) {
      throw ArgumentError('Название предмета не может быть пустым.');
    }
    final existing = subjectByName(title);
    if (existing != null) return existing;
    final subject = Subject(
      id: _newId('s'),
      name: title,
      teacherId: teacherById(teacherId)?.id,
      roomId: roomById(roomId)?.id,
    );
    _subjects = [..._subjects, subject];
    _changed();
    return subject;
  }

  /// Полностью переписывает предмет: имя и ссылки на преподавателя и
  /// кабинет. false — имя пустое или занято другим предметом.
  bool updateSubject(
    String id, {
    required String name,
    required String? teacherId,
    required String? roomId,
  }) {
    final title = name.trim();
    if (title.isEmpty) return false;
    final clash = subjectByName(title);
    if (clash != null && clash.id != id) return false;
    var replaced = false;
    final updated = <Subject>[];
    for (final item in _subjects) {
      if (item.id == id) {
        replaced = true;
        updated.add(
          Subject(
            id: item.id,
            name: title,
            teacherId: teacherById(teacherId)?.id,
            roomId: roomById(roomId)?.id,
          ),
        );
      } else {
        updated.add(item);
      }
    }
    if (!replaced) return false;
    _subjects = updated;
    _changed();
    return true;
  }

  /// Удаляет предмет; преподавателя и кабинет не трогает.
  bool removeSubject(String id) {
    final kept = [
      for (final item in _subjects)
        if (item.id != id) item,
    ];
    if (kept.length == _subjects.length) return false;
    _subjects = kept;
    _changed();
    return true;
  }

  // --- Расписание → база ---

  /// Пополняет базу из вставленного расписания: новые предметы,
  /// преподаватели и кабинеты попадают в селекты, а у знакомых
  /// предметов, у которых не хватало ссылок, они проставляются.
  ({int teachers, int rooms, int subjects}) syncFromLessons(
    Iterable<ScheduleLesson> lessons,
  ) {
    var addedTeachers = 0;
    var addedRooms = 0;
    var addedSubjects = 0;

    for (final lesson in lessons) {
      final teacherName = lesson.teacher?.trim() ?? '';
      final roomName = lesson.room?.trim() ?? '';
      Teacher? teacher;
      Room? room;
      if (teacherName.isNotEmpty) {
        final (value, added) = _ensureTeacher(teacherName);
        teacher = value;
        if (added) addedTeachers++;
      }
      if (roomName.isNotEmpty) {
        final (value, added) = _ensureRoom(roomName);
        room = value;
        if (added) addedRooms++;
      }

      if (normalizeCatalogName(lesson.subject).isEmpty) continue;
      final subject = subjectByName(lesson.subject);
      if (subject == null) {
        _subjects = [
          ..._subjects,
          Subject(
            id: _newId('s'),
            name: lesson.subject.trim(),
            teacherId: teacher?.id,
            roomId: room?.id,
          ),
        ];
        addedSubjects++;
      } else if ((subject.teacherId == null && teacher != null) ||
          (subject.roomId == null && room != null)) {
        _subjects = [
          for (final item in _subjects)
            if (item.id == subject.id)
              Subject(
                id: item.id,
                name: item.name,
                teacherId: item.teacherId ?? teacher?.id,
                roomId: item.roomId ?? room?.id,
              )
            else item,
        ];
      }
    }

    if (addedTeachers > 0 || addedRooms > 0 || addedSubjects > 0) _changed();
    return (teachers: addedTeachers, rooms: addedRooms, subjects: addedSubjects);
  }

  // --- Экспорт и импорт ---

  /// Экспорт базы в JSON-файл (с отступами — файл читается глазами).
  String exportJson() =>
      const JsonEncoder.withIndent('  ').convert(snapshot.toJson());

  /// Импорт базы из JSON-файла: записи по именам совмещаются с теми,
  /// что уже есть, дубликаты не создаются. Брошенный [FormatException]
  /// содержит текст для пользователя.
  CatalogImportReport importJson(String raw) {
    final incoming = CatalogData.parse(raw);
    var addedTeachers = 0;
    var addedRooms = 0;
    var addedSubjects = 0;

    // Идентификаторы из файла могут совпадать с местными, поэтому
    // записи файла сопоставляются по именам, а ссылки предметов
    // перекидываются на местные идентификаторы.
    final teacherIds = <String, String>{};
    for (final teacher in incoming.teachers) {
      final existing = teacherByName(teacher.name);
      if (existing != null) {
        teacherIds[teacher.id] = existing.id;
      } else {
        final created = _ensureTeacher(teacher.name).$1;
        teacherIds[teacher.id] = created.id;
        addedTeachers++;
      }
    }

    final roomIds = <String, String>{};
    for (final room in incoming.rooms) {
      final existing = roomByName(room.name);
      if (existing != null) {
        roomIds[room.id] = existing.id;
      } else {
        final created = _ensureRoom(room.name).$1;
        roomIds[room.id] = created.id;
        addedRooms++;
      }
    }

    for (final subject in incoming.subjects) {
      if (subjectByName(subject.name) != null) continue;
      _subjects = [
        ..._subjects,
        Subject(
          id: _newId('s'),
          name: subject.name,
          teacherId: subject.teacherId == null
              ? null
              : teacherIds[subject.teacherId],
          roomId: subject.roomId == null ? null : roomIds[subject.roomId],
        ),
      ];
      addedSubjects++;
    }

    if (addedTeachers > 0 || addedRooms > 0 || addedSubjects > 0) _changed();
    return CatalogImportReport(
      teachersAdded: addedTeachers,
      roomsAdded: addedRooms,
      subjectsAdded: addedSubjects,
      alreadyInBase:
          incoming.teachers.length -
          addedTeachers +
          incoming.rooms.length -
          addedRooms +
          incoming.subjects.length -
          addedSubjects,
    );
  }

  // --- Служебное ---

  (Teacher, bool) _ensureTeacher(String name) {
    final title = name.trim();
    final existing = teacherByName(title);
    if (existing != null) return (existing, false);
    final teacher = Teacher(id: _newId('t'), name: title);
    _teachers = [..._teachers, teacher];
    return (teacher, true);
  }

  (Room, bool) _ensureRoom(String name) {
    final title = name.trim();
    final existing = roomByName(title);
    if (existing != null) return (existing, false);
    final room = Room(id: _newId('r'), name: title);
    _rooms = [..._rooms, room];
    return (room, true);
  }

  /// Стирает базу: преподавателей, предметы и кабинеты.
  ///
  /// Расписание не трогается: предметы в парах остаются с теми
  /// названиями и ссылками, которые у них были.
  void clear() {
    if (_teachers.isEmpty && _rooms.isEmpty && _subjects.isEmpty) return;
    _teachers = const [];
    _rooms = const [];
    _subjects = const [];
    _changed();
  }

  String _newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}-${++_sequence}';

  void _changed() {
    notifyListeners();
    _persist();
  }

  void _persist() {
    final store = _store;
    if (store == null) return;
    unawaited(store.save(snapshot).catchError((Object _) {}));
  }
}

/// Итог импорта: что добавилось и что уже было в базе.
class CatalogImportReport {
  const CatalogImportReport({
    required this.teachersAdded,
    required this.roomsAdded,
    required this.subjectsAdded,
    required this.alreadyInBase,
  });

  final int teachersAdded;
  final int roomsAdded;
  final int subjectsAdded;

  /// Записи файла, которые уже были в базе (по имени).
  final int alreadyInBase;

  int get totalAdded => teachersAdded + roomsAdded + subjectsAdded;

  bool get hasChanges => totalAdded > 0;

  /// Текст для снекбара.
  String get message {
    final buffer = StringBuffer(
      'Добавлено: преподавателей — $teachersAdded, кабинетов — '
      '$roomsAdded, предметов — $subjectsAdded.',
    );
    if (alreadyInBase > 0) {
      buffer.write(' Уже были в базе: $alreadyInBase.');
    }
    return buffer.toString();
  }
}
