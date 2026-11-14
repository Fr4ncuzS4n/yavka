import '../../models/attendance_session.dart';
import '../../models/sync_notification.dart';
import 'notifications_sheet_codec.dart';
import 'sheet_attendance_codec.dart';
import 'sheets_api.dart';

/// Результат отправки отметок в таблицу.
class SyncResult {
  const SyncResult({
    required this.updated,
    required this.appended,
    required this.skipped,
  });

  final int updated;
  final int appended;
  final int skipped;

  int get total => updated + appended;

  @override
  String toString() =>
      'обновлено: $updated, добавлено: $appended, пропущено: $skipped';
}

/// Синхронизация посещаемости с листом Google Таблицы.
///
/// Важно: сервис не меняет права доступа и не удаляет таблицу. Он пишет
/// значения через Sheets API, поэтому достаточно прав «Редактор» — владельцем
/// таблицы может быть другой человек.
class GoogleSheetsSyncService {
  GoogleSheetsSyncService(this._api);

  final SheetsApi _api;

  /// Добавляет/обновляет отметки текущего дня.
  Future<SyncResult> push({
    required String spreadsheetId,
    required String sheetTitle,
    required AttendanceSession session,
  }) async {
    final meta = await _api.getSpreadsheet(spreadsheetId);
    if (!meta.hasTab(sheetTitle)) {
      await _api.addSheet(spreadsheetId, sheetTitle);
    }

    final range = SheetAttendanceCodec.sheetRange(sheetTitle);
    final values = await _api.getValues(spreadsheetId, range);

    var dataRows = values;
    var firstDataRow = 1;

    if (values.isEmpty) {
      await _api.updateValues(spreadsheetId, "'$sheetTitle'!A1:G1", [
        SheetAttendanceCodec.header,
      ]);
      dataRows = const [];
      firstDataRow = 2;
    } else if (SheetAttendanceCodec.isHeader(values.first)) {
      dataRows = values.sublist(1);
      firstDataRow = 2;

      // Старые таблицы были без колонки «Пара» — дополняем заголовок.
      if (values.first.length < SheetAttendanceCodec.header.length) {
        await _api.updateValues(spreadsheetId, "'$sheetTitle'!A1:G1", [
          SheetAttendanceCodec.header,
        ]);
      }
    }

    final rowByKey = <String, int>{};
    for (var i = 0; i < dataRows.length; i++) {
      final record = SheetAttendanceCodec.decode(dataRows[i]);
      if (record != null) rowByKey[record.key] = i + firstDataRow;
    }

    final updates = <SheetValueRange>[];
    final toAppend = <List<Object?>>[];
    var skipped = 0;

    for (final record in session.records) {
      final row = SheetAttendanceCodec.encode(record);
      final existingRow = rowByKey[record.key];
      if (existingRow != null) {
        updates.add(
          SheetValueRange(
            range: SheetAttendanceCodec.rowRange(sheetTitle, existingRow),
            values: [row],
          ),
        );
      } else {
        toAppend.add(row);
      }
    }

    // Строки, которые не удалось разобрать, не трогаем — пользователь мог
    // добавить их вручную.
    skipped = dataRows.length - rowByKey.length;

    if (updates.isNotEmpty) {
      await _api.batchUpdateValues(spreadsheetId, updates);
    }
    if (toAppend.isNotEmpty) {
      await _api.appendValues(spreadsheetId, range, toAppend);
    }

    return SyncResult(
      updated: updates.length,
      appended: toAppend.length,
      skipped: skipped < 0 ? 0 : skipped,
    );
  }

  /// Читает отметки текущего дня и объединяет их с локальными.
  Future<AttendanceSession> pull({
    required String spreadsheetId,
    required String sheetTitle,
    required AttendanceSession local,
  }) async {
    final meta = await _api.getSpreadsheet(spreadsheetId);
    if (!meta.hasTab(sheetTitle)) return local;

    final values = await _api.getValues(
      spreadsheetId,
      SheetAttendanceCodec.sheetRange(sheetTitle),
    );

    final remote = <AttendanceRecord>[];
    for (final row in values) {
      final record = SheetAttendanceCodec.decode(row);
      if (record == null) continue;
      if (record.groupName != local.groupName) continue;
      if (!isSameDate(record.date, local.date)) continue;
      remote.add(record);
    }

    return local.mergeRemote(remote);
  }

  /// Отправляет уведомления о отметках на парах в лист «Уведомления».
  ///
  /// Все, кто пользуется этой таблицей, увидят их при следующей загрузке.
  Future<void> pushNotifications({
    required String spreadsheetId,
    required List<SyncNotification> notifications,
  }) async {
    if (notifications.isEmpty) return;

    final title = SheetNotificationsCodec.sheetTitle;
    final meta = await _api.getSpreadsheet(spreadsheetId);
    if (!meta.hasTab(title)) {
      await _api.addSheet(spreadsheetId, title);
    }

    final values = await _api.getValues(
      spreadsheetId,
      SheetNotificationsCodec.sheetRange(title),
    );
    if (values.isEmpty) {
      await _api.updateValues(spreadsheetId, "'$title'!A1:F1", [
        SheetNotificationsCodec.header,
      ]);
    }

    await _api.appendValues(
      spreadsheetId,
      SheetNotificationsCodec.sheetRange(title),
      [
        for (final notification in notifications)
          SheetNotificationsCodec.encode(notification),
      ],
    );
  }

  /// Читает уведомления из листа «Уведомления».
  ///
  /// Если указана [groupName] — остаются уведомления только этой группы.
  Future<List<SyncNotification>> pullNotifications({
    required String spreadsheetId,
    String? groupName,
  }) async {
    final title = SheetNotificationsCodec.sheetTitle;
    final meta = await _api.getSpreadsheet(spreadsheetId);
    if (!meta.hasTab(title)) return const [];

    final values = await _api.getValues(
      spreadsheetId,
      SheetNotificationsCodec.sheetRange(title),
    );

    final notifications = <SyncNotification>[];
    for (final row in values) {
      final notification = SheetNotificationsCodec.decode(row);
      if (notification == null) continue;
      if (groupName != null && notification.groupName != groupName) continue;
      notifications.add(notification);
    }
    return notifications;
  }
}
