import 'oauth_models.dart';

OAuthFlow createPlatformOAuthFlow() => const UnsupportedOAuthFlow();

/// Запасная реализация для платформ без OAuth.
class UnsupportedOAuthFlow implements OAuthFlow {
  const UnsupportedOAuthFlow();

  @override
  Future<OAuthTokens> signIn(GoogleOAuthConfig config) =>
      throw const OAuthException(
        'Вход в Google не поддерживается на этой платформе.',
      );

  @override
  Future<OAuthTokens> refresh(GoogleOAuthConfig config, OAuthTokens tokens) =>
      throw const OAuthException(
        'Вход в Google не поддерживается на этой платформе.',
      );

  @override
  Future<void> signOut(OAuthTokens? tokens) async {}
}
