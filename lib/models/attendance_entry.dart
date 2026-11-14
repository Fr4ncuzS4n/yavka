import 'attendance_status.dart';

/// Одна отметка студента: статус, момент и (опционально) пара.
///
/// Если [lessonKey] и [lessonTitle] пусты — отметка относится ко всему дню
/// (главный экран отметки). Если пара указана — отметка считается
/// на конкретной паре из расписания.
class AttendanceEntry {
  const AttendanceEntry({
    required this.status,
    required this.markedAt,
    this.lessonKey,
    this.lessonTitle,
  });

  final AttendanceStatus status;

  /// Локальные дата и время отметки.
  final DateTime markedAt;

  /// Идентификатор пары из расписания (null — отметка на весь день).
  final String? lessonKey;

  /// Название пары на момент отметки — попадает в Google Таблицу и
  /// позволяет сопоставить отметку, если на другом устройстве расписание
  /// другое.
  final String? lessonTitle;

  /// Отметка относится к паре, а не ко всему дню.
  bool get hasLesson =>
      (lessonKey != null && lessonKey!.trim().isNotEmpty) ||
      (lessonTitle != null && lessonTitle!.trim().isNotEmpty);

  Map<String, Object?> toJson() => {
    'status': status.code,
    'markedAt': markedAt.toIso8601String(),
    if (lessonKey != null && lessonKey!.trim().isNotEmpty)
      'lessonKey': lessonKey,
    if (lessonTitle != null && lessonTitle!.trim().isNotEmpty)
      'lessonTitle': lessonTitle,
  };

  factory AttendanceEntry.fromJson(Map<String, Object?> json) {
    final status = AttendanceStatus.tryParse(json['status']);
    final markedAt = DateTime.tryParse(json['markedAt']?.toString() ?? '');
    if (status == null || markedAt == null) {
      throw const FormatException('Некорректная отметка посещаемости');
    }
    return AttendanceEntry(
      status: status,
      markedAt: markedAt,
      lessonKey: json['lessonKey']?.toString(),
      lessonTitle: json['lessonTitle']?.toString(),
    );
  }
}
