// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/attendance_entry.dart';
import '../models/attendance_session.dart';
import '../models/attendance_status.dart';
import '../models/student.dart';
import 'attendance_store.dart';
import 'example_group.dart';

/// Состояние посещаемости и операции над ним.
///
/// Отметки хранятся в памяти и (если передан [AttendanceStore]) сразу
/// сохраняются локально. Облачная синхронизация подписывается на изменения
/// через [ChangeNotifier].
class AttendanceController extends ChangeNotifier {
  AttendanceController({
    required AttendanceSession session,
    AttendanceStore? store,
  }) : _session = session,
       _store = store;

  /// Сессия с примером группы — удобна для тестов и первого запуска.
  factory AttendanceController.inMemory() => AttendanceController(
    session: AttendanceSession.forToday(
      groupName: exampleGroupName,
      students: exampleStudents,
    ),
  );

  AttendanceSession _session;
  final AttendanceStore? _store;
  bool _loaded = false;

  AttendanceSession get session => _session;

  List<Student> get students => _session.students;

  Map<String, AttendanceEntry> get entries => _session.entries;

  AttendanceEntry? entryFor(String studentId) => _session.entries[studentId];

  /// Загружает сохранённую сессию. Если сохранён вчерашний день — отметки
  /// сбрасываются, а список группы остаётся.
  Future<void> load() async {
    final store = _store;
    if (store == null || _loaded) return;
    _loaded = true;
    try {
      final saved = await store.load();
      if (saved != null) {
        _session = saved.forToday();
        notifyListeners();
      }
    } catch (_) {
      // Повреждённое локальное хранилище не должно мешать работе приложения.
    }
  }

  /// Ставит отметку выбранному студенту.
  void mark(Student student, AttendanceStatus status, DateTime markedAt) {
    // Если приложение открыто через полночь — начинаем новый день.
    final current = _session.forToday();
    _session = current.withEntry(
      student,
      AttendanceEntry(status: status, markedAt: markedAt),
    );
    notifyListeners();
    _persist();
  }

  /// Снимает отметку студента (кнопка «Отменить отметку»).
  void clearMark(Student student) {
    final entries = {..._session.entries};
    if (entries.remove(student.id) == null) return;
    _session = _session.copyWith(entries: entries);
    notifyListeners();
    _persist();
  }

  /// Заменяет локальные отметки удалёнными (используется после загрузки
  /// из Google Таблицы).
  void mergeRemote(Iterable<AttendanceRecord> records) {
    final merged = _session.mergeRemote(records);
    if (identical(merged, _session)) return;
    _session = merged;
    notifyListeners();
    _persist();
  }

  /// Полностью заменяет сессию (например, после выбора другого дня).
  void replaceSession(AttendanceSession session) {
    _session = session;
    notifyListeners();
    _persist();
  }

  void _persist() {
    final store = _store;
    if (store == null) return;
    unawaited(store.save(_session).catchError((Object _) {}));
  }
}
