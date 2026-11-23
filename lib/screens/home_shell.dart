import 'package:flutter/material.dart';

import '../data/attendance_controller.dart';
import '../data/catalog_controller.dart';
import '../data/notification_controller.dart';
import '../data/schedule_controller.dart';
import '../data/ui_settings.dart';
import '../services/cloud/cloud_sync_controller.dart';
import '../services/update/update_check.dart';
import 'attendance_screen.dart';
import 'schedule_screen.dart';
import 'settings_screen.dart';

/// Два раздела приложения: отметка посещаемости и расписание.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    this.attendance,
    this.cloud,
    this.schedule,
    this.notifications,
    this.uiSettings,
    this.catalog,
    this.updates,
  });

  final AttendanceController? attendance;
  final CloudSyncController? cloud;
  final ScheduleController? schedule;
  final NotificationController? notifications;

  /// Выборный дизайн («Настройки → Дизайн»).
  final UiSettingsController? uiSettings;

  /// Локальная база: преподаватели, предметы, кабинеты.
  final CatalogController? catalog;

  /// Проверка обновлений с GitHub Releases.
  final UpdateController? updates;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  late final AttendanceController _attendance =
      widget.attendance ?? AttendanceController.inMemory();
  late final ScheduleController _schedule =
      widget.schedule ?? ScheduleController.inMemory();
  late final NotificationController _notifications =
      widget.notifications ?? NotificationController();

  @override
  void initState() {
    super.initState();
    _schedule.load();
    _notifications.load();
    widget.catalog?.load();
    // Почта аккаунта меняется при входе/выходе — отражаем на экранах.
    widget.cloud?.addListener(_onCloudChanged);
  }

  void _onCloudChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.cloud?.removeListener(_onCloudChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasSettings = widget.uiSettings != null;
    final children = <Widget>[
      AttendanceScreen(
        attendance: _attendance,
        cloud: widget.cloud,
        schedule: _schedule,
        notifications: _notifications,
        uiSettings: widget.uiSettings,
        catalog: widget.catalog,
        updates: widget.updates,
      ),
      ScheduleScreen(
        schedule: _schedule,
        attendance: _attendance,
        notifications: _notifications,
        catalog: widget.catalog,
        accountEmail: widget.cloud?.accountEmail,
      ),
      if (hasSettings)
        SettingsScreen(
          settings: widget.uiSettings!,
          attendance: _attendance,
          schedule: _schedule,
          catalog: widget.catalog,
          notifications: _notifications,
          cloud: widget.cloud,
          updates: widget.updates,
          embedded: true,
        )
      else
        const Center(child: Text('Настройки недоступны')),
    ];
    return Scaffold(
      body: IndexedStack(
        index: _tab.clamp(0, children.length - 1),
        children: children,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab.clamp(0, children.length - 1),
        onDestinationSelected: (index) => setState(() => _tab = index),
        indicatorColor: scheme.primaryContainer,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.how_to_reg_outlined),
            selectedIcon: Icon(Icons.how_to_reg_rounded),
            label: 'Отметка',
          ),
          const NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note_rounded),
            label: 'Расписание',
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings_rounded),
            label: 'Настройки',
          ),
        ],
      ),
    );
  }
}
