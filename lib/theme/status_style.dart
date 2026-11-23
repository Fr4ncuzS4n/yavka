import 'package:flutter/material.dart';

import '../models/attendance_status.dart';

/// Визуальный стиль каждой отметки: цвет, иконка и короткая подпись.
///
/// Светлые цвета (`color`) читаются на светлом фоне, приглушённые
/// (`softColor`) — в тёмной теме. Использовать через `foreground()`
/// и `container()` — они сами выбирают вариант под яркость темы.
extension StatusStyle on AttendanceStatus {
  /// Плотный цвет статуса.
  Color get color => switch (this) {
    AttendanceStatus.came => const Color(0xFF1E7B34),
    AttendanceStatus.absent => const Color(0xFFC1372C),
    AttendanceStatus.late => const Color(0xFF96600A),
    AttendanceStatus.excused => const Color(0xFF1D5FB8),
  };

  /// Приглушённый цвет для тёмной темы.
  Color get softColor => switch (this) {
    AttendanceStatus.came => const Color(0xFF7BDD9B),
    AttendanceStatus.absent => const Color(0xFFFF9C94),
    AttendanceStatus.late => const Color(0xFFFFC86B),
    AttendanceStatus.excused => const Color(0xFF93C1FF),
  };

  /// Цвет контента (иконки, текст) под текущую яркость темы.
  Color foreground(Brightness brightness) =>
      brightness == Brightness.light ? color : softColor;

  /// Полупрозрачная подложка под контент.
  Color container(Brightness brightness) =>
      foreground(brightness)
          .withValues(alpha: brightness == Brightness.light ? 0.12 : 0.16);

  /// Иконка статуса.
  IconData get icon => switch (this) {
    AttendanceStatus.came => Icons.check_circle_rounded,
    AttendanceStatus.absent => Icons.cancel_rounded,
    AttendanceStatus.late => Icons.schedule_rounded,
    AttendanceStatus.excused => Icons.note_alt_rounded,
  };

  /// Короткая подпись под названием статуса.
  String get hint => switch (this) {
    AttendanceStatus.came => 'Обычная отметка',
    AttendanceStatus.absent => 'Повторное нажатие подтвердит',
    AttendanceStatus.late => 'Повторное нажатие — время',
    AttendanceStatus.excused => 'Уважительная причина',
  };
}
