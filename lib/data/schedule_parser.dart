import '../models/schedule_lesson.dart';

/// Результат разбора вставленного документа с расписанием.
class ParsedSchedule {
  const ParsedSchedule({required this.lessons, required this.weekdays});

  /// Разобранные пары.
  final List<ScheduleLesson> lessons;

  /// Дни недели, которые затронул документ (если в тексте есть
  /// заголовки дней — их и перечисляет; иначе один выбранный день).
  final Set<int> weekdays;
}

/// Разбор вставленного текста с расписанием в пары.
///
/// Поддерживает:
/// - строки вида «09:00–10:30 Математика, каб. 201, Иванова И.И.»;
/// - «09:00 Математика», «1. 09:00 Математика (каб. 201)»;
/// - колонки через табуляцию: «09:00 → 10:30 → Математика → 201»;
/// - заголовки дней: «Понедельник», «Пн:», «ВТОРНИК —».
abstract final class ScheduleParser {
  /// Разбирает [text]; пары без заголовка дня попадают на
  /// [fallbackWeekday].
  static ParsedSchedule parse(String text, {required int fallbackWeekday}) {
    final lessons = <ScheduleLesson>[];
    final weekdays = <int>{};
    var currentWeekday = fallbackWeekday.clamp(1, 7);
    var sawAnyLesson = false;

    for (final rawLine in text.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      final weekday = _matchWeekdayHeading(line);
      if (weekday != null) {
        currentWeekday = weekday;
        continue;
      }

      final lesson = _parseLessonLine(line, weekday: currentWeekday);
      if (lesson == null) continue;
      lessons.add(lesson);
      weekdays.add(lesson.weekday);
      sawAnyLesson = true;
    }

    return ParsedSchedule(
      lessons: sawAnyLesson ? lessons : const [],
      weekdays: sawAnyLesson ? weekdays : const {},
    );
  }

  /// «Понедельник», «пн:», «СРЕДА -» → номер дня; строка без времени.
  static int? _matchWeekdayHeading(String line) {
    final time = RegExp(r'\d{1,2}[:.]\d{2}').firstMatch(line);
    if (time != null) return null;
    // `\b` в Dart не работает с кириллицей, поэтому границу слова
    // проверяем негативным lookahead за кириллическую букву.
    final match = RegExp(
      r'^(?:\d+[.)]\s*)?(понедельник|вторник|среда|четверг|пятница|суббота|воскресенье|пн|вт|ср|чт|пт|сб|вс)(?![а-яА-ЯёЁ])',
      caseSensitive: false,
    ).firstMatch(line);
    if (match == null) return null;
    final word = match.group(1)!.toLowerCase();
    const full = {
      'понедельник': 1,
      'вторник': 2,
      'среда': 3,
      'четверг': 4,
      'пятница': 5,
      'суббота': 6,
      'воскресенье': 7,
    };
    const short = {'пн': 1, 'вт': 2, 'ср': 3, 'чт': 4, 'пт': 5, 'сб': 6, 'вс': 7};
    return full[word] ?? short[word];
  }

