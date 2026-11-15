import 'package:flutter/material.dart';

import '../data/attendance_controller.dart';
import '../data/catalog_controller.dart';
import '../data/notification_controller.dart';
import '../data/schedule_controller.dart';
import '../data/schedule_parser.dart';
import '../models/attendance_session.dart';
import '../models/catalog.dart';
import '../models/schedule_lesson.dart';
import '../theme/app_theme.dart';
import 'attendance_screen.dart';
import 'catalog_screen.dart';
import 'notifications_screen.dart';

/// Вкладка «Расписание»: пары по дням недели.
///
/// Расписание можно вставить документом (текст разберётся в пары) или
/// составить самому, добавляя пары списком. Предмет, преподаватель и
/// кабинет выбираются селектами из локальной базы (см. [catalog]); из
/// диалога пары в неё можно добавить новое. С каждой сегодняшней пары
/// можно сразу отметить посещаемость группы.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    required this.schedule,
    this.attendance,
    this.notifications,
    this.catalog,
    this.accountEmail,
  });

  final ScheduleController schedule;
  final AttendanceController? attendance;
  final NotificationController? notifications;

  /// Локальная база: преподаватели, предметы, кабинеты. Без неё диалог
  /// пары остаётся с селектами, но пополнять базу из него нельзя.
  final CatalogController? catalog;

  /// Почта аккаунта, к расписанию которого привязано приложение;
  /// `null` — расписание без входа в Google.
  final String? accountEmail;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen>
    with TickerProviderStateMixin {
  late final TabController _days = TabController(
    length: 7,
    vsync: this,
    initialIndex: DateTime.now().weekday - 1,
  );

  @override
  void initState() {
    super.initState();
    widget.schedule.addListener(_onChange);
    _days.addListener(_onChange);
    final attendance = widget.attendance;
    if (attendance != null) attendance.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.schedule.removeListener(_onChange);
    _days.removeListener(_onChange);
    _days.dispose();
    widget.attendance?.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  int get _selectedWeekday => _days.index + 1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    // Сегодня выходной: отметки на парах недоступны (сб и вс).
    final canMarkToday =
        today.weekday != DateTime.saturday && today.weekday != DateTime.sunday;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Расписание'),
        actions: [
          if (widget.notifications != null)
            NotificationBell(notifications: widget.notifications!),
          if (widget.catalog != null)
            IconButton(
              tooltip: 'База данных: преподаватели, предметы, кабинеты',
              onPressed: () => _openCatalog(context),
              icon: const Icon(Icons.storage_rounded),
            ),
          IconButton(
            tooltip: 'Вставить документ с расписанием',
            onPressed: () => _pasteDocument(context),
            icon: const Icon(Icons.post_add_rounded),
          ),
          IconButton(
            tooltip: 'Добавить пару',
            onPressed: () => _editLesson(context, weekday: _selectedWeekday),
            icon: const Icon(Icons.add_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: scheme.brightness == Brightness.light
                  ? AppPalette.canvas
                  : AppPalette.canvasDark,
              child: TabBar(
                controller: _days,
                labelColor: scheme.primary,
                unselectedLabelColor: scheme.onSurfaceVariant,
                indicatorColor: scheme.primary,
                tabs: [
                  for (var weekday = 1; weekday <= 7; weekday++)
                    Tab(text: weekdayShortName(weekday)),
                ],
              ),
            ),
            Divider(
              color: scheme.brightness == Brightness.light
                  ? AppPalette.line
                  : AppPalette.lineDark,
              height: 1,
              thickness: 1,
            ),
            if (widget.accountEmail != null)
              Material(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.alternate_email_rounded,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Расписание аккаунта ${widget.accountEmail}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: TabBarView(
                controller: _days,
                children: [
                  for (var weekday = 1; weekday <= 7; weekday++)
                    _DayPage(
                      key: ValueKey('day-$weekday'),
                      weekday: weekday,
                      isToday: weekday == today.weekday,
                      canMarkToday: weekday == today.weekday && canMarkToday,
                      lessons: widget.schedule.lessonsFor(weekday),
                      schedule: widget.schedule,
                      attendance: widget.attendance,
                      notifications: widget.notifications,
                      catalog: widget.catalog,
                      onPaste: () => _pasteDocument(context, weekday: weekday),
                      onAdd: () => _editLesson(context, weekday: weekday),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Экран локальной базы: преподаватели, предметы, кабинеты.
  Future<void> _openCatalog(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CatalogScreen(catalog: widget.catalog!),
      ),
    );
    if (mounted) setState(() {}); // селекты в диалогах обновились
  }

  /// Вставить документ с расписанием.
  Future<void> _pasteDocument(BuildContext context, {int? weekday}) async {
    final schedule = widget.schedule;
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<PasteOutcome>(
      context: context,
      builder: (_) =>
          _PasteDialog(fallbackWeekday: weekday ?? _selectedWeekday),
    );
    if (result == null || !mounted) return;

    final parsed = ScheduleParser.parse(
      result.text,
      fallbackWeekday: result.weekday,
    );
    if (parsed.lessons.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Не удалось распознать ни одной пары. Пример строки: '
            '«09:00–10:30 Математика, каб. 201».',
          ),
        ),
      );
      return;
    }

    // Предметы, преподаватели и кабинеты из документа пополняют базу —
    // дальше их можно выбирать селектами в диалоге пары.
    var catalogNote = '';
    final catalog = widget.catalog;
    if (catalog != null) {
      final added = catalog.syncFromLessons(parsed.lessons);
      final total = added.teachers + added.rooms + added.subjects;
      if (total > 0) {
        catalogNote =
            ' В базу добавлено: предметов — ${added.subjects}, '
            'преподавателей — ${added.teachers}, кабинетов — ${added.rooms}.';
      }
    }

    schedule.replaceWeekdays(parsed.lessons, weekdays: parsed.weekdays);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Добавлено пар: ${parsed.lessons.length}'
          '${result.replace ? ' (дни из документа заменены)' : ''}'
          '$catalogNote',
        ),
      ),
    );
  }

  /// Добавить или изменить пару.
  Future<void> _editLesson(
    BuildContext context, {
    required int weekday,
    ScheduleLesson? existing,
  }) async {
    final schedule = widget.schedule;
    final lesson = await showDialog<ScheduleLesson>(
      context: context,
      builder: (_) =>
          _LessonDialog(catalog: widget.catalog, weekday: weekday, existing: existing),
    );
    if (lesson == null || !mounted) return;
    if (existing == null) {
      schedule.add(lesson);
    } else {
      schedule.update(lesson);
    }
  }
}

