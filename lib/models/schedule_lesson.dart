/// Учебный день недели: 1 — понедельник … 7 — воскресенье.
int weekdayOf(DateTime date) => date.weekday;

/// Название дня недели (пн, вт, …).
String weekdayShortName(int weekday) =>
    const ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'][weekday - 1];

/// Полное название дня недели.
String weekdayFullName(int weekday) => const [
  'Понедельник',
  'Вторник',
  'Среда',
  'Четверг',
  'Пятница',
  'Суббота',
  'Воскресенье',
][weekday - 1];

/// Одна пара в расписании: день недели, время, предмет и кабинет.
class ScheduleLesson {
  const ScheduleLesson({
    required this.id,
    required this.weekday,
    required this.startMinutes,
    this.endMinutes,
    required this.subject,
    this.teacher,
    this.room,
  });

  /// Уникальный идентификатор пары (нужен для отметок посещаемости).
  final String id;

  /// День недели: 1 — понедельник … 7 — воскресенье.
  final int weekday;

  /// Начало пары в минутах от полуночи.
  final int startMinutes;

  /// Конец пары в минутах от полуночи (null — не указано).
  final int? endMinutes;

  /// Название предмета.
  final String subject;

  /// Преподаватель (необязательно).
  final String? teacher;

  /// Кабинет или аудитория (необязательно).
  final String? room;

  /// «09:00» — начало пары.
  String get startLabel => formatMinutes(startMinutes);

  /// «10:30» — конец пары или пустая строка.
  String get endLabel =>
      endMinutes == null ? '' : formatMinutes(endMinutes!);

  /// «09:00–10:30» или «09:00».
  String get timeLabel => endMinutes == null
      ? startLabel
      : '$startLabel–$endLabel';

  /// Короткая строка для списка: предмет и, при наличии, кабинет.
  String get subtitle {
    final parts = [if (room != null && room!.isNotEmpty) room];
    return parts.join(' · ');
  }

  ScheduleLesson copyWith({
    String? id,
    int? weekday,
    int? startMinutes,
    int? endMinutes,
    String? subject,
    String? teacher,
    String? room,
    bool clearEnd = false,
    bool clearTeacher = false,
    bool clearRoom = false,
  }) => ScheduleLesson(
    id: id ?? this.id,
    weekday: weekday ?? this.weekday,
    startMinutes: startMinutes ?? this.startMinutes,
    endMinutes: clearEnd ? null : (endMinutes ?? this.endMinutes),
    subject: subject ?? this.subject,
    teacher: clearTeacher ? null : (teacher ?? this.teacher),
    room: clearRoom ? null : (room ?? this.room),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'weekday': weekday,
    'startMinutes': startMinutes,
    if (endMinutes != null) 'endMinutes': endMinutes,
    'subject': subject,
    if (teacher != null && teacher!.isNotEmpty) 'teacher': teacher,
    if (room != null && room!.isNotEmpty) 'room': room,
  };

  factory ScheduleLesson.fromJson(Map<String, Object?> json) {
    final id = json['id']?.toString() ?? '';
    final weekday = int.tryParse(json['weekday']?.toString() ?? '') ?? 1;
    final start = int.tryParse(json['startMinutes']?.toString() ?? '') ?? 540;
    final end = int.tryParse(json['endMinutes']?.toString() ?? '');
    final subject = json['subject']?.toString() ?? '';
    if (id.isEmpty) {
      throw const FormatException('Некорректная пара расписания');
    }
    return ScheduleLesson(
      id: id,
      weekday: weekday.clamp(1, 7),
      startMinutes: start.clamp(0, 24 * 60),
      endMinutes: end?.clamp(0, 24 * 60),
      subject: subject,
      teacher: json['teacher']?.toString(),
      room: json['room']?.toString(),
    );
  }
}

/// «09:05» — время в минутах от полуночи.
String formatMinutes(int minutes) {
  final clamped = minutes.clamp(0, 24 * 60 - 1);
  final hour = (clamped ~/ 60).toString().padLeft(2, '0');
  final minute = (clamped % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// Разбирает «09:00» в минуты от полуночи; `null`, если не время.
int? parseClockTime(String value) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}
