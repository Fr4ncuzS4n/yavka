import '../../data/schedule_controller.dart';
import '../../models/schedule_lesson.dart';
import 'journal_cell_codec.dart';
import 'journal_layout.dart';
import 'journal_mapping.dart';

/// Одна строка отчёта о дне: что нашлось в таблице и что ждёт расписание.
class JournalCheckRow {
  const JournalCheckRow({
    required this.date,
    required this.columnRange,
    required this.columnCount,
    required this.pairCount,
  });

  final DateTime date;

  /// Блок колонок дня в буквенной ссылке, например «C:F».
  final String columnRange;

  /// Сколько колонок занял день в таблице.
  final int columnCount;

  /// Сколько пар в этот день по расписанию приложения.
  final int pairCount;
}

/// Проблема целостности: таблица и расписание не согласуются.
class JournalCheckIssue {
  const JournalCheckIssue(this.message);

  final String message;
}

/// Отчёт проверки: по дням с парами и список проблем.
class JournalCheckReport {
  const JournalCheckReport({required this.rows, required this.issues});

  final List<JournalCheckRow> rows;
  final List<JournalCheckIssue> issues;

  bool get ok => issues.isEmpty;
}

/// Сверяет журнал с расписанием приложения.
///
/// Пары в дне берутся из расписания: в один день их может быть две, в
/// другой — три. Приложение спрашивает пользователя, верно ли количество
/// пар, и проверяет таблицу на целостность: у каждого дня с парами
/// должен быть блок колонок, вмещающий все пары этого дня.
abstract final class JournalCheck {
  static JournalCheckReport check({
    required DateTime month,
    required JournalMapping mapping,
    required JournalLayout? layout,
    required ScheduleController schedule,
  }) {
    if (layout == null) {
      return JournalCheckReport(
        rows: const [],
        issues: const [
          JournalCheckIssue(
            'Не удалось найти числа дней. Проверьте строку с числами: '
            'в ней должны идти числа 1, 2, 3… слева направо.',
          ),
        ],
      );
    }

    final rows = <JournalCheckRow>[];
    final issues = <JournalCheckIssue>[];
    final days = JournalCellCodec.daysInMonth(month);

    for (var day = 1; day <= days; day++) {
      final date = DateTime(month.year, month.month, day);
      final pairs = schedule.lessonsFor(weekdayOf(date)).length;
      if (pairs == 0) continue; // дня без пар в таблице может и не быть

      final span = layout.spanOf(day);
      if (span == null) {
        issues.add(
          JournalCheckIssue(
            'Дня $day нет в строке чисел, хотя по расписанию в этот день '
            'пар: $pairs. Проверьте таблицу.',
          ),
        );
        continue;
      }

      rows.add(
        JournalCheckRow(
          date: date,
          columnRange:
              '${JournalMapping.columnLetter(span.startColumn)}–'
              '${JournalMapping.columnLetter(span.columnOfPair(span.width))}',
          columnCount: span.width,
          pairCount: pairs,
        ),
      );
      if (pairs > span.width) {
        issues.add(
          JournalCheckIssue(
            'День $day: колонок в блоке — ${span.width}, пар по расписанию '
            '— $pairs. Отметки не поместятся: проверьте таблицу или '
            'расписание.',
          ),
        );
      }
    }

    return JournalCheckReport(rows: rows, issues: issues);
  }
}
