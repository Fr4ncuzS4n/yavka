import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/cloud/cloud_sync_controller.dart';
import '../services/cloud/month_grid_codec.dart';
import '../theme/app_theme.dart';

/// Экран подключения Google Диска и синхронизации посещаемости.
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
                  _MonthCard(
                    cloud: cloud,
                    onMonthSelected: (month) => _runAction(
                      () => cloud.selectMonth(month),
                    ),
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
                        'Вставьте ссылку на существующую Google Таблицу или '
                        'создайте новую. Если таблица принадлежит другому '
                        'человеку, попросите у него доступ «Редактор».',
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
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
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
                          OutlinedButton.icon(
                            onPressed: cloud.isBusy
                                ? null
                                : () => _runAction(cloud.createSpreadsheet),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Создать таблицу'),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    const _Note(
                      icon: Icons.verified_user_outlined,
                      text:
                          'Приложение не меняет права доступа и не удаляет '
                          'таблицу. Оно только читает и записывает строки '
                          'посещаемости, поэтому подходит и для со-владельца '
                          '(редактора).',
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

/// Выбор месяца журнала.
///
/// Отметка пишется в лист того месяца, к которому относится день
/// посещаемости; обычно это текущий месяц. Выпадающим списком можно
/// переключиться на другой лист (например, чтобы отметить задним числом
/// на листе прошлого месяца).
class _MonthCard extends StatelessWidget {
  const _MonthCard({required this.cloud, required this.onMonthSelected});

  final CloudSyncController cloud;
  final void Function(DateTime month) onMonthSelected;

  static const _shifts = [-6, -5, -4, -3, -2, -1, 0, 1];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final now = DateTime.now().toLocal();
    final nowMonth = DateTime(now.year, now.month);
    final selected = DateTime(
      cloud.selectedMonth.year,
      cloud.selectedMonth.month,
    );

    final items = <DropdownMenuItem<String>>[];
    for (final shift in _shifts) {
      final month = DateTime(nowMonth.year, nowMonth.month + shift);
      final key =
          '${month.year}-${month.month.toString().padLeft(2, '0')}';
      final label =
          '${MonthGridCodec.monthsRu[month.month - 1]} ${month.year}';
      items.add(DropdownMenuItem(value: key, child: Text(label)));
    }

    final selectedKey =
        '${selected.year}-${selected.month.toString().padLeft(2, '0')}';
    final hasSelected = items.any((item) => item.value == selectedKey);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.light
            ? Colors.white
            : const Color(0xFF1C1D22),
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
          Text('Месяц журнала', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Отметки пишутся в лист выбранного месяца. Лист создаётся '
            'автоматически, если его ещё нет.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: hasSelected ? selectedKey : null,
            decoration: const InputDecoration(
              labelText: 'Месяц листа посещаемости',
              border: OutlineInputBorder(),
              suffixIcon: Icon(Icons.calendar_month_rounded),
            ),
            items: items,
            onChanged: cloud.isBusy
                ? null
                : (value) {
                    final month = _parseMonthKey(value);
                    if (month != null) onMonthSelected(month);
                  },
          ),
        ],
      ),
    );
  }

  DateTime? _parseMonthKey(String? value) {
    if (value == null) return null;
    final parts = value.split('-');
    final year = int.tryParse(parts.isNotEmpty ? parts.first : '');
    final month = int.tryParse(parts.length > 1 ? parts.last : '');
    if (year == null || month == null || month < 1 || month > 12) return null;
    return DateTime(year, month);
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
