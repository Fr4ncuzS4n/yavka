import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/attendance_controller.dart';
import '../data/catalog_controller.dart';
import '../data/notification_controller.dart';
import '../data/schedule_controller.dart';
import '../data/ui_settings.dart';
import '../services/cloud/cloud_sync_controller.dart';
import '../services/update/update_check.dart';
import '../theme/app_theme.dart';
import 'catalog_screen.dart';
import 'cloud_sync_screen.dart';
import 'notifications_screen.dart';

/// Сайт проекта и страница релизов.
const _siteUrl = 'https://fr4ncuzs4n.github.io/yavka-site/';
const _releasesUrl = 'https://github.com/Fr4ncuzS4n/yavka/releases';

/// Страница создания issue в репозитории «Явки».
const issuesNewUrl = 'https://github.com/Fr4ncuzS4n/yavka/issues/new';

/// Почта создателя — альтернатива GitHub issue. Та же, что указана
/// в политике конфиденциальности на сайте приложения.
const creatorEmail = 'Fr4ncuz.S4n@gmail.com';

/// Платформа для диагностики в сообщении об ошибке.
String bugReportPlatform() {
  if (kIsWeb) return 'Web';
  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'Android',
    TargetPlatform.iOS => 'iOS',
    TargetPlatform.windows => 'Windows',
    TargetPlatform.linux => 'Linux',
    TargetPlatform.macOS => 'macOS',
    TargetPlatform.fuchsia => 'Fuchsia',
  };
}

/// Текст сообщения об ошибке: шаблон и диагностика для issue и письма.
String bugReportBody({String? version, String? platform}) => [
  '**Что случилось:**',
  '',
  '',
  '**Шаги воспроизведения:**',
  '1. ',
  '2. ',
  '',
  '**Ожидаемое поведение:**',
  '',
  '',
  '---',
  'Версия: ${version ?? 'неизвестна'}',
  'Платформа: ${platform ?? bugReportPlatform()}',
].join('\n');

/// Готовая ссылка на issue: шаблон описания и диагностика уже вставлены.
///
/// Приложение не отправляет issue само (для этого нужен аккаунт GitHub и
/// API-токен): оно открывает страницу GitHub с заполненной формой —
/// пользователь проверяет описание и нажимает «Submit new issue».
Uri bugReportIssueUri({
  String? version,
  String? platform,
  String issueTitle = 'Сообщение об ошибке',
}) =>
    Uri.https('github.com', '/Fr4ncuzS4n/yavka/issues/new', {
      'title': issueTitle,
      'body': bugReportBody(version: version, platform: platform),
    });

/// Письмо создателю с тем же описанием — если нет аккаунта GitHub или
/// не хочется публиковать ошибку в issue. Открывает почтовое приложение
/// с готовым письмом; отправку подтверждает пользователь.
Uri bugReportMailUri({String? version, String? platform}) => Uri(
  scheme: 'mailto',
  path: creatorEmail,
  queryParameters: {
    'subject': 'Ошибка в Явке',
    'body': bugReportBody(version: version, platform: platform),
  },
);

/// Открывает ссылку во внешнем браузере; если браузер недоступен —
/// показывает сообщение, а не «тихую» ошибку.
Future<void> openExternalUrl(BuildContext context, Uri url) async {
  try {
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть ссылку: $url')),
      );
    }
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Не удалось открыть ссылку: $url')),
    );
  }
}

