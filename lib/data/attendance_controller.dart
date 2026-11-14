// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/attendance_entry.dart';
import '../models/attendance_session.dart';
import '../models/attendance_status.dart';
import '../models/student.dart';
import 'attendance_store.dart';

/// Состояние посещаемости и операции над ним.
///
/// Отметки хранятся по дням: контроллер держит сессию каждого дня, за
/// который отмечали, и умеет переключаться между днями ([selectDate]).
/// Отметки в выходные (суббота и воскресенье) запрещены — [mark] их
/// игнорирует. Локально сессии сохраняются через [AttendanceStore],
/// облако подписывается на изменения через [ChangeNotifier].
class AttendanceController extends ChangeNotifier {
  AttendanceController({
    required AttendanceSession session,
    AttendanceStore? store,
  }) : _days = {dateOnly(session.date): session},
       _selectedDate = dateOnly(session.date),
       _store = store;

  /// Пустой контроллер без списка группы — для тестов и первого запуска.
  ///
  /// Настоящий список группы приложение берёт из журнала Google Таблицы
  /// (колонка ФИО) при первой загрузке.
  factory AttendanceController.inMemory() => AttendanceController(
    session: AttendanceSession.forToday(groupName: '', students: const []),
  );

  final AttendanceStore? _store;
  Map<DateTime, AttendanceSession> _days;
  DateTime _selectedDate;
  bool _loaded = false;

  /// Сессия выбранного дня (см. [selectedDate]).
  AttendanceSession get session =>
      _days[_selectedDate] ?? _emptyDay(_selectedDate);

  /// День, к которому относятся отметки прямо сейчас.
  DateTime get selectedDate => _selectedDate;

  List<Student> get students => session.students;

  Map<String, AttendanceEntry> get entries => session.entries;

  AttendanceEntry? entryFor(String studentId) => session.entries[studentId];

  /// Отметка студента на конкретной паре из расписания.
  AttendanceEntry? entryInLesson(
    String studentId, {
    String? lessonKey,
    String? lessonTitle,
  }) => session.entryInLesson(
    studentId,
    lessonKey: lessonKey,
    lessonTitle: lessonTitle,
  );

  /// Сколько студентов отмечено на паре.
  int markedCountInLesson({String? lessonKey, String? lessonTitle}) => session
      .markedCountInLesson(lessonKey: lessonKey, lessonTitle: lessonTitle);

