import 'package:flutter/material.dart';

/// Нейтральная палитра «Явки».
///
/// База — тёплый серый, акцент — спокойный бирюзовый. Цвета статусов
/// вынесены в `status_style.dart`. Никаких гендерных стереотипов:
/// дизайн подходит любому старосте.
abstract final class AppPalette {
  /// Акцент приложения.
  static const accent = Color(0xFF176B62);

  /// Основной текст.
  static const ink = Color(0xFF1B1B1F);

  /// Второстепенный текст.
  static const inkSoft = Color(0xFF55565E);
  static const inkSoftDark = Color(0xFFA6A7AF);

  /// Границы карточек.
  static const line = Color(0xFFE5E5E1);
  static const lineDark = Color(0xFF2E2F35);

  /// Фон экрана.
  static const canvas = Color(0xFFF7F7F4);
  static const canvasDark = Color(0xFF121316);

  /// Фон карточек в тёмной теме.
  static const cardDark = Color(0xFF1C1D22);
}

/// Темы приложения: светлая и тёмная.
abstract final class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppPalette.accent,
      brightness: brightness,
    );
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final ink = isLight ? AppPalette.ink : const Color(0xFFECECEA);

    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: isLight
          ? AppPalette.canvas
          : AppPalette.canvasDark,
      appBarTheme: AppBarTheme(
        backgroundColor: isLight ? AppPalette.canvas : AppPalette.canvasDark,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      textTheme: base.textTheme.copyWith(
        headlineSmall: base.textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleLarge: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        titleMedium: base.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        labelLarge: base.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: isLight ? AppPalette.line : AppPalette.lineDark,
        space: 1,
        thickness: 1,
      ),
    );
  }
}
