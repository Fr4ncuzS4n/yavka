import '../../models/sync_notification.dart';
import 'sheet_attendance_codec.dart';

/// Формат листа «Уведомления» в той же Google Таблице, где хранится
/// посещаемость.
///
/// Каждый, кто пользуется таблицей, видит уведомления других: приложение
/// читает этот лист при синхронизации и показывает новые записи.
abstract final class SheetNotificationsCodec {
  /// Название листа с уведомлениями.
  static const String sheetTitle = 'Уведомления';

  static const List<String> header = [
    'Дата',
    'Время',
    'Автор',
    'Группа',
    'Пара',
    'Сообщение',
  ];

  static String sheetRange(String sheetTitle) => "'$sheetTitle'!A1:F";

  static List<Object?> encode(SyncNotification notification) => [
    SheetAttendanceCodec.formatDate(notification.createdAt),
    SheetAttendanceCodec.formatTime(notification.createdAt),
    notification.author,
    notification.groupName,
    notification.lessonTitle,
    notification.message,
  ];

  /// Строка таблицы → уведомление; испорченные строки пропускаются.
  static SyncNotification? decode(List<Object?> row) {
    if (row.length < 6 || row.first?.toString().trim().toLowerCase() == 'дата') {
      return null;
    }

    final date = SheetAttendanceCodec.parseDate(row[0]);
    final author = row[2]?.toString().trim() ?? '';
    final groupName = row[3]?.toString().trim() ?? '';
    final lessonTitle = row[4]?.toString().trim() ?? '';
    final message = row[5]?.toString().trim() ?? '';

    if (date == null || groupName.isEmpty || message.isEmpty) return null;

    final createdAt = SheetAttendanceCodec.parseMarkedAt(date, row[1]);

    // Стабильный ID для дедупликации: одна строка таблицы — одно
    // уведомление, сколько бы раз её ни читали.
    final id =
        '${SheetAttendanceCodec.formatDate(createdAt)}'
        '|${SheetAttendanceCodec.formatTime(createdAt)}'
        '|$author|$groupName|$lessonTitle|$message';

    return SyncNotification(
      id: id,
      createdAt: createdAt,
      author: author,
      groupName: groupName,
      lessonTitle: lessonTitle,
      message: message,
    );
  }
}
