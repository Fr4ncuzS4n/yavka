import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/attendance_status.dart';
import '../theme/app_theme.dart';
import '../theme/status_style.dart';

const _kGap = 12.0;
const _kRadius = 20.0;

/// Экран быстрой отметки посещаемости.
///
/// Содержит 4 кнопки-карточки: «Пришёл», «Непришёл», «Опоздал»,
/// «По уважительной». Выбранная отметка подсвечивается цветом статуса
/// и показывается в баннере сверху. «Непришёл» подтверждается вторым
/// нажатием с выбором времени.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  AttendanceStatus? _status;
  TimeOfDay? _markedAt;
  bool _absentArmed = false;

  void _mark(AttendanceStatus status) {
    final now = DateTime.now();
    setState(() {
      _status = status;
      _markedAt = TimeOfDay(hour: now.hour, minute: now.minute);
      _absentArmed = false;
    });
  }

  Future<void> _markAbsent() async {
    if (!mounted) return;

    // Первое нажатие — запоминаем намерение, второе — подтверждаем.
    if (!_absentArmed) {
      setState(() => _absentArmed = true);
      return;
    }

    // Подтверждение отсутствия: выбираем время (по умолчанию — текущее).
    final now = TimeOfDay(hour: DateTime.now().hour, minute: DateTime.now().minute);
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: now,
    );

    if (!mounted) return;

    setState(() {
      _status = AttendanceStatus.absent;
      _markedAt = pickedTime ?? now;
      _absentArmed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: _buildTitle(context, scheme)),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth = math.min(constraints.maxWidth, 880.0) - 32;
            final columns = contentWidth >= 640 ? 2 : 1;

            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_status != null) ...[
                        _StatusBanner(
                          status: _status!,
                          markedAt: _markedAt,
                        ),
                        const SizedBox(height: 20),
                      ],
                      Text(
                        'Отметить',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      ..._buildButtons(columns),
                      if (_absentArmed) ...[
                        const SizedBox(height: 12),
                        const _ArmedHint(),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTitle(BuildContext context, ColorScheme scheme) {
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

  List<Widget> _buildButtons(int columns) {
    const statuses = AttendanceStatus.values;
    final rows = <Widget>[];

    for (var i = 0; i < statuses.length; i += columns) {
      final slice = statuses.sublist(i, math.min(i + columns, statuses.length));
      if (rows.isNotEmpty) rows.add(const SizedBox(height: _kGap));

      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final status in slice) ...[
                if (status != slice.first) const SizedBox(width: _kGap),
                Expanded(
                  child: _StatusCard(
                    status: status,
                    selected: _status == status,
                    armed: status == AttendanceStatus.absent && _absentArmed,
                    onTap: status == AttendanceStatus.absent
                        ? _markAbsent
                        : () => _mark(status),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return rows;
  }

  /// «сб, 8 ноября» — дата на подзаголовке в шапке.
  static String _formatDate(DateTime date) {
    const weekdays = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'];
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
    ];
    return '${weekdays[date.weekday - 1]}, ${date.day} ${months[date.month - 1]}';
  }
}

/// Карточка одной отметки: иконка, название, подпись и состояние выбора.
class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.selected,
    required this.onTap,
    this.armed = false,
  });

  final AttendanceStatus status;
  final bool selected;
  final bool armed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLight = scheme.brightness == Brightness.light;
    final fg = status.foreground(scheme.brightness);
    final container = status.container(scheme.brightness);
    final cardBg = isLight ? Colors.white : AppPalette.cardDark;
    final active = selected || armed;

    final hint = armed ? 'Нажмите ещё раз — выберите время' : status.hint;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: active ? container : cardBg,
        borderRadius: BorderRadius.circular(_kRadius),
        border: Border.all(
          color: active ? fg : (isLight ? AppPalette.line : AppPalette.lineDark),
          width: active ? 2 : 1,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(_kRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
                  child: Icon(
                    status.icon,
                    size: 24,
                    color: isLight ? Colors.white : AppPalette.canvasDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        status.label,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hint,
                        style: theme.textTheme.bodySmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (armed)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.timer_outlined, color: fg, size: 22),
                  )
                else if (selected)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.check_circle_rounded, color: fg, size: 22),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Баннер с текущей отметкой и временем.
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status, this.markedAt});

  final AttendanceStatus status;
  final TimeOfDay? markedAt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final brightness = theme.colorScheme.brightness;
    final fg = status.foreground(brightness);
    final container = status.container(brightness);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: container,
        borderRadius: BorderRadius.circular(_kRadius),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            child: Icon(
              status.icon,
              size: 24,
              color: brightness == Brightness.light
                  ? Colors.white
                  : AppPalette.canvasDark,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Отметка: ${status.label}',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 2),
                Text(
                  status.hint,
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (markedAt != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: fg.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                _formatTime(markedAt!),
                style: theme.textTheme.labelLarge?.copyWith(color: fg),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatTime(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: container,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: fg, size: 20),
          const SizedBox(width: 10),
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
