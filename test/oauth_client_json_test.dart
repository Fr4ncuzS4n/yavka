// Тесты разбора JSON-файла OAuth-клиента из Google Cloud Console.

import 'package:flutter_test/flutter_test.dart';
import 'package:yavka/services/cloud/oauth/oauth_client_json.dart';

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
}
