/// Ошибка облачной синхронизации с понятным пользователю текстом.
class CloudSyncException implements Exception {
  const CloudSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Нет прав на редактирование таблицы (пользователь — читатель, а не
/// редактор, либо вход выполнен не в тот аккаунт Google).
class GooglePermissionException extends CloudSyncException {
  const GooglePermissionException()
    : super(
        'Не хватает доступа «Редактор» к таблице. Проверьте: '
        '(1) вам выдали доступ «Редактор» (со-владелец), а не «Читатель»; '
        '(2) вошёл именно тот аккаунт Google, которому '
        'выдали доступ.',
      );
}

/// Google Sheets API не включён в проекте OAuth-клиента — Google отвечает
/// 403, даже если пользователь редактор таблицы.
class GoogleSheetsApiDisabledException extends CloudSyncException {
  const GoogleSheetsApiDisabledException()
    : super(
        'Google Sheets API не включён для вашего OAuth-клиента. В Google '
        'Cloud Console откройте APIs & Services → Library, включите '
        '«Google Sheets API» для проекта, в котором создан Client ID, '
        'и подождите несколько минут.',
      );
}

/// Google отклоняет запросы из-за лимита (квоты) — нужно подождать.
class GoogleRateLimitException extends CloudSyncException {
  const GoogleRateLimitException()
    : super(
        'Google временно отклоняет запросы: превышен лимит. '
        'Подождите пару минут и повторите.',
      );
}

/// Таблица не найдена или у пользователя нет к ней доступа.
class SpreadsheetNotFoundException extends CloudSyncException {
  const SpreadsheetNotFoundException()
    : super('Таблица не найдена. Проверьте ссылку и доступ к ней.');
}

/// Сессия Google истекла.
class GoogleAuthRequiredException extends CloudSyncException {
  const GoogleAuthRequiredException()
    : super('Сессия Google истекла. Войдите в аккаунт снова.');
}

/// Прочая ошибка Google API.
class GoogleApiException extends CloudSyncException {
  const GoogleApiException(super.message, {this.statusCode});

  final int? statusCode;
}
