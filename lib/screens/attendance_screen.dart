import 'package:flutter/material.dart';

import '../data/attendance_controller.dart';
<<<<<<< HEAD
import '../data/ui_settings.dart';
=======
import '../data/notification_controller.dart';
>>>>>>> 7eccdcc (Вкладка «Расписание»: пары по дням недели, отметки на каждой паре и уведомления через таблицу)
import '../models/attendance_entry.dart';
import '../models/attendance_status.dart';
import '../models/schedule_lesson.dart';
import '../models/student.dart';
import '../services/cloud/cloud_sync_controller.dart';
import '../theme/app_theme.dart';
import '../theme/status_style.dart';
import 'cloud_sync_screen.dart';
<<<<<<< HEAD
import 'settings_screen.dart';
=======
import 'notifications_screen.dart';
>>>>>>> 7eccdcc (Вкладка «Расписание»: пары по дням недели, отметки на каждой паре и уведомления через таблицу)

/// Ключ списка группы (используется в тестах).
const kStudentListKey = Key('student-list');

const _kRowRadius = 16.0;
const _kButtonRadius = 14.0;
const _kGap = 12.0;

/// Экран отметки посещаемости группы.
///
/// Староста (или куратор) выбирает студента в списке и отмечает его
/// одной из 4 кнопок: «Пришёл», «Непришёл», «Опоздал», «По уважительной».
/// «Непришёл» подтверждается вторым нажатием с выбором времени
/// (по умолчанию — текущее).
///
/// Если передан [lesson] — отметки ставятся на конкретную пару из
/// расписания, а не на весь день.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({
    super.key,
    this.attendance,
    this.cloud,
<<<<<<< HEAD
    this.uiSettings,
=======
    this.lesson,
    this.notifications,
>>>>>>> 7eccdcc (Вкладка «Расписание»: пары по дням недели, отметки на каждой паре и уведомления через таблицу)
  });

  /// Состояние посещаемости. Если не передано — создаётся пример группы
  /// (удобно для тестов и превью).
  final AttendanceController? attendance;

  /// Облачная синхронизация. Если `null`, кнопка Google Диска не показывается.
  final CloudSyncController? cloud;

<<<<<<< HEAD
  /// Выборный дизайн («Настройки → Дизайн»). Если `null`, кнопка
  /// с шестерёнкой скрывается.
  final UiSettingsController? uiSettings;
=======
  /// Пара из расписания: отметки будут привязаны к ней.
  final ScheduleLesson? lesson;

  /// Уведомления о отметках других пользователей таблицы.
  final NotificationController? notifications;
