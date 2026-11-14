import 'sheets_api.dart';
import 'journal_mapping.dart';

/// Блок колонок одного дня журнала.
///
/// Ширина блока — сколько колонок между этим днём и следующим; пары в
/// блоке идут слева направо: пара N живёт в N-й колонке блока.
class JournalDaySpan {
  const JournalDaySpan({
    required this.day,
    required this.startColumn,
    required this.width,
  });

  /// Число дня месяца (1–31).
  final int day;

  /// Первая колонка блока (0-based).
  final int startColumn;

  /// Сколько колонок занимает день.
  final int width;

  /// Есть ли в блоке колонка для пары [pair] (1-based).
  bool hasPair(int pair) => pair >= 1 && pair <= width;

  /// Колонка пары [pair] (1-based) внутри блока.
  int columnOfPair(int pair) => startColumn + pair - 1;
}

/// Раскладка журнала, снятая с листа по настройке пользователя.
class JournalLayout {
  JournalLayout({required this.dayRow, required this.spans});

  /// Строка, в которой нашлись числа дней.
  final int dayRow;

  /// Блоки дней по возрастанию дня.
  final List<JournalDaySpan> spans;

  JournalDaySpan? spanOf(int day) {
    for (final span in spans) {
      if (span.day == day) return span;
    }
    return null;
  }

  /// Ищет числа дней в строке [mapping.dayRow] и строит блоки.
  ///
  /// Числа должны идти слева направо по возрастанию — как в настоящем
  /// журнале. Объединённые ячейки не мешают: значение объединённого
  /// блока живёт в первой ячейке. `null` — строка не разобралась.
  static JournalLayout? scan(SheetGrid grid, JournalMapping mapping) {
    if (mapping.dayRow >= grid.rows.length) return null;

    final spans = <JournalDaySpan>[];
    var previousDay = 0;
    for (var column = 0; column < grid.colCount; column++) {
      final value = int.tryParse(
        grid.cell(mapping.dayRow, column).value?.toString().trim() ?? '',
      );
      if (value == null || value < 1 || value > 31) continue;
      if (value <= previousDay) return null; // числа должны расти слева направо
      final span = JournalDaySpan(day: value, startColumn: column, width: 0);
      if (spans.isNotEmpty) {
        spans[spans.length - 1] = JournalDaySpan(
          day: spans.last.day,
          startColumn: spans.last.startColumn,
          width: column - spans.last.startColumn,
        );
      }
      spans.add(span);
      previousDay = value;
    }
    if (spans.isEmpty) return null;

    // Ширина последнего дня — до конца листа: следующего числа нет.
    final last = spans.last;
    spans[spans.length - 1] = JournalDaySpan(
      day: last.day,
      startColumn: last.startColumn,
      width: (grid.colCount - last.startColumn).clamp(1, 12),
    );
    return JournalLayout(dayRow: mapping.dayRow, spans: spans);
  }
}
