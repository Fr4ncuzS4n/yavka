import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/attendance_controller.dart';
import 'data/attendance_store.dart';
import 'data/cloud_settings.dart';
import 'data/example_group.dart';
<<<<<<< HEAD
import 'data/ui_settings.dart';
=======
import 'data/notification_controller.dart';
import 'data/notification_store.dart';
import 'data/schedule_controller.dart';
import 'data/schedule_store.dart';
>>>>>>> 7eccdcc (Вкладка «Расписание»: пары по дням недели, отметки на каждой паре и уведомления через таблицу)
import 'models/attendance_session.dart';
import 'screens/home_shell.dart';
import 'services/cloud/cloud_sync_controller.dart';
import 'services/cloud/google_auth_service.dart';
import 'services/cloud/google_sheets_api.dart';
import 'services/cloud/oauth/oauth_flow.dart';
import 'services/cloud/token_store.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var attendance = AttendanceController.inMemory();
  var schedule = ScheduleController.inMemory();
  var notifications = NotificationController();
  CloudSyncController? cloud;
  UiSettingsController? settings;

  try {
    final preferences = await SharedPreferences.getInstance();
    attendance = AttendanceController(
      session: AttendanceSession.forToday(
        groupName: exampleGroupName,
        students: exampleStudents,
      ),
      store: SharedPreferencesAttendanceStore(preferences),
    );
    await attendance.load();

    schedule = ScheduleController(
      store: SharedPreferencesScheduleStore(preferences),
    );
    await schedule.load();

    notifications = NotificationController(
      store: SharedPreferencesNotificationStore(preferences),
    );
    await notifications.load();

    final auth = GoogleAuthService(
      flow: createOAuthFlow(),
      tokenStore: SharedPreferencesTokenStore(preferences),
    );
    cloud = CloudSyncController(
      attendance: attendance,
      auth: auth,
      sheetsApi: GoogleSheetsApi(accessToken: auth.accessToken),
      settingsStore: SharedPreferencesCloudSettingsStore(preferences),
      isWeb: kIsWeb,
      notifications: notifications,
    );
    settings = UiSettingsController(preferences: preferences);
  } catch (error, stackTrace) {
    // Приложение должно запускаться даже без локального хранилища —
    // тогда данные живут только в памяти.
    debugPrint(
      'Не удалось инициализировать локальное хранилище: $error\n$stackTrace',
    );
  }

  runApp(
<<<<<<< HEAD
    AppRoot(
      attendance: attendance,
      cloud: cloud,
      settings: settings,
=======
    MyApp(
      attendance: attendance,
      schedule: schedule,
      notifications: notifications,
      cloud: cloud,
>>>>>>> 7eccdcc (Вкладка «Расписание»: пары по дням недели, отметки на каждой паре и уведомления через таблицу)
    ),
  );

  if (cloud != null) {
    unawaited(cloud.initialize());
  }
}

<<<<<<< HEAD
class AppRoot extends StatelessWidget {
  const AppRoot({
    super.key,
    this.attendance,
    this.cloud,
    this.settings,
=======
class MyApp extends StatelessWidget {
  const MyApp({
    super.key,
    this.attendance,
    this.schedule,
    this.notifications,
    this.cloud,
>>>>>>> 7eccdcc (Вкладка «Расписание»: пары по дням недели, отметки на каждой паре и уведомления через таблицу)
  });

  final AttendanceController? attendance;
  final ScheduleController? schedule;
  final NotificationController? notifications;
  final CloudSyncController? cloud;
  final UiSettingsController? settings;

  @override
  Widget build(BuildContext context) {
<<<<<<< HEAD
    if (settings == null) {
      return MaterialApp(
        title: 'Явка',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: AttendanceScreen(attendance: attendance, cloud: cloud),
      );
    }

    final controller = settings!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return MaterialApp(
          title: 'Явка',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(controller.accent),
          darkTheme: AppTheme.dark(controller.accent),
          themeMode: controller.themeMode,
          home: AttendanceScreen(
            attendance: attendance,
            cloud: cloud,
            uiSettings: controller,
          ),
        );
      },
=======
    return MaterialApp(
      title: 'Явка',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: HomeShell(
        attendance: attendance,
        schedule: schedule,
        notifications: notifications,
        cloud: cloud,
      ),
>>>>>>> 7eccdcc (Вкладка «Расписание»: пары по дням недели, отметки на каждой паре и уведомления через таблицу)
    );
  }
}