/// Экран «Настройки»: дизайн, разделы приложения, данные, о приложении.
///
/// Дизайн (тема и акцент) выбирается один раз и сохраняется на
/// устройстве. Названия и цвета нейтральные — без гендерных
/// стереотипов.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    this.attendance,
    this.schedule,
    this.catalog,
    this.notifications,
    this.cloud,
    this.updates,
    this.embedded = false,
  });

  final UiSettingsController settings;

  /// Разделы, в которые можно перейти с экрана настроек. Если контроллер
  /// не передан, его пункт скрывается — так экран работает и в тестах.
  final AttendanceController? attendance;
  final ScheduleController? schedule;
  final CatalogController? catalog;
  final NotificationController? notifications;
  final CloudSyncController? cloud;

  /// Проверка обновлений: без него карточка «О приложении» не
  /// предлагает свежую версию.
  final UpdateController? updates;

  /// Настройки как вкладка нижней панели: без собственного AppBar.
  /// При переходе со старого места (иконки на экране отметки) остаётся
  /// обычной страницей с AppBar.
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasSections = cloud != null || notifications != null || catalog != null;
    final hasData = attendance != null || schedule != null || catalog != null;
    return Scaffold(
      appBar: embedded ? null : AppBar(title: const Text('Настройки')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListenableBuilder(
              listenable: settings,
              builder: (context, _) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    if (embedded) ...[
                      Text(
                        'Настройки',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                    ],
                    _Card(
                      children: [
                        Text('Тема', style: Theme.of(context)
                            .textTheme.titleMedium),
                        const SizedBox(height: 12),
                        SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.system,
                              icon: Icon(Icons.brightness_auto_rounded),
                              label: Text('Авто'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              icon: Icon(Icons.light_mode_outlined),
                              label: Text('Светлая'),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              icon: Icon(Icons.dark_mode_outlined),
                              label: Text('Тёмная'),
                            ),
                          ],
                          selected: {settings.themeMode},
                          onSelectionChanged: (selection) {
                            if (selection.isNotEmpty) {
                              settings.setThemeMode(selection.first);
                            }
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _Card(
                      children: [
                        Text('Акцент', style: Theme.of(context)
                            .textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Text(
                          'Цвет кнопок и выделения. Фон и текст остаются '
                          'спокойными в любой палитре.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final variant in AccentVariant.values)
                              _AccentSwatch(
                                palette: variant,
                                selected: settings.accent == variant,
                                onTap: () => settings.setAccent(variant),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _Card(
                      children: [
                        Text('Отметка', style: Theme.of(context)
                            .textTheme.titleMedium),
                        const SizedBox(height: 4),
                        Material(
                          type: MaterialType.transparency,
                          child: SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Поочерёдная отметка'),
                            subtitle: const Text(
                              'После отметки студента приложение само '
                              'подсвечивает следующего',
                            ),
                            value: settings.sequentialMarking,
                            onChanged: settings.setSequentialMarking,
                          ),
                        ),
                      ],
                    ),
                    if (hasSections) ...[
                      const SizedBox(height: 12),
                      _Card(
                        children: [
                          Text('Приложение', style: Theme.of(context)
                              .textTheme.titleMedium),
                          const SizedBox(height: 4),
                          if (cloud != null)
                            _LinkTile(
                              icon: Icons.cloud_outlined,
                              title: 'Google Диск',
                              subtitle: 'Подключение таблицы и синхронизация',
                              onTap: () => _push(
                                context,
                                CloudSyncScreen(cloud: cloud!),
                              ),
                            ),
                          if (notifications != null)
                            _LinkTile(
                              icon: Icons.notifications_outlined,
                              title: 'Уведомления',
                              subtitle: 'Колокольчик: отметки на парах',
                              onTap: () => _push(
                                context,
                                NotificationsScreen(
                                  notifications: notifications!,
                                ),
                              ),
                            ),
                          if (catalog != null)
                            _LinkTile(
                              icon: Icons.storage_outlined,
                              title: 'База данных',
                              subtitle: 'Преподаватели, предметы, кабинеты',
                              onTap: () => _push(
                                context,
                                CatalogScreen(catalog: catalog!),
                              ),
                            ),
                        ],
                      ),
                    ],
                    if (hasData) ...[
                      const SizedBox(height: 12),
                      _Card(
                        children: [
                          Text('Данные', style: Theme.of(context)
                              .textTheme.titleMedium),
                          const SizedBox(height: 4),
                          _LinkTile(
                            icon: Icons.cleaning_services_outlined,
                            title: 'Сбросить локальные данные',
                            subtitle: 'Отметки, расписание и база — '
                                'с этого устройства',
                            destructive: true,
                            onTap: () => _confirmReset(context),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    const _BugReportCard(),
                    const SizedBox(height: 12),
                    _AboutCard(updates: updates),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          title: const Text('Стереть локальные данные?'),
          content: const Text(
            'Отметки, расписание и база предметов будут удалены с этого '
            'устройства. Таблица в Google не изменится: отметки вернутся '
            'из журнала при следующей синхронизации.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Стереть'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    attendance?.reset();
    schedule?.clear();
    catalog?.clear();
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Данные удалены с устройства')),
    );
  }
}

/// Карточка настройки: белая в светлой теме, тёмная в тёмной.
class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: light ? Colors.white : const Color(0xFF1C1D22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: light ? const Color(0xFFE5E5E1) : const Color(0xFF2E2F35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// Пункт перехода внутри карточки.
class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = destructive ? scheme.error : scheme.onSurface;
    // Свой Material: ListTile рисует фон и брызги на ближайшем Material,
    // а карточка-контейнер его перекрывает.
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: color),
        title: Text(title, style: TextStyle(color: color)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}

/// «Сообщить об ошибке»: открывает GitHub issue с готовым шаблоном.
///
/// Диагностика (версия и платформа) подставляется автоматически, чтобы
/// не расспрашивать пользователя о том, что он и так видит в приложении.
class _BugReportCard extends StatelessWidget {
  const _BugReportCard();

  static Future<PackageInfo?> _packageInfo() async {
    try {
      return await PackageInfo.fromPlatform();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Card(
      children: [
        Row(
          children: [
            Icon(Icons.bug_report_outlined, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Text('Сообщить об ошибке', style: theme.textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Ошибку можно отправить в GitHub issue или написать создателю '
          'на почту. Описание уже заполнено — проверьте его и добавьте '
          'шаги воспроизведения. Отправку подтверждаете вы сами.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        FutureBuilder<PackageInfo?>(
          future: _packageInfo(),
          builder: (context, snapshot) {
            final version = snapshot.data?.version;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: () => openExternalUrl(
                    context,
                    bugReportIssueUri(version: version),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Открыть GitHub issue'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => openExternalUrl(
                    context,
                    bugReportMailUri(version: version),
                  ),
                  icon: const Icon(Icons.mail_outline_rounded, size: 18),
                  label: const Text('Написать на почту'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// «О приложении»: лого, версия, обновления и ссылки.
class _AboutCard extends StatelessWidget {
  const _AboutCard({this.updates});

  final UpdateController? updates;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Card(
      children: [
        Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset('assets/logo.png', width: 64, height: 64),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Явка', style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  )),
                  const SizedBox(height: 2),
                  FutureBuilder<PackageInfo?>(
                    future: _packageInfo(),
                    builder: (context, snapshot) {
                      final version = snapshot.data?.version;
                      return Text(
                        version == null
                            ? 'Журнал посещаемости для старосты'
                            : 'Версия $version · журнал посещаемости',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        if (updates != null) ...[
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: updates!,
            builder: (context, _) {
              final update = updates!.available;
              if (update == null && !updates!.isChecking) {
                return const SizedBox.shrink();
              }
              return _UpdateRow(
                available: update,
                isChecking: updates!.isChecking,
              );
            },
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton.icon(
              onPressed: () =>
                  openExternalUrl(context, Uri.parse(_siteUrl)),
              icon: const Icon(Icons.language_rounded, size: 18),
              label: const Text('Сайт'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () =>
                  openExternalUrl(context, Uri.parse(_releasesUrl)),
              icon: const Icon(Icons.download_rounded, size: 18),
              label: const Text('Релизы'),
            ),
          ],
        ),
      ],
    );
  }

  /// Версия из pubspec.yaml; если пакет недоступен (например в тестах) —
  /// просто без строки версии.
  static Future<PackageInfo?> _packageInfo() async {
    try {
      return await PackageInfo.fromPlatform();
    } catch (_) {
      return null;
    }
  }
}

/// Строка «доступна новая версия»: проверка идёт, найдено — кнопка.
class _UpdateRow extends StatelessWidget {
  const _UpdateRow({required this.available, required this.isChecking});

  /// Найденное обновление; `null` — пока идёт проверка.
  final AvailableUpdate? available;
  final bool isChecking;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final update = available;

    if (update == null) {
      return Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text(
            'Ищу свежую версию…',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.system_update_alt_rounded, size: 20, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Доступна версия ${update.version}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          FilledButton(
            onPressed: () async {
              try {
                await launchUrl(
                  Uri.parse(update.downloadUrl),
                  mode: LaunchMode.externalApplication,
                );
              } catch (_) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Не удалось открыть ссылку: ${update.downloadUrl}',
                    ),
                  ),
                );
              }
            },
            child: const Text('Обновить'),
          ),
        ],
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final AccentVariant palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Tooltip(
        message: palette.label,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.seed,
            border: Border.all(
              width: selected ? 3 : 1,
              color: selected
                  ? scheme.onSurface
                  : scheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
          child: selected
              ? Icon(Icons.check_rounded, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}
