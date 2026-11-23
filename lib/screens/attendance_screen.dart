import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/attendance_controller.dart';
import '../data/catalog_controller.dart';
import '../data/notification_controller.dart';
import '../data/schedule_controller.dart';
import '../data/ui_settings.dart';
import '../models/attendance_entry.dart';
import '../models/attendance_session.dart';
import '../models/attendance_status.dart';
import '../models/schedule_lesson.dart';
import '../models/student.dart';
import '../services/cloud/cloud_sync_controller.dart';
import '../services/update/update_check.dart';
import '../theme/app_theme.dart';
import '../theme/status_style.dart';
import '../util/desktop_layout.dart';
import 'cloud_sync_screen.dart';
import 'notifications_screen.dart';

/// Ключ списка группы (используется в тестах).
const kStudentListKey = Key('student-list');

const _kRowRadius = 16.0;
const _kButtonRadius = 14.0;
const _kGap = 12.0;
const _kPanelWidth = 320.0;

/// Ключ панели кнопок отметки на десктопе (используется в тестах).
const kMarkingPanelKey = Key('marking-panel');

/// Экран отметки посещаемости группы.
///
/// Староста (или куратор) выбирает студента в списке и отмечает его
/// одной из 4 кнопок: «Пришёл», «Непришёл», «Опоздал», «По уважительной».
/// «Непришёл» подтверждается вторым нажатием. «Опоздал» ставится тоже
/// в два клика: первый — пустой «опоздал» без времени, второй — ставит
/// время (оно уходит в журнал). У «Пришёл» и «Непришёл» времени нет.
///
/// Над списком выбираются день и пара: отметки пишутся за выбранный день
/// (по умолчанию — сегодня, задним числом тоже можно) и, если выбрана
/// пара, — на конкретную пару из расписания. В выходные (суббота и
/// воскресенье) отметки недоступны.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({
    super.key,
    this.attendance,
    this.cloud,
    this.uiSettings,
    this.schedule,
    this.lesson,
    this.notifications,
    this.catalog,
    this.updates,
  });

  /// Состояние посещаемости. Если не передано — создаётся пример группы
  /// (удобно для тестов и превью).
  final AttendanceController? attendance;

  /// Облачная синхронизация. Если `null`, кнопка Google Диска не показывается.
  final CloudSyncController? cloud;

  /// Выборный дизайн («Настройки → Дизайн»). Если `null`, кнопка
  /// с шестерёнкой скрывается.
  final UiSettingsController? uiSettings;

  /// Расписание группы: источник списка пар для выбранного дня.
  final ScheduleController? schedule;

  /// Пара из расписания, выбранная при открытии экрана. Пару можно
  /// сменить на экране — выбор дня и пары всегда доступен.
  final ScheduleLesson? lesson;

  /// Уведомления о отметках других пользователей таблицы.
  final NotificationController? notifications;

  /// Локальная база: преподаватели, предметы, кабинеты. Если `null`,
  /// в настройках не будет пункта «База данных».
  final CatalogController? catalog;

  /// Проверка обновлений с GitHub Releases. Если `null`, баннер
  /// свежей версии в настройках не показывается.
  final UpdateController? updates;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late final AttendanceController _attendance =
      widget.attendance ?? AttendanceController.inMemory();
  String? _selectedStudentId;
  bool _absentArmed = false;

  /// Множественный выбор: отметка ставится сразу нескольким студентам.
  bool _multiSelect = false;
  final Set<String> _selectedIds = <String>{};

  /// День, за который ставятся отметки (по умолчанию — сегодня).
  late DateTime _day = dateOnly(_attendance.selectedDate);

  /// Выбранная пара (null — отметки на весь день).
  String? _lessonId;

  @override
  void initState() {
    super.initState();
    _lessonId = widget.lesson?.id;
    _selectedStudentId = _attendance.students.isEmpty
        ? null
        : _attendance.students.first.id;
    if (_sequential) {
      final unmarked = _firstUnmarked();
      if (unmarked != null) _selectedStudentId = unmarked.id;
    }
    _attendance.addListener(_onAttendanceChanged);
    widget.schedule?.addListener(_onScheduleChanged);
    widget.uiSettings?.addListener(_onUiSettingsChanged);
  }

  @override
  void dispose() {
    _attendance.removeListener(_onAttendanceChanged);
    widget.schedule?.removeListener(_onScheduleChanged);
    widget.uiSettings?.removeListener(_onUiSettingsChanged);
    super.dispose();
  }

  /// Поочерёдная отметка включена в настройках.
  bool get _sequential => widget.uiSettings?.sequentialMarking ?? false;

  void _onUiSettingsChanged() {
    if (!mounted) return;
    final wasSequential = _sequential;
    setState(() {});
    if (!wasSequential && _sequential) {
      // Режим только что включили: сразу подсвечиваем первого
      // неотмеченного студента.
      _snapToFirstUnmarked();
    }
  }

  void _onAttendanceChanged() {
    if (!mounted) return;
    // День могли переключить с другого экрана (например, отметка пары
    // из расписания) — синхронизируемся с контроллером.
    if (!isSameDate(_day, _attendance.selectedDate)) {
      setState(() {
        _day = dateOnly(_attendance.selectedDate);
        _absentArmed = false;
        if (_lessonId != null &&
            !_dayLessons.any((lesson) => lesson.id == _lessonId)) {
          _lessonId = null;
        }
      });
      _snapToFirstUnmarked();
      return;
    }
    setState(() {});
  }

  void _onScheduleChanged() {
    if (mounted) setState(() {});
  }

  Student? get _selectedStudent {
    for (final student in _attendance.students) {
      if (student.id == _selectedStudentId) return student;
    }
    return null;
  }

  /// Первый неотмеченный студент в текущем scope (день или пара),
  /// либо `null`, если отмечены все.
  Student? _firstUnmarked() {
    for (final student in _attendance.students) {
      if (_entryFor(student) == null) return student;
    }
    return null;
  }

  /// В режиме поочерёдной отметки подсвечивает первого неотмеченного
  /// студента. Вызывается при включении режима и при смене дня или пары.
  void _snapToFirstUnmarked() {
    if (!_sequential) return;
    final unmarked = _firstUnmarked();
    if (unmarked == null || unmarked.id == _selectedStudentId) return;
    setState(() {
      _selectedStudentId = unmarked.id;
      _absentArmed = false;
    });
  }

  /// В режиме поочерёдной отметки подсвечивает следующего
  /// неотмеченного студента после [from] (по кругу по списку группы).
  ///
  /// Если все отмечены — выделение остаётся на месте. Возвращает
  /// `true`, если переход состоялся.
  bool _advanceSequential(Student from) {
    final students = _attendance.students;
    if (!_sequential || students.isEmpty) return false;
    final startIndex = students.indexWhere((student) => student.id == from.id);
    for (
      var step = 1;
      step <= students.length;
      step++
    ) {
      final candidate = students[(startIndex + step) % students.length];
      if (_entryFor(candidate) == null) {
        _selectedStudentId = candidate.id;
        return true;
      }
    }
    return false;
  }

  /// Студенты, к которым применится отметка (или её отмена).
  List<Student> get _targets {
    if (_multiSelect) {
      return [
        for (final student in _attendance.students)
          if (_selectedIds.contains(student.id)) student,
      ];
    }
    final single = _selectedStudent;
    return single == null ? const <Student>[] : <Student>[single];
  }

  bool get _canMark =>
      !_isWeekend &&
      (_multiSelect ? _selectedIds.isNotEmpty : _selectedStudent != null);

  /// Выбранный день — выходной: отметки недоступны.
  bool get _isWeekend => isWeekendDate(_day);

  bool get _anyTargetMarked =>
      _targets.any((student) => _entryFor(student) != null);

  void _select(Student student) {
    if (_multiSelect) {
      setState(() {
        _absentArmed = false;
        if (!_selectedIds.remove(student.id)) {
          _selectedIds.add(student.id);
        }
        _selectedStudentId = student.id;
      });
      return;
    }
    if (student.id == _selectedStudentId) return;
    setState(() {
      _selectedStudentId = student.id;
      _absentArmed = false;
    });
  }

  void _toggleMultiSelect() {
    setState(() {
      _absentArmed = false;
      if (_multiSelect) {
        // Выходим из режима: одиночным остаётся первый из выбранных.
        _selectedStudentId = _selectedIds.isNotEmpty
            ? _selectedIds.first
            : _selectedStudentId;
        _selectedIds.clear();
        _multiSelect = false;
      } else {
        _multiSelect = true;
        _selectedIds.clear();
        final single = _selectedStudentId;
        if (single != null) _selectedIds.add(single);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _absentArmed = false;
      _selectedIds.addAll(_attendance.students.map((s) => s.id));
    });
  }

  void _clearSelection() {
    setState(() {
      _absentArmed = false;
      _selectedIds.clear();
    });
  }

  // -- Выбор дня и пары ------------------------------------------------------

  /// Пары расписания на выбранный день.
  List<ScheduleLesson> get _dayLessons =>
      widget.schedule?.effectiveLessonsFor(_day.weekday) ?? const [];

  /// Выбранная пара (null — отметки на весь день).
  ScheduleLesson? get _selectedLesson {
    final id = _lessonId;
    if (id == null) return null;
    for (final lesson in _dayLessons) {
      if (lesson.id == id) return lesson;
    }
    final fixed = widget.lesson;
    if (fixed != null && fixed.id == id) return fixed;
    return null;
  }

  /// Чипы выбора: «Весь день» и пары дня.
  List<Widget> _lessonChips() => [
    ChoiceChip(
      key: const Key('whole-day-chip'),
      label: const Text('Весь день'),
      selected: _lessonId == null,
      onSelected: (_) => _selectLesson(null),
    ),
    for (final lesson in _dayLessons)
      ChoiceChip(
        key: ValueKey('lesson-chip-${lesson.id}'),
        label: Text('${lesson.startLabel} · ${lesson.subject}'),
        selected: _lessonId == lesson.id,
        onSelected: (_) => _selectLesson(lesson.id),
      ),
  ];

  /// На Android пары идут одной строкой (Row со скроллом), на web —
  /// переноской в несколько строк (Wrap). На десктопе чипы стоят в колонку
  /// по одному: левая панель узкая, Wrap рвал названия пар на несколько строк.
  bool get _useRowForLessons {
    if (kIsWeb || isDesktopLayout()) return false;
    return defaultTargetPlatform == TargetPlatform.android;
  }

  /// На Android студента можно отметить смахиванием строки списка:
  /// влево — «Пришёл», вправо — «Опоздал». Web и десктоп свайпов не
  /// используют: там быстрее кнопками и мышью.
  bool get _useSwipeMarking {
    if (kIsWeb || isDesktopLayout()) return false;
    return defaultTargetPlatform == TargetPlatform.android;
  }

  /// Отметка смахиванием относится к тому студенту, чью строку смахнули,
  /// а не к текущему выбору: так можно отмечать подряд, не нажимая на
  /// каждую строку. Поочерёдная отметка при этом продолжает работать —
  /// [_mark] подсвечивает следующего неотмеченного.
  void _swipeMark(Student student, AttendanceStatus status) {
    if (_isWeekend || _multiSelect) return;
    if (_selectedStudentId != student.id) _select(student);
    _mark(status);
  }

  /// Самая ранняя дата, за которую можно отметить (год назад).
  DateTime get _minDay =>
      dateOnly(DateTime.now()).subtract(const Duration(days: 365));

  /// Есть ли будний день раньше выбранного (в пределах года).
  bool get _canGoPrev => _day.isAfter(_minDay);

  /// Есть ли будний день позже выбранного, но не в будущем.
  bool get _canGoNext {
    var day = _day.add(const Duration(days: 1));
    while (isWeekendDate(day)) {
      day = day.add(const Duration(days: 1));
    }
    return !day.isAfter(dateOnly(DateTime.now()));
  }

  /// Выбирает день; если выбранная пара не читается в новом дне —
  /// сбрасывает её на «весь день».
  void _setDay(DateTime day) {
    final normalized = dateOnly(day);
    if (isSameDate(normalized, _day)) return;
    setState(() {
      _day = normalized;
      _absentArmed = false;
      if (_lessonId != null &&
          !_dayLessons.any((lesson) => lesson.id == _lessonId)) {
        _lessonId = null;
      }
    });
    _attendance.selectDate(normalized);
    _snapToFirstUnmarked();
  }

  /// Сдвигает день вперёд или назад, перепрыгивая выходные.
  void _shiftDay(int direction) {
    var day = _day.add(Duration(days: direction));
    while (isWeekendDate(day)) {
      day = day.add(Duration(days: direction));
    }
    if (day.isAfter(dateOnly(DateTime.now()))) return;
    if (day.isBefore(_minDay)) return;
    _setDay(day);
  }

  void _selectLesson(String? lessonId) {
    if (_lessonId == lessonId) return;
    setState(() {
      _lessonId = lessonId;
      _absentArmed = false;
    });
    _snapToFirstUnmarked();
  }

  /// Диалог выбора даты: выходные и будущие дни не выбрать.
  Future<void> _pickDay() async {
    var initial = _day;
    while (isWeekendDate(initial)) {
      initial = initial.subtract(const Duration(days: 1));
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _minDay,
      lastDate: dateOnly(DateTime.now()),
      selectableDayPredicate: (date) => !isWeekendDate(date),
    );
    if (picked == null) return;
    _setDay(picked);
  }

  void _mark(AttendanceStatus status, {bool withTime = true}) {
    final targets = _targets;
    if (targets.isEmpty) return;
    // Дата отметки — выбранный день, время — момент отметки.
    // У «пустого опоздал» времени нет: ставится повторным кликом.
    final now = DateTime.now();
    final markedAt = withTime
        ? DateTime(_day.year, _day.month, _day.day, now.hour, now.minute)
        : DateTime(_day.year, _day.month, _day.day);
    final lesson = _selectedLesson;
    for (final student in targets) {
      _attendance.mark(
        student,
        status,
        markedAt,
        lessonKey: lesson?.id,
        lessonTitle: lesson?.subject,
      );
    }
    _queueLessonNotification();
    setState(() {
      _absentArmed = false;
      // Поочерёдная отметка: одиночная отметка подсвечивает следующего
      // неотмеченного. Множественный выбор не продвигает.
      if (!_multiSelect && targets.length == 1) {
        _advanceSequential(targets.single);
      }
    });
  }

  Future<void> _markAbsent() async {
    if (!_canMark || !mounted) return;

    // Первое нажатие — запоминаем намерение, второе — подтверждаем.
    if (!_absentArmed) {
      setState(() => _absentArmed = true);
      return;
    }

    // Времени у «не пришёл» нет: в журнал идёт только красная ячейка
    // с буквой «Н». Важен сам факт отсутствия.
    _mark(AttendanceStatus.absent);
  }

  /// «Опоздал» ставится в два клика.
  ///
  /// Первый клик по студенту без опоздания — пустой «опоздал» без
  /// времени. Повторный клик (когда у всех выбранных уже пустой
  /// «опоздал») ставит время отметки. Если опоздание с временем уже
  /// стоит — время обновляется на текущее, отметка не теряется.
  void _markLate() {
    final targets = _targets;
    if (targets.isEmpty) return;
    final allLate = targets.every((student) {
      final entry = _entryFor(student);
      return entry != null && entry.status == AttendanceStatus.late;
    });
    _mark(AttendanceStatus.late, withTime: allLate);
  }

  /// Отмена отметки у всех выбранных студентов.
  void _clearMarks() {
    final targets = _targets;
    if (targets.isEmpty) return;
    final lesson = _selectedLesson;
    for (final student in targets) {
      _attendance.clearMark(
        student,
        lessonKey: lesson?.id,
        lessonTitle: lesson?.subject,
      );
    }
    setState(() => _absentArmed = false);
  }

  /// Отмеченная пара попадает в локальные уведомления — колокольчик
  /// покажет её на этом устройстве.
  void _queueLessonNotification() {
    final lesson = _selectedLesson;
    final notifications = widget.notifications;
    if (lesson == null || notifications == null) return;
    notifications.queueLessonMark(
      groupName: _attendance.session.groupName,
      lesson: lesson,
      date: _day,
    );
  }

  /// Отметка студента с учётом режима: на паре или на весь день.
  ///
  /// Во вкладке «Весь день», если все пары дня у студента заполнены одним
  /// статусом («Пришёл», «По уважительной», «Не пришёл»), дневной
  /// считается эта отметка — см. [AttendanceSession.wholeDayEntryFor].
  AttendanceEntry? _entryFor(Student student) {
    final lesson = _selectedLesson;
    if (lesson == null) {
      return _attendance.session.wholeDayEntryFor(student.id, _dayLessons);
    }
    return _attendance.entryInLesson(
      student.id,
      lessonKey: lesson.id,
      lessonTitle: lesson.subject,
    );
  }

  /// Сколько студентов отмечено в текущем режиме: на паре — отметки
  /// этой пары, «весь день» — разные студенты с любой отметкой дня.
  int get _markedCount {
    final lesson = _selectedLesson;
    if (lesson == null) return _attendance.session.markedCountForDay;
    return _attendance.session.markedCountInLesson(
      lessonKey: lesson.id,
      lessonTitle: lesson.subject,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _buildTitle(context),
        actions: [
          IconButton(
            tooltip: _multiSelect
                ? 'Выйти из множественного выбора'
                : 'Множественный выбор',
            icon: Icon(
              _multiSelect ? Icons.close : Icons.library_add_check_outlined,
            ),
            onPressed: _toggleMultiSelect,
          ),
          if (widget.notifications != null)
            NotificationBell(notifications: widget.notifications!),
          if (widget.cloud != null) _buildCloudAction(context),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: isDesktopLayout()
            ? _buildDesktopBody()
            : Column(
                children: [
                  _buildDayLessonBar(),
                  Expanded(child: _buildList()),
                  _buildPanel(),
                ],
              ),
      ),
    );
  }

  /// Полоса выбора дня и пары: стрелки и календарь, чипы «Весь день»
  /// и пар расписания, предупреждение о выходном.
  Widget _buildDayLessonBar() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final today = dateOnly(DateTime.now());

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    key: const Key('day-prev'),
                    tooltip: 'Предыдущий учебный день',
                    onPressed: _canGoPrev ? () => _shiftDay(-1) : null,
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: InkWell(
                      key: const Key('day-label'),
                      onTap: _pickDay,
                      borderRadius: BorderRadius.circular(_kRowRadius),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                _formatDate(_day),
                                style: theme.textTheme.titleMedium,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              Icons.calendar_month_outlined,
                              size: 18,
                              color: scheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (!isSameDate(_day, today))
                    TextButton(
                      onPressed: () => _setDay(today),
                      child: const Text('Сегодня'),
                    ),
                  IconButton(
                    key: const Key('day-next'),
                    tooltip: 'Следующий учебный день',
                    onPressed: _canGoNext ? () => _shiftDay(1) : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
              if (_dayLessons.isNotEmpty) ...[
                const SizedBox(height: 4),
                // На десктопе — по одной кнопке на строку: в узкой левой
                // панели названия пар не должны переноситься и слипаться.
                // На Android — строка со скроллом, на web — Wrap.
                if (isDesktopLayout())
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final chip in _lessonChips())
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: chip,
                        ),
                    ],
                  )
                else if (_useRowForLessons)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(spacing: 8, children: _lessonChips()),
                  )
                else
                  Wrap(spacing: 8, runSpacing: 8, children: _lessonChips()),
              ],
              if (_isWeekend) ...[
                const SizedBox(height: 8),
                const _WeekendBanner(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Десктопная раскладка (Windows/Linux/macOS):
  /// слева — панель кнопок отметки, справа — список группы.
  Widget _buildDesktopBody() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLight = scheme.brightness == Brightness.light;
    final canMark = _canMark;
    final anyMarked = _anyTargetMarked;
    final single = _multiSelect ? null : _selectedStudent;

    final headerText = _multiSelect
        ? (_selectedIds.isEmpty
              ? 'Выберите студентов'
              : 'Выбрано: ${_selectedIds.length}')
        : (single == null
              ? 'Выберите студента'
              : 'Отметить: ${single.fullName}');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Левая колонка — выбор дня и пары, заголовок, режимы и 4 кнопки.
        Container(
          key: kMarkingPanelKey,
          width: _kPanelWidth,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(
                color: isLight ? AppPalette.line : AppPalette.lineDark,
              ),
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildDayLessonBar(),
                const SizedBox(height: 8),
                Text(
                  headerText,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: canMark ? null : scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (anyMarked) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _clearMarks,
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('Отменить отметку'),
                    ),
                  ),
                ],
                if (_multiSelect) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: TextButton.icon(
                          onPressed: _selectAll,
                          icon: const Icon(Icons.select_all, size: 18),
                          label: const Text('Выбрать всех'),
                        ),
                      ),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: _selectedIds.isEmpty
                              ? null
                              : _clearSelection,
                          icon: const Icon(Icons.close, size: 18),
                          label: const Text('Снять выбор'),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_absentArmed) ...[
                  const SizedBox(height: 8),
                  const _ArmedHint(),
                ],
                const SizedBox(height: 12),
                for (final (index, status)
                    in AttendanceStatus.values.indexed) ...[
                  if (index > 0) const SizedBox(height: _kGap),
                  _StatusButton(
                    status: status,
                    enabled: canMark,
                    armed: status == AttendanceStatus.absent && _absentArmed,
                    onTap: status == AttendanceStatus.absent
                        ? _markAbsent
                        : status == AttendanceStatus.late
                        ? _markLate
                        : () => _mark(status),
                  ),
                ],
              ],
            ),
          ),
        ),
        // Правая колонка — список студентов.
        Expanded(child: _buildList()),
      ],
    );
  }

  Widget _buildCloudAction(BuildContext context) {
    final cloud = widget.cloud!;
    return ListenableBuilder(
      listenable: cloud,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        if (cloud.isBusy) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final IconData icon;
        final String tooltip;
        if (!cloud.isConfigured) {
          icon = Icons.cloud_off_outlined;
          tooltip = 'Подключить Google Диск';
        } else if (cloud.error != null) {
          icon = Icons.cloud_off_rounded;
          tooltip = 'Ошибка синхронизации';
        } else if (cloud.hasPendingChanges) {
          icon = Icons.cloud_upload_outlined;
          tooltip = 'Есть несохранённые отметки';
        } else {
          icon = Icons.cloud_done_outlined;
          tooltip = 'Google Диск подключён';
        }

        return IconButton(
          tooltip: tooltip,
          onPressed: () => _openCloud(context),
          icon: Icon(icon, color: cloud.error != null ? scheme.error : null),
        );
      },
    );
  }

  void _openCloud(BuildContext context) {
    final cloud = widget.cloud;
    if (cloud == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => CloudSyncScreen(cloud: cloud)),
    );
  }

  Widget _buildTitle(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lesson = _selectedLesson;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(lesson == null ? 'Явка' : 'Пара «${lesson.subject}»'),
        const SizedBox(height: 2),
        Text(
          lesson == null
              ? _formatDate(_day)
              : _lessonSubtitle(lesson),
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  /// Подзаголовок шапки для пары: группа указывается, только если она
  /// известна (до настройки журнала имени группы нет).
  String _lessonSubtitle(ScheduleLesson lesson) {
    final group = _attendance.session.groupName;
    return [
      if (group.isNotEmpty) 'Группа $group',
      lesson.timeLabel,
      _formatDate(_day),
    ].join(' · ');
  }

  /// Название блока списка: «Список группы», пока имени группы нет.
  String get _groupTitle {
    final group = _attendance.session.groupName;
    return group.isEmpty ? 'Список группы' : 'Группа $group';
  }

  Widget _buildList() {
    final students = _attendance.students;
    final lesson = _selectedLesson;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: ListView(
          key: kStudentListKey,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            if (_sequential && !_isWeekend && students.isNotEmpty) ...[
              const _SequentialBanner(),
              const SizedBox(height: 16),
            ],
            _GroupHeader(
              title: lesson == null ? _groupTitle : 'Пара «${lesson.subject}»',
              subtitle: lesson == null
                  ? null
                  : _lessonSubtitle(lesson),
              marked: _markedCount,
              total: students.length,
            ),
            const SizedBox(height: 16),
            if (students.isEmpty)
              Text(
                'Список группы пуст. Подключите Google Таблицу с журналом '
                'и загрузите список — ФИО возьмутся из колонки журнала.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            for (var i = 0; i < students.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _studentRowItem(students[i]),
            ],
          ],
        ),
      ),
    );
  }

  /// Строка студента со свайпом на Android. В остальных режимах —
  /// обычная строка: тап выбирает студента, свайпов нет.
  Widget _studentRowItem(Student student) {
    final row = _StudentRow(
      key: ValueKey('student-${student.id}'),
      student: student,
      entry: _entryFor(student),
      selected: _multiSelect
          ? _selectedIds.contains(student.id)
          : _selectedStudentId == student.id,
      multiSelect: _multiSelect,
      onTap: () => _select(student),
    );
    if (!_useSwipeMarking || _isWeekend || _multiSelect) return row;
    return _SwipeableStudentRow(
      onSwipeLeft: () => _swipeMark(student, AttendanceStatus.came),
      onSwipeRight: () => _swipeMark(student, AttendanceStatus.late),
      child: row,
    );
  }

  /// Нижняя панель: цель отметки, отмена отметки и 4 кнопки.
  Widget _buildPanel() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLight = scheme.brightness == Brightness.light;
    final canMark = _canMark;
    final anyMarked = _anyTargetMarked;
    final single = _multiSelect ? null : _selectedStudent;

    final headerText = _multiSelect
        ? (_selectedIds.isEmpty
              ? 'Выберите студентов'
              : 'Выбрано: ${_selectedIds.length}')
        : (single == null
              ? 'Выберите студента'
              : 'Отметить: ${single.fullName}');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: isLight ? AppPalette.canvas : AppPalette.canvasDark,
        border: Border(
          top: BorderSide(
            color: isLight ? AppPalette.line : AppPalette.lineDark,
          ),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      headerText,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: canMark ? null : scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (anyMarked)
                    TextButton.icon(
                      onPressed: _clearMarks,
                      icon: const Icon(Icons.undo, size: 18),
                      label: const Text('Отменить отметку'),
                    ),
                ],
              ),
              if (_multiSelect) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _selectAll,
                        icon: const Icon(Icons.select_all, size: 18),
                        label: const Text('Выбрать всех'),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _selectedIds.isEmpty
                            ? null
                            : _clearSelection,
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Снять выбор'),
                      ),
                    ),
                  ],
                ),
              ],
              if (_absentArmed) ...[
                const SizedBox(height: 8),
                const _ArmedHint(),
              ],
              if (_useSwipeMarking && !_isWeekend && !_multiSelect) ...[
                const SizedBox(height: 2),
                Text(
                  'Свайп по строке: влево — пришёл, вправо — опоздал',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _StatusButton(
                      status: AttendanceStatus.came,
                      enabled: canMark,
                      onTap: () => _mark(AttendanceStatus.came),
                    ),
                  ),
                  const SizedBox(width: _kGap),
                  Expanded(
                    child: _StatusButton(
                      status: AttendanceStatus.absent,
                      enabled: canMark,
                      armed: _absentArmed,
                      onTap: _markAbsent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _StatusButton(
                      status: AttendanceStatus.late,
                      enabled: canMark,
                      onTap: _markLate,
                    ),
                  ),
                  const SizedBox(width: _kGap),
                  Expanded(
                    child: _StatusButton(
                      status: AttendanceStatus.excused,
                      enabled: canMark,
                      onTap: () => _mark(AttendanceStatus.excused),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Заголовок: название, счётчик отметок и прогресс.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.title,
    required this.marked,
    required this.total,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final int marked;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = total == 0 ? 0.0 : marked / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                '$marked из $total',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            color: scheme.primary,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

/// Строка студента со смахиванием: влево — «Пришёл», вправо — «Опоздал».
///
/// Пока палец ведёт строку, за ней видна подсказка нужной отметки.
/// Свайп срабатывает, только если сдвиг больше [_swipeThreshold] —
/// обычный тап по строке по-прежнему просто выбирает студента.
class _SwipeableStudentRow extends StatefulWidget {
  const _SwipeableStudentRow({
    required this.child,
    required this.onSwipeLeft,
    required this.onSwipeRight,
  });

  final Widget child;
  final VoidCallback onSwipeLeft;
  final VoidCallback onSwipeRight;

  @override
  State<_SwipeableStudentRow> createState() => _SwipeableStudentRowState();
}

class _SwipeableStudentRowState extends State<_SwipeableStudentRow> {
  static const _swipeThreshold = 56.0;
  static const _maxSlide = 80.0;

  double _drag = 0;

  void _onUpdate(DragUpdateDetails details) {
    setState(() => _drag += details.delta.dx);
  }

  void _onEnd(DragEndDetails details) {
    final drag = _drag;
    if (mounted) setState(() => _drag = 0);
    if (drag.abs() < _swipeThreshold) return;
    if (drag < 0) {
      widget.onSwipeLeft();
    } else {
      widget.onSwipeRight();
    }
  }

  void _onCancel() {
    if (mounted) setState(() => _drag = 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final drag = _drag;
    final status = drag < 0 ? AttendanceStatus.came : AttendanceStatus.late;
    final color = status.foreground(scheme.brightness);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: _onCancel,
      child: Stack(
        children: [
          if (drag.abs() > 1)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(_kRowRadius),
                ),
                alignment: drag < 0
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(status.icon, size: 18, color: color),
                    const SizedBox(width: 6),
                    Text(
                      status.label,
                      style: theme.textTheme.labelLarge?.copyWith(color: color),
                    ),
                  ],
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(drag.clamp(-_maxSlide, _maxSlide), 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// Строка студента: аватар с инициалами, имя, статус и время отметки.
class _StudentRow extends StatelessWidget {
  const _StudentRow({
    super.key,
    required this.student,
    required this.entry,
    required this.selected,
    required this.onTap,
    this.multiSelect = false,
  });

  final Student student;
  final AttendanceEntry? entry;
  final bool selected;
  final bool multiSelect;
  final VoidCallback onTap;

  String? get _subtitle {
    if (entry == null) return 'нет отметки';
    // Время важно только у опоздания — оно уходит в журнал. У «пришёл»,
    // «не пришёл» и «по уважительной» времени нет.
    if (entry!.status != AttendanceStatus.late) {
      return multiSelect ? entry!.status.label : null;
    }
    // Пустой «опоздал»: время ещё не поставлено, повторный клик
    // по кнопке «Опоздал» его добавит.
    if (!entry!.hasTime) {
      return multiSelect ? '${entry!.status.label} · без времени' : 'без времени';
    }
    final time = _formatTime(TimeOfDay.fromDateTime(entry!.markedAt));
    if (multiSelect) return '${entry!.status.label} · $time';
    return time;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLight = scheme.brightness == Brightness.light;

    final status = entry?.status;
    final marked = status != null;
    final fg = marked ? status.foreground(scheme.brightness) : null;
    final container = marked ? status.container(scheme.brightness) : null;
    final subtitle = _subtitle;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? scheme.primaryContainer
            : (isLight ? Colors.white : AppPalette.cardDark),
        borderRadius: BorderRadius.circular(_kRowRadius),
        border: Border.all(
          color: selected
              ? scheme.primary
              : (isLight ? AppPalette.line : AppPalette.lineDark),
          width: selected ? 2 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(_kRowRadius),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: marked ? container : scheme.surfaceContainerHighest,
                  ),
                  child: Text(
                    student.initials,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: marked ? fg : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        student.fullName,
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (marked ? subtitle != null : true) ...[
                        const SizedBox(height: 2),
                        Text(
                          marked ? subtitle! : 'нет отметки',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: marked ? fg : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (multiSelect)
                  Checkbox(
                    value: selected,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onChanged: (_) => onTap(),
                  )
                else if (marked) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: container,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(status.icon, size: 14, color: fg),
                        const SizedBox(width: 4),
                        Text(
                          status.label,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: fg,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Кнопка отметки в нижней панели.
class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.status,
    required this.enabled,
    required this.onTap,
    this.armed = false,
  });

  final AttendanceStatus status;
  final bool enabled;
  final bool armed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLight = scheme.brightness == Brightness.light;
    final fg = status.foreground(scheme.brightness);
    final container = status.container(scheme.brightness);
    final active = enabled && armed;

    final decoration = !enabled
        ? BoxDecoration(
            borderRadius: BorderRadius.circular(_kButtonRadius),
            border: Border.all(
              color: isLight ? AppPalette.line : AppPalette.lineDark,
            ),
          )
        : active
        ? BoxDecoration(
            color: container,
            borderRadius: BorderRadius.circular(_kButtonRadius),
            border: Border.all(color: fg, width: 2),
          )
        : BoxDecoration(
            color: isLight ? Colors.white : AppPalette.cardDark,
            borderRadius: BorderRadius.circular(_kButtonRadius),
            border: Border.all(
              color: isLight ? AppPalette.line : AppPalette.lineDark,
            ),
          );

    final contentFg = enabled
        ? (active ? fg : scheme.onSurface)
        : scheme.onSurfaceVariant;

    return DecoratedBox(
      key: ValueKey('status-button-${status.name}'),
      decoration: decoration,
      child: Material(
        type: MaterialType.transparency,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(_kButtonRadius),
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  active ? Icons.timer_outlined : status.icon,
                  size: 20,
                  color: enabled ? fg : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      status.label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: contentFg,
                      ),
                      maxLines: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Подсказка о подтверждении отсутствия.
class _ArmedHint extends StatelessWidget {
  const _ArmedHint();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.colorScheme.brightness;
    final fg = AttendanceStatus.absent.foreground(brightness);
    final container = AttendanceStatus.absent.container(brightness);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: container,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: fg, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Второе нажатие подтвердит отсутствие.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// «Поочерёдная отметка включена»: полоса над списком группы.
class _SequentialBanner extends StatelessWidget {
  const _SequentialBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      key: const Key('sequential-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.bolt_rounded, size: 18, color: scheme.onPrimaryContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Поочерёдная отметка: после отметки подсветится '
              'следующий неотмеченный.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// «Выходной — отметки недоступны»: полоса на месте кнопок отметки.
class _WeekendBanner extends StatelessWidget {
  const _WeekendBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.weekend_rounded, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Выходной — в субботу и воскресенье отметки недоступны.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// «сб, 8 ноября» — дата на подзаголовке в шапке.
String _formatDate(DateTime date) {
  const weekdays = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
  const months = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];
  return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';
}

String _formatTime(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
