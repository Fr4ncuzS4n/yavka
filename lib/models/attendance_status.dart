/// Категории отметок о посещаемости.
enum AttendanceStatus {
  came('Пришёл'),
  absent('Непришёл'),
  late('Опоздал'),
  excused('По уважительной');

  const AttendanceStatus(this.label);

  /// Подпись для интерфейса и Google Таблицы.
  final String label;

  /// Стабильный код для хранения в JSON.
  String get code => name;

  /// Восстанавливает статус по коду (`came`) или подписи (`Пришёл`).
  ///
  /// Возвращает `null`, если значение не распознано — например, если
  /// пользователь вручную испортил ячейку в таблице.
  static AttendanceStatus? tryParse(Object? value) {
    if (value == null) return null;
    final normalized = value.toString().trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final status in values) {
      if (status.code == normalized ||
          status.label.toLowerCase() == normalized) {
        return status;
      }
    }
    return null;
  }
}
