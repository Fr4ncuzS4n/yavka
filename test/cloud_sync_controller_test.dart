import 'package:flutter_test/flutter_test.dart';
import 'package:yavka/data/attendance_controller.dart';
import 'package:yavka/data/cloud_settings.dart';
import 'package:yavka/models/attendance_entry.dart';
import 'package:yavka/models/attendance_session.dart';
import 'package:yavka/models/attendance_status.dart';
import 'package:yavka/models/student.dart';
import 'package:yavka/services/cloud/cloud_sync_controller.dart';
import 'package:yavka/services/cloud/google_auth_service.dart';
import 'package:yavka/services/cloud/month_grid_codec.dart';
import 'package:yavka/services/cloud/oauth/oauth_models.dart';
import 'package:yavka/services/cloud/token_store.dart';

import 'support/fake_sheets_api.dart';
import 'support/month_journal_fixture.dart';

void main() {
  const group = 'БИТ-24-03';
  final date = DateTime(2026, 11, 9); // понедельник 9 ноября
  final month = DateTime(2026, 11);
  const alexey = Student(id: '1', fullName: 'Алексей Морозов');
  const title = 'Ноябрь 2026';

  AttendanceController attendanceWith(Map<String, AttendanceEntry> entries) =>
      AttendanceController(
        session: AttendanceSession(
          groupName: group,
          date: date,
          students: const [alexey],
          entries: entries,
        ),
      );

  ({
    CloudSyncController cloud,
    FakeSheetsApi api,
    MemoryCloudSettingsStore settings,
    AttendanceController attendance,
  })
  build({Map<String, AttendanceEntry>? entries, bool failBatchUpdate = false}) {
    final attendance = attendanceWith(entries ?? {});
    final api = FakeSheetsApi()..failBatchUpdate = failBatchUpdate;
    final settings = MemoryCloudSettingsStore(
      const CloudSettings(
        clientId: 'test-client-id.apps.googleusercontent.com',
        clientSecret: 'test-client-secret',
      ),
    );
    final cloud = CloudSyncController(
      attendance: attendance,
      auth: GoogleAuthService(
        flow: FakeOAuthFlow(),
        tokenStore: MemoryTokenStore(),
      ),
      sheetsApi: api,
      settingsStore: settings,
      isWeb: false,
    );
    return (cloud: cloud, api: api, settings: settings, attendance: attendance);
  }

  test('ссылка на Google Таблицу распознаётся', () {
    const id = '1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789';
    expect(
      parseSpreadsheetId(
        'https://docs.google.com/spreadsheets/d/$id/edit#gid=0',
      ),
      id,
    );
    expect(parseSpreadsheetId(id), id);
    expect(parseSpreadsheetId('  $id  '), id);
    expect(parseSpreadsheetId('https://example.com/not-a-sheet'), isNull);
    expect(parseSpreadsheetId(''), isNull);
  });

  test('по умолчанию выбран месяц сессии', () {
    final env = build();
    expect(env.cloud.selectedMonth.year, 2026);
    expect(env.cloud.selectedMonth.month, 11);
  });

  test('подключение таблицы сохраняет ID и пишет отметки в лист месяца',
      () async {
    const id = '1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789';
    final env = build(
      entries: {
        '1': AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: DateTime(2026, 11, 9, 9),
        ),
      },
    );

    await env.cloud.initialize();
    await env.cloud.signIn();
    await env.cloud.connectSpreadsheet(
      'https://docs.google.com/spreadsheets/d/$id/edit',
    );

    expect(env.cloud.error, isNull);
    expect(env.cloud.spreadsheetId, id);
    expect((await env.settings.load()).spreadsheetId, id);

    // Лист месяца создан, отметка «пришёл» лежит в заливке блока дня.
    expect(env.api.hasSheet(title), isTrue);
    final day9 = MonthGridCodec.firstColumnOf(month, 9);
    expect(env.api.cell(title, 3, day9).backgroundColor, 0x00CC00);
    // Студент добавлен списком под шапкой.
    expect(env.api.cell(title, 3, 1).value, 'Алексей Морозов');
  });

  test('создание новой таблицы подключает её и рисует шапку-журнал',
      () async {
    final env = build();

    await env.cloud.initialize();
    await env.cloud.signIn();
    await env.cloud.createSpreadsheet();

    expect(env.cloud.error, isNull);
    expect(env.cloud.spreadsheetId, 'created-spreadsheet');
    expect(env.api.hasSheet(title), isTrue);
    expect(env.api.cell(title, 0, 1).value, 'НОЯБРЬ');
    expect(env.api.cell(title, 1, 0).value, '№');
    expect(env.api.cell(title, 1, 1).value, 'ФИО');
    expect(env.api.mergeCount(title), 2 * 30);
  });

  test('загрузка с Диска обновляет локальные отметки', () async {
    const id = '1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789';
    final env = build(
      entries: {
        '1': AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: DateTime(2026, 11, 9, 9),
        ),
      },
    );
    seedJournal(
      env.api,
      month: month,
      students: const [alexey],
      marks: {
        9: {
          '1': AttendanceEntry(
            status: AttendanceStatus.late,
            markedAt: DateTime(2026, 11, 9, 9, 40),
          ),
        },
      },
    );

    await env.cloud.initialize();
    await env.cloud.signIn();
    await env.cloud.connectSpreadsheet(id);

    // Отметка листа (опоздал к 9:40) победила локальную.
    expect(env.attendance.entryFor('1')?.status, AttendanceStatus.late);
    expect(env.attendance.entryFor('1')?.markedAt, DateTime(2026, 11, 9, 9, 40));
    expect(env.cloud.error, isNull);
  });

  test('список группы подтягивается с листа', () async {
    const id = '1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789';
    const maria = Student(id: '2', fullName: 'Мария Соколова');
    final env = build();
    seedJournal(
      env.api,
      month: month,
      students: const [alexey, maria],
    );

    await env.cloud.initialize();
    await env.cloud.signIn();
    await env.cloud.connectSpreadsheet(id);

    expect(env.attendance.students.map((s) => s.fullName), contains(maria.fullName));
    expect(env.attendance.students.map((s) => s.fullName), contains(alexey.fullName));
  });

  test('выбор месяца сохраняется и переключает лист журнала', () async {
    const id = '1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789';
    final env = build();

    await env.cloud.initialize();
    await env.cloud.signIn();
    await env.cloud.connectSpreadsheet(id);

    // Лист ноября появился от автосинхронизации при подключении.
    expect(env.api.hasSheet(title), isTrue);

    await env.cloud.selectMonth(DateTime(2026, 10));

    expect(env.cloud.error, isNull);
    expect(env.cloud.selectedMonth.year, 2026);
    expect(env.cloud.selectedMonth.month, 10);

    final stored = await env.settings.load();
    expect(stored.sheetYear, 2026);
    expect(stored.sheetMonth, 10);

    await env.cloud.syncNow();

    // В новом месяце свой лист с шапкой; ноябрьский не тронут.
    expect(env.api.hasSheet('Октябрь 2026'), isTrue);
    expect(env.api.cell('Октябрь 2026', 0, 1).value, 'ОКТЯБРЬ');
    expect(env.api.cell('Октябрь 2026', 1, 0).value, '№');
  });

  test('ошибка прав редактора сохраняется в состоянии', () async {
    final env = build(
      entries: {
        '1': AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: DateTime(2026, 11, 9, 9),
        ),
      },
      failBatchUpdate: true,
    );

    await env.cloud.initialize();
    await env.cloud.signIn();
    await env.cloud.connectSpreadsheet(
      'https://docs.google.com/spreadsheets/d/'
      '1AbCdEfGhIjKlMnOpQrStUvWxYz0123456789/edit',
    );

    expect(env.cloud.error, contains('Редактор'));
    expect(env.cloud.isSignedIn, isTrue);
  });
}

class FakeOAuthFlow implements OAuthFlow {
  @override
  Future<OAuthTokens> signIn(GoogleOAuthConfig config) async {
    return OAuthTokens(
      accessToken: 'test-access-token',
      refreshToken: 'test-refresh-token',
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      scopes: kGoogleSheetsScopes,
    );
  }

  @override
  Future<OAuthTokens> refresh(
    GoogleOAuthConfig config,
    OAuthTokens tokens,
  ) async {
    return OAuthTokens(
      accessToken: 'refreshed-access-token',
      refreshToken: tokens.refreshToken,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      scopes: tokens.scopes,
    );
  }

  @override
  Future<void> signOut(OAuthTokens? tokens) async {}
}