/// Результат диалога вставки документа.
class PasteOutcome {
  const PasteOutcome({
    required this.text,
    required this.weekday,
    required this.replace,
  });

  final String text;
  final int weekday;
  final bool replace;
}

/// Диалог вставки документа с расписанием.
class _PasteDialog extends StatefulWidget {
  const _PasteDialog({required this.fallbackWeekday});

  final int fallbackWeekday;

  @override
  State<_PasteDialog> createState() => _PasteDialogState();
}

class _PasteDialogState extends State<_PasteDialog> {
  late final TextEditingController _controller;
  late int _weekday;
  bool _replace = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _weekday = widget.fallbackWeekday;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Вставить документ'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Вставьте текст расписания. Строки вида '
              '«09:00–10:30 Математика, каб. 201» станут парами. '
              'Если в документе есть заголовки дней («Понедельник»), '
              'пары распределятся по ним.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              maxLines: 8,
              autofocus: true,
              // Без этого кнопка «Вставить» не узнает, что текст введён.
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText:
                    'Понедельник\n09:00–10:30 Математика, каб. 201\n'
                    '10:40 Физика, ауд. 12, Иванова И.И.',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _weekday,
              decoration: const InputDecoration(
                labelText: 'Если день в строке не указан — добавить в',
                border: OutlineInputBorder(),
              ),
              items: [
                for (var day = 1; day <= 7; day++)
                  DropdownMenuItem(
                    value: day,
                    child: Text(weekdayFullName(day)),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _weekday = value ?? _weekday),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Заменить пары этих дней'),
              subtitle: const Text(
                'Существующие пары затронутых дней будут удалены.',
              ),
              value: _replace,
              onChanged: (value) => setState(() => _replace = value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _controller.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  PasteOutcome(
                    text: _controller.text,
                    weekday: _weekday,
                    replace: _replace,
                  ),
                ),
          child: const Text('Вставить'),
        ),
      ],
    );
  }
}

