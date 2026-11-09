import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/attendance_session.dart';

/// Локальное хранилище состояния посещаемости.
abstract interface class AttendanceStore {
  Future<AttendanceSession?> load();

  Future<void> save(AttendanceSession session);
}

/// Хранит сессию в памяти — используется в тестах и как запасной вариант.
class MemoryAttendanceStore implements AttendanceStore {
  AttendanceSession? _session;

  @override
  Future<AttendanceSession?> load() async => _session;

  @override
  Future<void> save(AttendanceSession session) async => _session = session;
}

/// Хранит сессию в SharedPreferences (Android, iOS, Linux, macOS, Windows, web).
class SharedPreferencesAttendanceStore implements AttendanceStore {
  SharedPreferencesAttendanceStore(this._preferences);

  static const _key = 'yavka.attendance.session.v1';

  final SharedPreferences _preferences;

  @override
  Future<AttendanceSession?> load() async {
    final raw = _preferences.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return AttendanceSession.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(AttendanceSession session) =>
      _preferences.setString(_key, jsonEncode(session.toJson()));
}
