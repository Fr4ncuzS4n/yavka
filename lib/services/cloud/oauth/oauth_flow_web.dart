import 'package:googleapis_auth/auth_browser.dart' as google_auth;

import 'oauth_models.dart';

OAuthFlow createPlatformOAuthFlow() => WebOAuthFlow();

/// OAuth 2.0 для web через Google Identity Services (token model).
///
/// Нужен OAuth-клиент типа «Web application» и адрес приложения в
/// «Authorized JavaScript origins». Refresh token в этом режиме не выдаётся:
/// при истечении токена приложение попросит войти снова.
class WebOAuthFlow implements OAuthFlow {
  @override
  Future<OAuthTokens> signIn(GoogleOAuthConfig config) async {
    if (!config.isConfigured) {
      throw const OAuthException(
        'Не указан Google OAuth Client ID для web. Откройте настройки '
        'Google Диска.',
      );
    }

    final credentials = await google_auth.requestAccessCredentials(
      clientId: config.clientId!,
      scopes: kGoogleSheetsScopes,
    );

    return OAuthTokens(
      accessToken: credentials.accessToken.data,
      expiresAt: credentials.accessToken.expiry,
      scopes: credentials.scopes,
    );
  }

  @override
  Future<OAuthTokens> refresh(GoogleOAuthConfig config, OAuthTokens tokens) =>
      // Google Identity Services не выдаёт refresh token для web-клиента.
      signIn(config);

  @override
  Future<void> signOut(OAuthTokens? tokens) async {
    final token = tokens?.accessToken;
    if (token == null || token.isEmpty) return;
    try {
      await google_auth.revokeConsent(token);
    } catch (_) {
      // Отзыв не должен мешать выходу.
    }
  }
}
