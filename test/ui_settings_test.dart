// Тесты выбора дизайна: тема и акцент сохраняются в настройках.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yavka/data/ui_settings.dart';
import 'package:yavka/screens/settings_screen.dart';
import 'package:yavka/theme/app_theme.dart';

void main() {
  testWidgets('по умолчанию — системная тема и бирюзовый акцент', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settings = UiSettingsController(preferences: preferences);

    expect(settings.themeMode, ThemeMode.system);
    expect(settings.accent, AccentVariant.teal);
  });

  testWidgets('выбор темы и акцента сохраняется на устройстве', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settings = UiSettingsController(preferences: preferences);

    await settings.setThemeMode(ThemeMode.dark);
    await settings.setAccent(AccentVariant.clay);

    expect(settings.themeMode, ThemeMode.dark);
    expect(settings.accent, AccentVariant.clay);
    expect(preferences.getString('yavka.ui.theme_mode'), 'dark');
    expect(preferences.getString('yavka.ui.accent'), 'clay');

    // Новый контроллер восстанавливает выбор.
    final restored = UiSettingsController(preferences: preferences);
    expect(restored.themeMode, ThemeMode.dark);
    expect(restored.accent, AccentVariant.clay);
  });

  test('темы строятся для каждого акцента в светлой и тёмной палитре', () {
    for (final variant in AccentVariant.values) {
      expect(AppTheme.light(variant), isNotNull);
      expect(AppTheme.dark(variant), isNotNull);
    }

    // Разные акценты дают разные цвета основного элемента.
    final teal = AppTheme.light(AccentVariant.teal).colorScheme.primary;
    final clay = AppTheme.light(AccentVariant.clay).colorScheme.primary;
    expect(teal, isNot(clay));
  });

  testWidgets('экран «Дизайн» показывает тему и все акценты', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final settings = UiSettingsController(preferences: preferences);

    await tester.pumpWidget(
      MaterialApp(home: SettingsScreen(settings: settings)),
    );

    expect(find.text('Тема'), findsOneWidget);
    expect(find.text('Акцент'), findsOneWidget);
    // Свотч на каждый вариант акцента.
    expect(find.byType(Tooltip), findsNWidgets(AccentVariant.values.length));

    // Тап по второму свотчу выбирает «Синий».
    await tester.tap(find.byType(Tooltip).at(1));
    await tester.pumpAndSettle();

    expect(settings.accent, AccentVariant.blue);
    expect(preferences.getString('yavka.ui.accent'), 'blue');
  });
}
