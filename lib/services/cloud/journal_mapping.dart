import 'dart:convert';

/// Что пользователь рассказал приложению о своём журнале.
///
/// Приложение не меняет таблицу, а подстраивается под неё: пользователь
/// один раз объясняет, где что находится — в каком листе журнал, в какой
/// строке числа дней, в какой колонке ФИО и с какой строки начинаются
/// студенты. Пары в дне берутся из расписания приложения.
class JournalMapping {
  const JournalMapping({
    required this.tabTitle,
    required this.dayRow,
    required this.fioColumn,
    required this.firstStudentRow,
  });

  /// Название листа с журналом, например «НОЯБРЬ : 2026».
  final String tabTitle;

  /// Строка с числами дней (0-based).
  final int dayRow;

  /// Колонка с ФИО студентов (0-based).
  final int fioColumn;

  /// Первая строка студентов (0-based).
  final int firstStudentRow;

  JournalMapping copyWith({
    String? tabTitle,
    int? dayRow,
    int? fioColumn,
    int? firstStudentRow,
  }) => JournalMapping(
    tabTitle: tabTitle ?? this.tabTitle,
    dayRow: dayRow ?? this.dayRow,
    fioColumn: fioColumn ?? this.fioColumn,
    firstStudentRow: firstStudentRow ?? this.firstStudentRow,
  );

  Map<String, Object?> toJson() => {
    'tabTitle': tabTitle,
    'dayRow': dayRow,
    'fioColumn': fioColumn,
    'firstStudentRow': firstStudentRow,
  };

  factory JournalMapping.fromJson(Map<String, Object?> json) {
    final tabTitle = json['tabTitle']?.toString() ?? '';
    final dayRow = int.tryParse(json['dayRow']?.toString() ?? '') ?? -1;
    final fioColumn =
        int.tryParse(json['fioColumn']?.toString() ?? '') ?? -1;
    final firstStudentRow =
        int.tryParse(json['firstStudentRow']?.toString() ?? '') ?? -1;
    if (tabTitle.trim().isEmpty ||
        dayRow < 0 ||
        fioColumn < 0 ||
        firstStudentRow < 0) {
      throw const FormatException('Некорректная настройка журнала');
    }
    return JournalMapping(
      tabTitle: tabTitle,
      dayRow: dayRow,
      fioColumn: fioColumn,
      firstStudentRow: firstStudentRow,
    );
  }

  static JournalMapping? tryDecode(String json) {
    if (json.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map) return null;
      return JournalMapping.fromJson(
        Map<String, Object?>.from(decoded.cast<String, dynamic>()),
      );
    } catch (_) {
      // Повреждённая настройка — считаем, что журнала не настроен.
      return null;
    }
  }

  String encode() => jsonEncode(toJson());

  /// «B» → 1: буквенная ссылка колонки Google Таблиц в 0-based индекс.
  ///
  /// Принимает и адрес вида «B2», берёт из него только буквы.
  static int? parseColumnLetter(String input) {
    final letters = input
        .trim()
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z]'), '');
    if (letters.isEmpty || letters.length > 3) return null;
    var index = 0;
    for (final letter in letters.runes) {
      index = index * 26 + (letter - 0x41 + 1);
    }
    return index - 1;
  }

  /// 1 → «B»: колонка в буквенной ссылке Google Таблиц.
  static String columnLetter(int index) {
    var rest = index + 1;
    final letters = <String>[];
    while (rest > 0) {
      letters.add(String.fromCharCode(0x41 + (rest - 1) % 26));
      rest = (rest - 1) ~/ 26;
    }
    return letters.reversed.join();
  }
}
