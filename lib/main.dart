import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/attendance_controller.dart';
import 'data/attendance_store.dart';
import 'data/catalog_controller.dart';
import 'data/catalog_store.dart';
import 'data/cloud_settings.dart';
import 'data/notification_controller.dart';
import 'data/notification_store.dart';
import 'data/schedule_controller.dart';
import 'data/schedule_store.dart';
import 'data/ui_settings.dart';
import 'models/attendance_session.dart';
import 'screens/home_shell.dart';
import 'services/cloud/cloud_sync_controller.dart';
import 'services/cloud/google_account_api.dart';
import 'services/cloud/google_auth_service.dart';
import 'services/cloud/google_sheets_api.dart';
import 'services/cloud/oauth/oauth_flow.dart';
import 'services/cloud/token_store.dart';
import 'services/update/update_check.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var attendance = AttendanceController.inMemory();
  var schedule = ScheduleController.inMemory();
  var catalog = CatalogController.inMemory();
  var notifications = NotificationController();
  CloudSyncController? cloud;
  UiSettingsController? settings;
  UpdateController? updates;

  try {
    final preferences = await SharedPreferences.getInstance();
    attendance = AttendanceController(
      session: AttendanceSession.forToday(groupName: '', students: const []),
      store: SharedPreferencesAttendanceStore(preferences),
    );
    await attendance.load();

    schedule = ScheduleController(
      store: SharedPreferencesScheduleStore(preferences),
      storeFactory: SharedPreferencesScheduleStoreFactory(preferences),
    );
    await schedule.load();

    catalog = CatalogController(
      store: SharedPreferencesCatalogStore(preferences),
    );
    await catalog.load();

    notifications = NotificationController(
      store: SharedPreferencesNotificationStore(preferences),
    );
    await notifications.load();

    final accountApi = GoogleAccountApi();
    final auth = GoogleAuthService(
      flow: createOAuthFlow(),
      tokenStore: SharedPreferencesTokenStore(preferences),
      accountEmailFetcher: accountApi.fetchEmail,
    );
    cloud = CloudSyncController(
      attendance: attendance,
      auth: auth,
      sheetsApi: GoogleSheetsApi(accessToken: auth.accessToken),
      settingsStore: SharedPreferencesCloudSettingsStore(preferences),
      isWeb: kIsWeb,
      schedule: schedule,
    );
    settings = UiSettingsController(preferences: preferences);

    // Свежая версия ищется в фоне; без сети приложение молчит.
    String? currentVersion;
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      currentVersion = packageInfo.version;
    } catch (_) {
      currentVersion = null;
    }
    updates = UpdateController(currentVersion: () async => currentVersion);
  } catch (error, stackTrace) {
    // Приложение должно запускаться даже без локального хранилища —
    // тогда данные живут только в памяти.
    debugPrint(
      'Не удалось инициализировать локальное хранилище: $error\n$stackTrace',
    );
  }

  runApp(
    AppRoot(
      attendance: attendance,
      schedule: schedule,
      catalog: catalog,
      notifications: notifications,
      cloud: cloud,
      settings: settings,
      updates: updates,
    ),
  );

  if (cloud != null) {
    unawaited(cloud.initialize());
  }
  if (updates != null) {
    unawaited(updates.check());
  }
}

class AppRoot extends StatelessWidget {
  const AppRoot({
    super.key,
    this.attendance,
    this.schedule,
    this.catalog,
    this.notifications,
    this.cloud,
    this.settings,
    this.updates,
  });

  final AttendanceController? attendance;
  final ScheduleController? schedule;

  /// Локальная база: преподаватели, предметы, кабинеты.
  final CatalogController? catalog;
  final NotificationController? notifications;
  final CloudSyncController? cloud;
  final UiSettingsController? settings;

  /// Проверка обновлений с GitHub Releases.
  final UpdateController? updates;

  @override
  Widget build(BuildContext context) {
    if (settings == null) {
      return MaterialApp(
        title: 'Явка',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        home: HomeShell(
          attendance: attendance,
          schedule: schedule,
          catalog: catalog,
          notifications: notifications,
          cloud: cloud,
          updates: updates,
        ),
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
          home: HomeShell(
            attendance: attendance,
            schedule: schedule,
            catalog: catalog,
            notifications: notifications,
            cloud: cloud,
            uiSettings: controller,
            updates: updates,
          ),
        );
      },
    );
  }
}
