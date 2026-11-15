import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/attendance_controller.dart';
import '../data/catalog_controller.dart';
import '../data/notification_controller.dart';
import '../data/schedule_controller.dart';
import '../data/ui_settings.dart';
import '../services/cloud/cloud_sync_controller.dart';
import '../theme/app_theme.dart';
import 'catalog_screen.dart';
import 'cloud_sync_screen.dart';
import 'notifications_screen.dart';

/// Сайт проекта и страница релизов.
const _siteUrl = 'https://fr4ncuzs4n.github.io/yavka-site/';
const _releasesUrl = 'https://github.com/Fr4ncuzS4n/yavka/releases';

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
  });

  final UiSettingsController settings;

  /// Разделы, в которые можно перейти с экрана настроек. Если контроллер
  /// не передан, его пункт скрывается — так экран работает и в тестах.
  final AttendanceController? attendance;
  final ScheduleController? schedule;
  final CatalogController? catalog;
  final NotificationController? notifications;
  final CloudSyncController? cloud;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasSections = cloud != null || notifications != null || catalog != null;
    final hasData = attendance != null || schedule != null || catalog != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
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
                    _AboutCard(),
                    const SizedBox(height: 16),
                    Text(
                      'Выбор дизайна сохраняется на устройстве. Дизайн '
                      'подойдёт любому старосте — «пацану» или «девочке».',
                      textAlign: TextAlign.center,
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

/// «О приложении»: лого, версия и ссылки.
class _AboutCard extends StatelessWidget {
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
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => _open(context, _siteUrl),
              icon: const Icon(Icons.language_rounded, size: 18),
              label: const Text('Сайт'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => _open(context, _releasesUrl),
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

  Future<void> _open(BuildContext context, String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось открыть ссылку: $url')),
      );
    }
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
