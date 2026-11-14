import 'package:flutter/material.dart';

import '../data/notification_controller.dart';
import '../models/sync_notification.dart';
import '../theme/app_theme.dart';

/// Колокольчик в шапке: количество непрочитанных уведомлений и переход
/// в центр уведомлений.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key, required this.notifications});

  final NotificationController notifications;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: notifications,
      builder: (context, _) {
        final unread = notifications.unreadCount;
        return IconButton(
          tooltip: 'Уведомления',
          onPressed: () => _open(context),
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: const Icon(Icons.notifications_outlined),
          ),
        );
      },
    );
  }

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotificationsScreen(notifications: notifications),
      ),
    );
  }
}

/// Центр уведомлений: отметки других людей на парах, полученные из
/// подключённой Google Таблицы.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key, required this.notifications});

  final NotificationController notifications;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Уведомления'),
        actions: [
          ListenableBuilder(
            listenable: notifications,
            builder: (context, _) {
              if (notifications.unreadCount == 0 &&
                  notifications.items.isEmpty) {
                return const SizedBox.shrink();
              }
              return TextButton(
                onPressed: notifications.markAllRead,
                child: const Text('Прочитать все'),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListenableBuilder(
              listenable: notifications,
              builder: (context, _) {
                final items = notifications.items;
                if (items.isEmpty) return const _EmptyState();
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) => _NotificationCard(
                    item: items[index],
                    notifications: notifications,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.notifications_none_rounded,
          size: 48,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(height: 12),
        Text(
          'Уведомлений пока нет',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Когда кто-то из тех, кто пользуется той же таблицей, отметит '
          'студентов на паре — уведомление появится здесь.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item, required this.notifications});

  final SyncNotification item;
  final NotificationController notifications;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLight = scheme.brightness == Brightness.light;
    final unread = !item.isRead;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isLight ? Colors.white : AppPalette.cardDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: unread
              ? scheme.primary.withValues(alpha: 0.5)
              : (isLight ? AppPalette.line : AppPalette.lineDark),
          width: unread ? 1.5 : 1,
        ),
      ),
      child: ListTile(
        onTap: unread ? () => notifications.markRead(item.id) : null,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 6,
        ),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: unread
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          foregroundColor: unread
              ? scheme.onPrimaryContainer
              : scheme.onSurfaceVariant,
          child: const Icon(Icons.event_available_rounded, size: 20),
        ),
        title: Text(
          item.message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${_meta(item)} · ${_formatStamp(item.createdAt)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        trailing: unread
            ? Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary,
                ),
              )
            : null,
      ),
    );
  }

  String _meta(SyncNotification item) {
    final parts = [
      if (item.author.isNotEmpty) item.author,
      if (item.groupName.isNotEmpty) 'группа ${item.groupName}',
    ];
    return parts.isEmpty ? 'без автора' : parts.join(' · ');
  }
}

String _formatStamp(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(value.day)}.${two(value.month)}.${value.year} '
      '${two(value.hour)}:${two(value.minute)}';
}
