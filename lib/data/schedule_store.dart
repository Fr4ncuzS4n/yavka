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
///
/// Хранилище может быть привязано к почте пользователя: каждой почте —
/// свой ключ, расписания разных аккаунтов не смешиваются. Без почты
/// (нет входа) используется общий ключ — он же был единственным до
/// привязки, поэтому старые данные продолжат читаться.
class SharedPreferencesScheduleStore implements ScheduleStore {
  SharedPreferencesScheduleStore(this._preferences, {String? email})
    : _email = _normalize(email);

  static const _key = 'yavka.schedule.lessons.v1';

  final SharedPreferences _preferences;

  /// Почта аккаунта, к расписанию которого привязано хранилище.
  final String? _email;

  /// Ключ, под которым расписание лежит в SharedPreferences.
  String get storageKey {
    final email = _email;
    if (email == null || email.isEmpty) return _key;
    return '$_key.$email';
  }

  /// Приводит почту к ключу: без пробелов и в нижнем регистре.
  static String? _normalize(String? email) {
    final trimmed = email?.trim().toLowerCase() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  @override
  Future<List<ScheduleLesson>> load() async {
    final raw = _preferences.getString(storageKey);
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
  Future<void> save(List<ScheduleLesson> lessons) => _preferences.setString(
    storageKey,
    jsonEncode([for (final lesson in lessons) lesson.toJson()]),
  );
}

/// Фабрика хранилищ расписания по почтам пользователей.
abstract interface class ScheduleStoreFactory {
  /// Хранилище расписания конкретного аккаунта; `null` — расписание
  /// без входа (локальное).
  ScheduleStore forAccount(String? email);
}

/// Фабрика хранилищ в SharedPreferences.
class SharedPreferencesScheduleStoreFactory implements ScheduleStoreFactory {
  SharedPreferencesScheduleStoreFactory(this._preferences);

  final SharedPreferences _preferences;

  @override
  ScheduleStore forAccount(String? email) =>
      SharedPreferencesScheduleStore(_preferences, email: email);
}

/// Фабрика хранилищ в памяти — используется в тестах и как запасной
/// вариант: у каждой почты своё хранилище.
class MemoryScheduleStoreFactory implements ScheduleStoreFactory {
  final Map<String, MemoryScheduleStore> _stores = {};

  @override
  ScheduleStore forAccount(String? email) {
    final key = email?.trim().toLowerCase() ?? '';
    return _stores.putIfAbsent(key, () => MemoryScheduleStore());
  }
}
