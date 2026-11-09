import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/attendance_controller.dart';
import 'data/attendance_store.dart';
import 'data/cloud_settings.dart';
import 'data/example_group.dart';
import 'models/attendance_session.dart';
import 'screens/attendance_screen.dart';
import 'services/cloud/cloud_sync_controller.dart';
import 'services/cloud/google_auth_service.dart';
import 'services/cloud/google_sheets_api.dart';
import 'services/cloud/oauth/oauth_flow.dart';
import 'services/cloud/token_store.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  var attendance = AttendanceController.inMemory();
  CloudSyncController? cloud;

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
    );
  } catch (error, stackTrace) {
    // Приложение должно запускаться даже без локального хранилища —
    // тогда отметки живут только в памяти.
    debugPrint(
      'Не удалось инициализировать локальное хранилище: $error\n$stackTrace',
    );
  }

  runApp(MyApp(attendance: attendance, cloud: cloud));

  if (cloud != null) {
    unawaited(cloud.initialize());
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, this.attendance, this.cloud});

  final AttendanceController? attendance;
  final CloudSyncController? cloud;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Явка',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: AttendanceScreen(attendance: attendance, cloud: cloud),
    );
  }
}
