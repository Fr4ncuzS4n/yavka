import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'oauth/oauth_models.dart';

/// Хранилище OAuth-токенов между запусками приложения.
abstract interface class TokenStore {
  Future<OAuthTokens?> load();

  Future<void> save(OAuthTokens? tokens);
}

/// Токены в памяти — для тестов.
class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this._tokens]);

  OAuthTokens? _tokens;

  @override
  Future<OAuthTokens?> load() async => _tokens;

  @override
  Future<void> save(OAuthTokens? tokens) async => _tokens = tokens;
}

/// Токены в SharedPreferences.
///
/// Для production лучше заменить на `flutter_secure_storage`: refresh token
/// даёт доступ к таблицам пользователя.
class SharedPreferencesTokenStore implements TokenStore {
  SharedPreferencesTokenStore(this._preferences);

  static const _key = 'yavka.google.oauth.tokens.v1';

  final SharedPreferences _preferences;

  @override
  Future<OAuthTokens?> load() async {
    final raw = _preferences.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return OAuthTokens.fromJson(Map<String, Object?>.from(decoded));
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(OAuthTokens? tokens) async {
    if (tokens == null) {
      await _preferences.remove(_key);
      return;
    }
    await _preferences.setString(_key, jsonEncode(tokens.toJson()));
  }
}
