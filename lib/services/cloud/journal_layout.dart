import 'sheets_api.dart';
import 'journal_mapping.dart';

/// Блок колонок одного дня журнала.
///
/// Ширина блока — сколько колонок между этим днём и следующим. Какие из
/// них колонки пар и под какими номерами, решает строка «ПАРА»: колонки
/// с числом получают свой номер, а если чисел в блоке нет вовсе, пары
/// нумеруются по колонкам слева направо (первая колонка — пара 1).
class JournalDaySpan {
  const JournalDaySpan({
    required this.day,
    required this.startColumn,
    required this.width,
    this.pairColumns = const {},
  });

  /// Число дня месяца (1–31).
  final int day;

  /// Первая колонка блока (0-based).
  final int startColumn;

  /// Сколько колонок занимает день.
  final int width;

  /// Номер пары → колонка блока (0-based).
  ///
  /// Числа берутся из строки «ПАРА» (см. [JournalMapping.pairRow]);
  /// если в блоке чисел нет, пары нумеруются по смещению: колонка
  /// с offset k — пара k + 1.
  final Map<int, int> pairColumns;

  /// Номера пар блока по возрастанию.
  List<int> get pairs {
    final numbers = pairColumns.keys.toList()..sort();
    return numbers;
  }

  /// Колонки всех пар блока по возрастанию номера пары.
  List<int> get pairColumnList => [
    for (final pair in pairs) pairColumns[pair]!,
  ];

  /// Первая и последняя колонки пар блока — для отчёта «колонки C:F».
  (int, int) get pairColumnRange {
    if (pairColumns.isEmpty) return (startColumn, startColumn + width - 1);
    final columns = pairColumns.values.toList()..sort();
    return (columns.first, columns.last);
  }

  /// Есть ли в блоке колонка для пары [pair].
  bool hasPair(int pair) => pairColumns.containsKey(pair);

  /// Колонка пары [pair] или `null`, если такой пары в блоке нет.
  int? columnOfPairOrNull(int pair) => pairColumns[pair];

  /// Колонка пары [pair] (1-based) внутри блока.
  int columnOfPair(int pair) =>
      pairColumns[pair] ?? (startColumn + pair - 1);
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

    // Номера пар: из строки «ПАРА», если пользователь её указал, иначе
    // по колонкам блока слева направо.
    final pairRow = mapping.pairRow;
    final hasPairRow = pairRow != null && pairRow < grid.rows.length;
    for (var i = 0; i < spans.length; i++) {
      spans[i] = JournalDaySpan(
        day: spans[i].day,
        startColumn: spans[i].startColumn,
        width: spans[i].width,
        pairColumns: hasPairRow
            ? _pairColumnsOf(spans[i], grid, pairRow)
            : _offsetPairColumns(spans[i]),
      );
    }

    // У последнего дня ширина «до конца листа» — уточняем её по строке
    // пар: настоящая ширина блока — по самую правую колонку с номером.
    final lastSpan = spans.last;
    if (hasPairRow && lastSpan.pairColumns.isNotEmpty) {
      final widthByPairs = lastSpan.pairColumns.values
          .map((column) => column - lastSpan.startColumn + 1)
          .reduce((a, b) => a > b ? a : b);
      if (widthByPairs < lastSpan.width) {
        spans[spans.length - 1] = JournalDaySpan(
          day: lastSpan.day,
          startColumn: lastSpan.startColumn,
          width: widthByPairs,
          pairColumns: lastSpan.pairColumns,
        );
      }
    }
    return JournalLayout(dayRow: mapping.dayRow, spans: spans);
  }

  /// Пары по колонкам блока: колонка с offset k — пара k + 1.
  static Map<int, int> _offsetPairColumns(JournalDaySpan span) => {
    for (var offset = 0; offset < span.width; offset++)
      offset + 1: span.startColumn + offset,
  };

  /// Номера пар блока по строке «ПАРА».
  ///
  /// Колонка с числом в строке пар — колонка пары с этим номером. Если
  /// в блоке чисел нет вовсе, пары нумеруются по колонкам блока слева
  /// направо (первая колонка — пара 1), как в журналах без строки пар.
  /// А если числа есть, колонки без числа парами не считаются: это
  /// колонка «на весь день» или просто пустое место за блоком.
  static Map<int, int> _pairColumnsOf(
    JournalDaySpan span,
    SheetGrid grid,
    int pairRow,
  ) {
    final columns = <int, int>{};
    var numbered = false;
    for (var offset = 0; offset < span.width; offset++) {
      final column = span.startColumn + offset;
      final value = int.tryParse(
        grid.cell(pairRow, column).value?.toString().trim() ?? '',
      );
      if (value != null && value >= 1) {
        columns.putIfAbsent(value, () => column);
        numbered = true;
      }
    }
    if (numbered) return columns;
    return _offsetPairColumns(span);
  }
}
