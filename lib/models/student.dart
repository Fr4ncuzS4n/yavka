/// Участник списка группы.
class Student {
  const Student({required this.id, required this.fullName});

  /// Идентификатор студента в рамках группы.
  final String id;

  /// Имя и фамилия.
  final String fullName;

  /// Инициалы для аватара, например «АМ».
  String get initials {
    final parts =
        fullName.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}
