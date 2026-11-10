import 'package:flutter/material.dart';

/// Нейтральная палитра «Явки».
///
/// База — тёплый серый, акцент пользователь выбирает в настройках.
/// Цвета статусов вынесены в `status_style.dart`. Никаких гендерных
/// стереотипов: дизайн подходит любому старосте.
abstract final class AppPalette {
  /// Акцент приложения по умолчанию.
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

/// Варианты оформления на выбор — «Настройки → Дизайн».
enum AccentVariant {
  teal('Бирюза', Color(0xFF176B62), Color(0xFF7BDDC8)),
  blue('Синий', Color(0xFF2B5EA8), Color(0xFF9FBFF2)),
  clay('Терракота', Color(0xFFB0563C), Color(0xFFF0A78F)),
  plum('Слива', Color(0xFF6D4C8F), Color(0xFFC9A8E8)),
  olive('Олива', Color(0xFF68723B), Color(0xFFC3CD8F));

  const AccentVariant(this.label, this.seed, this.seedDark);

  final String label;
  final Color seed;

  /// Приглушённый вариант семени для тёмной темы.
  final Color seedDark;
}

/// Темы приложения: светлая и тёмная, с выбранным акцентом.
abstract final class AppTheme {
  static ThemeData light([AccentVariant accent = AccentVariant.teal]) =>
      _build(Brightness.light, accent);

  static ThemeData dark([AccentVariant accent = AccentVariant.teal]) =>
      _build(Brightness.dark, accent);

  static ThemeData _build(Brightness brightness, AccentVariant accent) {
    final isLight = brightness == Brightness.light;
    final scheme = ColorScheme.fromSeed(
      seedColor: isLight ? accent.seed : accent.seedDark,
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
