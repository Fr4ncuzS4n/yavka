/// Уведомление о том, что кто-то отметил студентов на паре.
///
/// Приходит из листа «Уведомления» в подключённой Google Таблице:
/// все, кто пользуется этой таблицей, видят отметки друг друга.
class SyncNotification {
  const SyncNotification({
    required this.id,
    required this.createdAt,
    required this.author,
    required this.groupName,
    required this.lessonTitle,
    required this.message,
    this.isRead = false,
  });

  /// Стабильный ключ для дедупликации: одинаковая строка таблицы
  /// не должна показываться дважды.
  final String id;

  /// Момент, когда отметку поставили.
  final DateTime createdAt;

  /// Кто отметил (имя из настроек приложения).
  final String author;

  /// Группа, к которой относится пара.
  final String groupName;

  /// Название пары из расписания.
  final String lessonTitle;

  /// Человекочитаемый текст уведомления.
  final String message;

  /// Прочитано ли уведомление на этом устройстве.
  final bool isRead;

  SyncNotification copyWith({bool? isRead}) => SyncNotification(
    id: id,
    createdAt: createdAt,
    author: author,
    groupName: groupName,
    lessonTitle: lessonTitle,
    message: message,
    isRead: isRead ?? this.isRead,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAt': createdAt.toIso8601String(),
    'author': author,
    'groupName': groupName,
    'lessonTitle': lessonTitle,
    'message': message,
    'isRead': isRead,
  };

  factory SyncNotification.fromJson(Map<String, Object?> json) {
    final id = json['id']?.toString() ?? '';
    final createdAt = DateTime.tryParse(json['createdAt']?.toString() ?? '');
    final message = json['message']?.toString() ?? '';
    if (id.isEmpty || createdAt == null) {
      throw const FormatException('Некорректное уведомление');
    }
    return SyncNotification(
      id: id,
      createdAt: createdAt,
      author: json['author']?.toString() ?? '',
      groupName: json['groupName']?.toString() ?? '',
      lessonTitle: json['lessonTitle']?.toString() ?? '',
      message: message,
      isRead: json['isRead']?.toString() == 'true',
    );
  }
}

/// Отложенное уведомление: пара, отмеченная локально, но ещё не
/// отправленная в таблицу (отправится при следующей синхронизации).
class PendingLessonMark {
  const PendingLessonMark({
    required this.id,
    required this.date,
    required this.groupName,
    required this.lessonTitle,
    required this.lessonTime,
    this.count = 1,
  });

  /// Ключ дедупликации внутри отложенных: один день + одна пара.
  final String id;

  /// День, к которому относится пара.
  final DateTime date;

  /// Название группы.
  final String groupName;

  /// Название пары.
  final String lessonTitle;

  /// Время начала пары, «09:00».
  final String lessonTime;

  /// Сколько студентов отмечено на паре.
  final int count;

  PendingLessonMark copyWith({int? count}) => PendingLessonMark(
    id: id,
    date: date,
    groupName: groupName,
    lessonTitle: lessonTitle,
    lessonTime: lessonTime,
    count: count ?? this.count,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'date': date.toIso8601String().substring(0, 10),
    'groupName': groupName,
    'lessonTitle': lessonTitle,
    'lessonTime': lessonTime,
    'count': count,
  };

  factory PendingLessonMark.fromJson(Map<String, Object?> json) {
    final id = json['id']?.toString() ?? '';
    final date = DateTime.tryParse(json['date']?.toString() ?? '');
    final lessonTitle = json['lessonTitle']?.toString() ?? '';
    if (id.isEmpty || date == null || lessonTitle.isEmpty) {
      throw const FormatException('Некорректное отложенное уведомление');
    }
    return PendingLessonMark(
      id: id,
      date: date,
      groupName: json['groupName']?.toString() ?? '',
      lessonTitle: lessonTitle,
      lessonTime: json['lessonTime']?.toString() ?? '',
      count: int.tryParse(json['count']?.toString() ?? '') ?? 1,
    );
  }
}
