// Тесты разбора JSON-файла OAuth-клиента из Google Cloud Console
// и приоритета учётных данных: настройки приложения, вшитый клиент.

import 'package:flutter_test/flutter_test.dart';
import 'package:yavka/data/cloud_settings.dart';
import 'package:yavka/services/cloud/oauth/oauth_client_json.dart';
import 'package:yavka/services/cloud/oauth/oauth_models.dart';

void main() {
  test('файл типа «Desktop app» разбирается', () {
    const text = '''
{
  "installed": {
    "client_id": "123-abc.apps.googleusercontent.com",
    "project_id": "yavka",
    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
    "client_secret": "GOCSPX-secret",
    "redirect_uris": ["http://localhost"]
  }
}
''';
    final client = OAuthClientJson.parse(text);

    expect(client.kind, 'Desktop app');
    expect(client.clientId, '123-abc.apps.googleusercontent.com');
    expect(client.clientSecret, 'GOCSPX-secret');
    expect(client.summary, 'Client ID и Client Secret');
  });

  test('клиент Android/iOS без секрета — тоже Desktop app', () {
    const text = '''
{
  "installed": {
    "client_id": "456-def.apps.googleusercontent.com",
    "project_id": "yavka"
  }
}
''';
    final client = OAuthClientJson.parse(text);

    expect(client.kind, 'Desktop app');
    expect(client.clientId, '456-def.apps.googleusercontent.com');
    expect(client.clientSecret, isNull);
    expect(client.summary, 'Client ID');
  });

  test('файл типа «Web application» разбирается в web client', () {
    const text = '''
{
  "web": {
    "client_id": "789-web.apps.googleusercontent.com",
    "project_id": "yavka",
    "client_secret": "GOCSPX-web-secret",
    "javascript_origins": ["http://localhost:8080"]
  }
}
''';
    final client = OAuthClientJson.parse(text);

    expect(client.kind, 'Web application');
    expect(client.webClientId, '789-web.apps.googleusercontent.com');
    expect(client.clientSecret, 'GOCSPX-web-secret');
    expect(client.summary, 'Web Client ID и Client Secret');
  });

  test('ключ сервисного аккаунта объясняется отдельно', () {
    const text = '''
{
  "type": "service_account",
  "project_id": "yavka",
  "private_key": "-----BEGIN PRIVATE KEY-----"
}
''';
    expect(
      () => OAuthClientJson.parse(text),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('сервисного аккаунта'),
        ),
      ),
    );
  });

  test('не JSON и не файл клиента — понятные ошибки', () {
    expect(
      () => OAuthClientJson.parse('это точно не json {'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('не JSON'),
        ),
      ),
    );
    expect(
      () => OAuthClientJson.parse('["массив", "вместо объекта"]'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('не похож'),
        ),
      ),
    );
    expect(
      () => OAuthClientJson.parse('{"project_id": "yavka"}'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('installed'),
        ),
      ),
    );
    expect(
      () => OAuthClientJson.parse('{"installed": {"project_id": "yavka"}}'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('client_id'),
        ),
      ),
    );
  });

  test('настройки приложения перекрывают вшитый OAuth-клиент', () {
    const settings = CloudSettings(
      clientId: 'own-id.apps.googleusercontent.com',
      clientSecret: 'own-secret',
    );

    final config = GoogleOAuthConfig.fromSettings(settings, isWeb: false);

    expect(config.clientId, 'own-id.apps.googleusercontent.com');
    expect(config.clientSecret, 'own-secret');
    expect(config.isConfigured, isTrue);
  });

  test('без своих настроек работает вшитый клиент сборки', () {
    // В тестах --dart-define пуст, поэтому «вшитый» клиент отсутствует:
    // конфигурация не задана, экран входа это покажет.
    const settings = CloudSettings();

    final config = GoogleOAuthConfig.fromSettings(settings, isWeb: false);

    expect(config.isConfigured, isFalse);
  });

  test('web-клиент берётся из своих настроек или из сборки', () {
    const settings = CloudSettings(
      webClientId: 'web-id.apps.googleusercontent.com',
    );

    final web = GoogleOAuthConfig.fromSettings(settings, isWeb: true);

    expect(web.clientId, 'web-id.apps.googleusercontent.com');
    expect(web.isConfigured, isTrue);
  });
}
