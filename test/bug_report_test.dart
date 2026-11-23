// Тесты вкладки «Сообщить об ошибке» и нижней панели с Настройками.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yavka/data/ui_settings.dart';
import 'package:yavka/screens/home_shell.dart';
import 'package:yavka/screens/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ссылка issue содержит шаблон и диагностику', () {
    final uri = bugReportIssueUri(version: '1.2.3', platform: 'Android');

    expect(uri.scheme, 'https');
    expect(uri.host, 'github.com');
    expect(uri.path, '/Fr4ncuzS4n/yavka/issues/new');
    expect(uri.queryParameters['title'], contains('ошибк'));

    final body = uri.queryParameters['body']!;
    expect(body, contains('Что случилось'));
    expect(body, contains('Шаги воспроизведения'));
    expect(body, contains('1.2.3'));
    expect(body, contains('Android'));
  });

  test('платформа для диагностики определена', () {
    expect(bugReportPlatform(), isNotEmpty);
  });

  testWidgets('кнопка открывает GitHub issue с заполненной формой', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settings = UiSettingsController(preferences: preferences);

    final calls = <MethodCall>[];
    const channel = MethodChannel('plugins.flutter.io/url_launcher');
    final messenger = TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });
    addTearDown(
      () =>
          messenger.setMockMethodCallHandler(channel, null),
    );

    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(settings: settings)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Сообщить об ошибке'), findsOneWidget);
    await tester.ensureVisible(find.text('Открыть GitHub issue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Открыть GitHub issue'));
    await tester.pumpAndSettle();

    final launch = calls.singleWhere((call) => call.method == 'launch');
    final url = launch.arguments['url'] as String;
    expect(url, startsWith(issuesNewUrl));
    final uri = Uri.parse(url);
    expect(uri.queryParameters['body'], contains('Шаги воспроизведения'));
    expect(uri.queryParameters['body'], contains(bugReportPlatform()));
  });

  testWidgets('настройки — вкладка нижней панели без собственного AppBar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settings = UiSettingsController(preferences: preferences);

    await tester.pumpWidget(MaterialApp(home: HomeShell(uiSettings: settings)));
    await tester.pumpAndSettle();

    expect(find.text('Настройки'), findsOneWidget);
    await tester.tap(find.text('Настройки'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Сообщить об ошибке'),
      400,
    );
    await tester.pumpAndSettle();
    expect(find.text('Сообщить об ошибке'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
  });
}
