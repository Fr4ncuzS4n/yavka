// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import 'oauth/oauth_models.dart';
import 'token_store.dart';

/// Управляет входом в Google и access token для запросов к Sheets API.
class GoogleAuthService extends ChangeNotifier {
  GoogleAuthService({required OAuthFlow flow, required TokenStore tokenStore})
    : _flow = flow,
      _tokenStore = tokenStore;

  final OAuthFlow _flow;
  final TokenStore _tokenStore;

  GoogleOAuthConfig _config = const GoogleOAuthConfig.none();
  OAuthTokens? _tokens;
  bool _busy = false;
  String? _error;

  bool get isConfigured => _config.isConfigured;

  bool get isSignedIn => _tokens != null;

  bool get isBusy => _busy;

  String? get error => _error;

  GoogleOAuthConfig get config => _config;

  void configure(GoogleOAuthConfig config) {
    _config = config;
    notifyListeners();
  }

  /// Поднимает сохранённые токены и продлевает их при необходимости.
  Future<void> restore() async {
    _tokens = await _tokenStore.load();
    if (_tokens == null) return;

    if (_tokens!.isExpired) {
      if (_tokens!.refreshToken == null) {
        _tokens = null;
        await _tokenStore.save(null);
      } else {
        await _refresh();
      }
    }
    notifyListeners();
  }

  /// Открывает окно входа Google.
  Future<void> signIn() async {
    if (!_config.isConfigured) {
      throw OAuthException(
        _config.isWeb
            ? 'Сначала укажите Google OAuth Client ID для web.'
            : 'Сначала укажите Google OAuth Client ID и Client Secret.',
      );
    }
    if (_busy) return;

    _busy = true;
    _error = null;
    notifyListeners();
    try {
      final tokens = await _flow.signIn(_config);
      _tokens = tokens;
      await _tokenStore.save(tokens);
    } catch (error) {
      _error = _message(error);
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    final tokens = _tokens;
    _tokens = null;
    _error = null;
    await _tokenStore.save(null);
    notifyListeners();
    await _flow.signOut(tokens);
  }

  /// Возвращает действующий access token или `null`, если нужен повторный вход.
  Future<String?> accessToken() async {
    final tokens = _tokens;
    if (tokens == null) return null;
    if (!tokens.isExpired) return tokens.accessToken;

    if (tokens.refreshToken == null) {
      // Web-клиент не получает refresh token — нужен новый вход.
      _tokens = null;
      await _tokenStore.save(null);
      notifyListeners();
      return null;
    }

    final refreshed = await _refresh();
    return refreshed?.accessToken;
  }

  Future<OAuthTokens?> _refresh() async {
    final tokens = _tokens;
    if (tokens == null) return null;
    try {
      final refreshed = await _flow.refresh(_config, tokens);
      _tokens = refreshed;
      await _tokenStore.save(refreshed);
      _error = null;
      notifyListeners();
      return refreshed;
    } catch (error) {
      _tokens = null;
      _error = _message(error);
      await _tokenStore.save(null);
      notifyListeners();
      return null;
    }
  }

  String _message(Object error) {
    if (error is OAuthException) return error.message;
    return 'Не удалось войти в Google: $error';
  }
}
