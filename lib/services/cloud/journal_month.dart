/// Месяц журнала, определённый по названию таблицы или листа.
///
/// Пользователь меняет ссылку на таблицу, когда начинается новый месяц,
/// поэтому приложение само подбирает месяц из названия: «МЕСЯЦ : ГОД».
abstract final class JournalMonth {
  static const List<String> monthsRu = [
    'Январь',
    'Февраль',
    'Март',
    'Апрель',
    'Май',
    'Июнь',
    'Июль',
    'Август',
    'Сентябрь',
    'Октябрь',
    'Ноябрь',
    'Декабрь',
  ];

  static const List<String> _monthsRuGenitive = [
    'января',
    'февраля',
    'марта',
    'апреля',
    'мая',
    'июня',
    'июля',
    'августа',
    'сентября',
    'октября',
    'ноября',
    'декабря',
  ];

  /// Название месяца с большой буквы, например «Ноябрь».
  static String monthName(int month) => monthsRu[month - 1];

  /// «Ноябрь 2026» — человекочитаемое имя месяца для интерфейса.
  static String displayName(DateTime month) =>
      '${monthName(month.month)} ${month.year}';

  /// Разбирает название в месяц.
  ///
  /// Понимает «МЕСЯЦ : ГОД» и близкие варианты: «Ноябрь : 2026»,
  /// «ноябрь:2026», «Ноябрь 2026», «НОЯБРЬ». Без года берётся текущий
  /// год. `null`, если название не похоже на месяц.
  static DateTime? parseTitle(String title) {
    final match = RegExp(
      r'^([А-Яа-яЁё]{3,10})\s*[:\-–—]?\s*(\d{4})?$',
    ).firstMatch(title.trim());
    if (match == null) return null;
    final month = _monthFromName(match.group(1)!);
    if (month == null) return null;
    final year = int.tryParse(match.group(2) ?? '') ?? DateTime.now().year;
    return DateTime(year, month);
  }

  static int? _monthFromName(String raw) {
    final name = raw.toLowerCase().replaceAll('ё', 'е');
    for (var i = 0; i < monthsRu.length; i++) {
      if (name == monthsRu[i].toLowerCase().replaceAll('ё', 'е')) return i + 1;
    }
    for (var i = 0; i < _monthsRuGenitive.length; i++) {
      if (name == _monthsRuGenitive[i]) return i + 1;
    }
    return null;
  }
}
