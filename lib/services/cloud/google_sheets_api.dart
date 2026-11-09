// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cloud_exceptions.dart';
import 'sheets_api.dart';

/// Клиент Google Sheets API v4 поверх REST.
class GoogleSheetsApi implements SheetsApi {
  GoogleSheetsApi({
    required Future<String?> Function() accessToken,
    http.Client? client,
    String baseUrl = 'https://sheets.googleapis.com/v4',
  }) : _accessToken = accessToken,
       _client = client ?? http.Client(),
       _baseUrl = baseUrl;

  final Future<String?> Function() _accessToken;
  final http.Client _client;
  final String _baseUrl;

  @override
  Future<SpreadsheetMeta> getSpreadsheet(String spreadsheetId) async {
    final response = await _send(
      'GET',
      '/spreadsheets/${Uri.encodeComponent(spreadsheetId)}',
      query: {
        'fields':
            'spreadsheetId,properties.title,spreadsheetUrl,'
            'sheets.properties(sheetId,title)',
      },
    );
    return _metaFromJson(_decode(response));
  }

  @override
  Future<SpreadsheetMeta> createSpreadsheet(String title) async {
    final response = await _send(
      'POST',
      '/spreadsheets',
      body: {
        'properties': {'title': title},
      },
    );
    return _metaFromJson(_decode(response));
  }

  @override
  Future<void> addSheet(String spreadsheetId, String title) async {
    await _send(
      'POST',
      '/spreadsheets/${Uri.encodeComponent(spreadsheetId)}:batchUpdate',
      body: {
        'requests': [
          {
            'addSheet': {
              'properties': {'title': title},
            },
          },
        ],
      },
    );
  }

  @override
  Future<List<List<Object?>>> getValues(
    String spreadsheetId,
    String range,
  ) async {
    final response = await _send(
      'GET',
      '/spreadsheets/${Uri.encodeComponent(spreadsheetId)}'
          '/values/${Uri.encodeComponent(range)}',
      query: {
        'valueRenderOption': 'UNFORMATTED_VALUE',
        'majorDimension': 'ROWS',
      },
    );
    final json = _decode(response);
    final values = json['values'];
    if (values is! List) return const [];
    return [
      for (final row in values)
        if (row is List) [for (final cell in row) cell as Object?],
    ];
  }

  @override
  Future<void> updateValues(
    String spreadsheetId,
    String range,
    List<List<Object?>> values,
  ) async {
    await _send(
      'PUT',
      '/spreadsheets/${Uri.encodeComponent(spreadsheetId)}'
          '/values/${Uri.encodeComponent(range)}',
      query: {'valueInputOption': 'RAW'},
      body: {'range': range, 'majorDimension': 'ROWS', 'values': values},
    );
  }

  @override
  Future<void> batchUpdateValues(
    String spreadsheetId,
    List<SheetValueRange> data,
  ) async {
    await _send(
      'POST',
      '/spreadsheets/${Uri.encodeComponent(spreadsheetId)}/values:batchUpdate',
      body: {
        'valueInputOption': 'RAW',
        'data': [for (final item in data) item.toJson()],
      },
    );
  }

  @override
  Future<void> appendValues(
    String spreadsheetId,
    String range,
    List<List<Object?>> values,
  ) async {
    await _send(
      'POST',
      '/spreadsheets/${Uri.encodeComponent(spreadsheetId)}'
          '/values/${Uri.encodeComponent(range)}:append',
      query: {'valueInputOption': 'RAW', 'insertDataOption': 'INSERT_ROWS'},
      body: {'range': range, 'majorDimension': 'ROWS', 'values': values},
    );
  }

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final token = await _accessToken();
    if (token == null || token.isEmpty) {
      throw const GoogleAuthRequiredException();
    }

    final uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final headers = {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json; charset=utf-8',
    };
    final payload = body == null ? null : jsonEncode(body);

    late http.Response response;
    switch (method) {
      case 'GET':
        response = await _client.get(uri, headers: headers);
        break;
      case 'POST':
        response = await _client.post(uri, headers: headers, body: payload);
        break;
      case 'PUT':
        response = await _client.put(uri, headers: headers, body: payload);
        break;
      case 'DELETE':
        response = await _client.delete(uri, headers: headers);
        break;
      default:
        throw ArgumentError.value(method, 'method');
    }

