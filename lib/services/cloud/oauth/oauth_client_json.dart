import 'dart:convert';

/// OAuth-клиент, распознанный из JSON-файла Google Cloud Console.
class OAuthClientFile {
  const OAuthClientFile({
    required this.kind,
    this.clientId,
    this.clientSecret,
    this.webClientId,
  });

  /// Client ID для Android/iOS/Linux/Windows (секция «installed»).
  final String? clientId;

  /// Client Secret для Desktop-клиента.
  final String? clientSecret;

  /// Client ID для web (секция «web»).
  final String? webClientId;

  /// Какой тип клиента распознан: «Desktop app» или «Web application».
  final String kind;

  /// Что распозналось — для сообщения пользователю.
  String get summary {
    final hasSecret = clientSecret != null && clientSecret!.trim().isNotEmpty;
    return switch (kind) {
      'Web application' => hasSecret
          ? 'Web Client ID и Client Secret'
          : 'Web Client ID',
      _ => hasSecret ? 'Client ID и Client Secret' : 'Client ID',
    };
  }
}

/// Разбор JSON-файла OAuth-клиента, скачанного из Google Cloud Console.
///
/// Кнопка «Скачать JSON» в разделе Credentials отдаёт файл с одной из
/// секций: «installed» (тип «Desktop app», а также Android/iOS) или «web»
/// (тип «Web application»). Ключ сервисного аккаунта в приложение не
/// подходит — о нём сообщаем отдельно.
abstract final class OAuthClientJson {
  /// Разбирает файл. [FormatException] с понятным текстом — если файл
  /// не тот, что нужен.
  static OAuthClientFile parse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const FormatException(
        'Это не JSON. Скачайте файл OAuth-клиента из Google Cloud Console: '
        'Credentials → клиент → «Скачать JSON».',
      );
    }
    if (decoded is! Map) {
      throw const FormatException(
        'Файл не похож на OAuth-клиент. Скачайте JSON из Google Cloud '
        'Console: Credentials → клиент → «Скачать JSON».',
      );
    }
    if (decoded['type']?.toString() == 'service_account') {
      throw const FormatException(
        'Это ключ сервисного аккаунта — для входа в приложении он не '
        'подходит. Нужен OAuth-клиент типа «Desktop app» или '
        '«Web application»: Credentials → Create credentials → OAuth '
        'client ID → «Скачать JSON».',
      );
    }

    final installed = _section(decoded, 'installed');
    final web = _section(decoded, 'web');
    if (installed == null && web == null) {
      throw const FormatException(
        'В файле нет секции «installed» или «web». Скачайте JSON '
        'OAuth-клиента в Google Cloud Console: Credentials → клиент → '
        '«Скачать JSON».',
      );
    }

    if (installed != null) {
      final clientId = _string(installed['client_id']);
      if (clientId == null) {
        throw const FormatException('В файле нет client_id.');
      }
      return OAuthClientFile(
        kind: 'Desktop app',
        clientId: clientId,
        clientSecret: _string(installed['client_secret']),
      );
    }

    final webClientId = _string(web!['client_id']);
    if (webClientId == null) {
      throw const FormatException('В файле нет client_id.');
    }
    return OAuthClientFile(
      kind: 'Web application',
      webClientId: webClientId,
      clientSecret: _string(web['client_secret']),
    );
  }

  static Map<Object?, Object?>? _section(Map decoded, String key) {
    final section = decoded[key];
    return section is Map ? section : null;
  }

  static String? _string(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }
}
