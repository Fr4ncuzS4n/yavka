import '../../models/attendance_entry.dart';
import '../../models/attendance_session.dart';
import '../../models/attendance_status.dart';
import '../../models/student.dart';

/// Формат листа посещаемости в Google Таблице.
///
/// Колонки: дата, время, группа, ID студента, ФИО, статус, пара.
/// Формат намеренно человекочитаемый: таблицу можно открыть и поправить
/// прямо в Google Диске. Старые таблицы без колонки «Пара» читаются как
/// раньше — отметки считаются отметками на весь день.
abstract final class SheetAttendanceCodec {
  static const List<String> header = [
    'Дата',
    'Время',
    'Группа',
    'ID',
    'ФИО',
    'Статус',
    'Пара',
  ];

  static String sheetRange(String sheetTitle) => "'$sheetTitle'!A1:G";

  static String rowRange(String sheetTitle, int row) =>
      "'$sheetTitle'!A$row:G$row";

  static List<Object?> encode(AttendanceRecord record) => [
    formatDate(record.date),
    formatTime(record.entry.markedAt),
    record.groupName,
    record.student.id,
    record.student.fullName,
    record.entry.status.label,
    record.entry.lessonTitle ?? '',
  ];

  static bool isHeader(List<Object?> row) {
    if (row.isEmpty) return false;
    final first = row.first?.toString().trim().toLowerCase();
    if (first == 'дата') return true;
    // На случай, если пользователь переставил колонки — ищем несколько
    // узнаваемых заголовков.
    final cells = row.map((c) => c?.toString().trim().toLowerCase()).toSet();
    return cells.containsAll({'дата', 'группа', 'фио', 'статус'});
  }

  static AttendanceRecord? decode(List<Object?> row) {
    if (row.length < 6 || isHeader(row)) return null;

    final date = parseDate(row[0]);
    final groupName = row[2]?.toString().trim() ?? '';
    final studentId = row[3]?.toString().trim() ?? '';
    final fullName = row[4]?.toString().trim() ?? '';
    final status = AttendanceStatus.tryParse(row[5]);
    final lessonTitle = row.length > 6
        ? (row[6]?.toString().trim() ?? '')
        : '';

    if (date == null ||
        groupName.isEmpty ||
        studentId.isEmpty ||
        fullName.isEmpty ||
        status == null) {
      return null;
    }

    return AttendanceRecord(
      groupName: groupName,
      date: date,
      student: Student(id: studentId, fullName: fullName),
      entry: AttendanceEntry(
        status: status,
        markedAt: parseMarkedAt(date, row[1]),
        lessonTitle: lessonTitle.isEmpty ? null : lessonTitle,
      ),
    );
  }

  static DateTime? parseDate(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    if (text.isEmpty) return null;

    final iso = DateTime.tryParse(text);
    if (iso != null) return dateOnly(iso);

    // Google Таблицы могут вернуть дату как серийный номер (дни с 30.12.1899),
    // если ячейку отформатировали как дату.
    final serial = num.tryParse(text);
    if (serial != null && serial > 0 && serial < 100000) {
      return dateOnly(
        DateTime(1899, 12, 30).add(Duration(days: serial.floor())),
      );
    }

    // Поддержка формата, который часто ставят вручную: 09.11.2026.
    final match = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$').firstMatch(text);
    if (match != null) {
      final day = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final year = int.parse(match.group(3)!);
      final date = DateTime(year, month, day);
      if (date.year == year && date.month == month && date.day == day) {
        return date;
      }
    }
    return null;
  }

  static DateTime parseMarkedAt(DateTime date, Object? timeValue) {
    final text = timeValue?.toString().trim() ?? '';
    final match = RegExp(r'^(\d{1,2}):(\d{2})(?::(\d{2}))?$').firstMatch(text);
    if (match == null) return date;

    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final second = int.tryParse(match.group(3) ?? '') ?? 0;
    if (hour > 23 || minute > 59 || second > 59) return date;

    return DateTime(date.year, date.month, date.day, hour, minute, second);
  }

  static String formatDate(DateTime date) {
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static String formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
