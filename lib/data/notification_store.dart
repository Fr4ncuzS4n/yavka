import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/sync_notification.dart';

/// Локальное хранилище уведомлений: полученные из таблицы и отложенные
/// (отмеченные локально, но ещё не отправленные).
abstract interface class NotificationStore {
  Future<List<SyncNotification>> loadReceived();

  Future<void> saveReceived(List<SyncNotification> items);

  Future<List<PendingLessonMark>> loadOutbox();

  Future<void> saveOutbox(List<PendingLessonMark> items);
}

/// Всё в памяти — для тестов и как запасной вариант.
class MemoryNotificationStore implements NotificationStore {
  List<SyncNotification> _received = const [];
  List<PendingLessonMark> _outbox = const [];

  @override
  Future<List<SyncNotification>> loadReceived() async => _received;

  @override
  Future<void> saveReceived(List<SyncNotification> items) async =>
      _received = items;

  @override
  Future<List<PendingLessonMark>> loadOutbox() async => _outbox;

  @override
  Future<void> saveOutbox(List<PendingLessonMark> items) async =>
      _outbox = items;
}

/// Хранит уведомления в SharedPreferences.
class SharedPreferencesNotificationStore implements NotificationStore {
  SharedPreferencesNotificationStore(this._preferences);

  static const _receivedKey = 'yavka.notifications.received.v1';
  static const _outboxKey = 'yavka.notifications.outbox.v1';

  final SharedPreferences _preferences;

  @override
  Future<List<SyncNotification>> loadReceived() async {
    final raw = _preferences.getString(_receivedKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = _decodeList(raw);
    final items = <SyncNotification>[];
    for (final item in decoded) {
      try {
        items.add(SyncNotification.fromJson(item));
      } on FormatException {
        // Испорченное уведомление пропускаем.
      }
    }
    return items;
  }

  @override
  Future<void> saveReceived(List<SyncNotification> items) =>
      _preferences.setString(
        _receivedKey,
        jsonEncode([for (final item in items) item.toJson()]),
      );

  @override
  Future<List<PendingLessonMark>> loadOutbox() async {
    final raw = _preferences.getString(_outboxKey);
    if (raw == null || raw.isEmpty) return const [];
    final decoded = _decodeList(raw);
    final items = <PendingLessonMark>[];
    for (final item in decoded) {
      try {
        items.add(PendingLessonMark.fromJson(item));
      } on FormatException {
        // Испорченное отложенное уведомление пропускаем.
      }
    }
    return items;
  }

  @override
  Future<void> saveOutbox(List<PendingLessonMark> items) =>
      _preferences.setString(
        _outboxKey,
        jsonEncode([for (final item in items) item.toJson()]),
      );

  static List<Map<String, Object?>> _decodeList(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map) Map<String, Object?>.from(item),
      ];
    } on FormatException {
      return const [];
    }
  }
}