/// Диалог создания и изменения пары.
///
/// Предмет, преподаватель и кабинет выбираются селектами из локальной
/// базы; кнопкой «+» рядом с селектом можно сразу добавить новую
/// запись в базу. У выбранного предмета преподаватель и кабинет
/// подставляются из базы — при желании их можно поменять в самой паре.
class _LessonDialog extends StatefulWidget {
  const _LessonDialog({required this.weekday, this.catalog, this.existing});

  final int weekday;
  final CatalogController? catalog;
  final ScheduleLesson? existing;

  @override
  State<_LessonDialog> createState() => _LessonDialogState();
}

class _LessonDialogState extends State<_LessonDialog> {
  /// Выбранное название предмета (null — не выбрано).
  String? _subjectName;

  /// Выбранный преподаватель (null — «Не указан»).
  String? _teacherName;

  /// Выбранный кабинет (null — «Не указан»).
  String? _roomName;

  late int _weekday;
  int? _start;
  int? _end;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Старые пары хранят преподавателя и кабинет строками — их названия
    // остаются в селектах, даже если в базе такой записи ещё нет.
    _subjectName = _trimOrNull(widget.existing?.subject);
    _teacherName = _trimOrNull(widget.existing?.teacher);
    _roomName = _trimOrNull(widget.existing?.room);
    _weekday = widget.existing?.weekday ?? widget.weekday;
    _start = widget.existing?.startMinutes;
    _end = widget.existing?.endMinutes;
  }

  static String? _trimOrNull(String? value) {
    final text = value?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  CatalogController? get _catalog => widget.catalog;

  TimeOfDay _toTime(int? minutes) => minutes == null
      ? const TimeOfDay(hour: 9, minute: 0)
      : TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);

  Future<void> _pickStart() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _toTime(_start),
    );
    if (picked == null) return;
    setState(() {
      _start = picked.hour * 60 + picked.minute;
      if (_end != null && _end! <= _start!) _end = null;
    });
  }

  Future<void> _pickEnd() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _toTime(_end ?? (_start ?? 540) + 90),
    );
    if (picked == null) return;
    final end = picked.hour * 60 + picked.minute;
    if (_start != null && end <= _start!) {
      setState(() => _error = 'Конец пары должен быть позже начала.');
      return;
    }
    setState(() {
      _end = end;
      _error = null;
    });
  }

  /// Выбор предмета: преподаватель и кабинет подставляются из базы.
  void _onSubjectChanged(String? name) {
    final catalog = _catalog;
    setState(() {
      _subjectName = name;
      final subject = name == null || catalog == null
          ? null
          : catalog.subjectByName(name);
      _teacherName = subject == null
          ? null
          : catalog?.teacherById(subject.teacherId)?.name;
      _roomName = subject == null
          ? null
          : catalog?.roomById(subject.roomId)?.name;
    });
  }

  // --- Пополнение базы прямо из диалога ---

  Future<void> _addSubjectToCatalog() async {
    final catalog = _catalog;
    if (catalog == null) return;
    final subject = await showDialog<Subject>(
      context: context,
      builder: (_) => SubjectEditDialog(catalog: catalog),
    );
    if (subject == null || !mounted) return;
    setState(() {
      _subjectName = subject.name;
      _teacherName = catalog.teacherById(subject.teacherId)?.name;
      _roomName = catalog.roomById(subject.roomId)?.name;
    });
  }

  Future<void> _addTeacherToCatalog() async {
    final catalog = _catalog;
    if (catalog == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const CatalogNameDialog(
        title: 'Новый преподаватель',
        actionLabel: 'Добавить',
      ),
    );
    if (name == null) return;
    final teacher = catalog.addTeacher(name);
    setState(() => _teacherName = teacher.name);
  }

  Future<void> _addRoomToCatalog() async {
    final catalog = _catalog;
    if (catalog == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const CatalogNameDialog(
        title: 'Новый кабинет',
        actionLabel: 'Добавить',
      ),
    );
    if (name == null) return;
    final room = catalog.addRoom(name);
    setState(() => _roomName = room.name);
  }

  // --- Пункты селектов ---

  /// Предметы из базы; название старой пары остаётся пунктом, даже если
  /// предмет ещё не завели в базу.
  List<DropdownMenuItem<String>> get _subjectItems {
    final names = [
      for (final subject in _catalog?.subjects ?? const <Subject>[])
        subject.name,
    ];
    final selected = _subjectName;
    if (selected != null && !_hasName(names, selected)) {
      names.insert(0, selected);
    }
    return [
      for (final name in names)
        DropdownMenuItem<String>(value: name, child: Text(name)),
    ];
  }

  /// Преподаватели из базы плюс «Не указан».
  List<DropdownMenuItem<String?>> get _teacherItems {
    final names = [
      for (final teacher in _catalog?.teachers ?? const <Teacher>[])
        teacher.name,
    ];
    final selected = _teacherName;
    if (selected != null && !_hasName(names, selected)) {
      names.insert(0, selected);
    }
    return [
      const DropdownMenuItem<String?>(value: null, child: Text('Не указан')),
      for (final name in names)
        DropdownMenuItem<String?>(value: name, child: Text(name)),
    ];
  }

  /// Кабинеты из базы плюс «Не указан».
  List<DropdownMenuItem<String?>> get _roomItems {
    final names = [
      for (final room in _catalog?.rooms ?? const <Room>[]) room.name,
    ];
    final selected = _roomName;
    if (selected != null && !_hasName(names, selected)) {
      names.insert(0, selected);
    }
    return [
      const DropdownMenuItem<String?>(value: null, child: Text('Не указан')),
      for (final name in names)
        DropdownMenuItem<String?>(value: name, child: Text(name)),
    ];
  }

  static bool _hasName(List<String> names, String name) {
    final key = normalizeCatalogName(name);
    for (final candidate in names) {
      if (normalizeCatalogName(candidate) == key) return true;
    }
    return false;
  }

  void _save() {
    if (_subjectName == null || _subjectName!.trim().isEmpty) {
      setState(() => _error = 'Укажите название предмета.');
      return;
    }
    if (_start == null) {
      setState(() => _error = 'Укажите время начала пары.');
      return;
    }
    if (widget.existing == null) {
      Navigator.of(context).pop(
        ScheduleLesson(
          id: 'lesson-${DateTime.now().microsecondsSinceEpoch}',
          weekday: _weekday,
          startMinutes: _start!,
          endMinutes: _end,
          subject: _subjectName!,
          teacher: _teacherName,
          room: _roomName,
        ),
      );
      return;
    }
    Navigator.of(context).pop(
      widget.existing!.copyWith(
        weekday: _weekday,
        startMinutes: _start,
        endMinutes: _end,
        clearEnd: _end == null,
        subject: _subjectName!,
        teacher: _teacherName ?? '',
        clearTeacher: _teacherName == null,
        room: _roomName ?? '',
        clearRoom: _roomName == null,
      ),
    );
  }

  InputDecoration _withSuffix(
    InputDecoration decoration, {
    required String tooltip,
    required VoidCallback onPressed,
  }) => decoration.copyWith(
    suffixIcon: IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    final startLabel = _start == null ? 'Начало' : formatMinutes(_start!);
    final endLabel = _end == null
        ? 'Конец (необязательно)'
        : formatMinutes(_end!);

    return AlertDialog(
      title: Text(widget.existing == null ? 'Новая пара' : 'Изменить пару'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _subjectName,
              autofocus: true,
              isExpanded: true,
              hint: const Text('Выберите предмет'),
              decoration: InputDecoration(
                labelText: 'Предмет',
                border: const OutlineInputBorder(),
                suffixIcon: catalog == null
                    ? null
                    : IconButton(
                        tooltip: 'Добавить предмет в базу',
                        onPressed: _addSubjectToCatalog,
                        icon: const Icon(
                          Icons.add_circle_outline_rounded,
                          size: 22,
                        ),
                      ),
              ),
              items: _subjectItems,
              onChanged: _onSubjectChanged,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _weekday,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'День недели',
                border: OutlineInputBorder(),
              ),
              items: [
                for (var day = 1; day <= 7; day++)
                  DropdownMenuItem(
                    value: day,
                    child: Text(weekdayFullName(day)),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _weekday = value ?? _weekday),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickStart,
                    child: Text(startLabel),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _pickEnd,
                    child: Text(endLabel, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _teacherName,
              isExpanded: true,
              decoration: catalog == null
                  ? const InputDecoration(
                      labelText: 'Преподаватель (необязательно)',
                      border: OutlineInputBorder(),
                    )
                  : _withSuffix(
                      const InputDecoration(
                        labelText: 'Преподаватель (необязательно)',
                        border: OutlineInputBorder(),
                      ),
                      tooltip: 'Добавить преподавателя в базу',
                      onPressed: _addTeacherToCatalog,
                    ),
              items: _teacherItems,
              onChanged: (value) => setState(() => _teacherName = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _roomName,
              isExpanded: true,
              decoration: catalog == null
                  ? const InputDecoration(
                      labelText: 'Кабинет (необязательно)',
                      border: OutlineInputBorder(),
                    )
                  : _withSuffix(
                      const InputDecoration(
                        labelText: 'Кабинет (необязательно)',
                        border: OutlineInputBorder(),
                      ),
                      tooltip: 'Добавить кабинет в базу',
                      onPressed: _addRoomToCatalog,
                    ),
              items: _roomItems,
              onChanged: (value) => setState(() => _roomName = value),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(onPressed: _save, child: const Text('Сохранить')),
      ],
    );
  }
}

/// Страница одного дня недели: список пар.
class _DayPage extends StatelessWidget {
  const _DayPage({
    super.key,
    required this.weekday,
    required this.isToday,
    required this.canMarkToday,
    required this.lessons,
    required this.schedule,
    required this.attendance,
    required this.notifications,
    required this.onPaste,
    required this.onAdd,
    this.catalog,
  });

  final int weekday;
  final bool isToday;

  /// Можно ли отметить пары этого дня: только сегодня и только в будни.
  final bool canMarkToday;
  final List<ScheduleLesson> lessons;
  final ScheduleController schedule;
  final AttendanceController? attendance;
  final NotificationController? notifications;
  final VoidCallback onPaste;
  final VoidCallback onAdd;
  final CatalogController? catalog;

  @override
  Widget build(BuildContext context) {
    if (lessons.isEmpty) return _EmptyDay(onPaste: onPaste, onAdd: onAdd);

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _DayHeader(weekday: weekday, isToday: isToday),
            const SizedBox(height: 12),
            if (isToday && !canMarkToday) ...[
              const _WeekendNotice(),
              const SizedBox(height: 12),
            ],
            for (var i = 0; i < lessons.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              _LessonCard(
                lesson: lessons[i],
                isToday: isToday,
                canMark: canMarkToday,
                schedule: schedule,
                catalog: catalog,
                attendance: attendance,
                notifications: notifications,
                onTap: canMarkToday
                    ? () => _openLesson(context, lessons[i])
                    : null,
              ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Добавить пару'),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onPaste,
              icon: const Icon(Icons.post_add_rounded),
              label: const Text('Вставить документ с расписанием'),
            ),
          ],
        ),
      ),
    );
  }

  void _openLesson(BuildContext context, ScheduleLesson lesson) {
    final attendance = this.attendance;
    if (attendance == null) return;
    // Пара открыта с сегодняшнего дня — отметки идут за сегодня.
    attendance.selectDate(dateOnly(DateTime.now()));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AttendanceScreen(
          attendance: attendance,
          schedule: schedule,
          lesson: lesson,
          notifications: notifications,
        ),
      ),
    );
  }
}

