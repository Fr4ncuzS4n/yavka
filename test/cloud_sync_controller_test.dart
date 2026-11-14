// Тесты облачного контроллера: таблица не меняется, приложение
// подстраивается под журнал, месяц подбирается из названия таблицы.

import 'package:flutter_test/flutter_test.dart';
import 'package:yavka/data/attendance_controller.dart';
import 'package:yavka/data/cloud_settings.dart';
import 'package:yavka/data/schedule_controller.dart';
import 'package:yavka/models/attendance_entry.dart';
import 'package:yavka/models/attendance_session.dart';
import 'package:yavka/models/attendance_status.dart';
import 'package:yavka/models/schedule_lesson.dart';
import 'package:yavka/models/student.dart';
import 'package:yavka/services/cloud/cloud_sync_controller.dart';
import 'package:yavka/services/cloud/google_auth_service.dart';
import 'package:yavka/services/cloud/journal_mapping.dart';
import 'package:yavka/services/cloud/oauth/oauth_models.dart';
import 'package:yavka/services/cloud/token_store.dart';

import 'support/fake_sheets_api.dart';
import 'support/month_journal_fixture.dart';

void main() {
  const group = 'БИТ-24-03';
  final date = DateTime(2026, 11, 9); // понедельник 9 ноября
  final month = DateTime(2026, 11);
  const alexey = Student(id: '1', fullName: 'Алексей Морозов');
  const maria = Student(id: '2', fullName: 'Мария Соколова');
  const tabTitle = 'НОЯБРЬ : 2026';
  const spreadsheetId = 'created-spreadsheet';

  // Блоки по дням недели (7 колонок цикла): пн — 3 колонки.
  const pairsByDay = [1, 3, 2, 1, 2, 1, 1];

  int blockStart(int day) {
    var column = 2;
    for (var d = 1; d < day; d++) {
      column += pairsByDay[(d - 1) % pairsByDay.length];
    }
    return column;
  }

  ScheduleController scheduleWith({int monday = 3}) {
    final schedule = ScheduleController.inMemory();
    for (var i = 1; i <= monday; i++) {
      schedule.add(
        ScheduleLesson(
          id: 'mon-$i',
          weekday: 1,
          startMinutes: 480 + i * 100,
          subject: 'Понедельничная пара $i',
        ),
      );
    }
    return schedule;
  }

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
    ScheduleController schedule,
  })
  build({
    Map<String, AttendanceEntry>? entries,
    bool failBatchUpdate = false,
    int monday = 3,
  }) {
    final attendance = attendanceWith(entries ?? {});
    final schedule = scheduleWith(monday: monday);
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
      schedule: schedule,
    );
    return (
      cloud: cloud,
      api: api,
      settings: settings,
      attendance: attendance,
      schedule: schedule,
    );
  }

  /// Подключает таблицу «НОЯБРЬ : 2026» с готовым журналом.
  Future<void> connectJournal(
    CloudSyncController cloud,
    FakeSheetsApi api, {
    Map<int, Map<String, Map<int, AttendanceEntry>>> marks = const {},
    List<Student> students = const [alexey, maria],
  }) async {
    seedJournal(
      api,
      month: month,
      pairsByDay: pairsByDay,
      students: students,
      marks: marks,
    );
    await api.createSpreadsheet('НОЯБРЬ : 2026');
    await cloud.initialize();
    await cloud.signIn();
    await cloud.connectSpreadsheet(
      'https://docs.google.com/spreadsheets/d/$spreadsheetId/edit',
    );
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

  test('подключение без настройки журнала ничего не пишет в таблицу',
      () async {
    final env = build();
    await connectJournal(env.cloud, env.api);

    expect(env.cloud.error, isNull);
    expect(env.cloud.needsJournalSetup, isTrue);
    // Ни одного изменения структуры и содержимого.
    expect(env.api.batchUpdateCalls, 0);
  });

  test('настройка журнала: расспрос, проверка и сохранение', () async {
    final env = build(entries: {
      '1': AttendanceEntry(
        status: AttendanceStatus.came,
        markedAt: DateTime(2026, 11, 9, 9),
      ),
    });
    await connectJournal(env.cloud, env.api);

    // Приложение пробует раскладку и сверяет с расписанием.
    final preview = await env.cloud.previewJournal(
      tabTitle: tabTitle,
      dayRow: 1,
      fioColumn: 1,
      firstStudentRow: 3,
    );
    expect(preview.month, month);
    expect(preview.check.ok, isTrue);

    await env.cloud.saveJournalMapping(
      const JournalMapping(
        tabTitle: tabTitle,
        dayRow: 1,
        fioColumn: 1,
        firstStudentRow: 3,
      ),
    );

    expect(env.cloud.error, isNull);
    expect(env.cloud.needsJournalSetup, isFalse);
    // Месяц подобрался из названия таблицы.
    expect(env.cloud.journalMonth, month);

    // Отметка «пришёл» легла в первую колонку блока 9 ноября.
    expect(
      env.api.cell(tabTitle, 3, blockStart(9)).backgroundColor,
      0x00CC00,
    );
    // Писались только ячейки: никаких updateSheetProperties/mergeCells.
    for (final batch in env.api.batchRequestLog) {
      for (final request in batch) {
        expect(request, 'updateCells');
      }
    }
  });

  test('настройка сохраняется между запусками', () async {
    final env = build();
    await connectJournal(env.cloud, env.api);
    await env.cloud.saveJournalMapping(
      const JournalMapping(
        tabTitle: tabTitle,
        dayRow: 1,
        fioColumn: 1,
        firstStudentRow: 3,
      ),
    );

    final stored = await env.settings.load();
    expect(stored.journalMapping!.tabTitle, tabTitle);
    expect(stored.journalMapping!.dayRow, 1);
    expect(stored.journalMapping!.fioColumn, 1);
    expect(stored.journalMapping!.firstStudentRow, 3);
  });

  test('без настройки журнала синхронизация просит настроить', () async {
    final env = build();
    await connectJournal(env.cloud, env.api);

    await env.cloud.syncNow();

    expect(env.cloud.error, contains('настройте журнал'));
  });

  test('таблица не согласована с расписанием — синхронизация блокируется',
      () async {
    // Четыре пары в понедельник, а в блоке дня 3 колонки.
    final env = build(entries: {
      '1': AttendanceEntry(
        status: AttendanceStatus.came,
        markedAt: DateTime(2026, 11, 9, 9),
      ),
    }, monday: 4);
    await connectJournal(env.cloud, env.api);

    await env.cloud.saveJournalMapping(
      const JournalMapping(
        tabTitle: tabTitle,
        dayRow: 1,
        fioColumn: 1,
        firstStudentRow: 3,
      ),
    );

    expect(env.cloud.error, contains('День 2'));
    // Отметка не ушла: структура и содержимое не тронуты.
    expect(env.api.batchUpdateCalls, 0);

    await env.cloud.syncNow();
    expect(env.cloud.error, contains('День 2'));
  });

  test('загрузка с Диска обновляет локальные отметки по ФИО', () async {
    final env = build(entries: {
      '1': AttendanceEntry(
        status: AttendanceStatus.came,
        markedAt: DateTime(2026, 11, 9, 9),
      ),
    });
    await connectJournal(
      env.cloud,
      env.api,
      marks: {
        9: {
          'Алексей Морозов': {
            1: AttendanceEntry(
              status: AttendanceStatus.late,
              markedAt: DateTime(2026, 11, 9, 9, 40),
            ),
          },
        },
      },
    );

    await env.cloud.saveJournalMapping(
      const JournalMapping(
        tabTitle: tabTitle,
        dayRow: 1,
        fioColumn: 1,
        firstStudentRow: 3,
      ),
    );

    // Отметка листа (опоздал к 9:40) победила локальную; студент
    // остался с локальным идентификатором.
    expect(env.cloud.error, isNull);
    expect(env.attendance.entryFor('1')?.status, AttendanceStatus.late);
    expect(
      env.attendance.entryFor('1')?.markedAt,
      DateTime(2026, 11, 9, 9, 40),
    );
    // Список группы подтянулся по ФИО.
    expect(
      env.attendance.students.map((student) => student.fullName),
      contains(maria.fullName),
    );
  });

  test('название без месяца — понятная ошибка вместо записи', () async {
    final env = build(entries: {
      '1': AttendanceEntry(
        status: AttendanceStatus.came,
        markedAt: DateTime(2026, 11, 9, 9),
      ),
    });
    seedJournal(
      env.api,
      month: month,
      pairsByDay: pairsByDay,
      students: const [alexey],
      tabTitle: 'Посещаемость',
    );
    await env.api.createSpreadsheet('Посещаемость');
    await env.cloud.initialize();
    await env.cloud.signIn();
    await env.cloud.connectSpreadsheet(
      'https://docs.google.com/spreadsheets/d/$spreadsheetId/edit',
    );

    await env.cloud.saveJournalMapping(
      const JournalMapping(
        tabTitle: 'Посещаемость',
        dayRow: 1,
        fioColumn: 1,
        firstStudentRow: 3,
      ),
    );

    expect(env.cloud.error, contains('определить месяц'));
    expect(env.api.batchUpdateCalls, 0);
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
    await connectJournal(env.cloud, env.api);

    await env.cloud.saveJournalMapping(
      const JournalMapping(
        tabTitle: tabTitle,
        dayRow: 1,
        fioColumn: 1,
        firstStudentRow: 3,
      ),
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