>>>>>>> 7eccdcc (Вкладка «Расписание»: пары по дням недели, отметки на каждой паре и уведомления через таблицу)

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

  @override
  void initState() {
    super.initState();
    _selectedStudentId = _attendance.students.isEmpty
        ? null
        : _attendance.students.first.id;
    _attendance.addListener(_onAttendanceChanged);
  }

  @override
  void dispose() {
    _attendance.removeListener(_onAttendanceChanged);
    super.dispose();
  }

  void _onAttendanceChanged() {
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
      _multiSelect ? _selectedIds.isNotEmpty : _selectedStudent != null;

  bool get _anyTargetMarked =>
      _targets.any((student) => _attendance.entryFor(student.id) != null);

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
        _selectedStudentId =
            _selectedIds.isNotEmpty ? _selectedIds.first : _selectedStudentId;
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

  void _mark(AttendanceStatus status) {
<<<<<<< HEAD
    final targets = _targets;
    if (targets.isEmpty) return;
    final now = DateTime.now();
    for (final student in targets) {
      _attendance.mark(student, status, now);
    }
=======
    final student = _selectedStudent;
    if (student == null) return;
    final lesson = widget.lesson;
    _attendance.mark(
      student,
      status,
      DateTime.now(),
      lessonKey: lesson?.id,
      lessonTitle: lesson?.subject,
    );
    _queueLessonNotification();
>>>>>>> 7eccdcc (Вкладка «Расписание»: пары по дням недели, отметки на каждой паре и уведомления через таблицу)
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
<<<<<<< HEAD
    for (final student in targets) {
      _attendance.mark(
        student,
        AttendanceStatus.absent,
        DateTime(now.year, now.month, now.day, time.hour, time.minute),
      );
    }
    setState(() => _absentArmed = false);
  }

  /// Отмена отметки у всех выбранных студентов.
  void _clearMarks() {
    final targets = _targets;
    if (targets.isEmpty) return;
    for (final student in targets) {
      _attendance.clearMark(student);
    }
=======
    final lesson = widget.lesson;
    _attendance.mark(
      student,
      AttendanceStatus.absent,
      DateTime(now.year, now.month, now.day, time.hour, time.minute),
      lessonKey: lesson?.id,
      lessonTitle: lesson?.subject,
    );
    _queueLessonNotification();
>>>>>>> 7eccdcc (Вкладка «Расписание»: пары по дням недели, отметки на каждой паре и уведомления через таблицу)
    setState(() => _absentArmed = false);
  }

  /// Отмеченная пара попадает в отложенное уведомление — оно уйдёт
  /// в таблицу при следующей синхронизации, и её увидят другие.
  void _queueLessonNotification() {
    final lesson = widget.lesson;
    final cloud = widget.cloud;
    if (lesson == null || cloud == null) return;
    cloud.notifications?.queueLessonMark(
      groupName: _attendance.session.groupName,
      lesson: lesson,
      date: _attendance.session.date,
    );
  }

  /// Отметка студента с учётом режима: на паре или на весь день.
  AttendanceEntry? _entryFor(Student student) {
    final lesson = widget.lesson;
    if (lesson == null) return _attendance.entryFor(student.id);
    return _attendance.entryInLesson(
      student.id,
      lessonKey: lesson.id,
      lessonTitle: lesson.subject,
    );
  }

  /// Сколько студентов отмечено в текущем режиме.
  int get _markedCount {
    final lesson = widget.lesson;
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
<<<<<<< HEAD
          IconButton(
            tooltip: _multiSelect
                ? 'Выйти из множественного выбора'
                : 'Множественный выбор',
            icon: Icon(
              _multiSelect ? Icons.close : Icons.library_add_check_outlined,
            ),
            onPressed: _toggleMultiSelect,
          ),
=======
          if (widget.notifications != null)
            NotificationBell(notifications: widget.notifications!),
>>>>>>> 7eccdcc (Вкладка «Расписание»: пары по дням недели, отметки на каждой паре и уведомления через таблицу)
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
        child: Column(
          children: [
            Expanded(child: _buildList()),
            _buildPanel(),
          ],
        ),
      ),
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
    final lesson = widget.lesson;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(lesson == null ? 'Явка' : 'Пара «${lesson.subject}»'),
        const SizedBox(height: 2),
        Text(
          lesson == null
              ? _formatDate(DateTime.now())
              : 'Группа ${_attendance.session.groupName} · '
                    '${lesson.timeLabel} · ${_formatDate(DateTime.now())}',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildList() {
    final students = _attendance.students;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: ListView(
          key: kStudentListKey,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            _GroupHeader(
              title: widget.lesson == null
                  ? 'Группа ${_attendance.session.groupName}'
                  : 'Пара «${widget.lesson!.subject}»',
              subtitle: widget.lesson == null
                  ? null
                  : 'Группа ${_attendance.session.groupName} · '
                        '${widget.lesson!.timeLabel}',
              marked: _markedCount,
              total: students.length,
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < students.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _StudentRow(
                key: ValueKey('student-${students[i].id}'),
                student: students[i],
<<<<<<< HEAD
                entry: _attendance.entryFor(students[i].id),
                selected: _multiSelect
                    ? _selectedIds.contains(students[i].id)
                    : _selectedStudentId == students[i].id,
                multiSelect: _multiSelect,
=======
                entry: _entryFor(students[i]),
                selected: _selectedStudentId == students[i].id,
>>>>>>> 7eccdcc (Вкладка «Расписание»: пары по дням недели, отметки на каждой паре и уведомления через таблицу)
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
                        onPressed: _selectedIds.isEmpty ? null : _clearSelection,
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
