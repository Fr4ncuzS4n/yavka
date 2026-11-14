// Тесты разбора вставленного документа с расписанием.

import 'package:flutter_test/flutter_test.dart';
import 'package:yavka/data/schedule_parser.dart';

void main() {
  test('строка «время–время предмет, каб. N» разбирается в пару', () {
    final parsed = ScheduleParser.parse(
      '09:00–10:30 Математика, каб. 201',
      fallbackWeekday: 1,
    );

    expect(parsed.lessons, hasLength(1));
    expect(parsed.weekdays, {1});
    final lesson = parsed.lessons.single;
    expect(lesson.weekday, 1);
    expect(lesson.startMinutes, 9 * 60);
    expect(lesson.endMinutes, 10 * 60 + 30);
    expect(lesson.subject, 'Математика');
    expect(lesson.room, '201');
  });

  test('маркеры списка и точка вместо двоеточия не мешают разбору', () {
    final parsed = ScheduleParser.parse(
      '1. 9.00 Физика\n- 10:40 Химия',
      fallbackWeekday: 3,
    );

    expect(parsed.lessons, hasLength(2));
    expect(parsed.lessons[0].startMinutes, 9 * 60);
    expect(parsed.lessons[0].subject, 'Физика');
    expect(parsed.lessons[1].startMinutes, 10 * 60 + 40);
    expect(parsed.lessons[1].weekday, 3);
  });

  test('заголовки дней распределяют пары по дням недели', () {
    final parsed = ScheduleParser.parse('''
Понедельник
09:00 Математика
10:40 Физика

Вторник
09:00 История
''', fallbackWeekday: 5);

    expect(parsed.weekdays, {1, 2});
    final monday = parsed.lessons.where((l) => l.weekday == 1).toList();
    final tuesday = parsed.lessons.where((l) => l.weekday == 2).toList();
    expect(monday.map((l) => l.subject), ['Математика', 'Физика']);
    expect(tuesday.map((l) => l.subject), ['История']);
  });

  test('короткие названия дней тоже распознаются', () {
    final parsed = ScheduleParser.parse('Пн:\n08:00 Зарядка', fallbackWeekday: 2);
    expect(parsed.lessons.single.weekday, 1);
  });

  test('колонки через табуляцию: время, конец, предмет, кабинет', () {
    final parsed = ScheduleParser.parse(
      '09:00\t10:30\tМатематика\t201\tИванова И.И.',
      fallbackWeekday: 4,
    );

    final lesson = parsed.lessons.single;
    expect(lesson.startMinutes, 9 * 60);
    expect(lesson.endMinutes, 10 * 60 + 30);
    expect(lesson.subject, 'Математика');
    expect(lesson.room, '201');
    expect(lesson.teacher, 'Иванова И.И.');
  });

  test('преподаватель после тире и «преп.» выносится отдельно', () {
    final parsed = ScheduleParser.parse(
      '09:00 История — Петров П.П.',
      fallbackWeekday: 1,
    );
    expect(parsed.lessons.single.teacher, 'Петров П.П.');
    expect(parsed.lessons.single.subject, 'История');

    final parsed2 = ScheduleParser.parse(
      '09:00 Физика, ауд. 12, преп. Сидоров',
      fallbackWeekday: 1,
    );
    expect(parsed2.lessons.single.teacher, 'Сидоров');
    expect(parsed2.lessons.single.room, '12');
    expect(parsed2.lessons.single.subject, 'Физика');
  });

  test('строки без времени и мусор пропускаются', () {
    final parsed = ScheduleParser.parse(
      'Расписание на неделю\nКонсультации\n09:00 Математика',
      fallbackWeekday: 1,
    );
    expect(parsed.lessons, hasLength(1));
    expect(parsed.lessons.single.subject, 'Математика');
  });

  test('пустой документ не даёт пар', () {
    final parsed = ScheduleParser.parse('   \n \n', fallbackWeekday: 1);
    expect(parsed.lessons, isEmpty);
    expect(parsed.weekdays, isEmpty);
  });

  test('некорректное время отбрасывает строку целиком', () {
    final parsed = ScheduleParser.parse(
      '25:99 Математика',
      fallbackWeekday: 1,
    );
    expect(parsed.lessons, isEmpty);
  });
}
