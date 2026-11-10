// ignore_for_file: prefer_initializing_formals

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';

/// Дизайн, который выбрал пользователь: тема и акцент.
abstract interface class UiSettings {
  ThemeMode get themeMode;

  AccentVariant get accent;
}

/// Слушабельный контроллер выбранных настроек.
class UiSettingsController extends ChangeNotifier {
  UiSettingsController({required SharedPreferences preferences})
    : _preferences = preferences {
    _themeMode = _readThemeMode();
    _accent = _readAccent();
  }

  final SharedPreferences _preferences;

  static const _themeModeKey = 'yavka.ui.theme_mode';
  static const _accentKey = 'yavka.ui.accent';

  ThemeMode _themeMode = ThemeMode.system;
  AccentVariant _accent = AccentVariant.teal;

  ThemeMode get themeMode => _themeMode;

  AccentVariant get accent => _accent;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();
    await _preferences.setString(_themeModeKey, mode.name);
  }

  Future<void> setAccent(AccentVariant accent) async {
    if (_accent == accent) return;
    _accent = accent;
    notifyListeners();
    await _preferences.setString(_accentKey, accent.name);
  }

  ThemeMode _readThemeMode() {
    return switch (_preferences.getString(_themeModeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  AccentVariant _readAccent() {
    final stored = _preferences.getString(_accentKey);
    for (final variant in AccentVariant.values) {
      if (variant.name == stored) return variant;
    }
    return AccentVariant.teal;
  }
}
