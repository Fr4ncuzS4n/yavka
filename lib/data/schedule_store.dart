import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/schedule_lesson.dart';

/// Локальное хранилище расписания.
abstract interface class ScheduleStore {
  Future<List<ScheduleLesson>> load();

  Future<void> save(List<ScheduleLesson> lessons);
}

/// Расписание в памяти — используется в тестах и как запасной вариант.
class MemoryScheduleStore implements ScheduleStore {
  MemoryScheduleStore([this._lessons = const []]);

  List<ScheduleLesson> _lessons;

  @override
  Future<List<ScheduleLesson>> load() async => _lessons;

  @override
  Future<void> save(List<ScheduleLesson> lessons) async => _lessons = lessons;
}

/// Расписание в SharedPreferences (все платформы).
class SharedPreferencesScheduleStore implements ScheduleStore {
  SharedPreferencesScheduleStore(this._preferences);

  static const _key = 'yavka.schedule.lessons.v1';

  final SharedPreferences _preferences;

  @override
  Future<List<ScheduleLesson>> load() async {
    final raw = _preferences.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final lessons = <ScheduleLesson>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          lessons.add(ScheduleLesson.fromJson(Map<String, Object?>.from(item)));
        } on FormatException {
          // Испорченную пару пропускаем, остальные сохраняем.
        }
      }
      return lessons;
    } on FormatException {
      return const [];
    }
  }

  @override
  Future<void> save(List<ScheduleLesson> lessons) =>
      _preferences.setString(
        _key,
        jsonEncode([for (final lesson in lessons) lesson.toJson()]),
      );
}