  /// Все дни, за которые есть сессии, по возрастанию даты.
  List<AttendanceSession> get sessions {
    final list = _days.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  /// Дни выбранного месяца, за которые есть отметки
  /// (для отправки в журнал Google Таблицы).
  List<AttendanceSession> sessionsInMonth(DateTime month) => [
    for (final day in sessions)
      if (day.date.year == month.year &&
          day.date.month == month.month &&
          day.entries.isNotEmpty)
        day,
  ];

  /// Загружает сохранённые дни. Сохранённые данные главнее стартовой
  /// сессии; выбранным днём остаётся день стартовой сессии.
  Future<void> load() async {
    final store = _store;
    if (store == null || _loaded) return;
    _loaded = true;
    try {
      final saved = await store.loadAll();
      if (saved.isEmpty) return;
      final days = Map.of(_days);
      days.addAll(saved);
      days.putIfAbsent(_selectedDate, () => _emptyDay(_selectedDate));
      _days = days;
      notifyListeners();
    } catch (_) {
      // Повреждённое локальное хранилище не должно мешать работе приложения.
    }
  }

  /// Переключает день отметок.
  ///
  /// Если сессии дня ещё нет — создаётся пустая с тем же списком группы,
  /// что и в последнем отмеченном дне.
  void selectDate(DateTime date) {
    final day = dateOnly(date);
    if (isSameDate(day, _selectedDate)) return;
    _selectedDate = day;
    if (!_days.containsKey(day)) {
      _days = {..._days, day: _emptyDay(day)};
    }
    notifyListeners();
  }

  /// Ставит отметку выбранному студенту в выбранный день.
  ///
  /// Без [lessonKey]/[lessonTitle] отметка относится ко всему дню;
  /// с ними — к конкретной паре из расписания.
  ///
  /// В выходные (суббота и воскресенье) отметки не ставятся.
  void mark(
    Student student,
    AttendanceStatus status,
    DateTime markedAt, {
    String? lessonKey,
    String? lessonTitle,
  }) {
    if (isWeekendDate(_selectedDate)) return;

    final current = _days[_selectedDate] ?? _emptyDay(_selectedDate);
    _days = {
      ..._days,
      _selectedDate: current.withEntry(
        student,
        AttendanceEntry(
          status: status,
          markedAt: markedAt,
          lessonKey: lessonKey,
          lessonTitle: lessonTitle,
        ),
      ),
    };
    notifyListeners();
    _persist();
  }

  /// Снимает отметку студента (кнопка «Отменить отметку»).
  ///
  /// Без [lessonKey]/[lessonTitle] снимается отметка на весь день,
  /// с ними — отметка на конкретной паре.
  void clearMark(Student student, {String? lessonKey, String? lessonTitle}) {
    final current = _days[_selectedDate];
    if (current == null) return;
    final entries = {...current.entries};
    if (entries.remove(
          AttendanceSession.entryKey(
            studentId: student.id,
            lessonKey: lessonKey,
            lessonTitle: lessonTitle,
          ),
        ) ==
        null) {
      return;
    }
    _days = {..._days, _selectedDate: current.copyWith(entries: entries)};
    notifyListeners();
    _persist();
  }

  /// Объединяет удалённые отметки с локальными (удалённые важнее).
  ///
  /// Отметки группируются по дате: каждая попадает в сессию своего дня.
  void mergeRemote(Iterable<AttendanceRecord> records) {
    final byDay = <DateTime, List<AttendanceRecord>>{};
    for (final record in records) {
      byDay.putIfAbsent(dateOnly(record.date), () => []).add(record);
    }
    if (byDay.isEmpty) return;

    var days = _days;
    var changed = false;
    byDay.forEach((day, dayRecords) {
      final current = days[day] ?? _emptyDay(day);
      final merged = current.mergeRemote(dayRecords);
      if (identical(merged, current)) return;
      days = {...days, day: merged};
      changed = true;
    });
    if (!changed) return;
    _days = days;
    notifyListeners();
    _persist();
  }

  /// Синхронизирует список группы со списком из таблицы: новых студентов
  /// добавляем во все дни, знакомых обновляем.
  void mergeRoster(Iterable<Student> roster) {
    final incoming = roster.toList();
    if (incoming.isEmpty) return;

    var days = _days;
    var changed = false;
    for (final entry in _days.entries) {
      final merged = entry.value.withRoster(incoming);
      if (identical(merged, entry.value)) continue;
      days = {...days, entry.key: merged};
      changed = true;
    }
    if (!changed) return;
    _days = days;
    notifyListeners();
    _persist();
  }

  /// Выравнивает список группы по журналу во всех сессиях: студенты,
  /// которых в [roster] нет, удаляются из списка вместе со своими
  /// отметками (журнал — источник правды о списке). Пустой [roster]
  /// список не трогает: пустой журнал — не повод стирать группу.
  void alignRoster(Iterable<Student> roster) {
    final incoming = roster.toList();
    if (incoming.isEmpty) return;

    var days = _days;
    var changed = false;
    for (final entry in _days.entries) {
      final aligned = entry.value.alignedToRoster(incoming);
      if (identical(aligned, entry.value)) continue;
      days = {...days, entry.key: aligned};
      changed = true;
    }
    if (!changed) return;
    _days = days;
    notifyListeners();
    _persist();
  }

  /// Полностью заменяет сессию дня (например, после загрузки из таблицы).
  void replaceSession(AttendanceSession session) {
    final day = dateOnly(session.date);
    if (identical(_days[day], session)) return;
    _days = {..._days, day: session};
    notifyListeners();
    _persist();
  }

  /// Пустая сессия дня с составом группы из последнего отмеченного дня.
  AttendanceSession _emptyDay(DateTime day) => AttendanceSession(
    groupName: _groupName,
    date: day,
    students: _seedStudents(),
  );

  String get _groupName {
    final current = _days[_selectedDate];
    if (current != null) return current.groupName;
    for (final day in _days.values) {
      return day.groupName;
    }
    return '';
  }

  List<Student> _seedStudents() {
    final current = _days[_selectedDate];
    if (current != null && current.students.isNotEmpty) return current.students;

    AttendanceSession? latest;
    for (final day in _days.values) {
      if (day.students.isEmpty) continue;
      if (latest == null || day.date.isAfter(latest.date)) latest = day;
    }
    return latest?.students ?? const [];
  }

  void _persist() {
    final store = _store;
    if (store == null) return;
    // Хранить пустые дни незачем — только дни, за которые есть отметки.
    final days = [
      for (final session in _days.values)
        if (session.entries.isNotEmpty) session,
    ];
    unawaited(store.saveAll(days).catchError((Object _) {}));
  }
}
