import 'package:flutter/material.dart';

import '../data/ui_settings.dart';
import '../theme/app_theme.dart';

/// Экран «Дизайн»: тема и акцент на выбор.
///
/// Вариант выбирается один раз и сохраняется на устройстве. Названия
/// и цвета нейтральные — без гендерных стереотипов.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.settings});

  final UiSettingsController settings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Дизайн')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListenableBuilder(
              listenable: settings,
              builder: (context, _) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.light
                            ? Colors.white
                            : const Color(0xFF1C1D22),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context).brightness ==
                                  Brightness.light
                              ? const Color(0xFFE5E5E1)
                              : const Color(0xFF2E2F35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Тема', style: Theme.of(context)
                              .textTheme.titleMedium),
                          const SizedBox(height: 12),
                          SegmentedButton<ThemeMode>(
                            segments: const [
                              ButtonSegment(
                                value: ThemeMode.system,
                                icon: Icon(Icons.brightness_auto_rounded),
                                label: Text('Авто'),
                              ),
                              ButtonSegment(
                                value: ThemeMode.light,
                                icon: Icon(Icons.light_mode_outlined),
                                label: Text('Светлая'),
                              ),
                              ButtonSegment(
                                value: ThemeMode.dark,
                                icon: Icon(Icons.dark_mode_outlined),
                                label: Text('Тёмная'),
                              ),
                            ],
                            selected: {settings.themeMode},
                            onSelectionChanged: (selection) {
                              if (selection.isNotEmpty) {
                                settings.setThemeMode(selection.first);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.light
                            ? Colors.white
                            : const Color(0xFF1C1D22),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Theme.of(context).brightness ==
                                  Brightness.light
                              ? const Color(0xFFE5E5E1)
                              : const Color(0xFF2E2F35),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Акцент', style: Theme.of(context)
                              .textTheme.titleMedium),
                          const SizedBox(height: 4),
                          Text(
                            'Цвет кнопок и выделения. Фон и текст остаются '
                            'спокойными в любой палитре.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              for (final variant in AccentVariant.values)
                                _AccentSwatch(
                                  palette: variant,
                                  selected: settings.accent == variant,
                                  onTap: () => settings.setAccent(variant),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Выбор сохраняется на устройстве. Дизайн подойдёт '
                      'любому старосте — «пацану» или «девочке».',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final AccentVariant palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Tooltip(
        message: palette.label,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: palette.seed,
            border: Border.all(
              width: selected ? 3 : 1,
              color: selected
                  ? scheme.onSurface
                  : scheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
          ),
          child: selected
              ? Icon(Icons.check_rounded, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}
