// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';

import 'oauth/oauth_models.dart';
import 'token_store.dart';

/// Управляет входом в Google и access token для запросов к Sheets API.
///
/// Вместе с токенами узнаёт и хранит почту аккаунта: она нужна, чтобы
/// расписание было привязано к конкретному пользователю.
class GoogleAuthService extends ChangeNotifier {
  GoogleAuthService({
    required OAuthFlow flow,
    required TokenStore tokenStore,
    Future<String?> Function(String accessToken)? accountEmailFetcher,
  }) : _flow = flow,
       _tokenStore = tokenStore,
       _accountEmailFetcher = accountEmailFetcher;

  final OAuthFlow _flow;
  final TokenStore _tokenStore;

  /// Лучший способ узнать почту аккаунта по access token.
  final Future<String?> Function(String accessToken)? _accountEmailFetcher;

  GoogleOAuthConfig _config = const GoogleOAuthConfig.none();
  OAuthTokens? _tokens;
  bool _busy = false;
  String? _error;

  bool get isConfigured => _config.isConfigured;

  bool get isSignedIn => _tokens != null;

  /// Почта аккаунта, под которым выполнен вход, если её удалось узнать.
  String? get accountEmail => _tokens?.email;

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
    } else {
      await _fillEmail();
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
      var tokens = await _flow.signIn(_config);
      // Токены сохраняются сразу: запрос почты может зависнуть или
      // не удаться, но аккаунт не должен теряться из-за неё.
      _tokens = tokens;
      notifyListeners();
      await _tokenStore.save(tokens);
      final withEmail = await _fillEmail(tokens) ?? tokens;
      if (withEmail.email != tokens.email) {
        tokens = withEmail;
        _tokens = tokens;
        await _tokenStore.save(tokens);
      }
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
      // Почта не меняется при продлении токена — переносим её.
      final updated = refreshed.email == null
          ? refreshed.withEmail(tokens.email)
          : refreshed;
      _tokens = updated;
      await _tokenStore.save(updated);
      _error = null;
      notifyListeners();
      return updated;
    } catch (error) {
      _error = _message(error);
      // Сетевая ошибка (нет интернета, таймаут) не отменяет вход:
      // токены остаются и продлятся при следующем запросе. Иначе
      // перезапуск без сети стирал аккаунт, будто выхода не было.
      notifyListeners();
      return null;
    }
  }

  /// Сколько ждём почту у Google — чтобы зависший запрос не держал
  /// вход (на Android запрос мог висеть бесконечно, и все кнопки
  /// экрана оставались неактивными).
  static const _emailTimeout = Duration(seconds: 15);

  /// Дособирает почту аккаунта, если токены её ещё не содержат.
  Future<OAuthTokens?> _fillEmail([OAuthTokens? source]) async {
    final tokens = source ?? _tokens;
    if (tokens == null || tokens.email != null) return tokens;
    final fetcher = _accountEmailFetcher;
    if (fetcher == null) return tokens;
    try {
      // `then<String?>` выравнивает тип результата: fetcher может
      // возвращать и `String`, и `String?` — таймауту нужен `String?`.
      final email = await fetcher(
        tokens.accessToken,
      ).then<String?>((value) => value).timeout(
        _emailTimeout,
        onTimeout: () => null,
      );
      if (email == null || email.isEmpty) return tokens;
      final updated = tokens.withEmail(email);
      _tokens = updated;
      notifyListeners();
      return updated;
    } catch (_) {
      // Почта — лучший результат: без неё расписание просто не
      // привязывается к аккаунту.
      return tokens;
    }
  }

  String _message(Object error) {
    if (error is OAuthException) return error.message;
    return 'Не удалось войти в Google: $error';
  }
}
