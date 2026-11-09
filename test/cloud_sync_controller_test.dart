import 'package:flutter_test/flutter_test.dart';
import 'package:yavka/data/attendance_controller.dart';
import 'package:yavka/data/cloud_settings.dart';
import 'package:yavka/models/attendance_entry.dart';
import 'package:yavka/models/attendance_session.dart';
import 'package:yavka/models/attendance_status.dart';
import 'package:yavka/models/student.dart';
import 'package:yavka/services/cloud/cloud_sync_controller.dart';
import 'package:yavka/services/cloud/google_auth_service.dart';
import 'package:yavka/services/cloud/oauth/oauth_models.dart';
import 'package:yavka/services/cloud/sheet_attendance_codec.dart';
import 'package:yavka/services/cloud/token_store.dart';

import 'support/fake_sheets_api.dart';

void main() {
  const group = 'БИТ-24-03';
  final date = DateTime(2026, 11, 9);
  const alexey = Student(id: '1', fullName: 'Алексей Морозов');

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
  build({Map<String, AttendanceEntry>? entries, bool failAppend = false}) {
    final attendance = attendanceWith(entries ?? {});
    final api = FakeSheetsApi()..failAppend = failAppend;
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

  test('подключение таблицы сохраняет ID и отправляет отметки', () async {
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
    expect(env.api.rowsFor('Посещаемость'), hasLength(2));
    expect(env.api.rowsFor('Посещаемость')[1][5], 'Пришёл');
  });

  test('создание новой таблицы подключает её и пишет заголовок', () async {
    final env = build();

    await env.cloud.initialize();
    await env.cloud.signIn();
    await env.cloud.createSpreadsheet();

    expect(env.cloud.error, isNull);
    expect(env.cloud.spreadsheetId, 'created-spreadsheet');
    expect(env.api.rowsFor('Посещаемость').first, SheetAttendanceCodec.header);
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

    await env.cloud.initialize();
    await env.cloud.signIn();
    await env.cloud.connectSpreadsheet(id);

    env.api.setRows('Посещаемость', [
      SheetAttendanceCodec.header,
      SheetAttendanceCodec.encode(
        AttendanceRecord(
          groupName: group,
          date: date,
          student: alexey,
          entry: AttendanceEntry(
            status: AttendanceStatus.late,
            markedAt: DateTime(2026, 11, 9, 9, 40),
          ),
        ),
      ),
    ]);

    await env.cloud.pullNow();

    expect(env.attendance.entryFor('1')?.status, AttendanceStatus.late);
    expect(env.cloud.error, isNull);
  });

  test('ошибка прав редактора сохраняется в состоянии', () async {
    final env = build(
      entries: {
        '1': AttendanceEntry(
          status: AttendanceStatus.came,
          markedAt: DateTime(2026, 11, 9, 9),
        ),
      },
      failAppend: true,
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
