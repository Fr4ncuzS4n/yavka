import 'package:flutter/material.dart';

import '../data/attendance_controller.dart';
import '../data/notification_controller.dart';
import '../data/schedule_controller.dart';
import '../data/ui_settings.dart';
import '../models/attendance_entry.dart';
import '../models/attendance_session.dart';
import '../models/attendance_status.dart';
import '../models/schedule_lesson.dart';
import '../models/student.dart';
import '../services/cloud/cloud_sync_controller.dart';
import '../theme/app_theme.dart';
import '../theme/status_style.dart';
import '../util/desktop_layout.dart';
import 'cloud_sync_screen.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';

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
/// «Непришёл» подтверждается вторым нажатием с выбором времени
/// (по умолчанию — текущее).
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
    _selectedStudentId = _attendance.students.isEmpty
        ? null
        : _attendance.students.first.id;
    _lessonId = widget.lesson?.id;
    _attendance.addListener(_onAttendanceChanged);
    widget.schedule?.addListener(_onScheduleChanged);
  }

  @override
  void dispose() {
    _attendance.removeListener(_onAttendanceChanged);
    widget.schedule?.removeListener(_onScheduleChanged);
    super.dispose();
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
      widget.schedule?.lessonsFor(_day.weekday) ?? const [];

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

  void _mark(AttendanceStatus status) {
    final targets = _targets;
    if (targets.isEmpty) return;
    // Дата отметки — выбранный день, время — момент отметки.
    final now = DateTime.now();
    final markedAt = DateTime(
      _day.year,
      _day.month,
      _day.day,
      now.hour,
      now.minute,
    );
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
    setState(() => _absentArmed = false);
  }

  Future<void> _markAbsent() async {
    if (!_canMark || !mounted) return;

    // Первое нажатие — запоминаем намерение, второе — подтверждаем.
    if (!_absentArmed) {
      setState(() => _absentArmed = true);
      return;
    }

    // Кого отмечаем — фиксируем до открытия диалога времени.
    final targets = _targets;
    if (targets.isEmpty) return;

    // Подтверждение отсутствия: выбираем время (по умолчанию — текущее).
    final now = DateTime.now();
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );

    if (!mounted) return;

    final time = pickedTime ?? TimeOfDay.fromDateTime(now);
    final lesson = _selectedLesson;
    for (final student in targets) {
      _attendance.mark(
        student,
        AttendanceStatus.absent,
        DateTime(_day.year, _day.month, _day.day, time.hour, time.minute),
        lessonKey: lesson?.id,
        lessonTitle: lesson?.subject,
      );
    }
    _queueLessonNotification();
    setState(() => _absentArmed = false);
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

  /// Отмеченная пара попадает в отложенное уведомление — оно уйдёт
  /// в таблицу при следующей синхронизации, и её увидят другие.
  void _queueLessonNotification() {
    final lesson = _selectedLesson;
    final cloud = widget.cloud;
    if (lesson == null || cloud == null) return;
    cloud.notifications?.queueLessonMark(
      groupName: _attendance.session.groupName,
      lesson: lesson,
      date: _day,
    );
  }

  /// Отметка студента с учётом режима: на паре или на весь день.
  AttendanceEntry? _entryFor(Student student) {
    final lesson = _selectedLesson;
    if (lesson == null) return _attendance.entryFor(student.id);
    return _attendance.entryInLesson(
      student.id,
      lessonKey: lesson.id,
      lessonTitle: lesson.subject,
    );
  }

  /// Сколько студентов отмечено в текущем режиме.
  int get _markedCount {
    final lesson = _selectedLesson;
    if (lesson == null) return _attendance.entries.length;
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
          if (widget.uiSettings != null)
            IconButton(
              tooltip: 'Дизайн',
              onPressed: () => _openSettings(context),
              icon: const Icon(Icons.palette_outlined),
            ),
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
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Весь день'),
                      selected: _lessonId == null,
                      onSelected: (_) => _selectLesson(null),
                    ),
                    for (final lesson in _dayLessons)
                      ChoiceChip(
                        label: Text('${lesson.startLabel} · ${lesson.subject}'),
                        selected: _lessonId == lesson.id,
                        onSelected: (_) => _selectLesson(lesson.id),
                      ),
                  ],
                ),
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

  void _openSettings(BuildContext context) {
    final settings = widget.uiSettings;
    if (settings == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(settings: settings),
      ),
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
              : 'Группа ${_attendance.session.groupName} · '
                    '${lesson.timeLabel} · ${_formatDate(_day)}',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
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
            _GroupHeader(
              title: lesson == null
                  ? 'Группа ${_attendance.session.groupName}'
                  : 'Пара «${lesson.subject}»',
              subtitle: lesson == null
                  ? null
                  : 'Группа ${_attendance.session.groupName} · '
                        '${lesson.timeLabel}',
              marked: _markedCount,
              total: students.length,
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < students.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _StudentRow(
                key: ValueKey('student-${students[i].id}'),
                student: students[i],
                entry: _entryFor(students[i]),
                selected: _multiSelect
                    ? _selectedIds.contains(students[i].id)
                    : _selectedStudentId == students[i].id,
                multiSelect: _multiSelect,
                onTap: () => _select(students[i]),
              ),
            ],
          ],
        ),
      ),
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
                      onTap: () => _mark(AttendanceStatus.late),
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
                      const SizedBox(height: 2),
                      Text(
                        marked ? subtitle! : 'нет отметки',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: marked ? fg : scheme.onSurfaceVariant,
                        ),
                      ),
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
              'Второе нажатие: выберите время или используйте текущее.',
              style: theme.textTheme.bodySmall,
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
