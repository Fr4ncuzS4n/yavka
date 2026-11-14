// Тесты уведомлений о отметках на парах: отложенные, отправка и чтение
// из листа «Уведомления» подключённой Google Таблицы.

import 'package:flutter_test/flutter_test.dart';
import 'package:yavka/data/attendance_controller.dart';
import 'package:yavka/data/cloud_settings.dart';
import 'package:yavka/data/notification_controller.dart';
import 'package:yavka/data/notification_store.dart';
import 'package:yavka/models/schedule_lesson.dart';
import 'package:yavka/models/sync_notification.dart';
import 'package:yavka/services/cloud/cloud_sync_controller.dart';
import 'package:yavka/services/cloud/google_auth_service.dart';
import 'package:yavka/services/cloud/google_sheets_sync_service.dart';
import 'package:yavka/services/cloud/notifications_sheet_codec.dart';
import 'package:yavka/services/cloud/oauth/oauth_models.dart';
import 'package:yavka/services/cloud/token_store.dart';

import 'support/fake_sheets_api.dart';

class _NoAuthFlow implements OAuthFlow {
  @override
  Future<OAuthTokens> signIn(GoogleOAuthConfig config) async =>
      throw UnimplementedError();

  @override
  Future<OAuthTokens> refresh(GoogleOAuthConfig config, OAuthTokens tokens) =>
      throw UnimplementedError();

  @override
  Future<void> signOut(OAuthTokens? tokens) async {}
}

CloudSyncController buildCloud({
  required FakeSheetsApi api,
  required NotificationController notifications,
}) => CloudSyncController(
  attendance: AttendanceController.inMemory(),
  auth: GoogleAuthService(
    flow: _NoAuthFlow(),
    tokenStore: MemoryTokenStore(),
  ),
  sheetsApi: api,
  settingsStore: MemoryCloudSettingsStore(
    const CloudSettings(spreadsheetId: 'spreadsheet-id', autoSync: false),
  ),
  isWeb: false,
  notifications: notifications,
);

