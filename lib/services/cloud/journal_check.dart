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

/// Отчёт проверки: по дням с парами, блокирующие проблемы и
/// предупреждения.
class JournalCheckReport {
  const JournalCheckReport({
    required this.rows,
    required this.issues,
    this.warnings = const [],
  });

  final List<JournalCheckRow> rows;

  /// Проблемы, из-за которых синхронизация заблокирована.
  final List<JournalCheckIssue> issues;

  /// Предупреждения: не блокируют синхронизацию. Например, обрывки —
  /// дни, в которые посещаемость расставить нельзя.
  final List<JournalCheckIssue> warnings;

  bool get ok => issues.isEmpty;
}

/// Сверяет журнал с расписанием приложения.
///
/// Пары в дне берутся из расписания: в один день их может быть две, в
/// другой — три. Приложение спрашивает пользователя, верно ли количество
/// пар, и проверяет таблицу на целостность: у каждого дня с парами
/// должен быть блок колонок, вмещающий все пары этого дня. Выходные
/// (суббота и воскресенье) не проверяются и в отчёт не попадают:
/// отмечать в них нельзя, значит и колонок под них в журнале нет.
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
    final warnings = <JournalCheckIssue>[];
    final days = JournalCellCodec.daysInMonth(month);

    for (var day = 1; day <= days; day++) {
      final date = DateTime(month.year, month.month, day);
      // В выходные отмечать нельзя, поэтому колонок под них в журнале
      // нет — и требовать их не нужно.
      if (weekdayOf(date) >= 6) continue;
      final pairs = schedule.lessonsFor(weekdayOf(date)).length;
      if (pairs == 0) continue; // дня без пар в таблице может и не быть

      final span = layout.spanOf(day);
      if (span == null) {
        // Журнал может начинаться не с 1 числа: дня нет — отметки в
        // него не расставить, но и синхронизацию блокировать нечего.
        warnings.add(
          JournalCheckIssue(
            'Дня $day нет в журнале — посещаемость за этот день '
            'расставить нельзя.',
          ),
        );
        continue;
      }

      final (firstColumn, lastColumn) = span.pairColumnRange;
      rows.add(
        JournalCheckRow(
          date: date,
          columnRange:
              '${JournalMapping.columnLetter(firstColumn)}–'
              '${JournalMapping.columnLetter(lastColumn)}',
          columnCount: span.width,
          pairCount: pairs,
        ),
      );

      // Каждая пара расписания должна найти свою колонку в блоке: либо
      // по номеру в строке пар, либо по смещению, если строки пар нет.
      // Обрывок блока — предупреждение: в такой день посещаемость не
      // расставить, но остальные дни синхронизируются.
      final missing = [
        for (var pair = 1; pair <= pairs; pair++)
          if (!span.hasPair(pair)) pair,
      ];
      if (missing.isNotEmpty) {
        warnings.add(
          JournalCheckIssue(
            'День $day: в блоке нет колонок для пар(ы) '
            '${missing.join(", ")} — посещаемость за этот день расставить '
            'нельзя.',
          ),
        );
      }
    }

    return JournalCheckReport(
      rows: rows,
      issues: issues,
      warnings: warnings,
    );
  }
}
