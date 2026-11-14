// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/schedule_lesson.dart';
import 'schedule_store.dart';

/// Расписание группы: пары по дням недели.
///
/// Пары можно добавить вручную (списком) или вставить документом с
/// расписанием. Хранятся локально и переживают перезапуск приложения.
class ScheduleController extends ChangeNotifier {
  ScheduleController({ScheduleStore? store, List<ScheduleLesson>? lessons})
    : _store = store,
      _lessons = List<ScheduleLesson>.unmodifiable(lessons ?? const []);

  /// Пустое расписание — удобно для тестов и первого запуска.
  factory ScheduleController.inMemory() => ScheduleController();

  final ScheduleStore? _store;
  List<ScheduleLesson> _lessons;
  bool _loaded = false;

  /// Все пары расписания (по всем дням).
  List<ScheduleLesson> get lessons => _lessons;

  /// Пары конкретного дня недели, отсортированные по времени начала.
  List<ScheduleLesson> lessonsFor(int weekday) {
    final result = _lessons.where((lesson) => lesson.weekday == weekday)
        .toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return List.unmodifiable(result);
  }

  ScheduleLesson? byId(String id) {
    for (final lesson in _lessons) {
      if (lesson.id == id) return lesson;
    }
    return null;
  }

  /// Загружает сохранённое расписание.
  Future<void> load() async {
    final store = _store;
    if (store == null || _loaded) return;
    _loaded = true;
    try {
      final saved = await store.load();
      if (saved.isNotEmpty) {
        _lessons = List<ScheduleLesson>.unmodifiable(saved);
        notifyListeners();
      }
    } catch (_) {
      // Повреждённое хранилище не должно мешать работе приложения.
    }
  }

  /// Добавляет пару в расписание.
  void add(ScheduleLesson lesson) {
    _lessons = List<ScheduleLesson>.unmodifiable([..._lessons, lesson]);
    notifyListeners();
    _persist();
  }

  /// Обновляет существующую пару.
  void update(ScheduleLesson lesson) {
    final updated = <ScheduleLesson>[
      for (final item in _lessons) if (item.id == lesson.id) lesson else item,
    ];
    _lessons = List<ScheduleLesson>.unmodifiable(updated);
    notifyListeners();
    _persist();
  }

  /// Удаляет пару по идентификатору.
  void remove(String id) {
    _lessons = List<ScheduleLesson>.unmodifiable([
      for (final item in _lessons)
        if (item.id != id) item,
    ]);
    notifyListeners();
    _persist();
  }

  /// Заменяет пары перечисленных дней новыми (используется при вставке
  /// документа с расписанием).
  void replaceWeekdays(
    Iterable<ScheduleLesson> lessons, {
    required Iterable<int> weekdays,
  }) {
    final days = weekdays.toSet();
    final kept = <ScheduleLesson>[
      for (final item in _lessons)
        if (!days.contains(item.weekday)) item,
    ];
    _lessons = List<ScheduleLesson>.unmodifiable([...kept, ...lessons]);
    notifyListeners();
    _persist();
  }

  void _persist() {
    final store = _store;
    if (store == null) return;
    unawaited(store.save(_lessons).catchError((Object _) {}));
  }
}
