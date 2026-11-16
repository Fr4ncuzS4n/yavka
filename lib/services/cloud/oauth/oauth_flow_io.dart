import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'oauth_models.dart';

OAuthFlow createPlatformOAuthFlow() => IoOAuthFlow();

/// OAuth 2.0 для установленных приложений (loopback redirect).
///
/// Работает на Android, iOS, Linux, macOS и Windows. Для входа нужен
/// OAuth-клиент типа «Desktop app»: Google разрешает для него
/// `http://127.0.0.1:<порт>` без предварительной регистрации порта.
class IoOAuthFlow implements OAuthFlow {
  IoOAuthFlow({http.Client? client}) : _client = client ?? http.Client();

  static const _authorizationEndpoint =
      'https://accounts.google.com/o/oauth2/v2/auth';
  static const _tokenEndpoint = 'https://oauth2.googleapis.com/token';
  static const _revokeEndpoint = 'https://oauth2.googleapis.com/revoke';
  static const _charset =
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~';

  /// Сколько ждём ответа Google. Без таймаута зависший запрос (сеть
  /// отвалилась, пока приложение в фоне) держал вход «вечно»: все
  /// кнопки оставались неактивными, токены не сохранялись.
  static const _networkTimeout = Duration(seconds: 60);

  final http.Client _client;

  @override
  Future<OAuthTokens> signIn(GoogleOAuthConfig config) async {
    _validate(config);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final redirectUri = 'http://127.0.0.1:${server.port}';
      final state = _randomString(32);
      final verifier = _randomString(64);
      final challenge = base64Url
          .encode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', '');

      final authUrl = Uri.parse(_authorizationEndpoint).replace(
        queryParameters: {
          'client_id': config.clientId!,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': kGoogleSheetsScopes.join(' '),
          'access_type': 'offline',
          'prompt': 'consent',
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
          'state': state,
        },
      );

      final codeFuture = _waitForCode(server, state);

      bool launched;
      try {
        launched = await launchUrl(
          authUrl,
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        launched = false;
      }
      if (!launched) {
        codeFuture.ignore();
        throw OAuthException(
          'Не удалось открыть браузер. Откройте ссылку вручную:\n$authUrl',
        );
      }

      final code = await codeFuture;
      return await _exchangeCode(
        config: config,
        code: code,
        verifier: verifier,
        redirectUri: redirectUri,
      );
    } finally {
      await server.close(force: true);
    }
  }

  @override
  Future<OAuthTokens> refresh(
    GoogleOAuthConfig config,
    OAuthTokens tokens,
  ) async {
    _validate(config);
    final refreshToken = tokens.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const OAuthException('Сессия Google истекла. Войдите снова.');
    }

    final response = await _client
        .post(
          Uri.parse(_tokenEndpoint),
          body: {
            'client_id': config.clientId!,
            'client_secret': config.clientSecret!,
            'refresh_token': refreshToken,
            'grant_type': 'refresh_token',
          },
        )
        .timeout(_networkTimeout, onTimeout: () { throw _timeoutError(); });

