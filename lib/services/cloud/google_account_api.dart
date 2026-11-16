// ignore_for_file: prefer_initializing_formals

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Почта аккаунта Google по access token.
///
/// Лучший результат — не гарантия: Google может не ответить, тогда
/// расписание остаётся привязанным к локальному профилю устройства.
class GoogleAccountApi {
  GoogleAccountApi({
    http.Client? client,
    String? baseUrl,
    Duration emailTimeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client(),
       _baseUrl = baseUrl ?? 'https://www.googleapis.com/oauth2/v3/userinfo',
       _emailTimeout = emailTimeout;

  final http.Client _client;
  final String _baseUrl;

  /// Сколько ждём ответ Google. Почта — лучший результат, а не
  /// гарантия: зависший запрос не должен держать вход и хранить
  /// токены несохранёнными.
  final Duration _emailTimeout;

  /// Возвращает почту аккаунта или `null`, если узнать её не удалось.
  Future<String?> fetchEmail(String accessToken) async {
    if (accessToken.isEmpty) return null;
    try {
      final response = await _client
          .get(
            Uri.parse(_baseUrl),
            headers: {'Authorization': 'Bearer $accessToken'},
          )
          .timeout(_emailTimeout, onTimeout: () => http.Response('', 408));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final email = decoded['email']?.toString() ?? '';
      return email.contains('@') ? email : null;
    } catch (_) {
      return null;
    }
  }
}
