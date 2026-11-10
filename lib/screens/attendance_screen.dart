import 'package:flutter/material.dart';

import '../data/attendance_controller.dart';
import '../data/ui_settings.dart';
import '../models/attendance_entry.dart';
import '../models/attendance_status.dart';
import '../models/student.dart';
import '../services/cloud/cloud_sync_controller.dart';
import '../theme/app_theme.dart';
import '../theme/status_style.dart';
import 'cloud_sync_screen.dart';
import 'settings_screen.dart';

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
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({
    super.key,
    this.attendance,
    this.cloud,
    this.uiSettings,
  });

  /// Состояние посещаемости. Если не передано — создаётся пример группы
  /// (удобно для тестов и превью).
  final AttendanceController? attendance;

  /// Облачная синхронизация. Если `null`, кнопка Google Диска не показывается.
  final CloudSyncController? cloud;

  /// Выборный дизайн («Настройки → Дизайн»). Если `null`, кнопка
  /// с шестерёнкой скрывается.
  final UiSettingsController? uiSettings;

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  late final AttendanceController _attendance =
      widget.attendance ?? AttendanceController.inMemory();
  String? _selectedStudentId;
  bool _absentArmed = false;

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

  void _select(Student student) {
    if (student.id == _selectedStudentId) return;
    setState(() {
      _selectedStudentId = student.id;
      _absentArmed = false;
    });
  }

  void _mark(AttendanceStatus status) {
    final student = _selectedStudent;
    if (student == null) return;
    _attendance.mark(student, status, DateTime.now());
    setState(() => _absentArmed = false);
  }

  Future<void> _markAbsent() async {
    final student = _selectedStudent;
    if (student == null || !mounted) return;

    // Первое нажатие — запоминаем намерение, второе — подтверждаем.
    if (!_absentArmed) {
      setState(() => _absentArmed = true);
      return;
    }

    // Подтверждение отсутствия: выбираем время (по умолчанию — текущее).
    final now = DateTime.now();
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );

    if (!mounted) return;

    final time = pickedTime ?? TimeOfDay.fromDateTime(now);
    _attendance.mark(
      student,
      AttendanceStatus.absent,
      DateTime(now.year, now.month, now.day, time.hour, time.minute),
    );
    setState(() => _absentArmed = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _buildTitle(context),
        actions: [
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Явка'),
        const SizedBox(height: 2),
        Text(
          _formatDate(DateTime.now()),
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
              groupName: _attendance.session.groupName,
              marked: _attendance.entries.length,
              total: students.length,
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < students.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _StudentRow(
                key: ValueKey('student-${students[i].id}'),
                student: students[i],
                entry: _attendance.entryFor(students[i].id),
                selected: _selectedStudentId == students[i].id,
                onTap: () => _select(students[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Нижняя панель с 4 кнопками отметки.
  Widget _buildPanel() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLight = scheme.brightness == Brightness.light;
    final selected = _selectedStudent;
    final enabled = selected != null;

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
              Text(
                enabled
                    ? 'Отметить: ${selected.fullName}'
                    : 'Выберите студента',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: enabled ? null : scheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
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
                      enabled: enabled,
                      onTap: () => _mark(AttendanceStatus.came),
                    ),
                  ),
                  const SizedBox(width: _kGap),
                  Expanded(
                    child: _StatusButton(
                      status: AttendanceStatus.absent,
                      enabled: enabled,
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
                      enabled: enabled,
                      onTap: () => _mark(AttendanceStatus.late),
                    ),
                  ),
                  const SizedBox(width: _kGap),
                  Expanded(
                    child: _StatusButton(
                      status: AttendanceStatus.excused,
                      enabled: enabled,
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

/// Заголовок: название группы, счётчик отметок и прогресс.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.groupName,
    required this.marked,
    required this.total,
  });

  final String groupName;
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
              child: Text(
                'Группа $groupName',
                style: theme.textTheme.titleLarge,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
  });

  final Student student;
  final AttendanceEntry? entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLight = scheme.brightness == Brightness.light;

    final status = entry?.status;
    final marked = status != null;
    final fg = marked ? status.foreground(scheme.brightness) : null;
    final container = marked ? status.container(scheme.brightness) : null;

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
                        marked && entry != null
                            ? _formatTime(
                                TimeOfDay.fromDateTime(entry!.markedAt),
                              )
                            : 'нет отметки',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: marked ? fg : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (marked) ...[
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