    final json = _decodeTokenResponse(response);
    return OAuthTokens(
      accessToken: json['access_token'] as String,
      refreshToken: (json['refresh_token'] as String?) ?? refreshToken,
      expiresAt: _expiryFrom(json),
      scopes: _scopesFrom(json, fallback: tokens.scopes),
    );
  }

  @override
  Future<void> signOut(OAuthTokens? tokens) async {
    final token = tokens?.refreshToken ?? tokens?.accessToken;
    if (token == null || token.isEmpty) return;
    try {
      await _client.post(
        Uri.parse(_revokeEndpoint).replace(queryParameters: {'token': token}),
      );
    } catch (_) {
      // Отзыв токена не должен мешать выходу из приложения.
    }
  }

  Future<String> _waitForCode(HttpServer server, String expectedState) {
    final completer = Completer<String>();
    late StreamSubscription<HttpRequest> subscription;

    subscription = server.listen((request) async {
      final params = request.uri.queryParameters;
      final code = params['code'];
      final error = params['error'];

      // Браузер может запросить favicon — просто отвечаем 404.
      if (code == null && error == null) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      try {
        if (error != null) {
          await _writePage(
            request.response,
            'Вход отменён',
            'Можно закрыть эту вкладку и вернуться в приложение.',
          );
          if (!completer.isCompleted) {
            completer.completeError(
              OAuthException(
                error == 'access_denied'
                    ? 'Вход отменён.'
                    : 'Google вернул ошибку: $error',
                cancelled: error == 'access_denied',
              ),
            );
          }
          return;
        }

        if (params['state'] != expectedState) {
          await _writePage(
            request.response,
            'Ошибка входа',
            'Ответ Google не совпал с запросом. Попробуйте снова.',
          );
          if (!completer.isCompleted) {
            completer.completeError(
              const OAuthException(
                'Не удалось проверить ответ Google. Попробуйте снова.',
              ),
            );
          }
          return;
        }

        await _writePage(
          request.response,
          'Готово',
          'Доступ получен. Можно закрыть эту вкладку и вернуться в «Явку».',
        );
        if (!completer.isCompleted) completer.complete(code);
      } catch (error) {
        if (!completer.isCompleted) completer.completeError(error);
      } finally {
        await subscription.cancel();
      }
    });

    return completer.future.timeout(
      const Duration(minutes: 5),
      onTimeout: () {
        unawaited(subscription.cancel());
        throw const OAuthException(
          'Время ожидания входа истекло. Попробуйте снова.',
        );
      },
    );
  }

  Future<OAuthTokens> _exchangeCode({
    required GoogleOAuthConfig config,
    required String code,
    required String verifier,
    required String redirectUri,
  }) async {
    final response = await _client
        .post(
          Uri.parse(_tokenEndpoint),
          body: {
            'client_id': config.clientId!,
            'client_secret': config.clientSecret!,
            'code': code,
            'code_verifier': verifier,
            'grant_type': 'authorization_code',
            'redirect_uri': redirectUri,
          },
        )
        .timeout(_networkTimeout, onTimeout: () { throw _timeoutError(); });

    final json = _decodeTokenResponse(response);
    return OAuthTokens(
      accessToken: json['access_token'] as String,
      refreshToken: json['refresh_token'] as String?,
      expiresAt: _expiryFrom(json),
      scopes: _scopesFrom(json, fallback: kGoogleSheetsScopes),
    );
  }

  OAuthException _timeoutError() => const OAuthException(
    'Google не отвечает. Проверьте интернет и попробуйте снова.',
  );

  Map<String, dynamic> _decodeTokenResponse(http.Response response) {
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(response.body);
      json = decoded is Map<String, dynamic>
          ? decoded
          : Map<String, dynamic>.from(decoded as Map);
    } catch (_) {
      throw OAuthException(
        'Google вернул неожиданный ответ (HTTP ${response.statusCode}).',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final description = json['error_description'] ?? json['error'];
      throw OAuthException(
        description == null
            ? 'Не удалось получить доступ к Google (HTTP ${response.statusCode}).'
            : 'Не удалось получить доступ к Google: $description',
      );
    }

    if (json['access_token'] is! String) {
      throw const OAuthException('Google не вернул access token.');
    }
    return json;
  }

  DateTime _expiryFrom(Map<String, dynamic> json) {
    final expiresIn = json['expires_in'];
    final seconds = expiresIn is num
        ? expiresIn.toInt()
        : int.tryParse(expiresIn?.toString() ?? '') ?? 3600;
    return DateTime.now().toUtc().add(Duration(seconds: seconds));
  }

  List<String> _scopesFrom(
    Map<String, dynamic> json, {
    required List<String> fallback,
  }) {
    final scope = json['scope'];
    if (scope is String && scope.trim().isNotEmpty) {
      return scope.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    }
    return fallback;
  }

  void _validate(GoogleOAuthConfig config) {
    if (!config.isConfigured) {
      throw const OAuthException(
        'Не указан Google OAuth Client ID. Откройте настройки Google Диска.',
      );
    }
    if (config.clientSecret == null || config.clientSecret!.isEmpty) {
      throw const OAuthException(
        'Не указан Google OAuth Client Secret. Создайте OAuth-клиент '
        'типа «Desktop app» и вставьте оба значения.',
      );
    }
  }

  String _randomString(int length) {
    final random = Random.secure();
    return List.generate(
      length,
      (_) => _charset[random.nextInt(_charset.length)],
    ).join();
  }

  Future<void> _writePage(
    HttpResponse response,
    String title,
    String message,
  ) async {
    response.headers.contentType = ContentType.html;
    response.write(
      '<!doctype html><html lang="ru"><head><meta charset="utf-8">'
      '<meta name="viewport" content="width=device-width,initial-scale=1">'
      '<title>$title</title>'
      '<style>body{font-family:system-ui,sans-serif;background:#f7f7f4;'
      'color:#1b1b1f;display:flex;min-height:100vh;align-items:center;'
      'justify-content:center;margin:0;padding:24px;box-sizing:border-box}'
      'main{max-width:420px;background:#fff;border:1px solid #e5e5e1;'
      'border-radius:16px;padding:24px;text-align:center}'
      'h1{font-size:20px;margin:0 0 8px}p{margin:0;color:#55565e}'
      '</style></head><body><main><h1>$title</h1><p>$message</p></main>'
      '</body></html>',
    );
    await response.close();
  }
}
