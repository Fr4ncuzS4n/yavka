import 'package:flutter/material.dart';

import '../data/attendance_controller.dart';
import '../data/catalog_controller.dart';
import '../data/notification_controller.dart';
import '../data/schedule_controller.dart';
import '../data/ui_settings.dart';
import '../services/cloud/cloud_sync_controller.dart';
import 'attendance_screen.dart';
import 'schedule_screen.dart';

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
  });

  final AttendanceController? attendance;
  final CloudSyncController? cloud;
  final ScheduleController? schedule;
  final NotificationController? notifications;

  /// Выборный дизайн («Настройки → Дизайн»).
  final UiSettingsController? uiSettings;

  /// Локальная база: преподаватели, предметы, кабинеты.
  final CatalogController? catalog;

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
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          AttendanceScreen(
            attendance: _attendance,
            cloud: widget.cloud,
            schedule: _schedule,
            notifications: _notifications,
            uiSettings: widget.uiSettings,
          ),
          ScheduleScreen(
            schedule: _schedule,
            attendance: _attendance,
            notifications: _notifications,
            catalog: widget.catalog,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        indicatorColor: scheme.primaryContainer,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.how_to_reg_outlined),
            selectedIcon: Icon(Icons.how_to_reg_rounded),
            label: 'Отметка',
          ),
          NavigationDestination(
            icon: Icon(Icons.event_note_outlined),
            selectedIcon: Icon(Icons.event_note_rounded),
            label: 'Расписание',
          ),
        ],
      ),
    );
  }
}