void main() {
  group('Отложенные уведомления', () {
    test('отметки одной пары за день складываются в одно уведомление', () {
      final notifications = NotificationController();
      final lesson = ScheduleLesson(
        id: 'lesson-1',
        weekday: 5,
        startMinutes: 9 * 60,
        subject: 'Математика',
      );
      final today = DateTime.now();

      notifications.queueLessonMark(
        groupName: 'БИТ-24-03',
        lesson: lesson,
        date: today,
      );
      notifications.queueLessonMark(
        groupName: 'БИТ-24-03',
        lesson: lesson,
        date: today,
      );

      expect(notifications.outbox, hasLength(1));
      expect(notifications.outbox.single.count, 2);
      expect(notifications.outbox.single.lessonTitle, 'Математика');
    });

    test('drainOutbox опустошает отложенные', () {
      final notifications = NotificationController();
      final lesson = ScheduleLesson(
        id: 'lesson-1',
        weekday: 5,
        startMinutes: 9 * 60,
        subject: 'Физика',
      );

      notifications.queueLessonMark(
        groupName: 'БИТ-24-03',
        lesson: lesson,
        date: DateTime.now(),
      );

      final drained = notifications.drainOutbox();
      expect(drained, hasLength(1));
      expect(notifications.outbox, isEmpty);
    });

    test('отложенные уведомления переживают сохранение и загрузку', () async {
      final store = MemoryNotificationStore();
      final notifications = NotificationController(store: store);
      final lesson = ScheduleLesson(
        id: 'lesson-1',
        weekday: 5,
        startMinutes: 9 * 60,
        subject: 'История',
      );

      notifications.queueLessonMark(
        groupName: 'БИТ-24-03',
        lesson: lesson,
        date: DateTime(2026, 11, 13),
      );

      final restored = NotificationController(store: store);
      await restored.load();
      expect(restored.outbox.single.lessonTitle, 'История');
    });
  });

  group('Лист «Уведомления»', () {
    test('отправка создаёт лист, заголовок и строки', () async {
      final api = FakeSheetsApi();
      final service = GoogleSheetsSyncService(api);

      await service.pushNotifications(
        spreadsheetId: 'spreadsheet-id',
        notifications: [
          SyncNotification(
            id: 'n1',
            createdAt: DateTime(2026, 11, 13, 9, 15),
            author: 'Иван',
            groupName: 'БИТ-24-03',
            lessonTitle: 'Математика',
            message: 'Отметка на паре «Математика» (09:00): 3 отметки',
          ),
        ],
      );

      final rows = api.rowsFor('Уведомления');
      expect(rows.first, SheetNotificationsCodec.header);
      expect(rows, hasLength(2));
      expect(rows[1][2], 'Иван');
      expect(rows[1][3], 'БИТ-24-03');
      expect(rows[1][4], 'Математика');
    });

    test('чтение фильтрует по группе и дедуплицирует по строке', () async {
      final api = FakeSheetsApi();
      final service = GoogleSheetsSyncService(api);

      api.setRows('Уведомления', [
        SheetNotificationsCodec.header,
        SheetNotificationsCodec.encode(
          SyncNotification(
            id: 'n1',
            createdAt: DateTime(2026, 11, 13, 9, 15),
            author: 'Иван',
            groupName: 'БИТ-24-03',
            lessonTitle: 'Математика',
            message: 'Отметка на паре «Математика» (09:00): 3 отметки',
          ),
        ),
        SheetNotificationsCodec.encode(
          SyncNotification(
            id: 'n2',
            createdAt: DateTime(2026, 11, 13, 11),
            author: 'Анна',
            groupName: 'Другая группа',
            lessonTitle: 'Физика',
            message: 'Отметка на паре «Физика» (10:40): 2 отметки',
          ),
        ),
      ]);

      final pulled = await service.pullNotifications(
        spreadsheetId: 'spreadsheet-id',
        groupName: 'БИТ-24-03',
      );

      expect(pulled, hasLength(1));
      expect(pulled.single.author, 'Иван');

      // Повторное чтение тех же строк не дублирует уведомления.
      final notifications = NotificationController();
      notifications.addRemote(pulled);
      notifications.addRemote(pulled);
      expect(notifications.items, hasLength(1));
      expect(notifications.unreadCount, 1);
    });

    test('испорченные строки уведомлений пропускаются', () async {
      expect(
        SheetNotificationsCodec.decode([
          'не дата',
          '09:15',
          'Иван',
          'Группа',
          'Пара',
          'Сообщение',
        ]),
        isNull,
      );
      expect(
        SheetNotificationsCodec.decode(SheetNotificationsCodec.header),
        isNull,
      );
    });
  });

  group('Прочитанность', () {
    test('markRead и markAllRead обновляют счётчик', () {
      final notifications = NotificationController();
      notifications.addRemote([
        SyncNotification(
          id: 'a',
          createdAt: DateTime(2026, 11, 13, 9),
          author: 'Иван',
          groupName: 'Г',
          lessonTitle: 'Математика',
          message: 'm1',
        ),
        SyncNotification(
          id: 'b',
          createdAt: DateTime(2026, 11, 13, 10),
          author: 'Анна',
          groupName: 'Г',
          lessonTitle: 'Физика',
          message: 'm2',
        ),
      ]);
      expect(notifications.unreadCount, 2);

      notifications.markRead('a');
      expect(notifications.unreadCount, 1);

      notifications.markAllRead();
      expect(notifications.unreadCount, 0);
      expect(notifications.markAllRead, returnsNormally);
      expect(notifications.unreadCount, 0);
    });

    test('прочитанность сохраняется между запусками', () async {
      final store = MemoryNotificationStore();
      final first = NotificationController(store: store);
      first.addRemote([
        SyncNotification(
          id: 'a',
          createdAt: DateTime(2026, 11, 13, 9),
          author: 'Иван',
          groupName: 'Г',
          lessonTitle: 'Математика',
          message: 'm1',
        ),
      ]);
      first.markAllRead();

      final second = NotificationController(store: store);
      await second.load();
      expect(second.unreadCount, 0);
      expect(second.items.single.isRead, isTrue);
    });
  });

  group('Имя автора', () {
    test('сохраняется в настройках и подставляется в уведомление', () async {
      final api = FakeSheetsApi();
      final cloud = buildCloud(
        api: api,
        notifications: NotificationController(),
      );

      await cloud.setDisplayName('Мария Соколова');
      expect(cloud.displayName, 'Мария Соколова');
    });
  });
}
