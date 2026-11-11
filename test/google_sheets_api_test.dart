import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yavka/services/cloud/cloud_exceptions.dart';
import 'package:yavka/services/cloud/google_sheets_api.dart';
import 'package:yavka/services/cloud/sheets_api.dart';

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
      () => api.getSheetGrid('spreadsheet-id', 'Ноябрь 2026'),
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

  test('400 показывает, какой именно запрос отклонён', () async {
    // Настоящая форма ошибки Google: безликое «Request contains an
    // invalid argument.» в message, а конкретная причина — в
    // error.details[].fieldViolations. Без неё найти виновный запрос
    // невозможно.
    final api = apiWith(
      MockClient(
        (request) async => http.Response(
          jsonEncode({
            'error': {
              'code': 400,
              'message': 'Request contains an invalid argument.',
              'status': 'INVALID_ARGUMENT',
              'details': [
                {
                  '@type': 'type.googleapis.com/google.rpc.BadRequest',
                  'fieldViolations': [
                    {
                      'field': 'requests[0].updateDimensionProperties',
                      'description': 'This operation would shrink the grid.',
                    },
                    {
                      'field': 'requests[1].mergeCells',
                      'description': 'One of the cells is already merged.',
                    },
                  ],
                },
              ],
            },
          }),
          400,
        ),
      ),
    );

    await expectLater(
      api.batchUpdate('sid', const []),
      throwsA(
        isA<GoogleApiException>()
            .having(
              (error) => error.message,
              'message',
              contains('Request contains an invalid argument.'),
            )
            .having(
              (error) => error.message,
              'message',
              contains(
                'requests[0].updateDimensionProperties: '
                'This operation would shrink the grid.',
              ),
            )
            .having(
              (error) => error.message,
              'message',
              contains(
                'requests[1].mergeCells: One of the cells is already merged.',
              ),
            ),
      ),
    );
  });

  test('сетка листа читается из ответа Google', () async {
    final api = apiWith(
      MockClient((request) async {
        expect(
          request.url.toString(),
          contains('includeGridData=true'),
        );
        return http.Response(
          jsonEncode({
            'sheets': [
              {
                'properties': {
                  'sheetId': 7,
                  'title': 'Ноябрь 2026',
                },
                'data': [
                  {
                    'startRow': 0,
                    'startColumn': 0,
                    'gridProperties': {'rowCount': 4, 'columnCount': 6},
                    'rowData': [
                      {'values': []},
                      {
                        'values': [
                          {'formattedValue': '№'},
                          {'formattedValue': 'ФИО'},
                          {'formattedValue': '1'},
                          {
                            'formattedValue': '',
                            'effectiveFormat': {
                              'backgroundColorStyle': {
                                'rgb': {'red': 0.6, 'green': 0.1, 'blue': 0.1},
                              },
                            },
                          },
                        ],
                      },
                      {
                        'values': [
                          {'formattedValue': '1'},
                          {'formattedValue': 'Алексей Морозов'},
                          {'formattedValue': ''},
                          {'formattedValue': ''},
                        ],
                      },
                    ],
                  },
                ],
                'merges': [
                  {
                    'startRowIndex': 0,
                    'endRowIndex': 1,
                    'startColumnIndex': 2,
                    'endColumnIndex': 6,
                  },
                ],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final grid = await api.getSheetGrid('spreadsheet-id', 'Ноябрь 2026');

    expect(grid, isNotNull);
    expect(grid!.rowCount, 4);
    expect(grid.colCount, 6);
    expect(grid.cell(1, 0).value, '№');
    expect(grid.cell(1, 2).value, '1');
    // Красная заливка 0x991A1A: 0.6*255≈153, 0.1*255≈26.
    expect(grid.cell(1, 3).backgroundColor, isNotNull);
    expect(grid.cell(2, 1).value, 'Алексей Морозов');
    // Merge разворачивается: значение на краях объединения совпадает.
    expect(grid.merges, hasLength(1));
    expect(grid.mergedView()[0][4].value, grid.cell(0, 2).value);
  });

  test('лист без совпадающего названия не найден', () async {
    final api = apiWith(
      MockClient(
        (request) async => http.Response(
          jsonEncode({
            'sheets': [
              {
                'properties': {'sheetId': 1, 'title': 'Другой лист'},
                'data': [
                  {
                    'gridProperties': {'rowCount': 1, 'columnCount': 1},
                  },
                ],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );

    expect(
      await api.getSheetGrid('spreadsheet-id', 'Ноябрь 2026'),
      isNull,
    );
  });

  test('batchUpdate отправляет список запросов', () async {
    Map<String, Object?>? decodedBody;
    final api = apiWith(
      MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, endsWith('spreadsheets/sid:batchUpdate'));
        decodedBody = (jsonDecode(request.body) as Map).cast<String, Object?>();
        return http.Response(
          jsonEncode({'spreadsheetId': 'sid'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await api.batchUpdate('sid', <Map<String, Object?>>[
      {
        'updateCells': {
          'start': {'sheetId': 0, 'rowIndex': 0, 'columnIndex': 0},
          'rows': [
            {
              'values': [
                {
                  'userEnteredValue': {'stringValue': 'Н'},
                },
              ],
            },
          ],
          'fields': 'userEnteredValue',
        },
      },
    ]);

    expect(decodedBody?['requests'], hasLength(1));
  });

  test('addSheet возвращает sheetId нового листа', () async {
    final api = apiWith(
      MockClient(
        (request) async => http.Response(
          jsonEncode({
            'spreadsheetId': 'sid',
            'replies': [
              {
                'addSheet': {
                  'properties': {'sheetId': 42, 'title': 'Ноябрь 2026'},
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );

    expect(await api.addSheet('sid', 'Ноябрь 2026'), 42);
  });

  test('белый и прозрачный фон не считается заливкой', () async {
    final api = apiWith(
      MockClient(
        (request) async => http.Response(
          jsonEncode({
            'sheets': [
              {
                'properties': {'sheetId': 1, 'title': 'Ноябрь 2026'},
                'data': [
                  {
                    'gridProperties': {'rowCount': 1, 'columnCount': 3},
                    'rowData': [
                      {
                        'values': [
                          {
                            'effectiveFormat': {
                              'backgroundColor': {
                                'red': 1,
                                'green': 1,
                                'blue': 1,
                              },
                            },
                          },
                          {
                            'effectiveFormat': {
                              'backgroundColor': {
                                'red': 1,
                                'green': 1,
                                'blue': 1,
                                'alpha': 0,
                              },
                            },
                          },
                          {
                            'effectiveFormat': {
                              'backgroundColor': {
                                'red': 0,
                                'green': 0.8,
                                'blue': 0,
                              },
                            },
                          },
                        ],
                      },
                    ],
                  },
                ],
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );

    final grid = await api.getSheetGrid('spreadsheet-id', 'Ноябрь 2026');

    expect(grid!.cell(0, 0).backgroundColor, isNull);
    expect(grid.cell(0, 1).backgroundColor, isNull);
    // Зелёная заливка 0.8*255 ≈ 204.
    expect(grid.cell(0, 2).backgroundColor, 0x00CC00);
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

  test('sameCell сравнивает значение и заливку', () {
    const a = GridCell(value: 'Н', backgroundColor: 0xFF0000);
    const b = GridCell(value: 'Н', backgroundColor: 0xFF0000);
    const c = GridCell(value: '', backgroundColor: 0xFF0000);

    expect(sameCell(a, b), isTrue);
    expect(sameCell(a, c), isFalse);
    expect(sameCell(const GridCell(), const GridCell()), isTrue);
  });
}
