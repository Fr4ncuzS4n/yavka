import 'dart:convert';

import 'package:http/http.dart' as http;

/// Почта аккаунта Google по access token.
///
/// Лучший результат — не гарантия: Google может не ответить, тогда
/// расписание остаётся привязанным к локальному профилю устройства.
class GoogleAccountApi {
  GoogleAccountApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? 'https://www.googleapis.com/oauth2/v3/userinfo';

  final http.Client _client;
  final String _baseUrl;

  /// Возвращает почту аккаунта или `null`, если узнать её не удалось.
  Future<String?> fetchEmail(String accessToken) async {
    if (accessToken.isEmpty) return null;
    try {
      final response = await _client.get(
        Uri.parse(_baseUrl),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
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
