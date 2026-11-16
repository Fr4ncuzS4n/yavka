// Тесты временного порядка пар: при пустом расписании экран отметки
// показывает «Пара 1…N», а журнал подстраивает N под колонки пар дня.

import 'package:flutter_test/flutter_test.dart';
import 'package:yavka/data/schedule_controller.dart';
import 'package:yavka/models/schedule_lesson.dart';

ScheduleController scheduleWith({required int weekday, required int count}) {
  final schedule = ScheduleController.inMemory();
  for (var i = 1; i <= count; i++) {
    schedule.add(
      ScheduleLesson(
        id: 'lesson-$i',
        weekday: weekday,
        startMinutes: 480 + i * 100,
        endMinutes: 500 + i * 100,
        subject: 'Пара расписания $i',
      ),
    );
  }
  return schedule;
}

void main() {
  group('temporaryPairCount', () {
    test('по умолчанию 4 пары', () {
      expect(ScheduleController.inMemory().temporaryPairCount, 4);
    });

    test('значение зажимается в 1..12', () {
      final schedule = ScheduleController.inMemory();
      schedule.temporaryPairCount = 0;
      expect(schedule.temporaryPairCount, 1);
      schedule.temporaryPairCount = 100;
      expect(schedule.temporaryPairCount, 12);
    });
  });

  group('effectiveLessonsFor', () {
    const monday = 1;

    test('расписание пустое — временный порядок пар', () {
      final schedule = ScheduleController.inMemory();
      final lessons = schedule.effectiveLessonsFor(monday);
      expect(lessons, hasLength(4));
      expect([for (final lesson in lessons) lesson.id], [
        'temp-pair-1',
        'temp-pair-2',
        'temp-pair-3',
        'temp-pair-4',
      ]);
      // Названия совпадают с журнальными: отметки из таблицы попадают
      // в те же пары.
      expect(lessons.first.subject, 'Пара 1');
    });

    test('число временных пар берётся из temporaryPairCount', () {
      final schedule = ScheduleController.inMemory();
      schedule.temporaryPairCount = 3;
      expect(
        [for (final lesson in schedule.effectiveLessonsFor(monday)) lesson.id],
        hasLength(3),
      );
    });

    test('расписание заполнено — временных пар нет вовсе', () {
      // Даже день без пар ничего не подставляет: частичное расписание
      // ведёт себя по-старому, «весь день» вместо порядка пар.
      final schedule = scheduleWith(weekday: monday, count: 2);
      expect(schedule.effectiveLessonsFor(monday), hasLength(2));
      expect(schedule.effectiveLessonsFor(3), isEmpty);
    });
  });
}
