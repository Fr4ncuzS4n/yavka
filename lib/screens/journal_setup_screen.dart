import 'package:flutter/material.dart';

import '../models/schedule_lesson.dart';
import '../services/cloud/cloud_exceptions.dart';
import '../services/cloud/cloud_sync_controller.dart';
import '../services/cloud/journal_check.dart';
import '../services/cloud/journal_mapping.dart';
import '../services/cloud/journal_month.dart';
import '../services/cloud/journal_sync_service.dart';
import '../services/cloud/sheets_api.dart';

/// Экран настройки журнала: приложение расспрашивает, где что находится
/// в существующей таблице, и проверяет её на целостность.
///
/// Приложение не меняет таблицу, а подстраивается под неё: месяц
/// подбирается из названия «МЕСЯЦ : ГОД», пары в дне — из расписания
/// приложения, а пользователь объясняет, где числа дней, колонка ФИО
/// и с какой строки начинаются студенты.
class JournalSetupScreen extends StatefulWidget {
  const JournalSetupScreen({super.key, required this.cloud});

  final CloudSyncController cloud;

  @override
  State<JournalSetupScreen> createState() => _JournalSetupScreenState();
}

class _JournalSetupScreenState extends State<JournalSetupScreen> {
  final _dayRowController = TextEditingController();
  final _fioColumnController = TextEditingController();
  final _firstStudentRowController = TextEditingController();
  final _pairRowController = TextEditingController();
  final _lastStudentRowController = TextEditingController();

  List<SheetTab> _tabs = const [];
  String? _tabTitle;
  JournalSnapshot? _preview;
  String? _error;
  bool _loading = true;
  bool _checking = false;

  CloudSyncController get _cloud => widget.cloud;

  @override
  void initState() {
    super.initState();
    _fillFromMapping();
    _loadTabs();
  }

  @override
  void dispose() {
    _dayRowController.dispose();
    _fioColumnController.dispose();
    _firstStudentRowController.dispose();
    _pairRowController.dispose();
    _lastStudentRowController.dispose();
    super.dispose();
  }

  void _fillFromMapping() {
    final mapping = _cloud.journalMapping;
    final dayRow = mapping?.dayRow ?? 1;
    _dayRowController.text = '${dayRow + 1}';
    _fioColumnController.text = mapping == null
        ? 'B'
        : JournalMapping.columnLetter(mapping.fioColumn);
    _firstStudentRowController.text =
        '${(mapping?.firstStudentRow ?? 3) + 1}';
    // Строка пар обычно сразу под числами дней.
    _pairRowController.text = '${(mapping?.pairRow ?? dayRow + 1) + 1}';
    final lastStudentRow = mapping?.lastStudentRow;
    _lastStudentRowController.text = lastStudentRow == null
        ? ''
        : '${lastStudentRow + 1}';
  }

  Future<void> _loadTabs() async {
    try {
      final tabs = await _cloud.fetchTabs();
      if (!mounted) return;
      setState(() {
        _tabs = tabs;
        final mapping = _cloud.journalMapping;
        _tabTitle = _pickTabTitle(
          tabs.map((tab) => tab.title).toList(),
          mapping?.tabTitle,
        );
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _message(error);
        _loading = false;
      });
    }
  }

  /// Лист по умолчанию: сохранённый, затем лист с месяцем в названии,
  /// затем первый.
  String? _pickTabTitle(List<String> titles, String? saved) {
    if (saved != null && titles.any((title) => title == saved)) return saved;
    final now = DateTime.now();
    for (final title in titles) {
      final month = JournalMonth.parseTitle(title);
      if (month != null &&
          month.year == now.year &&
          month.month == now.month) {
        return title;
      }
    }
    return titles.isEmpty ? null : titles.first;
  }

  Future<void> _check() async {
    final draft = _draft();
    if (draft == null) return;
    setState(() {
      _checking = true;
      _error = null;
      _preview = null;
    });
    try {
      final snapshot = await _cloud.previewJournal(
        tabTitle: draft.tabTitle,
        dayRow: draft.dayRow,
        fioColumn: draft.fioColumn,
        firstStudentRow: draft.firstStudentRow,
        pairRow: draft.pairRow,
        lastStudentRow: draft.lastStudentRow,
      );
      if (!mounted) return;
      setState(() {
        _preview = snapshot;
        _checking = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = _message(error);
        _checking = false;
      });
    }
  }

  ({
    String tabTitle,
    int dayRow,
    int fioColumn,
    int firstStudentRow,
    int pairRow,
    int? lastStudentRow,
  })? _draft() {
    final tabTitle = _tabTitle;
    final dayRow = int.tryParse(_dayRowController.text.trim());
    final fioColumn = JournalMapping.parseColumnLetter(
      _fioColumnController.text,
    );
    final firstStudentRow = int.tryParse(
      _firstStudentRowController.text.trim(),
    );
    final pairRow = int.tryParse(_pairRowController.text.trim());
    final lastStudentText = _lastStudentRowController.text.trim();
    final lastStudentRow = lastStudentText.isEmpty
        ? null
        : int.tryParse(lastStudentText);
    if (tabTitle == null ||
        dayRow == null ||
        dayRow < 1 ||
        fioColumn == null ||
        firstStudentRow == null ||
        firstStudentRow < 1 ||
        pairRow == null ||
        pairRow < 1 ||
        (lastStudentRow != null && lastStudentRow < 1)) {
      setState(() {
        _error = 'Заполните поля: лист, строку чисел, колонку ФИО, '
            'строку первого студента и строку с номерами пар; '
            'конечную строку ФИО можно оставить пустой.';
      });
      return null;
    }
    if (pairRow <= dayRow) {
      setState(() {
        _error = 'Строка с номерами пар должна быть ниже строки с числами '
            'дней: под числами идут номера пар.';
      });
      return null;
    }
    if (lastStudentRow != null && lastStudentRow < firstStudentRow) {
      setState(() {
        _error = 'Конечная строка ФИО не может быть выше строки первого '
            'студента.';
      });
      return null;
    }
    return (
      tabTitle: tabTitle,
      // Пользователь считает строки и колонки с единицы, внутри — с нуля.
      dayRow: dayRow - 1,
      fioColumn: fioColumn,
      firstStudentRow: firstStudentRow - 1,
      pairRow: pairRow - 1,
      lastStudentRow: lastStudentRow == null ? null : lastStudentRow - 1,
    );
  }

