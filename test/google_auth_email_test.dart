import 'package:flutter_test/flutter_test.dart';
import 'package:yavka/services/cloud/google_auth_service.dart';
import 'package:yavka/services/cloud/oauth/oauth_models.dart';
import 'package:yavka/services/cloud/token_store.dart';

GoogleOAuthConfig _config() => const GoogleOAuthConfig(
  clientId: 'test-client-id.apps.googleusercontent.com',
  clientSecret: 'test-client-secret',
  isWeb: false,
);

class FakeFlow implements OAuthFlow {
  FakeFlow({this.refreshEmail});

  /// Почта, которую Google возвращает при продлении токена.
  final String? refreshEmail;

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
  ) async => OAuthTokens(
    accessToken: 'new-access-token',
    refreshToken: tokens.refreshToken,
    expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    scopes: tokens.scopes,
    email: refreshEmail,
  );

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
}
