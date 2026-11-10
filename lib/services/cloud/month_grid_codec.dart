import 'dart:ui';

import '../../models/attendance_entry.dart';
import '../../models/attendance_status.dart';

/// Формат листа Google Таблицы за один месяц.
///
/// Структура повторяет привычный классный журнал (см. README):
/// - строка 1: баннер месяца в колонке B (например «НОЯБРЬ»), а над каждой
///   группой колонок дня — название дня недели («Понедельник»);
/// - строка 2: «№» и «ФИО», под каждым днём — число месяца (2, 3, 4…);
/// - строка 3: «ПАРА» и метки пар внутри дня (1, 2, 3, 4);
/// - ниже — строки студентов: отметка дня лежит в колонке первой пары
///   блока этого дня.
///
/// Обозначения в ячейках:
/// - зелёная заливка — «пришёл»;
/// - оранжевая заливка + время («8:30») — «опоздал»;
/// - красная заливка + буква «Н» — «не пришёл»;
/// - синяя заливка — «по уважительной причине».
///
/// Каждая таблица описывает одну группу: колонки «Группа» формате нет.
abstract final class MonthGridCodec {
  /// Сколько колонок-пар в блоке каждого дня.
  static const int pairsPerDay = 4;

  /// Индекс первой колонки блока первого дня месяца (A=0 — №, B=1 — ФИО).
  static const int firstDayColumn = 2;

  /// Первая строка студентов (0-based): 0 — дни недели, 1 — числа,
  /// 2 — «ПАРА».
  static const int firstStudentRow = 3;

  static const List<String> monthsRu = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];

  static const List<String> _weekdaysRu = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];

  /// Название листа для месяца, например «Ноябрь 2026».
  static String monthSheetTitle(DateTime month) =>
      '${monthsRu[month.month - 1]} ${month.year}';

  /// Баннер месяца в ячейке B1, например «НОЯБРЬ».
  static String monthBanner(DateTime month) =>
      monthsRu[month.month - 1].toUpperCase();

  /// День недели целиком по-русски, например «Понедельник».
  static String weekdayName(DateTime date) =>
      _weekdaysRu[date.weekday - 1];

  /// Играет роль «смотрит в упор»: ищет существующий лист месяца.
  ///
  /// Понимает и старые листы без года в названии («НОЯБРЬ», «ноябрь»).
  /// Год уточняем, потому что листов «Ноябрь» может быть несколько
  /// в разных файлах — берём первый подходящий.
  static String? findMonthTab(List<String> titles, DateTime month) {
    final wantedFull = '${monthsRu[month.month - 1]} ${month.year}'
        .toLowerCase();
    final wantedShort = monthsRu[month.month - 1].toLowerCase();
    String? shortMatch;
    for (final title in titles) {
      final normalized = title.trim().toLowerCase();
      if (normalized == wantedFull) return title;
      if (shortMatch == null && normalized == wantedShort) shortMatch = title;
    }
    return shortMatch;
  }

  /// Число дней в месяце.
  static int daysInMonth(DateTime month) {
    final nextMonth = month.month == 12
        ? DateTime(month.year + 1, 1, 1)
        : DateTime(month.year, month.month + 1, 1);
    return nextMonth.add(const Duration(seconds: -1)).day;
  }

  /// Границы колонок блока дня.
  static int firstColumnOf(DateTime month, int day) =>
      firstDayColumn + (day - 1) * pairsPerDay;

  /// Статусы и их заливки — ровно как в бумажном журнале.
  static const cameColor = Color(0xFF00CC00); // зелёная
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

  /// Текст ячейки для статуса: время для «опоздал», «Н» для «не пришёл»,
  /// у остальных заливка без текста.
  static String? cellTextFor(AttendanceEntry entry) => switch (entry.status) {
    AttendanceStatus.late => formatTime(entry.markedAt),
    AttendanceStatus.absent => absentMark,
    _ => null,
  };

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

  /// Время отметки как в журнале, например «8:30».
  static String formatTime(DateTime date) =>
      '${date.hour}:${date.minute.toString().padLeft(2, '0')}';

  /// Шапка листа месяца для создания «с нуля».
  ///
  /// Возвращает три строки: дни недели, числа месяца, «ПАРА»/метки пар.
  /// Строки идут колонками от A.
  static List<List<Object?>> buildHeader(DateTime month) {
    final days = daysInMonth(month);
    final totalColumns = firstDayColumn + days * pairsPerDay;
    final weekdayRow = List<Object?>.filled(totalColumns, null);
    final dayRow = List<Object?>.filled(totalColumns, null);
    final pairRow = List<Object?>.filled(totalColumns, null);

    weekdayRow[1] = monthBanner(month);
    dayRow[0] = '№';
    dayRow[1] = 'ФИО';
    pairRow[1] = 'ПАРА';

    for (var day = 1; day <= days; day++) {
      final first = firstColumnOf(month, day);
      final date = DateTime(month.year, month.month, day);
      // Значение пишем в первую колонку блока: mergeCells объединит блок,
      // и значение показывается поверх всей группы колонок.
      weekdayRow[first] = weekdayName(date);
      dayRow[first] = day;
      for (var pair = 1; pair <= pairsPerDay; pair++) {
        pairRow[first + pair - 1] = pair;
      }
    }

    return [weekdayRow, dayRow, pairRow];
  }

  /// Диапазоны объединения для шапки: по блоку на каждую строку 1 и 2.
  ///
  /// Например: для понедельника диапазон C1:F1 и C2:F2 (0-based: строки 0
  /// и 1, колонки 2..5).
  static List<Map<String, int>> buildHeaderMerges(DateTime month) {
    final merges = <Map<String, int>>[];
    for (var day = 1; day <= daysInMonth(month); day++) {
      final first = firstColumnOf(month, day);
      final last = first + pairsPerDay - 1;
      merges.add(
        {
          'startRowIndex': 0,
          'endRowIndex': 1,
          'startColumnIndex': first,
          'endColumnIndex': last + 1,
        },
      );
      merges.add(
        {
          'startRowIndex': 1,
          'endRowIndex': 2,
          'startColumnIndex': first,
          'endColumnIndex': last + 1,
        },
      );
    }
    return merges;
  }
}
