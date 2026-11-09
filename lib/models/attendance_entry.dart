import 'attendance_status.dart';

/// Одна отметка студента: статус и момент, когда её поставили.
class AttendanceEntry {
  const AttendanceEntry({required this.status, required this.markedAt});

  final AttendanceStatus status;

  /// Локальные дата и время отметки.
  final DateTime markedAt;

  Map<String, Object?> toJson() => {
    'status': status.code,
    'markedAt': markedAt.toIso8601String(),
  };

  factory AttendanceEntry.fromJson(Map<String, Object?> json) {
    final status = AttendanceStatus.tryParse(json['status']);
    final markedAt = DateTime.tryParse(json['markedAt']?.toString() ?? '');
    if (status == null || markedAt == null) {
      throw const FormatException('Некорректная отметка посещаемости');
    }
    return AttendanceEntry(status: status, markedAt: markedAt);
  }
}
