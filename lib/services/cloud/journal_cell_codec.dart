import 'dart:ui';

import '../../models/attendance_entry.dart';
import '../../models/attendance_status.dart';

/// Как отметка выглядит в ячейке журнала.
///
/// - зелёная заливка — «пришёл»;
/// - оранжевая заливка + время («8:30») — «опоздал»;
/// - красная заливка + буква «Н» — «не пришёл»;
/// - синяя заливка — «по уважительной причине».
abstract final class JournalCellCodec {
  /// Зелёный из стандартной палитры Google Таблиц — тот, что Google
  /// даёт при выборе простого «Зелёного» в цвете заливки.
  static const cameColor = Color(0xFF00FF00);

  /// Зелёный, который писала ранняя версия приложения; журналы с ним
  /// продолжают читаться.
  static const legacyCameColor = Color(0xFF00CC00);
  static const lateColor = Color(0xFFFF9900); // оранжевая
  static const absentColor = Color(0xFFFF0000); // красная
  static const excusedColor = Color(0xFF4472C4); // синяя

  /// Буква «не пришёл» в красной ячейке.
  static const String absentMark = 'Н';

  /// Цвет ячейки для статуса.
  static Color colorFor(AttendanceStatus status) => switch (status) {
    AttendanceStatus.came => cameColor,
    AttendanceStatus.late => lateColor,
    AttendanceStatus.absent => absentColor,
    AttendanceStatus.excused => excusedColor,
  };

  /// Статус по цвету заливки или `null`, если заливка не из списка.
  static AttendanceStatus? statusFromColor(int rgb) {
    for (final status in AttendanceStatus.values) {
      if (matchesColor(rgb, colorFor(status))) return status;
    }
    // Старые отметки приложения пишем в новый зелёный при первой
    // отправке, но читаем их, пока журнал не перезаписан.
    if (matchesColor(rgb, legacyCameColor)) return AttendanceStatus.came;
    return null;
  }

  /// Сравнение цветов с запасом на округление Google.
  static bool matchesColor(int rgb, Color reference) {
    final argb = reference.toARGB32();
    return ((rgb >> 16) & 0xFF) - ((argb >> 16) & 0xFF) <= 10 &&
        ((rgb >> 16) & 0xFF) - ((argb >> 16) & 0xFF) >= -10 &&
        ((rgb >> 8) & 0xFF) - ((argb >> 8) & 0xFF) <= 10 &&
        ((rgb >> 8) & 0xFF) - ((argb >> 8) & 0xFF) >= -10 &&
        (rgb & 0xFF) - (argb & 0xFF) <= 10 &&
        (rgb & 0xFF) - (argb & 0xFF) >= -10;
  }

  /// Заливка той же ячейки без альфа-канала (Google хранит RGB).
  static int cellColor(AttendanceStatus status) =>
      colorFor(status).toARGB32() & 0xFFFFFF;

  /// Текст ячейки для статуса: время для «опоздал», «Н» для «не пришёл»,
  /// у остальных заливка без текста.
  static String? cellTextFor(AttendanceEntry entry) => switch (entry.status) {
    AttendanceStatus.late => formatTime(entry.markedAt),
    AttendanceStatus.absent => absentMark,
    _ => null,
  };

  /// Время отметки как в журнале, например «8:30».
  static String formatTime(DateTime date) =>
      '${date.hour}:${date.minute.toString().padLeft(2, '0')}';

  /// Разбор статуса ячейки: сначала заливка, потом текст.
  static AttendanceEntry? decodeCell(
    int? backgroundColor,
    Object? value,
    DateTime date,
  ) {
    if (backgroundColor != null) {
      final status = statusFromColor(backgroundColor);
      if (status != null) {
        return AttendanceEntry(
          status: status,
          markedAt: parseMarkedAt(date, value),
        );
      }
    }
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    final status = AttendanceStatus.tryParse(text);
    if (status == null) return null;
    return AttendanceEntry(
      status: status,
      markedAt: parseMarkedAt(date, value),
    );
  }

  /// Обрабатываем почерк бумажного журнала: «8:30», «8:3» (=8:30 —
  /// однозначные минуты писали без ноля), «8.30» и полное время.
  static DateTime parseMarkedAt(DateTime date, Object? value) {
    final text = value?.toString().trim() ?? '';
    final match = RegExp(r'^(\d{1,2})\D?(\d{1,2})').firstMatch(text);
    if (match == null || text.isEmpty) return date;

    final hour = int.tryParse(match.group(1)!) ?? -1;
    var minute = int.tryParse(match.group(2)!) ?? -1;
    if (hour < 0 || hour > 23 || minute < 0) return date;
    // Однозначная минута означает десятки: «8:3» — это 8:30.
    if (match.group(2)!.length == 1) minute *= 10;
    if (minute > 59) return date;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  /// Число дней в месяце.
  static int daysInMonth(DateTime month) {
    final nextMonth = month.month == 12
        ? DateTime(month.year + 1, 1, 1)
        : DateTime(month.year, month.month + 1, 1);
    return nextMonth.add(const Duration(seconds: -1)).day;
  }
}
