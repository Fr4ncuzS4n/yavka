/// Ошибка облачной синхронизации с понятным пользователю текстом.
class CloudSyncException implements Exception {
  const CloudSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Нет прав на редактирование таблицы (пользователь — читатель, а не редактор).
class GooglePermissionException extends CloudSyncException {
  const GooglePermissionException()
    : super(
        'Нет прав на редактирование таблицы. Убедитесь, что у вас есть '
        'доступ «Редактор» (со-владелец), или создайте новую таблицу.',
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