/// Подсказка на вкладке дня: сегодня выходной, отметки недоступны.
class _WeekendNotice extends StatelessWidget {
  const _WeekendNotice();

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
              'Сегодня выходной — отметки посещаемости недоступны.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Заголовок дня: «Понедельник · сегодня».
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.weekday, required this.isToday});

  final int weekday;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        Text(weekdayFullName(weekday), style: theme.textTheme.titleLarge),
        const SizedBox(width: 8),
        if (isToday)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              'сегодня',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onPrimaryContainer,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }
}

/// Карточка пары: время, предмет, кабинет и кнопка отметки.
class _LessonCard extends StatelessWidget {
  const _LessonCard({
    required this.lesson,
    required this.isToday,
    required this.canMark,
    required this.schedule,
    required this.attendance,
    required this.notifications,
    required this.onTap,
    this.catalog,
  });

  final ScheduleLesson lesson;
  final bool isToday;

  /// Показывать кнопку «Отметить»: только сегодня и только в будни.
  final bool canMark;
  final ScheduleController schedule;

  /// База для диалога изменения пары из меню карточки.
  final CatalogController? catalog;
  final AttendanceController? attendance;
  final NotificationController? notifications;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLight = scheme.brightness == Brightness.light;
    final session = attendance?.session;
    final markedToday = canMark && session != null
        ? session.markedCountInLesson(
            lessonKey: lesson.id,
            lessonTitle: lesson.subject,
          )
        : 0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : AppPalette.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLight ? AppPalette.line : AppPalette.lineDark,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 64,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lesson.startLabel,
                        style: theme.textTheme.titleMedium,
                      ),
                      if (lesson.endMinutes != null)
                        Text(
                          lesson.endLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lesson.subject,
                        style: theme.textTheme.titleMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (lesson.teacher != null) lesson.teacher!,
                          if (lesson.room != null) lesson.room!,
                          if (!isToday) weekdayFullName(lesson.weekday),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (canMark && attendance != null) ...[
                  const SizedBox(width: 8),
                  _MarkChip(
                    marked: markedToday,
                    lesson: lesson,
                    schedule: schedule,
                    attendance: attendance!,
                    notifications: notifications,
                  ),
                ],
                _LessonMenu(lesson: lesson, schedule: schedule, catalog: catalog),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Кнопка отметки на паре: показывает, сколько студентов отмечено.
class _MarkChip extends StatelessWidget {
  const _MarkChip({
    required this.marked,
    required this.lesson,
    required this.schedule,
    required this.attendance,
    required this.notifications,
  });

  final int marked;
  final ScheduleLesson lesson;
  final ScheduleController schedule;
  final AttendanceController attendance;
  final NotificationController? notifications;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = attendance.students.length;
    final allMarked = total > 0 && marked >= total;
    return FilledButton.tonalIcon(
      style: FilledButton.styleFrom(
        backgroundColor: marked > 0 && !allMarked
            ? scheme.primaryContainer
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        minimumSize: const Size(0, 36),
      ),
      onPressed: () {
        // Пара открыта с сегодняшнего дня — отметки идут за сегодня.
        attendance.selectDate(dateOnly(DateTime.now()));
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AttendanceScreen(
              attendance: attendance,
              schedule: schedule,
              lesson: lesson,
              notifications: notifications,
            ),
          ),
        );
      },
      icon: Icon(
        marked > 0 ? Icons.task_alt_rounded : Icons.how_to_reg_outlined,
        size: 18,
      ),
      label: Text(
        total == 0
            ? 'Отметить'
            : (marked == 0 ? 'Отметить' : '$marked из $total'),
        style: const TextStyle(fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Меню пары: изменить, удалить.
class _LessonMenu extends StatelessWidget {
  const _LessonMenu({
    required this.lesson,
    required this.schedule,
    this.catalog,
  });

  final ScheduleLesson lesson;
  final ScheduleController schedule;
  final CatalogController? catalog;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Действия',
      icon: Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onPressed: () async {
        final action = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Изменить'),
                  onTap: () => Navigator.of(sheetContext).pop('edit'),
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Удалить'),
                  onTap: () => Navigator.of(sheetContext).pop('delete'),
                ),
              ],
            ),
          ),
        );
        if (action == null || !context.mounted) return;
        if (action == 'delete') {
          schedule.remove(lesson.id);
        } else if (action == 'edit') {
          final updated = await showDialog<ScheduleLesson>(
            context: context,
            builder: (_) => _LessonDialog(
              catalog: catalog,
              weekday: lesson.weekday,
              existing: lesson,
            ),
          );
          if (updated == null || !context.mounted) return;
          schedule.update(updated);
        }
      },
    );
  }
}

/// Пустой день: предложение вставить документ или создать пары самому.
class _EmptyDay extends StatelessWidget {
  const _EmptyDay({required this.onPaste, required this.onAdd});

  final VoidCallback onPaste;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_note_rounded,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text('На этот день пар нет', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Вставьте готовый документ с расписанием или добавьте '
              'пары списком.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onPaste,
              icon: const Icon(Icons.post_add_rounded),
              label: const Text('Вставить документ'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Добавить пару'),
            ),
          ],
        ),
      ),
    );
  }
}
