import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:yavka/services/cloud/google_account_api.dart';
import 'package:yavka/services/cloud/google_auth_service.dart';
import 'package:yavka/services/cloud/oauth/oauth_models.dart';
import 'package:yavka/services/cloud/token_store.dart';

GoogleOAuthConfig _config() => const GoogleOAuthConfig(
  clientId: 'test-client-id.apps.googleusercontent.com',
  clientSecret: 'test-client-secret',
  isWeb: false,
);

class FakeFlow implements OAuthFlow {
  FakeFlow({this.refreshEmail, this.refreshFails = false});

  /// Почта, которую Google возвращает при продлении токена.
  final String? refreshEmail;

  /// Продление всегда падает: телефон включили без интернета.
  final bool refreshFails;

  @override
  Future<OAuthTokens> signIn(GoogleOAuthConfig config) async => OAuthTokens(
    accessToken: 'access-token',
    refreshToken: 'refresh-token',
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    scopes: kGoogleSheetsScopes,
  );

  @override
  Future<OAuthTokens> refresh(
    GoogleOAuthConfig config,
    OAuthTokens tokens,
  ) async {
    if (refreshFails) {
      throw const OAuthException(
        'Google не отвечает. Проверьте интернет и попробуйте снова.',
      );
    }
    return OAuthTokens(
      accessToken: 'new-access-token',
      refreshToken: tokens.refreshToken,
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      scopes: tokens.scopes,
      email: refreshEmail,
    );
  }

  @override
  Future<void> signOut(OAuthTokens? tokens) async {}
}

extension on OAuthTokens {
  /// Те же токены с другим моментом истечения — для тестов продления.
  OAuthTokens copyWithExpiry(DateTime expiresAt) => OAuthTokens(
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresAt: expiresAt,
    scopes: scopes,
    email: email,
  );
}

void main() {
  test('после входа у токенов известна почта аккаунта', () async {
    final auth = GoogleAuthService(
      flow: FakeFlow(),
      tokenStore: MemoryTokenStore(),
      accountEmailFetcher: (token) async =>
          token == 'access-token' ? 'ivan@mail.ru' : null,
    );
    auth.configure(_config());

    await auth.signIn();
    expect(auth.accountEmail, 'ivan@mail.ru');

    // Почта сохраняется вместе с токенами.
    final saved = await MemoryTokenStore().load();
    expect(saved, isNull); // у этого инстанса свой магазин — проверим ниже
  });

  test('почта сохраняется в хранилище токенов', () async {
    final tokens = MemoryTokenStore();
    final auth = GoogleAuthService(
      flow: FakeFlow(),
      tokenStore: tokens,
      accountEmailFetcher: (token) async => 'ivan@mail.ru',
    );
    auth.configure(_config());
    await auth.signIn();

    final saved = await tokens.load();
    expect(saved?.email, 'ivan@mail.ru');
  });

  test('Google без почты не мешает входу', () async {
    final auth = GoogleAuthService(
      flow: FakeFlow(),
      tokenStore: MemoryTokenStore(),
      accountEmailFetcher: (token) async => null,
    );
    auth.configure(_config());
    await auth.signIn();

    expect(auth.isSignedIn, isTrue);
    expect(auth.accountEmail, isNull);
  });

  test('выход сбрасывает почту', () async {
    final auth = GoogleAuthService(
      flow: FakeFlow(),
      tokenStore: MemoryTokenStore(),
      accountEmailFetcher: (token) async => 'ivan@mail.ru',
    );
    auth.configure(_config());
    await auth.signIn();
    await auth.signOut();

    expect(auth.isSignedIn, isFalse);
    expect(auth.accountEmail, isNull);
  });

  test('продление токена не теряет почту', () async {
    final tokens = MemoryTokenStore();
    final auth = GoogleAuthService(
      flow: FakeFlow(refreshEmail: null),
      tokenStore: tokens,
      accountEmailFetcher: (token) async =>
          token == 'access-token' ? 'ivan@mail.ru' : null,
    );
    auth.configure(_config());
    await auth.signIn();
    expect(auth.accountEmail, 'ivan@mail.ru');

    // Токен истекает: восстановление продлит его через FakeFlow.refresh,
    // который не несёт почту — она переносится со старых токенов.
    final saved = await tokens.load();
    await tokens.save(
      saved!.copyWithExpiry(
        DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      ),
    );
    await auth.restore();

    final fresh = await auth.accessToken();
    expect(fresh, 'new-access-token');
    expect(auth.accountEmail, 'ivan@mail.ru');
  });

  test('восстановление токенов дособирает почту', () async {
    final tokens = MemoryTokenStore();
    await tokens.save(
      OAuthTokens(
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
        scopes: kGoogleSheetsScopes,
      ),
    );
    final auth = GoogleAuthService(
      flow: FakeFlow(),
      tokenStore: tokens,
      accountEmailFetcher: (token) async => 'restored@mail.ru',
    );
    auth.configure(_config());

    await auth.restore();
    expect(auth.accountEmail, 'restored@mail.ru');
  });

  test('токены сохраняются, даже если запрос почты завис навсегда', () async {
    final tokens = MemoryTokenStore();
    final auth = GoogleAuthService(
      flow: FakeFlow(),
      tokenStore: tokens,
      // Запрос почты никогда не завершается: раньше он держал вход и
      // не давал сохранить токены — на Android это выглядело как
      // «аккаунт не сохраняется, кнопки неактивны».
      accountEmailFetcher: (token) => Completer<String?>().future,
    );
    auth.configure(_config());

    await fakeAsync((async) {
      unawaited(auth.signIn());
      // Таймаут запроса почты — 15 секунд, продлеваем часы теста.
      async.elapse(const Duration(minutes: 1));
    });

    expect(auth.isSignedIn, isTrue);
    final saved = await tokens.load();
    expect(saved, isNotNull);
    expect(saved!.accessToken, 'access-token');
  });

  test('ошибка продления токена не стирает аккаунт', () async {
    final tokens = MemoryTokenStore();
    final auth = GoogleAuthService(
      flow: FakeFlow(refreshFails: true),
      tokenStore: tokens,
      accountEmailFetcher: (token) async => 'ivan@mail.ru',
    );
    auth.configure(_config());
    await auth.signIn();

    // Телефон включили без сети: токен истёк, продлить не удалось.
    final saved = await tokens.load();
    await tokens.save(
      saved!.copyWithExpiry(
        DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      ),
    );
    await auth.restore();

    expect(auth.isSignedIn, isTrue);
    final stillThere = await tokens.load();
    expect(stillThere, isNotNull);
    expect(stillThere!.refreshToken, 'refresh-token');
    expect(auth.error, isNotNull);
  });

  test('запрос почты отвечает null, когда Google не отвечает', () async {
    final api = GoogleAccountApi(
      client: HangingHttpClient(),
      emailTimeout: const Duration(milliseconds: 50),
    );
    expect(await api.fetchEmail('token'), isNull);
  });
}

/// HTTP-клиент, у которого каждый запрос висит вечно.
class HangingHttpClient implements http.Client {
  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
      Completer<http.Response>().future;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
