import 'dart:convert';

/// Локальная база «Явки»: преподаватели, кабинеты и предметы.
///
/// База живёт на устройстве (SharedPreferences), пары расписания
/// выбирают предмет/преподавателя/кабинет селектами из неё. Базу можно
/// перенести на другое устройство файлом: экспорт и импорт JSON
/// (формат описан в [CatalogData.toJson] и [CatalogData.parse]).
///
/// Преподаватели и кабинеты — просто названия. Предмет ссылается на
/// них по идентификаторам, поэтому переименование не ломает связи.

/// Преподаватель: пока только ФИО.
class Teacher {
  const Teacher({required this.id, required this.name});

  /// Уникальный идентификатор внутри базы.
  final String id;

  /// ФИО, как ввёл староста.
  final String name;

  Teacher copyWithName(String name) => Teacher(id: id, name: name);

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  /// Толерантно к старым файлам: запись без имени пропускается
  /// вызывающим кодом (см. [CatalogData.fromJson]).
  factory Teacher.fromJson(Map<String, Object?> json) => Teacher(
    id: json['id']?.toString() ?? '',
    name: (json['name'] ?? '').toString().trim(),
  );

  /// Имя без лишних пробелов — для сравнения «тот же преподаватель?».
  String get normalizedKey => normalizeCatalogName(name);

  @override
  String toString() => 'Teacher($id, $name)';
}

/// Кабинет или аудитория: пока только название.
class Room {
  const Room({required this.id, required this.name});

  /// Уникальный идентификатор внутри базы.
  final String id;

  /// Название, как ввёл староста («201», «каб. 201»).
  final String name;

  Room copyWithName(String name) => Room(id: id, name: name);

  Map<String, Object?> toJson() => {'id': id, 'name': name};

  factory Room.fromJson(Map<String, Object?> json) => Room(
    id: json['id']?.toString() ?? '',
    name: (json['name'] ?? '').toString().trim(),
  );

  String get normalizedKey => normalizeCatalogName(name);

  @override
  String toString() => 'Room($id, $name)';
}

/// Предмет: название и ссылки на преподавателя и кабинет.
class Subject {
  const Subject({required this.id, required this.name, this.teacherId, this.roomId});

  /// Уникальный идентификатор внутри базы.
  final String id;

  /// Название предмета.
  final String name;

  /// Идентификатор преподавателя ([Teacher.id]) или null.
  final String? teacherId;

  /// Идентификатор кабинета ([Room.id]) или null.
  final String? roomId;

  Subject copyWith({
    String? name,
    String? teacherId,
    String? roomId,
  }) => Subject(
    id: id,
    name: name ?? this.name,
    teacherId: teacherId ?? this.teacherId,
    roomId: roomId ?? this.roomId,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    if (teacherId != null && teacherId!.isNotEmpty) 'teacherId': teacherId,
    if (roomId != null && roomId!.isNotEmpty) 'roomId': roomId,
  };

  factory Subject.fromJson(Map<String, Object?> json) => Subject(
    id: json['id']?.toString() ?? '',
    name: (json['name'] ?? '').toString().trim(),
    teacherId: _optionalId(json['teacherId']),
    roomId: _optionalId(json['roomId']),
  );

  static String? _optionalId(Object? value) {
    final text = value?.toString() ?? '';
    return text.isEmpty ? null : text;
  }

  String get normalizedKey => normalizeCatalogName(name);

  @override
  String toString() => 'Subject($id, $name)';
}

/// Снимок базы целиком — формат хранилища и файла импорта/экспорта.
///
/// Файл выглядит так:
/// ```json
/// {
///   "kind": "yavka.catalog",
///   "version": 1,
///   "teachers": [{"id": "t-1", "name": "Иванов И.И."}],
///   "rooms": [{"id": "r-1", "name": "201"}],
///   "subjects": [{"id": "s-1", "name": "Математика",
///                 "teacherId": "t-1", "roomId": "r-1"}]
/// }
/// ```
class CatalogData {
  const CatalogData({
    this.teachers = const [],
    this.rooms = const [],
    this.subjects = const [],
  });

  /// Метка формата в файле импорта/экспорта.
  static const kind = 'yavka.catalog';

  /// Версия формата.
  static const version = 1;

  final List<Teacher> teachers;
  final List<Room> rooms;
  final List<Subject> subjects;

  bool get isEmpty => teachers.isEmpty && rooms.isEmpty && subjects.isEmpty;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'version': version,
    'teachers': [for (final item in teachers) item.toJson()],
    'rooms': [for (final item in rooms) item.toJson()],
    'subjects': [for (final item in subjects) item.toJson()],
  };

  /// Толерантный разбор (для хранилища): битые записи пропускаются,
  /// отсутствующие поля дают пустые списки.
  factory CatalogData.fromJson(Object? json) => CatalogData(
    teachers: _list(json is Map ? json['teachers'] : null, Teacher.fromJson),
    rooms: _list(json is Map ? json['rooms'] : null, Room.fromJson),
    subjects: _list(json is Map ? json['subjects'] : null, Subject.fromJson),
  );

  static List<T> _list<T>(
    Object? raw,
    T Function(Map<String, Object?>) convert,
  ) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map && _hasName(item)) convert(Map<String, Object?>.from(item)),
    ];
  }

  static bool _hasName(Object item) =>
      item is Map && (item['name'] ?? '').toString().trim().isNotEmpty;

  /// Разбор файла импорта: строгий — чужие файлы и новые версии
  /// формата сообщают об этом понятно, а не падают с трейсбеком.
  factory CatalogData.parse(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw const FormatException(
        'Файл не похож на JSON: проверьте, что скопировался экспорт '
        'целиком.',
      );
    }
    if (decoded is! Map) {
      throw const FormatException(
        'Файл должен быть JSON-объектом со списками преподавателей, '
        'кабинетов и предметов.',
      );
    }
    final fileKind = decoded['kind']?.toString();
    if (fileKind != null && fileKind != kind) {
      throw const FormatException('Это не файл базы «Явки».');
    }
    final fileVersion = int.tryParse(decoded['version']?.toString() ?? '');
    if (fileVersion != null && fileVersion > version) {
      throw const FormatException(
        'Файл сделан в более новой версии «Явки»: обновите приложение '
        'и попробуйте снова.',
      );
    }
    return CatalogData.fromJson(decoded);
  }
}

/// «Иванов и.и.» и «Иванов И.И.» — один преподаватель: ключ сравнения
/// имён без лишних пробелов и регистра.
String normalizeCatalogName(String name) => name
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ')
    .toLowerCase();
