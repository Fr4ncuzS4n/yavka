import '../../../data/cloud_settings.dart';

/// Область доступа: просмотр, создание и редактирование Google Таблиц.
///
/// Отдельный Drive-scope не нужен: таблица — это файл на Google Диске,
/// а доступ к ней определяется правами пользователя (владелец/редактор).
const List<String> kGoogleSheetsScopes = [
  'https://www.googleapis.com/auth/spreadsheets',
];

/// Параметры OAuth-клиента.
class GoogleOAuthConfig {
  const GoogleOAuthConfig({
    this.clientId,
    this.clientSecret,
    required this.isWeb,
  });

  const GoogleOAuthConfig.none({this.isWeb = false})
    : clientId = null,
      clientSecret = null;

  final String? clientId;
  final String? clientSecret;
  final bool isWeb;

  bool get isConfigured => clientId != null && clientId!.trim().isNotEmpty;

  /// Значения по умолчанию из `--dart-define`.
  ///
  /// Desktop/Android/iOS: `GOOGLE_CLIENT_ID` + `GOOGLE_CLIENT_SECRET`.
  /// Web: `GOOGLE_WEB_CLIENT_ID`.
  factory GoogleOAuthConfig.fromEnvironment({required bool isWeb}) {
    if (isWeb) {
      return GoogleOAuthConfig(
        clientId: _nonEmpty(
          const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
        ),
        isWeb: true,
      );
    }
    return GoogleOAuthConfig(
      clientId: _nonEmpty(const String.fromEnvironment('GOOGLE_CLIENT_ID')),
      clientSecret: _nonEmpty(
        const String.fromEnvironment('GOOGLE_CLIENT_SECRET'),
      ),
      isWeb: false,
    );
  }

  /// Настройки из приложения важнее значений, собранных в бинарник.
  factory GoogleOAuthConfig.fromSettings(
    CloudSettings settings, {
    required bool isWeb,
  }) {
    final environment = GoogleOAuthConfig.fromEnvironment(isWeb: isWeb);
    if (isWeb) {
      return GoogleOAuthConfig(
        clientId: _nonEmpty(settings.webClientId) ?? environment.clientId,
        isWeb: true,
      );
    }
    return GoogleOAuthConfig(
      clientId: _nonEmpty(settings.clientId) ?? environment.clientId,
      clientSecret:
          _nonEmpty(settings.clientSecret) ?? environment.clientSecret,
      isWeb: false,
    );
  }

  static String? _nonEmpty(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// Токены OAuth 2.0, которые можно сохранить между запусками.
class OAuthTokens {
  const OAuthTokens({
    required this.accessToken,
    required this.expiresAt,
    required this.scopes,
    this.refreshToken,
  });

  final String accessToken;
  final String? refreshToken;

  /// Момент истечения access token (UTC).
  final DateTime expiresAt;
  final List<String> scopes;

  bool get isExpired => DateTime.now().toUtc().isAfter(
    expiresAt.subtract(const Duration(seconds: 60)),
  );

  Map<String, Object?> toJson() => {
    'accessToken': accessToken,
    if (refreshToken != null) 'refreshToken': refreshToken,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'scopes': scopes,
  };

  factory OAuthTokens.fromJson(Map<String, Object?> json) {
    final accessToken = json['accessToken']?.toString();
    final expiresAt = DateTime.tryParse(json['expiresAt']?.toString() ?? '');
    final scopes = json['scopes'];
    if (accessToken == null ||
        accessToken.isEmpty ||
        expiresAt == null ||
        scopes is! List) {
      throw const FormatException('Некорректные OAuth-токены');
    }
    return OAuthTokens(
      accessToken: accessToken,
      refreshToken: json['refreshToken']?.toString(),
      expiresAt: expiresAt.toUtc(),
      scopes: scopes.map((e) => e.toString()).toList(),
    );
  }
}

/// Ошибка входа в Google.
class OAuthException implements Exception {
  const OAuthException(this.message, {this.cancelled = false});

  final String message;
  final bool cancelled;

  @override
  String toString() => message;
}

/// Платформенный OAuth-поток.
abstract interface class OAuthFlow {
  Future<OAuthTokens> signIn(GoogleOAuthConfig config);

  Future<OAuthTokens> refresh(GoogleOAuthConfig config, OAuthTokens tokens);

  Future<void> signOut(OAuthTokens? tokens);
}
