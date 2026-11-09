import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yavka/services/cloud/cloud_exceptions.dart';
import 'package:yavka/services/cloud/google_sheets_api.dart';

void main() {
  GoogleSheetsApi apiWith(MockClient client) => GoogleSheetsApi(
    accessToken: () async => 'test-token',
    client: client,
    baseUrl: 'https://example.test/v4',
  );

  test('403 объясняет, что нужен доступ редактора', () async {
    final api = apiWith(
      MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-token');
        return http.Response(
          jsonEncode({
            'error': {
              'code': 403,
              'message': 'The caller does not have permission',
              'status': 'PERMISSION_DENIED',
            },
          }),
          403,
        );
      }),
    );

    expect(
      () => api.getSpreadsheet('spreadsheet-id'),
      throwsA(isA<GooglePermissionException>()),
    );
  });

  test('403 из-за отключённого Sheets API не путают с правами', () async {
    final api = apiWith(
      MockClient(
        (request) async => http.Response(
          jsonEncode({
            'error': {
              'code': 403,
              'message': 'Google Sheets API has not been used in project '
                  '12345 before or it is disabled. Enable it by visiting '
                  'https://console.developers.google.com/apis/api/'
                  'sheets.googleapis.com/overview?project=12345 then retry.',
              'status': 'PERMISSION_DENIED',
            },
          }),
          403,
        ),
      ),
    );

    expect(
      () => api.getSpreadsheet('spreadsheet-id'),
      throwsA(isA<GoogleSheetsApiDisabledException>()),
    );
  });

  test('403 превышения лимита не путают с правами редактора', () async {
    final api = apiWith(
      MockClient(
        (request) async => http.Response(
          jsonEncode({
            'error': {
              'code': 403,
              'message': 'Quota exceeded',
              'errors': [
                {'reason': 'userRateLimitExceeded'},
              ],
            },
          }),
          403,
        ),
      ),
    );

    expect(
      () => api.getSpreadsheet('spreadsheet-id'),
      throwsA(isA<GoogleRateLimitException>()),
    );
  });

  test('429 предлагает подождать, а не проверять права', () async {
    final api = apiWith(
      MockClient((request) async => http.Response('', 429)),
    );

    expect(
      () => api.getSpreadsheet('spreadsheet-id'),
      throwsA(isA<GoogleRateLimitException>()),
    );
  });

  test('401 требует повторного входа', () async {
    final api = apiWith(MockClient((request) async => http.Response('', 401)));

    expect(
      () => api.getValues('spreadsheet-id', "'Лист'!A1:F"),
      throwsA(isA<GoogleAuthRequiredException>()),
    );
  });

  test('404 сообщает, что таблица не найдена', () async {
    final api = apiWith(MockClient((request) async => http.Response('', 404)));

    expect(
      () => api.getSpreadsheet('missing'),
      throwsA(isA<SpreadsheetNotFoundException>()),
    );
  });

  test('прочая ошибка содержит сообщение Google', () async {
    final api = apiWith(
      MockClient(
        (request) async => http.Response(
          jsonEncode({
            'error': {'message': 'Quota exceeded'},
          }),
          500,
        ),
      ),
    );

    expect(
      () => api.getSpreadsheet('spreadsheet-id'),
      throwsA(
        isA<GoogleApiException>().having(
          (error) => error.message,
          'message',
          contains('Quota exceeded'),
        ),
      ),
    );
  });

  test('значения читаются из ответа Google', () async {
    final api = apiWith(
      MockClient(
        (request) async => http.Response(
          jsonEncode({
            'range': "'Лист'!A1:F",
            'values': [
              ['Дата', 'Время', 'Группа', 'ID', 'ФИО', 'Статус'],
              ['2026-11-09', '09:05', 'БИТ-24-03', '1', 'Алексей', 'Пришёл'],
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );

    final values = await api.getValues('spreadsheet-id', "'Лист'!A1:F");
    expect(values, hasLength(2));
    expect(values[1][3], '1');
  });

  test('без access token запрос не выполняется', () async {
    final api = GoogleSheetsApi(
      accessToken: () async => null,
      client: MockClient((request) async => http.Response('', 200)),
    );

    expect(
      () => api.getSpreadsheet('spreadsheet-id'),
      throwsA(isA<GoogleAuthRequiredException>()),
    );
  });
}
