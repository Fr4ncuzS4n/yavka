/// Категории отметок о посещаемости.
enum AttendanceStatus {
  came('Пришёл'),
  absent('Непришёл'),
  late('Опоздал'),
  excused('По уважительной');

  const AttendanceStatus(this.label);

  final String label;
}