    _checkResponse(response);
    return response;
  }

  void _checkResponse(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) return;

    final apiError = ParsedGoogleError.fromJsonBody(response.body);

    switch (response.statusCode) {
      case 401:
        throw const GoogleAuthRequiredException();
      case 403:
        // Пользователь может быть редактором, но получить 403 по другой
        // причине — например, Sheets API не включён в проекте клиента.
        if (_isSheetsApiDisabled(apiError)) {
          throw const GoogleSheetsApiDisabledException();
        }
        if (_isRateLimited(response.statusCode, apiError)) {
          throw const GoogleRateLimitException();
        }
        throw const GooglePermissionException();
      case 429:
        throw const GoogleRateLimitException();
      case 404:
        throw const SpreadsheetNotFoundException();
    }

    final apiMessage = apiError?.message;
    throw GoogleApiException(
      apiMessage == null
          ? 'Google Таблицы вернули ошибку (HTTP ${response.statusCode}).'
          : 'Google Таблицы: $apiMessage',
      statusCode: response.statusCode,
    );
  }

  // Настоящее сообщение Google для отключённого API:
  // «Google Sheets API has not been used in project NNN before
  // or it is disabled. …»
  bool _isSheetsApiDisabled(ParsedGoogleError? error) {
    final message = error?.message?.toLowerCase() ?? '';
    return message.contains('has not been used in') &&
        message.contains('disabled');
  }

  bool _isRateLimited(int statusCode, ParsedGoogleError? error) {
    const rateLimitReasons = {
      'rateLimitExceeded',
      'userRateLimitExceeded',
      'dailyLimitExceeded',
      'RATE_LIMIT_EXCEEDED',
    };
    if (error != null) {
      if (error.reasons.any(rateLimitReasons.contains)) return true;
      if (error.status == 'RESOURCE_EXHAUSTED') return true;
    }
    if (statusCode == 429) return true;

    final message = error?.message?.toLowerCase();
    if (message == null) return false;
    return message.contains('rate limit') ||
        message.contains('rate exceeded') ||
        message.contains('too many requests');
  }

  Map<String, dynamic> _decode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // Ниже будет понятная ошибка.
    }
    throw const GoogleApiException('Google вернул некорректный ответ.');
  }

  SpreadsheetMeta _metaFromJson(Map<String, dynamic> json) {
    final id = json['spreadsheetId']?.toString() ?? '';
    final properties = json['properties'];
    final title = properties is Map
        ? properties['title']?.toString() ?? 'Без названия'
        : 'Без названия';
    final url =
        json['spreadsheetUrl']?.toString() ??
        'https://docs.google.com/spreadsheets/d/$id/edit';

    final tabs = <SheetTab>[];
    final sheets = json['sheets'];
    if (sheets is List) {
      for (final sheet in sheets) {
        if (sheet is! Map) continue;
        final props = sheet['properties'];
        if (props is! Map) continue;
        final tabId = props['sheetId'];
        final tabTitle = props['title']?.toString();
        if (tabId is num && tabTitle != null) {
          tabs.add(SheetTab(id: tabId.toInt(), title: tabTitle));
        }
      }
    }

    return SpreadsheetMeta(id: id, title: title, url: url, tabs: tabs);
  }
}

/// Разобранное тело ошибки Google API.
///
/// Формат: `{"error": {"code": 403, "message": "…", "status":
/// "PERMISSION_DENIED", "errors": [{"reason": "rateLimitExceeded"}]}}`.
class ParsedGoogleError {
  const ParsedGoogleError({
    this.message,
    this.status,
    this.reasons = const [],
  });

  final String? message;
  final String? status;
  final List<String> reasons;

  /// Reasons из `error.errors[].reason` (старый формат Google).
  static ParsedGoogleError? fromJsonBody(String body) {
    Map<String, dynamic> error;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final raw = decoded['error'];
      if (raw is! Map) return null;
      error = Map<String, dynamic>.from(raw);
    } catch (_) {
      // Тело ошибки может быть не JSON — показываем общее сообщение.
      return null;
    }

    final reasons = <String>[];
    final errors = error['errors'];
    if (errors is List) {
      for (final item in errors) {
        if (item is! Map) continue;
        final reason = item['reason']?.toString();
        if (reason != null && reason.isNotEmpty) reasons.add(reason);
      }
    }

    return ParsedGoogleError(
      message: error['message']?.toString(),
      status: error['status']?.toString(),
      reasons: reasons,
    );
  }
}
