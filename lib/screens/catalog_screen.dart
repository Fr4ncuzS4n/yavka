import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;

import '../data/catalog_controller.dart';
import '../models/catalog.dart';

/// Имя файла экспорта базы.
const _kExportFileName = 'yavka-baza.json';

/// Экран локальной базы: преподаватели, предметы и кабинеты.
///
/// Отсюда записи попадают в селекты диалога пары на вкладке
/// «Расписание». База переносится файлом: экспорт и импорт JSON
/// (формат — см. [CatalogData.toJson]).
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key, required this.catalog});

  final CatalogController catalog;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  CatalogController get _catalog => widget.catalog;

  void _notify(String message, {bool isError = false}) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? scheme.error : null,
      ),
    );
  }

  // --- Преподаватели ---

  Future<void> _addTeacher() => _editTeacherDialog(null);

  Future<void> _editTeacherDialog(Teacher? existing) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => CatalogNameDialog(
        title: existing == null
            ? 'Новый преподаватель'
            : 'Изменить преподавателя',
        actionLabel: 'Сохранить',
        initial: existing?.name,
      ),
    );
    if (name == null) return;
    if (existing == null) {
      // Повторное имя не создаёт дубликат — совмещается с имеющимся.
      _catalog.addTeacher(name);
      return;
    }
    if (!_catalog.updateTeacher(existing.id, name)) {
      _notify('Такой преподаватель уже есть.', isError: true);
    }
  }

  Future<void> _removeTeacher(Teacher teacher) async {
    if (!await _confirmRemove(
      'Удалить преподавателя?',
      '«${teacher.name}» исчезнет из селектов. Предметы останутся, '
      'но без преподавателя.',
    )) {
      return;
    }
    final cleared = _catalog.removeTeacher(teacher.id);
    _notify(
      cleared > 0
          ? 'Преподаватель удалён. Предметов без него: $cleared.'
          : 'Преподаватель удалён.',
    );
  }

  // --- Кабинеты ---

  Future<void> _addRoom() => _editRoomDialog(null);

  Future<void> _editRoomDialog(Room? existing) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => CatalogNameDialog(
        title: existing == null ? 'Новый кабинет' : 'Изменить кабинет',
        actionLabel: 'Сохранить',
        initial: existing?.name,
      ),
    );
    if (name == null) return;
    if (existing == null) {
      _catalog.addRoom(name);
      return;
    }
    if (!_catalog.updateRoom(existing.id, name)) {
      _notify('Такой кабинет уже есть.', isError: true);
    }
  }

  Future<void> _removeRoom(Room room) async {
    if (!await _confirmRemove(
      'Удалить кабинет?',
      '«${room.name}» исчезнет из селектов. Предметы останутся, '
      'но без кабинета.',
    )) {
      return;
    }
    final cleared = _catalog.removeRoom(room.id);
    _notify(
      cleared > 0
          ? 'Кабинет удалён. Предметов без него: $cleared.'
          : 'Кабинет удалён.',
    );
  }

  // --- Предметы ---

  Future<void> _addSubject() => _editSubjectDialog(null);

  Future<void> _editSubjectDialog(Subject? existing) async {
    // Список обновится сам: экран слушает контроллер базы.
    await showDialog<Subject>(
      context: context,
      builder: (_) =>
          SubjectEditDialog(catalog: _catalog, existing: existing),
    );
  }

  Future<void> _removeSubject(Subject subject) async {
    if (!await _confirmRemove(
      'Удалить предмет?',
      '«${subject.name}» исчезнет из селектов. Пары в расписании '
      'останутся, но предмет придёт в них выбирать заново.',
    )) {
      return;
    }
    _catalog.removeSubject(subject.id);
    _notify('Предмет удалён.');
  }

  // --- Экспорт и импорт ---

  /// Экспорт базы в JSON-файл. На web файл сразу скачивается браузером,
  /// на десктопе и Android — открывается диалог сохранения.
  Future<void> _export() async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final json = _catalog.exportJson();
    final bytes = utf8.encode(json);
    try {
      if (kIsWeb) {
        await XFile.fromData(
          bytes,
          mimeType: 'application/json',
        ).saveTo(_kExportFileName);
      } else {
        final location = await getSaveLocation(
          suggestedName: _kExportFileName,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'JSON', extensions: ['json']),
          ],
        );
        if (location == null) return; // сохранение отменено
        await XFile.fromData(
          bytes,
          mimeType: 'application/json',
        ).saveTo(location.path);
      }
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(_filePickerErrorText(error)),
          backgroundColor: errorColor,
        ),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text('База сохранена в файл $_kExportFileName')),
    );
  }

  /// Импорт базы из JSON-файла: записи совмещаются по именам,
  /// дубликаты не создаются.
  Future<void> _import() async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final XFile? file;
    try {
      file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON', extensions: ['json']),
        ],
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(_filePickerErrorText(error)),
          backgroundColor: errorColor,
        ),
      );
      return;
    }
    if (file == null) return; // выбор файла отменён

    try {
      final report = _catalog.importJson(await file.readAsString());
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            report.hasChanges
                ? report.message
                : 'В базе уже есть все записи из файла.',
          ),
        ),
      );
    } on FormatException catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: errorColor,
        ),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Не удалось прочитать файл: $error'),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  /// Текст ошибки выбора файла: у channel-error и missing-plugin
  /// причина одна — бинарник собран до добавления плагина.
  String _filePickerErrorText(Object error) {
    if (error is PlatformException &&
        (error.code == 'channel-error' || error.code == 'missing-plugin')) {
      return 'Выбор файла не встроен в запущенную сборку. Полностью '
          'остановите приложение и запустите заново (flutter run) — '
          'native-часть плагина подключается при сборке.';
    }
    return 'Не удалось открыть выбор файла: $error';
  }

  Future<bool> _confirmRemove(String title, String text) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('База данных'),
        actions: [
          IconButton(
            tooltip: 'Импорт базы из файла',
            onPressed: _import,
            icon: const Icon(Icons.upload_file_rounded),
          ),
          IconButton(
            tooltip: 'Экспорт базы в файл',
            onPressed: _export,
            icon: const Icon(Icons.save_alt_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListenableBuilder(
              listenable: _catalog,
              builder: (context, _) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    const Text(
                      'Записи отсюда выбираются селектами при создании '
                      'пары во вкладке «Расписание».',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    _SectionHeader(
                      title: 'Преподаватели',
                      addTooltip: 'Добавить преподавателя',
                      onAdd: _addTeacher,
                    ),
                    for (final teacher in _catalog.teachers) ...[
                      _EntryTile(
                        title: teacher.name,
                        onEdit: () => _editTeacherDialog(teacher),
                        onRemove: () => _removeTeacher(teacher),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (_catalog.teachers.isEmpty)
                      const _EmptyHint(
                        'Преподавателей пока нет — добавьте здесь или '
                        'прямо в диалоге пары.',
                      ),
                    const SizedBox(height: 16),
                    _SectionHeader(
                      title: 'Предметы',
                      addTooltip: 'Добавить предмет',
                      onAdd: _addSubject,
                    ),
                    for (final subject in _catalog.subjects) ...[
                      _EntryTile(
                        title: subject.name,
                        subtitle: _subjectSubtitle(subject),
                        onEdit: () => _editSubjectDialog(subject),
                        onRemove: () => _removeSubject(subject),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (_catalog.subjects.isEmpty)
                      const _EmptyHint(
                        'Предметов пока нет — добавьте здесь или прямо '
                        'в диалоге пары.',
                      ),
                    const SizedBox(height: 16),
                    _SectionHeader(
                      title: 'Кабинеты',
                      addTooltip: 'Добавить кабинет',
                      onAdd: _addRoom,
                    ),
                    for (final room in _catalog.rooms) ...[
                      _EntryTile(
                        title: room.name,
                        onEdit: () => _editRoomDialog(room),
                        onRemove: () => _removeRoom(room),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (_catalog.rooms.isEmpty)
                      const _EmptyHint(
                        'Кабинетов пока нет — добавьте здесь или прямо '
                        'в диалоге пары.',
                      ),
                    const SizedBox(height: 16),
                    Text(
                      'Экспорт сохраняет всю базу в JSON-файл, импорт '
                      'совмещает его с тем, что уже есть: дубликаты по '
                      'именам не создаются.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Подпись предмета в списке: преподаватель и кабинет.
  String? _subjectSubtitle(Subject subject) {
    final teacher = _catalog.teacherById(subject.teacherId)?.name;
    final room = _catalog.roomById(subject.roomId)?.name;
    final parts = [
      if (teacher != null && teacher.isNotEmpty) teacher,
      if (room != null && room.isNotEmpty) room,
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// Заголовок раздела базы с кнопкой добавления.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.addTooltip,
    required this.onAdd,
  });

  final String title;
  final String addTooltip;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          IconButton(
            tooltip: addTooltip,
            onPressed: onAdd,
            icon: Icon(Icons.add_rounded, color: scheme.primary),
          ),
        ],
      ),
    );
  }
}

/// Строка записи: название, подпись и кнопки изменения и удаления.
class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.title,
    required this.onEdit,
    required this.onRemove,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        title: Text(title),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Изменить',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined, size: 20),
            ),
            IconButton(
              tooltip: 'Удалить',
              onPressed: onRemove,
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Подсказка под пустым разделом.
class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Диалог ввода названия — новый преподаватель или кабинет.
class CatalogNameDialog extends StatefulWidget {
  const CatalogNameDialog({
    super.key,
    required this.title,
    required this.actionLabel,
    this.initial,
  });

  final String title;
  final String actionLabel;
  final String? initial;

  @override
  State<CatalogNameDialog> createState() => _CatalogNameDialogState();
}

class _CatalogNameDialogState extends State<CatalogNameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final ready = _controller.text.trim().isNotEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _controller,
          autofocus: true,
          onChanged: (_) => setState(() {}),
          onSubmitted: ready ? (_) => _save() : null,
          decoration: const InputDecoration(
            labelText: 'Название',
            border: OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: ready ? _save : null,
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}

/// Диалог добавления и изменения предмета: название плюс селекты
/// преподавателя и кабинета из базы.
class SubjectEditDialog extends StatefulWidget {
  const SubjectEditDialog({super.key, required this.catalog, this.existing});

  final CatalogController catalog;
  final Subject? existing;

  @override
  State<SubjectEditDialog> createState() => _SubjectEditDialogState();
}

class _SubjectEditDialogState extends State<SubjectEditDialog> {
  late final TextEditingController _name;
  String? _teacherId;
  String? _roomId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _teacherId = widget.existing?.teacherId;
    _roomId = widget.existing?.roomId;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Укажите название предмета.');
      return;
    }
    final existing = widget.existing;
    final clash = widget.catalog.subjectByName(name);
    if (clash != null && clash.id != existing?.id) {
      setState(() => _error = 'Такой предмет уже есть.');
      return;
    }
    final Subject saved;
    if (existing == null) {
      saved = widget.catalog.addSubject(
        name,
        teacherId: _teacherId,
        roomId: _roomId,
      );
    } else {
      final ok = widget.catalog.updateSubject(
        existing.id,
        name: name,
        teacherId: _teacherId,
        roomId: _roomId,
      );
      if (!ok) {
        setState(() => _error = 'Не удалось сохранить предмет.');
        return;
      }
      saved = widget.catalog.subjectById(existing.id)!;
    }
    Navigator.of(context).pop(saved);
  }

  @override
  Widget build(BuildContext context) {
    final teachers = widget.catalog.teachers;
    final rooms = widget.catalog.rooms;
    return AlertDialog(
      title: Text(widget.existing == null ? 'Новый предмет' : 'Изменить предмет'),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Название предмета',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _teacherId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Преподаватель (необязательно)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Не указан'),
                ),
                for (final teacher in teachers)
                  DropdownMenuItem<String?>(
                    value: teacher.id,
                    child: Text(teacher.name),
                  ),
              ],
              onChanged: (value) => setState(() => _teacherId = value),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _roomId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Кабинет (необязательно)',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Не указан'),
                ),
                for (final room in rooms)
                  DropdownMenuItem<String?>(
                    value: room.id,
                    child: Text(room.name),
                  ),
              ],
              onChanged: (value) => setState(() => _roomId = value),
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
