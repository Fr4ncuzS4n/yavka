import 'dart:convert';

/// Что пользователь рассказал приложению о своём журнале.
///
/// Приложение не меняет таблицу, а подстраивается под неё: пользователь
/// один раз объясняет, где что находится — в каком листе журнал, в какой
/// строке числа дней, в какой колонке ФИО, с какой строки начинаются
/// студенты и какой строкой заканчиваются, а также в какой строке номера
/// пар. Пары в дне берутся из расписания приложения, а если расписания
/// нет — номера пар берутся из таблицы.
class JournalMapping {
  const JournalMapping({
    required this.tabTitle,
    required this.dayRow,
    required this.fioColumn,
    required this.firstStudentRow,
    this.pairRow,
    this.lastStudentRow,
  });

  /// Название листа с журналом, например «НОЯБРЬ : 2026».
  final String tabTitle;

  /// Строка с числами дней (0-based).
  final int dayRow;

  /// Колонка с ФИО студентов (0-based).
  final int fioColumn;

  /// Первая строка студентов (0-based).
  final int firstStudentRow;

  /// Строка с номерами пар («ПАРА», 0-based).
  ///
  /// В блоке дня колонками пар считаются те, у которых в этой строке
  /// стоит число. Если строки нет, пары нумеруются по колонкам блока
  /// слева направо: первая колонка — пара 1 и так далее.
  final int? pairRow;

  /// Последняя строка студентов (0-based, включительно).
  ///
  /// `null` — студенты до конца листа.
  final int? lastStudentRow;

  JournalMapping copyWith({
    String? tabTitle,
    int? dayRow,
    int? fioColumn,
    int? firstStudentRow,
    int? pairRow,
    int? lastStudentRow,
  }) => JournalMapping(
    tabTitle: tabTitle ?? this.tabTitle,
    dayRow: dayRow ?? this.dayRow,
    fioColumn: fioColumn ?? this.fioColumn,
    firstStudentRow: firstStudentRow ?? this.firstStudentRow,
    pairRow: pairRow ?? this.pairRow,
    lastStudentRow: lastStudentRow ?? this.lastStudentRow,
  );

  Map<String, Object?> toJson() => {
    'tabTitle': tabTitle,
    'dayRow': dayRow,
    'fioColumn': fioColumn,
    'firstStudentRow': firstStudentRow,
    if (pairRow != null) 'pairRow': pairRow,
    if (lastStudentRow != null) 'lastStudentRow': lastStudentRow,
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
    // Новые поля необязательны: настройка, сохранённая раньше, без них
    // продолжает работать — пары нумеруются по колонкам блока.
    int? optional(String key) {
      if (!json.containsKey(key) || json[key] == null) return null;
      final value = int.tryParse(json[key].toString());
      return value != null && value >= 0 ? value : null;
    }

    return JournalMapping(
      tabTitle: tabTitle,
      dayRow: dayRow,
      fioColumn: fioColumn,
      firstStudentRow: firstStudentRow,
      pairRow: optional('pairRow'),
      lastStudentRow: optional('lastStudentRow'),
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
