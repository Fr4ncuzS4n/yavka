import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/cloud/cloud_sync_controller.dart';
import '../services/cloud/journal_mapping.dart';
import '../services/cloud/journal_month.dart';
import 'journal_setup_screen.dart';
import '../theme/app_theme.dart';

/// Экран подключения Google Диска и синхронизации посещаемости.
///
/// Приложение подстраивается под существующий журнал и не меняет его:
/// пишутся только отметки в ячейки пар. Месяц подбирается из названия
/// таблицы «МЕСЯЦ : ГОД», поэтому новый месяц — просто новая ссылка.
class CloudSyncScreen extends StatefulWidget {
  const CloudSyncScreen({super.key, required this.cloud});

  final CloudSyncController cloud;

  @override
  State<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends State<CloudSyncScreen> {
  final _linkController = TextEditingController();
  final _clientIdController = TextEditingController();
  final _clientSecretController = TextEditingController();
  final _webClientIdController = TextEditingController();
  final _displayNameController = TextEditingController();

  CloudSyncController get _cloud => widget.cloud;

  @override
  void initState() {
    super.initState();
    _fillFromSettings();
    _cloud.addListener(_onCloudChanged);
  }

  @override
  void dispose() {
    _cloud.removeListener(_onCloudChanged);
    _linkController.dispose();
    _clientIdController.dispose();
    _clientSecretController.dispose();
    _webClientIdController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  void _onCloudChanged() {
    if (!mounted) return;
    // Настройки могли загрузиться уже после открытия экрана.
    if (_clientIdController.text.isEmpty &&
        _clientSecretController.text.isEmpty &&
        _webClientIdController.text.isEmpty) {
      _fillFromSettings();
    }
    setState(() {});
  }

  void _fillFromSettings() {
    final settings = _cloud.settings;
    _linkController.text = settings.spreadsheetId ?? '';
    _clientIdController.text = settings.clientId ?? '';
    _clientSecretController.text = settings.clientSecret ?? '';
    _webClientIdController.text = settings.webClientId ?? '';
    _displayNameController.text = settings.displayName;
  }

  Future<void> _runAction(Future<void> Function() action) async {
    await action();
    if (!mounted) return;
    final error = _cloud.error;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(error ?? 'Готово'),
        backgroundColor: error == null
            ? null
            : Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _openSpreadsheet() async {
    final url = _cloud.spreadsheetUrl;
    if (url.isEmpty) return;
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть ссылку: $url')),
      );
    }
  }

  Future<void> _openJournalSetup() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => JournalSetupScreen(cloud: _cloud),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _saveOAuthConfig() async {
    await _cloud.saveOAuthConfig(
      clientId: _clientIdController.text.trim(),
      clientSecret: _clientSecretController.text.trim(),
      webClientId: _webClientIdController.text.trim(),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Настройки OAuth сохранены')));
  }

  @override
  Widget build(BuildContext context) {
    final cloud = _cloud;
    return Scaffold(
      appBar: AppBar(title: const Text('Google Диск')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _StatusCard(cloud: cloud),
                const SizedBox(height: 12),
                if (cloud.isConfigured) ...[
                  _JournalCard(
                    cloud: cloud,
                    onSetup: _openJournalSetup,
                    onReset: cloud.isBusy
                        ? null
                        : () => _runAction(cloud.resetJournalMapping),
                  ),
                  const SizedBox(height: 12),
                ],
                _SectionCard(
                  title: 'Аккаунт Google',
                  children: [
                    if (cloud.isSignedIn)
                      _SignedInAccount(
                        onSignOut: cloud.isBusy
                            ? null
                            : () => _runAction(cloud.signOut),
                      )
                    else ...[
                      const Text(
                        'Войдите в аккаунт, у которого есть доступ к таблице '
                        'посещаемости. Достаточно прав «Редактор».',
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: cloud.isBusy
                            ? null
                            : () => _runAction(cloud.signIn),
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('Войти через Google'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Таблица посещаемости',
                  children: [
                    if (cloud.isConfigured)
                      _ConnectedSpreadsheet(
                        cloud: cloud,
                        onOpen: _openSpreadsheet,
                        onDisconnect: cloud.isBusy
                            ? null
                            : () => _runAction(cloud.disconnectSpreadsheet),
                      )
                    else ...[
                      const Text(
                        'Вставьте ссылку на Google Таблицу с готовым '
                        'журналом. Если таблица принадлежит другому '
                        'человеку, попросите у него доступ «Редактор». '
                        'Новый месяц — новая ссылка, месяц подбирается '
                        'из названия «МЕСЯЦ : ГОД».',
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _linkController,
                        decoration: const InputDecoration(
                          labelText: 'Ссылка на таблицу или её ID',
                          hintText:
                              'https://docs.google.com/spreadsheets/d/…/edit',
                          border: OutlineInputBorder(),
                        ),
                        minLines: 1,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: cloud.isBusy
                            ? null
                            : () => _runAction(
                                () => cloud.connectSpreadsheet(
                                  _linkController.text,
                                ),
                              ),
                        icon: const Icon(Icons.link_rounded),
                        label: const Text('Подключить'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    const _Note(
                      icon: Icons.verified_user_outlined,
                      text:
                          'Приложение не меняет таблицу: не рисует шапки, '
                          'не объединяет ячейки и не создаёт листы. Оно '
                          'только отмечает ячейки пар цветом, поэтому '
                          'подходит и со-владельцу (редактору).',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Синхронизация',
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Автосохранение'),
                      subtitle: const Text(
                        'Отправлять отметки в таблицу через пару секунд '
                        'после изменения.',
                      ),
                      value: cloud.autoSync,
                      onChanged: cloud.setAutoSync,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      cloud.lastSyncAt == null
                          ? 'Ещё не синхронизировалось'
                          : 'Последняя синхронизация: '
                                '${_formatDateTime(cloud.lastSyncAt!)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (cloud.hasPendingChanges) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Есть несохранённые изменения',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _displayNameController,
                      decoration: const InputDecoration(
                        labelText: 'Ваше имя (для уведомлений)',
                        hintText: 'Иван Петров',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await _cloud.setDisplayName(
                            _displayNameController.text,
                          );
                          if (!mounted) return;
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('Имя сохранено'),
                            ),
                          );
                        },
                        child: const Text('Сохранить имя'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: cloud.isBusy || !cloud.isConfigured
                              ? null
                              : () => _runAction(cloud.syncNow),
                          icon: const Icon(Icons.cloud_upload_outlined),
                          label: const Text('Отправить'),
                        ),
                        OutlinedButton.icon(
                          onPressed: cloud.isBusy || !cloud.isConfigured
                              ? null
                              : () => _runAction(cloud.pullNow),
                          icon: const Icon(Icons.cloud_download_outlined),
                          label: const Text('Загрузить'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Уведомления',
                  children: [
                    const Text(
                      'Когда вы отмечаете студентов на паре из расписания, '
                      'уведомление появляется в колокольчике на этом '
                      'устройстве.',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _OAuthConfigCard(
                  cloud: cloud,
                  clientIdController: _clientIdController,
                  clientSecretController: _clientSecretController,
                  webClientIdController: _webClientIdController,
                  onSave: _saveOAuthConfig,
                ),
                const SizedBox(height: 16),
                Text(
                  'Google Таблица хранится на Google Диске. Приложение '
                  'использует только доступ к Google Таблицам.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

/// Карточка настройки журнала: где числа, ФИО и пары.
class _JournalCard extends StatelessWidget {
  const _JournalCard({
    required this.cloud,
    required this.onSetup,
    required this.onReset,
  });

  final CloudSyncController cloud;
  final VoidCallback onSetup;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mapping = cloud.journalMapping;
    final month = cloud.journalMonth;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.light
            ? Colors.white
            : AppPalette.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.brightness == Brightness.light
              ? AppPalette.line
              : AppPalette.lineDark,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                mapping == null
                    ? Icons.tune_rounded
                    : Icons.check_circle_rounded,
                color: mapping == null ? scheme.tertiary : scheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  mapping == null
                      ? 'Журнал не настроен'
                      : 'Журнал настроен: лист «${mapping.tabTitle}»',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            mapping == null
                ? 'Объясните приложению, где в таблице числа дней, ФИО '
                      'и пары, — и оно само подстроится под ваш журнал.'
                : 'Числа дней: строка ${(mapping.dayRow + 1)}, ФИО: колонка '
                      '${JournalMapping.columnLetter(mapping.fioColumn)}, '
                      'студенты: со строки '
                      '${(mapping.firstStudentRow + 1)}.'
                      '${month == null ? '' : ' Месяц: ${JournalMonth.displayName(month)}.'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: cloud.isBusy ? null : onSetup,
                icon: const Icon(Icons.tune_rounded),
                label: Text(
                  mapping == null ? 'Настроить журнал' : 'Изменить настройку',
                ),
              ),
              if (mapping != null)
                TextButton(onPressed: onReset, child: const Text('Сбросить')),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.cloud});

  final CloudSyncController cloud;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final IconData icon;
    final String title;
    Color color = scheme.primary;

    if (!cloud.isConfigured) {
      icon = Icons.cloud_off_outlined;
      title = 'Google Диск не подключён';
      color = scheme.onSurfaceVariant;
    } else if (!cloud.isSignedIn) {
      icon = Icons.login_rounded;
      title = 'Нужно войти в Google';
      color = scheme.tertiary;
    } else if (cloud.needsJournalSetup) {
      icon = Icons.tune_rounded;
      title = 'Настройте журнал';
      color = scheme.tertiary;
    } else if (cloud.isBusy) {
      icon = Icons.sync_rounded;
      title = 'Синхронизация…';
    } else if (cloud.error != null) {
      icon = Icons.error_outline_rounded;
      title = 'Ошибка синхронизации';
      color = scheme.error;
    } else if (cloud.hasPendingChanges) {
      icon = Icons.cloud_upload_outlined;
      title = 'Есть несохранённые отметки';
      color = scheme.tertiary;
    } else {
      icon = Icons.cloud_done_outlined;
      title = 'Синхронизация включена';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  cloud.error ??
                      (cloud.isConfigured
                          ? 'Таблица: ${cloud.spreadsheetId}'
                          : 'Подключите таблицу, чтобы отметки сохранялись '
                                'на Google Диске.'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignedInAccount extends StatelessWidget {
  const _SignedInAccount({required this.onSignOut});

  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.check_circle_rounded, color: scheme.primary),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'Аккаунт Google подключён. Токен хранится на устройстве.',
          ),
        ),
        TextButton(onPressed: onSignOut, child: const Text('Выйти')),
      ],
    );
  }
}

class _ConnectedSpreadsheet extends StatelessWidget {
  const _ConnectedSpreadsheet({
    required this.cloud,
    required this.onOpen,
    required this.onDisconnect,
  });

  final CloudSyncController cloud;
  final VoidCallback onOpen;
  final VoidCallback? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.table_chart_outlined, color: scheme.primary),
            const SizedBox(width: 10),
            const Expanded(child: Text('Таблица подключена')),
          ],
        ),
        const SizedBox(height: 8),
        SelectableText(
          cloud.spreadsheetId ?? '',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Открыть в Google Таблицах'),
            ),
            TextButton(onPressed: onDisconnect, child: const Text('Отключить')),
          ],
        ),
      ],
    );
  }
}

class _OAuthConfigCard extends StatelessWidget {
  const _OAuthConfigCard({
    required this.cloud,
    required this.clientIdController,
    required this.clientSecretController,
    required this.webClientIdController,
    required this.onSave,
  });

  final CloudSyncController cloud;
  final TextEditingController clientIdController;
  final TextEditingController clientSecretController;
  final TextEditingController webClientIdController;
  final Future<void> Function() onSave;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).brightness == Brightness.light
              ? AppPalette.line
              : AppPalette.lineDark,
        ),
      ),
      child: ExpansionTile(
        initiallyExpanded: !cloud.auth.isConfigured,
        shape: const Border(),
        collapsedShape: const Border(),
        title: const Text('Настройки OAuth'),
        subtitle: Text(
          cloud.auth.isConfigured
              ? 'OAuth-клиент настроен'
              : 'Нужен Client ID из Google Cloud Console',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Создайте OAuth-клиент в Google Cloud Console, включите Google '
            'Sheets API. Для Android/iOS/Linux/Windows подойдёт тип '
            '«Desktop app»; для web — «Web application». Значения можно '
            'также задать при сборке через --dart-define.',
          ),
          const SizedBox(height: 12),
          if (cloud.isWeb)
            TextField(
              controller: webClientIdController,
              decoration: const InputDecoration(
                labelText: 'Web Client ID',
                border: OutlineInputBorder(),
              ),
            )
          else ...[
            TextField(
              controller: clientIdController,
              decoration: const InputDecoration(
                labelText: 'Client ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: clientSecretController,
              decoration: const InputDecoration(
                labelText: 'Client Secret',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: onSave,
              child: const Text('Сохранить настройки OAuth'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isLight ? Colors.white : AppPalette.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLight ? AppPalette.line : AppPalette.lineDark,
        ),
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

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(value.day)}.${two(value.month)}.${value.year} '
      '${two(value.hour)}:${two(value.minute)}';
}
