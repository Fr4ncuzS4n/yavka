// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/schedule_lesson.dart';
import 'schedule_store.dart';

/// Расписание группы: пары по дням недели.
///
/// Пары можно добавить вручную (списком) или вставить документом с
/// расписанием. Хранятся локально и переживают перезапуск приложения.
///
/// Расписание привязывается к почте аккаунта Google: у каждой почты
/// своё расписание ([switchAccount]), без входа — общее локальное.
class ScheduleController extends ChangeNotifier {
  ScheduleController({
    ScheduleStore? store,
    ScheduleStoreFactory? storeFactory,
    List<ScheduleLesson>? lessons,
  }) : _store = store,
       _storeFactory = storeFactory,
       _lessons = List<ScheduleLesson>.unmodifiable(lessons ?? const []);

  /// Пустое расписание — удобно для тестов и первого запуска.
  factory ScheduleController.inMemory() => ScheduleController();

  final ScheduleStoreFactory? _storeFactory;

  /// Хранилище текущего аккаунта. Меняется при переключении почты —
  /// поэтому не final.
  ScheduleStore? _store;
  List<ScheduleLesson> _lessons;
  bool _loaded = false;

  /// Почта аккаунта, к расписанию которого привязан контроллер;
  /// `null` — локальное расписание без входа.
  String? get accountEmail => _accountEmail;
  String? _accountEmail;

  /// Загружаемое сейчас расписание — чтобы параллельные переключения
  /// на ту же почту не путали данные.
  Future<void>? _switching;

  /// Все пары расписания (по всем дням).
  List<ScheduleLesson> get lessons => _lessons;

  /// Пары конкретного дня недели, отсортированные по времени начала.
  List<ScheduleLesson> lessonsFor(int weekday) {
    final result = _lessons.where((lesson) => lesson.weekday == weekday)
        .toList()
      ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
    return List.unmodifiable(result);
  }

  /// Сколько пар показывать в дне без расписания.
  ///
  /// Порядок пар — временное расписание: обычно в день 3–4 пары. После
  /// подключения журнала количество подстраивается под число колонок
  /// пар у одного дня таблицы (см. [JournalSyncService]).
  int get temporaryPairCount => _temporaryPairCount;
  int _temporaryPairCount = 4;

  set temporaryPairCount(int value) {
    final clamped = value.clamp(1, 12);
    if (clamped == _temporaryPairCount) return;
    _temporaryPairCount = clamped;
    notifyListeners();
  }

  /// Пары дня для отметок: настоящие, а если расписания нет вовсе —
  /// временный порядок пар («Пара 1», «Пара 2»…).
  ///
  /// Названия совпадают с журнальными («Пара N»), поэтому отметки,
  /// загруженные из таблицы, попадают в те же пары. При частичном
  /// расписании (заполнены не все дни) временные пары не показываются:
  /// дни без пар отмечаются «весь день», как раньше.
  List<ScheduleLesson> effectiveLessonsFor(int weekday) {
    if (_lessons.isEmpty) return _temporaryLessons(weekday);
    return lessonsFor(weekday);
  }

  /// Временное расписание-порядок: пары [temporaryPairCount] штук.
  List<ScheduleLesson> _temporaryLessons(int weekday) {
    const slots = [
      (8 * 60 + 30, 10 * 60 + 5),
      (10 * 60 + 15, 11 * 60 + 50),
      (12 * 60 + 30, 14 * 60 + 5),
      (14 * 60 + 15, 15 * 60 + 50),
      (16 * 60, 17 * 60 + 35),
      (17 * 60 + 45, 19 * 60 + 20),
      (19 * 60 + 30, 21 * 60 + 5),
      (21 * 60 + 15, 22 * 60 + 50),
      (22 * 60 + 15, 23 * 60 + 50),
      (22 * 60 + 45, 23 * 60 + 59),
      (23 * 60, 23 * 60 + 59),
      (23 * 60 + 15, 23 * 60 + 59),
    ];
    return [
      for (var i = 1; i <= _temporaryPairCount; i++)
        ScheduleLesson(
          id: 'temp-pair-$i',
          weekday: weekday,
          startMinutes: slots[i - 1].$1,
          endMinutes: slots[i - 1].$2,
          subject: 'Пара $i',
        ),
    ];
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

  /// Стирает всё расписание.
  void clear() {
    if (_lessons.isEmpty) return;
    _lessons = const <ScheduleLesson>[];
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

  /// Переключает расписание на почту [email] аккаунта Google.
  ///
  /// Текущее расписание сохраняется под прежней почтой, затем
  /// загружается расписание новой: у каждой почты — своё. `null`
  /// возвращает локальное расписание (без входа). Повторный вызов с
  /// той же почтой ничего не меняет и дожидается прежней загрузки.
  Future<void> switchAccount(String? email) {
    final factory = _storeFactory;
    if (factory == null || email == _accountEmail) {
      return _switching ?? Future.value();
    }

    // Сохраняем под прежней почтой до подмены хранилища.
    _persist();
    _accountEmail = email;
    _store = factory.forAccount(email);
    final done = _loadCurrent();
    _switching = done;
    return done.whenComplete(() {
      if (_switching == done) _switching = null;
    });
  }

  /// Загружает расписание из текущего хранилища.
  Future<void> _loadCurrent() async {
    try {
      final saved = await _store?.load() ?? const <ScheduleLesson>[];
      _lessons = List<ScheduleLesson>.unmodifiable(saved);
      notifyListeners();
    } catch (_) {
      // Повреждённое хранилище не должно мешать работе приложения.
    }
  }

  void _persist() {
    final store = _store;
    if (store == null) return;
    unawaited(store.save(_lessons).catchError((Object _) {}));
  }
}
