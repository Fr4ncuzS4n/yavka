import 'package:flutter/material.dart';

import '../data/example_group.dart';
import '../models/attendance_status.dart';
import '../models/student.dart';
import '../theme/app_theme.dart';
import '../theme/status_style.dart';

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
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  String? _selectedStudentId = exampleStudents.first.id;
  final _marks = <String, AttendanceStatus>{};
  final _markTimes = <String, TimeOfDay>{};
  bool _absentArmed = false;

  Student? get _selectedStudent {
    for (final student in exampleStudents) {
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
    final now = DateTime.now();
    setState(() {
      _marks[student.id] = status;
      _markTimes[student.id] = TimeOfDay(hour: now.hour, minute: now.minute);
      _absentArmed = false;
    });
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
    final now =
        TimeOfDay(hour: DateTime.now().hour, minute: DateTime.now().minute);
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: now,
    );

    if (!mounted) return;

    setState(() {
      _marks[student.id] = AttendanceStatus.absent;
      _markTimes[student.id] = pickedTime ?? now;
      _absentArmed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: _buildTitle(context)),
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
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildList() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: ListView(
          key: kStudentListKey,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            _GroupHeader(marked: _marks.length, total: exampleStudents.length),
            const SizedBox(height: 16),
            for (var i = 0; i < exampleStudents.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _StudentRow(
                key: ValueKey('student-${exampleStudents[i].id}'),
                student: exampleStudents[i],
                status: _marks[exampleStudents[i].id],
                markedAt: _markTimes[exampleStudents[i].id],
                selected: _selectedStudentId == exampleStudents[i].id,
                onTap: () => _select(exampleStudents[i]),
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
        border: Border(top: BorderSide(color: isLight ? AppPalette.line : AppPalette.lineDark)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 880),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                enabled ? 'Отметить: ${selected.fullName}' : 'Выберите студента',
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
  const _GroupHeader({required this.marked, required this.total});

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
                'Группа $exampleGroupName',
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
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: scheme.onPrimaryContainer),
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
    required this.status,
    required this.markedAt,
    required this.selected,
    required this.onTap,
  });

  final Student student;
  final AttendanceStatus? status;
  final TimeOfDay? markedAt;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLight = scheme.brightness == Brightness.light;

    final marked = status != null;
    final fg = marked ? status!.foreground(scheme.brightness) : null;
    final container = marked ? status!.container(scheme.brightness) : null;

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
                    color: marked
                        ? container
                        : scheme.surfaceContainerHighest,
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
                        marked && markedAt != null
                            ? _formatTime(markedAt!)
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: container,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(status!.icon, size: 14, color: fg),
                        const SizedBox(width: 4),
                        Text(
                          status!.label,
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
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
  ];
  return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';
}

String _formatTime(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
