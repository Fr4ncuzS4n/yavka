import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/attendance_session.dart';

/// Локальное хранилище состояния посещаемости: сессии по дням.
abstract interface class AttendanceStore {
  Future<Map<DateTime, AttendanceSession>> loadAll();

  Future<void> saveAll(List<AttendanceSession> sessions);
}

/// Хранит сессии в памяти — используется в тестах и как запасной вариант.
class MemoryAttendanceStore implements AttendanceStore {
  final Map<DateTime, AttendanceSession> _days = {};

  @override
  Future<Map<DateTime, AttendanceSession>> loadAll() async => Map.of(_days);

  @override
  Future<void> saveAll(List<AttendanceSession> sessions) async => _days
    ..clear()
    ..addEntries([
      for (final session in sessions) MapEntry(dateOnly(session.date), session),
    ]);
}

/// Хранит сессии в SharedPreferences (Android, iOS, Linux, macOS, Windows, web).
class SharedPreferencesAttendanceStore implements AttendanceStore {
  SharedPreferencesAttendanceStore(this._preferences);

  /// Дни отметок: `{ 'ГГГГ-ММ-ДД': сессия }`.
  static const _key = 'yavka.attendance.days.v1';

  /// Старый формат: одна сессия «сегодня». Читается при миграции.
  static const _legacyKey = 'yavka.attendance.session.v1';

  /// Демонстрационная группа из ранних версий приложения: идентификатор
  /// → ФИО.
  ///
  /// Раньше они заливались при каждом запуске и сохранялись в
  /// хранилище. При чтении такие студенты вычищаются вместе с их
  /// отметками, а хранилище переписывается без них.
  static const Map<String, String> _demoRoster = {
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

  final SharedPreferences _preferences;

  @override
  Future<Map<DateTime, AttendanceSession>> loadAll() async {
    final raw = _preferences.getString(_key);
    if (raw == null || raw.isEmpty) {
      return _cleanupDays(_loadLegacy());
    }

    final decoded = _decode(raw);
    // Формат `saveAll`: обёртка `{ 'days': { 'ГГГГ-ММ-ДД': сессия } }`.
    // Раньше чтение обходило верхний уровень и ничего не находило —
    // отметки не переживали перезапуск.
    final wrapped = decoded is Map ? decoded['days'] : null;
    final source = wrapped is Map ? wrapped : decoded;
    final days = <DateTime, AttendanceSession>{};
    if (source is! Map) return days;
    for (final item in source.entries) {
      final date = DateTime.tryParse(item.key.toString());
      if (date == null || item.value is! Map) continue;
      try {
        days[dateOnly(date)] = AttendanceSession.fromJson(
          Map<String, Object?>.from(item.value as Map),
        );
      } on FormatException {
        // Повреждённый день пропускаем, остальные читаем.
      }
    }
    return _cleanupDays(days);
  }

  /// Вычищает демонстрационных студентов из прочитанных дней и, если
  /// что-то изменилось, переписывает хранилище без них.
  Future<Map<DateTime, AttendanceSession>> _cleanupDays(
    Map<DateTime, AttendanceSession> days,
  ) async {
    final cleaned = <DateTime, AttendanceSession>{};
    var changed = false;
    for (final item in days.entries) {
      final session = item.value.withoutDemoStudents(_demoRoster);
      if (!identical(session, item.value)) changed = true;
      cleaned[item.key] = session;
    }
    if (changed) {
      // Хранить пустые дни незачем — как и при обычной записи.
      await saveAll([
        for (final session in cleaned.values)
          if (session.entries.isNotEmpty) session,
      ]);
    }
    // Дни, опустевшие после вычистки (там были только демо-отметки),
    // из результата тоже уходят.
    cleaned.removeWhere(
      (_, session) => session.students.isEmpty && session.entries.isEmpty,
    );
    return cleaned;
  }

  Map<DateTime, AttendanceSession> _loadLegacy() {
    final raw = _preferences.getString(_legacyKey);
    if (raw == null || raw.isEmpty) return const {};
    final decoded = _decode(raw);
    if (decoded is! Map) return const {};
    try {
      final session = AttendanceSession.fromJson(
        Map<String, Object?>.from(decoded),
      );
      return {dateOnly(session.date): session};
    } on FormatException {
      return const {};
    }
  }

  Object? _decode(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> saveAll(List<AttendanceSession> sessions) =>
      _preferences.setString(
        _key,
        jsonEncode({
          'days': {
            for (final session in sessions)
              dateOnly(session.date).toIso8601String().substring(0, 10): session
                  .toJson(),
          },
        }),
      );
}
