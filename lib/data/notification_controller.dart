// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/schedule_lesson.dart';
import '../models/sync_notification.dart';
import 'notification_store.dart';

/// Максимум отложенных и полученных уведомлений, чтобы хранилище
/// не разрасталось.
const int kNotificationLimit = 200;

/// Уведомления о отметках на парах.
///
/// Отмеченные локально пары накапливаются в отложенных ([outbox]) и
/// отправляются в лист «Уведомления» Google Таблицы при следующей
/// синхронизации. Отметки других людей, прочитанные из таблицы, показываются
/// в центре уведомлений ([items]).
class NotificationController extends ChangeNotifier {
  NotificationController({NotificationStore? store}) : _store = store;

  final NotificationStore? _store;
  List<SyncNotification> _items = const [];
  List<PendingLessonMark> _outbox = const [];
  bool _loaded = false;

  /// Полученные уведомления (новые — сверху).
  List<SyncNotification> get items => _items;

  /// Отложенные уведомления, ждущие отправки в таблицу.
  List<PendingLessonMark> get outbox => _outbox;

  int get unreadCount =>
      _items.where((item) => !item.isRead).length;

  /// Загружает сохранённые уведомления.
  Future<void> load() async {
    final store = _store;
    if (store == null || _loaded) return;
    _loaded = true;
    try {
      final received = await store.loadReceived();
      final outbox = await store.loadOutbox();
      _items = received;
      _outbox = outbox;
      notifyListeners();
    } catch (_) {
      // Повреждённое хранилище не должно мешать работе приложения.
    }
  }

  /// Фиксирует локальную отметку студентов на паре: если уведомление об
  /// этой паре за день уже отложено — увеличивает счётчик, иначе добавляет
  /// новое. Отправится в таблицу при следующей синхронизации.
  void queueLessonMark({
    required String groupName,
    required ScheduleLesson? lesson,
    required DateTime date,
  }) {
    if (lesson == null) return;
    final marker = lesson.id.trim().isNotEmpty ? lesson.id : lesson.subject;
    final id = '${date.toIso8601String().substring(0, 10)}|$marker';
    final existing = _outbox.indexWhere((item) => item.id == id);
    final updated = [..._outbox];
    if (existing >= 0) {
      updated[existing] = updated[existing].copyWith(
        count: updated[existing].count + 1,
      );
    } else {
      updated.add(
        PendingLessonMark(
          id: id,
          date: date,
          groupName: groupName,
          lessonTitle: lesson.subject,
          lessonTime: lesson.startLabel,
        ),
      );
      if (updated.length > kNotificationLimit) {
        updated.removeRange(0, updated.length - kNotificationLimit);
      }
    }
    _outbox = updated;
    notifyListeners();
    _persistOutbox();
  }

  /// Забирает отложенные уведомления (например, для отправки в таблицу).
  List<PendingLessonMark> drainOutbox() {
    if (_outbox.isEmpty) return const [];
    final drained = _outbox;
    _outbox = const [];
    notifyListeners();
    _persistOutbox();
    return drained;
  }

  /// Возвращает уведомления в отложенные — если отправка не удалась.
  void restoreOutbox(List<PendingLessonMark> items) {
    if (items.isEmpty) return;
    final merged = [..._outbox];
    for (final item in items) {
      final index = merged.indexWhere((existing) => existing.id == item.id);
      if (index >= 0) {
        merged[index] = item;
      } else {
        merged.add(item);
      }
    }
    if (merged.length > kNotificationLimit) {
      merged.removeRange(0, merged.length - kNotificationLimit);
    }
    _outbox = merged;
    notifyListeners();
    _persistOutbox();
  }

  /// Добавляет уведомления, полученные из таблицы. Дубликаты (те же
  /// строки таблицы) пропускаются, новые — показываются как непрочитанные.
  void addRemote(List<SyncNotification> incoming) {
    if (incoming.isEmpty) return;
    final known = _items.map((item) => item.id).toSet();
    final fresh = [
      for (final item in incoming)
        if (!known.contains(item.id)) item,
    ];
    if (fresh.isEmpty) return;
    _items = [...fresh.reversed, ..._items];
    if (_items.length > kNotificationLimit) {
      _items = _items.sublist(0, kNotificationLimit);
    }
    notifyListeners();
    _persistReceived();
  }

  /// Отмечает уведомление прочитанным.
  void markRead(String id) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0 || _items[index].isRead) return;
    _items = [
      for (var i = 0; i < _items.length; i++)
        i == index ? _items[i].copyWith(isRead: true) : _items[i],
    ];
    notifyListeners();
    _persistReceived();
  }

  /// Отмечает все уведомления прочитанными.
  void markAllRead() {
    var changed = false;
    final updated = <SyncNotification>[];
    for (final item in _items) {
      if (item.isRead) {
        updated.add(item);
      } else {
        updated.add(item.copyWith(isRead: true));
        changed = true;
      }
    }
    if (!changed) return;
    _items = updated;
    notifyListeners();
    _persistReceived();
  }

  void _persistReceived() {
    final store = _store;
    if (store == null) return;
    unawaited(store.saveReceived(_items).catchError((Object _) {}));
  }

  void _persistOutbox() {
    final store = _store;
    if (store == null) return;
    unawaited(store.saveOutbox(_outbox).catchError((Object _) {}));
  }
}