  static ScheduleLesson? _parseLessonLine(
    String line, {
    required int weekday,
  }) {
    // Колонки через табуляцию: время, конец (может отсутствовать),
    // предмет, кабинет, преподаватель.
    if (line.contains('\t')) {
      final cells = [
        for (final cell in line.split('\t'))
          if (cell.trim().isNotEmpty) cell.trim(),
      ];
      if (cells.isEmpty) return null;
      final start = _parseTime(cells.first);
      if (start == null) return null;
      var index = 1;
      int? end;
      if (cells.length > 1 && _isEndTime(cells[1], start)) {
        end = _parseTime(cells[1]);
        index = 2;
      }
      final subject = index < cells.length ? _cleanSubject(cells[index]) : '';
      if (subject.isEmpty) return null;
      final room = index + 1 < cells.length ? cells[index + 1] : null;
      final teacher = index + 2 < cells.length ? cells[index + 2] : null;
      return _build(
        weekday: weekday,
        start: start,
        end: end,
        subject: subject,
        room: _roomValue(room),
        teacher: _teacherValue(teacher),
      );
    }

    // Снимаем маркеры списка: «1.», «-», «•».
    final body = line.replaceFirst(
      RegExp(r'^(?:\d+\s*[.)]|[-–—•*])\s*'),
      '',
    );

    // Время: «09:00», «9.00», диапазон «09:00-10:30», «9:00 до 10:30».
    final timeMatch = RegExp(
      r'^(\d{1,2})[:.](\d{2})(?:\s*(?:-|–|—|до)\s*(\d{1,2})[:.](\d{2}))?',
    ).firstMatch(body);
    if (timeMatch == null) return null;

    final start = _minutes(timeMatch.group(1)!, timeMatch.group(2)!);
    if (start == null) return null;
    final endGroup = timeMatch.group(3);
    final end = endGroup == null
        ? null
        : _minutes(endGroup, timeMatch.group(4)!);

    var rest = body.substring(timeMatch.end).trim();
    // Отделяем пережитки разделителей после времени.
    rest = rest.replaceFirst(RegExp(r'^[-–—:,|·]\s*'), '');

    // Кабинет: «каб. 201», «ауд. 3-14», «кабинет 5».
    String? room;
    final roomMatch = RegExp(
      r'(?:каб\.?|ауд\.?|кабинет|аудитория|комн\.?)\s*([^\s,;|·]+)',
      caseSensitive: false,
    ).firstMatch(rest);
    if (roomMatch != null) {
      room = _roomValue(roomMatch.group(0));
      rest = rest.replaceRange(roomMatch.start, roomMatch.end, ' ');
    }

    // Преподаватель — после длинного тире или «преп.».
    String? teacher;
    final dashIndex = rest.lastIndexOf(RegExp(r'[–—]'));
    if (dashIndex >= 0) {
      final candidate = _cleanSubject(rest.substring(dashIndex + 1));
      if (_looksLikeName(candidate)) {
        teacher = candidate;
        rest = rest.substring(0, dashIndex);
      }
    }
    if (teacher == null) {
      final prepMatch = RegExp(
        r'(?:преп\.?|преподаватель)\s+([^\s,;|·].*)$',
        caseSensitive: false,
      ).firstMatch(rest);
      if (prepMatch != null) {
        final candidate = _cleanSubject(prepMatch.group(1) ?? '');
        if (candidate.isNotEmpty) {
          teacher = candidate;
          rest = rest.substring(0, prepMatch.start);
        }
      }
    }

    final subject = _cleanSubject(rest);
    if (subject.isEmpty) return null;

    return _build(
      weekday: weekday,
      start: start,
      end: end,
      subject: subject,
      room: room,
      teacher: teacher,
    );
  }

  static ScheduleLesson _build({
    required int weekday,
    required int start,
    required int? end,
    required String subject,
    required String? room,
    required String? teacher,
  }) => ScheduleLesson(
    id: _generateId(),
    weekday: weekday.clamp(1, 7),
    startMinutes: start,
    endMinutes: end,
    subject: subject,
    room: (room == null || room.trim().isEmpty) ? null : room.trim(),
    teacher: (teacher == null || teacher.trim().isEmpty) ? null : teacher.trim(),
  );

  static int? _minutes(String hourText, String minuteText) {
    final hour = int.tryParse(hourText);
    final minute = int.tryParse(minuteText);
    if (hour == null || minute == null) return null;
    if (hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }

  static int? _parseTime(String value) {
    final match = RegExp(r'^(\d{1,2})[:.](\d{2})$').firstMatch(value.trim());
    if (match == null) return null;
    return _minutes(match.group(1)!, match.group(2)!);
  }

  /// Вторая колонка — конец пары, если это более позднее время.
  static bool _isEndTime(String value, int start) {
    final end = _parseTime(value);
    return end != null && end > start;
  }

  static String _cleanSubject(String value) => value
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(
        RegExp(r'^[-–—:,|·\s]+|[-–—,;:|·\s]+$'),
        '',
      )
      .trim();

  /// Похоже ли на имя человека: «Петров», «Петров П.П.», «Иванова И.И.».
  static bool _looksLikeName(String value) {
    if (value.isEmpty || value.length > 60) return false;
    return RegExp(
      r"^[A-ZА-ЯЁ][A-Za-zА-Яа-яЁё\.\- ]{0,60}$",
    ).hasMatch(value);
  }

  /// «каб. 201» → «201», «аудитория 3-14» → «3-14».
  static String? _roomValue(String? value) {
    if (value == null) return null;
    final match = RegExp(
      r'(?:каб\.?|ауд\.?|кабинет|аудитория|комн\.?)\s*([^\s,;|·]+)',
      caseSensitive: false,
    ).firstMatch(value.trim());
    final raw = match?.group(1) ?? value.trim();
    final cleaned = _cleanSubject(raw);
    return cleaned.isEmpty ? null : cleaned;
  }

  static String? _teacherValue(String? value) {
    if (value == null) return null;
    final cleaned = _cleanSubject(value);
    return cleaned.isEmpty ? null : cleaned;
  }

  static int _idCounter = 0;

  static String _generateId() {
    final stamp = DateTime.now().microsecondsSinceEpoch;
    return 'lesson-$stamp-${_idCounter++}';
  }
}
