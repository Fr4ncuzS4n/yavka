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

  final SharedPreferences _preferences;

  @override
  Future<Map<DateTime, AttendanceSession>> loadAll() async {
    final raw = _preferences.getString(_key);
    if (raw == null || raw.isEmpty) return _loadLegacy();

    final decoded = _decode(raw);
    final days = <DateTime, AttendanceSession>{};
    if (decoded is! Map) return days;
    for (final item in decoded.entries) {
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
    return days;
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