  Future<void> _save() async {
    final draft = _draft();
    final preview = _preview;
    if (draft == null || preview == null) return;
    if (preview.month == null || !preview.check.ok) return;

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    await _cloud.saveJournalMapping(
      JournalMapping(
        tabTitle: draft.tabTitle,
        dayRow: draft.dayRow,
        fioColumn: draft.fioColumn,
        firstStudentRow: draft.firstStudentRow,
        pairRow: draft.pairRow,
        lastStudentRow: draft.lastStudentRow,
      ),
    );
    final error = _cloud.error;
    final isError = error != null;
    messenger.showSnackBar(
      SnackBar(
        content: Text(error ?? 'Журнал настроен'),
        backgroundColor: isError
            ? const Color(0xFFB3261E)
            : null,
      ),
    );
    if (error == null) navigator.pop();
  }

  String _message(Object error) => switch (error) {
    final CloudSyncException exception => exception.message,
    _ => 'Не получилось: $error',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Настройка журнала')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  'Приложение ничего не меняет в таблице, а подстраивается '
                  'под неё. Ответьте на вопросы — и оно само найдёт, '
                  'куда ставить отметки.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                _Section(
                  title: 'Журнал',
                  children: [
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(),
                      )
                    else if (_tabs.isEmpty)
                      Text(
                        _error ?? 'В таблице нет ни одного листа.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      )
                    else ...[
                      DropdownButtonFormField<String>(
                        initialValue: _tabTitle,
                        decoration: const InputDecoration(
                          labelText: 'Лист журнала',
                          helperText: 'Например «НОЯБРЬ : 2026» — месяц '
                              'подбирается из названия',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final tab in _tabs)
                            DropdownMenuItem(
                              value: tab.title,
                              child: Text(tab.title),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          _tabTitle = value;
                          _preview = null;
                        }),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                _Section(
                  title: 'Где что находится',
                  children: [
                    TextField(
                      controller: _dayRowController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Строка с числами дней',
                        helperText: 'Строка, где идут числа 1, 2, 3…',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _fioColumnController,
                      decoration: const InputDecoration(
                        labelText: 'Колонка ФИО',
                        helperText: 'Буква колонки, например B',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _firstStudentRowController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Строка первого студента',
                        helperText: 'Первая строка со списком группы',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _pairRowController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Строка с номерами пар',
                        helperText: 'Строка «ПАРА», где под числами дней '
                            'идут номера пар (1, 2, 3…)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _lastStudentRowController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Конечная строка ФИО',
                        helperText: 'Последняя строка списка группы; '
                            'пусто — до конца листа',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _checking || _loading ? null : _check,
                  icon: const Icon(Icons.search_rounded),
                  label: Text(_checking ? 'Проверяю…' : 'Проверить журнал'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                if (_preview != null) ...[
                  const SizedBox(height: 16),
                  _PreviewCard(snapshot: _preview!),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed:
                        _preview!.month != null && _preview!.check.ok
                        ? _save
                        : null,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Сохранить настройку'),
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

/// Что нашлось при проверке: месяц, дни с колонками и проблемы.
class _PreviewCard extends StatelessWidget {
  const _PreviewCard({required this.snapshot});

  final JournalSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF1C1D22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Что нашлось', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            snapshot.month == null
                ? 'Месяц: не определён — назовите таблицу или лист '
                      '«МЕСЯЦ : ГОД», например «Ноябрь : 2026».'
                : 'Месяц: ${JournalMonth.displayName(snapshot.month!)} '
                      '(из названия таблицы).',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          for (final row in snapshot.check.rows) ...[
            _DayRow(row: row),
            const SizedBox(height: 4),
          ],
          if (snapshot.check.rows.isEmpty)
            Text(
              'Дней с парами не нашлось: заполните расписание в приложении '
              'и проверьте снова. Отметки на весь день разложатся по всем '
              'колонкам пар дня даже без расписания.',
              style: theme.textTheme.bodyMedium,
            ),
          if (snapshot.check.issues.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final issue in snapshot.check.issues)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  issue.message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ),
          ],
          if (snapshot.check.ok && snapshot.month != null) ...[
            const SizedBox(height: 8),
            Text(
              'Таблица сходится с расписанием. Отметки будут ставиться '
              'цветом в колонки пар; отметка на весь день разложится на '
              'все пары дня, при опоздании пишется ещё и время.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.row});

  final JournalCheckRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fits = row.pairCount <= row.columnCount;
    return Row(
      children: [
        SizedBox(
          width: 108,
          child: Text(
            '${row.date.day} ${_weekdayShort(row.date)}',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        Expanded(
          child: Text(
            'колонки ${row.columnRange}, пар: ${row.pairCount}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Icon(
          fits ? Icons.check_circle_outline_rounded : Icons.error_outline,
          size: 18,
          color: fits ? scheme.primary : scheme.error,
        ),
      ],
    );
  }

  String _weekdayShort(DateTime date) =>
      weekdayShortName(weekdayOf(date));
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : const Color(0xFF1C1D22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}
