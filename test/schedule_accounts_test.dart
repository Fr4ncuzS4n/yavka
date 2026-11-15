import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yavka/data/attendance_controller.dart';
import 'package:yavka/data/cloud_settings.dart';
import 'package:yavka/data/schedule_controller.dart';
import 'package:yavka/data/schedule_store.dart';
import 'package:yavka/models/schedule_lesson.dart';
import 'package:yavka/services/cloud/cloud_sync_controller.dart';
import 'package:yavka/services/cloud/google_auth_service.dart';
import 'package:yavka/services/cloud/oauth/oauth_models.dart';
import 'package:yavka/services/cloud/token_store.dart';

import 'support/fake_sheets_api.dart';

ScheduleLesson lesson(int id, int weekday) => ScheduleLesson(
  id: 'l$id',
  weekday: weekday,
  startMinutes: 9 * 60,
  endMinutes: 10 * 60 + 30,
  subject: 'Математика',
);

/// Идентификаторы пар — ScheduleLesson не сравнивается по значению.
List<String> ids(List<ScheduleLesson> lessons) =>
    [for (final lesson in lessons) lesson.id];

void main() {
  group('Хранилище расписания по почтам', () {
    test('без почты расписание лежит под общим ключом — как раньше', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesScheduleStore(preferences);
      expect(store.storageKey, 'yavka.schedule.lessons.v1');
    });

    test('у каждой почты — свой ключ и своё расписание', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final factory = SharedPreferencesScheduleStoreFactory(preferences);

      await factory.forAccount('ivan@mail.ru').save([lesson(1, 1)]);
      await factory
          .forAccount('maria@mail.ru')
          .save([lesson(2, 2), lesson(3, 2)]);
      await factory.forAccount(null).save([lesson(4, 3)]);

      // Регистр и пробелы в почте не создают отдельный аккаунт.
      expect(
        (factory.forAccount('  IVAN@mail.RU ')
                as SharedPreferencesScheduleStore)
            .storageKey,
        'yavka.schedule.lessons.v1.ivan@mail.ru',
      );

      expect(ids(await factory.forAccount('ivan@mail.ru').load()), ['l1']);
      expect(
        ids(await factory.forAccount('maria@mail.ru').load()),
        ['l2', 'l3'],
      );
      expect(ids(await factory.forAccount(null).load()), ['l4']);
    });

    test('старое расписание из общего ключа читается как локальное', () async {
      SharedPreferences.setMockInitialValues({
        'yavka.schedule.lessons.v1': '''
          [{"id":"old","weekday":5,"startMinutes":540,"endMinutes":630,"subject":"Физика"}]
        ''',
      });
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesScheduleStore(preferences);
      final lessons = await store.load();
      expect(lessons, hasLength(1));
      expect(lessons.first.subject, 'Физика');
    });
  });

  group('Переключение аккаунта в контроллере', () {
    test('расписания разных почт не смешиваются', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final schedule = ScheduleController(
        storeFactory: SharedPreferencesScheduleStoreFactory(preferences),
      );
      await schedule.load();

      await schedule.switchAccount('ivan@mail.ru');
      schedule.add(lesson(1, 1));

      await schedule.switchAccount('maria@mail.ru');
      expect(schedule.lessons, isEmpty);
      schedule.add(lesson(2, 2));

      // Возврат к прежним почтам поднимает их расписания.
      await schedule.switchAccount('ivan@mail.ru');
      expect(ids(schedule.lessons), ['l1']);
      expect(schedule.accountEmail, 'ivan@mail.ru');

      await schedule.switchAccount('maria@mail.ru');
      expect(ids(schedule.lessons), ['l2']);
    });

    test('выход возвращает локальное расписание', () async {
      SharedPreferences.setMockInitialValues({
        'yavka.schedule.lessons.v1': '''
          [{"id":"local","weekday":1,"startMinutes":540,"endMinutes":630,"subject":"Локальная пара"}]
        ''',
      });
      final preferences = await SharedPreferences.getInstance();
      final schedule = ScheduleController(
        store: SharedPreferencesScheduleStore(preferences),
        storeFactory: SharedPreferencesScheduleStoreFactory(preferences),
      );
      await schedule.load();
      expect(schedule.lessons, hasLength(1));

      await schedule.switchAccount('ivan@mail.ru');
      schedule.add(lesson(1, 1));
      expect(ids(schedule.lessons), ['l1']);

      await schedule.switchAccount(null);
      expect(schedule.accountEmail, isNull);
      expect(schedule.lessons.single.subject, 'Локальная пара');

      // Локальное расписание не пострадало, аккаунтное сохранилось.
      await schedule.switchAccount('ivan@mail.ru');
      expect(ids(schedule.lessons), ['l1']);
    });

    test('повторное переключение на ту же почту ничего не меняет', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final schedule = ScheduleController(
        storeFactory: SharedPreferencesScheduleStoreFactory(preferences),
      );
      await schedule.switchAccount('ivan@mail.ru');
      schedule.add(lesson(1, 1));

      await schedule.switchAccount('ivan@mail.ru');
      expect(ids(schedule.lessons), ['l1']);
    });

    test('без фабрики переключение недоступно', () async {
      final schedule = ScheduleController();
      await schedule.load();
      schedule.add(lesson(1, 1));

      await schedule.switchAccount('ivan@mail.ru');
      expect(schedule.accountEmail, isNull);
      expect(ids(schedule.lessons), ['l1']);
    });
  });

  group('Смена аккаунта через облачный контроллер', () {
    test('вход и выход переключают расписание по почте', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final schedule = ScheduleController(
        storeFactory: SharedPreferencesScheduleStoreFactory(preferences),
      );
      await schedule.load();

      // Заранее сохранённое расписание аккаунта ivan.
      await SharedPreferencesScheduleStoreFactory(
        preferences,
      ).forAccount('ivan@mail.ru').save([lesson(1, 1)]);

      final cloud = CloudSyncController(
        attendance: AttendanceController.inMemory(),
        auth: GoogleAuthService(
          flow: _FakeFlow(),
          tokenStore: MemoryTokenStore(),
          accountEmailFetcher: (token) async => 'ivan@mail.ru',
        ),
        sheetsApi: FakeSheetsApi(),
        settingsStore: MemoryCloudSettingsStore(
          const CloudSettings(
            clientId: 'test-client-id.apps.googleusercontent.com',
            clientSecret: 'test-client-secret',
          ),
        ),
        isWeb: false,
        schedule: schedule,
      );
      await cloud.initialize();

      // Вход дожидается перепривязки расписания на почту аккаунта.
      await cloud.signIn();
      expect(cloud.accountEmail, 'ivan@mail.ru');
      expect(schedule.accountEmail, 'ivan@mail.ru');
      expect(ids(schedule.lessons), ['l1']);

      await cloud.signOut();
      expect(cloud.accountEmail, isNull);
      expect(schedule.accountEmail, isNull);
      expect(schedule.lessons, isEmpty);
    });
  });
}

/// Поток входа, отдающий токен без почты — почту узнаёт fetcher.
class _FakeFlow implements OAuthFlow {
  @override
  Future<OAuthTokens> signIn(GoogleOAuthConfig config) async => OAuthTokens(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    scopes: kGoogleSheetsScopes,
  );

  @override
  Future<OAuthTokens> refresh(
    GoogleOAuthConfig config,
    OAuthTokens tokens,
  ) async => tokens;

  @override
  Future<void> signOut(OAuthTokens? tokens) async {}
}
