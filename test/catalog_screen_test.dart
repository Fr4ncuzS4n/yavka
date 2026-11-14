// Тесты экрана базы и селектов в диалоге пары вкладки «Расписание».

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yavka/data/catalog_controller.dart';
import 'package:yavka/data/schedule_controller.dart';
import 'package:yavka/models/schedule_lesson.dart';
import 'package:yavka/screens/catalog_screen.dart';
import 'package:yavka/screens/schedule_screen.dart';

/// База с одним предметом, преподавателем и кабинетом.
CatalogController seeded() {
  final catalog = CatalogController.inMemory();
  final teacher = catalog.addTeacher('Иванов И.И.');
  final room = catalog.addRoom('201');
  catalog.addSubject('Математика', teacherId: teacher.id, roomId: room.id);
  return catalog;
}

Future<void> _pumpCatalog(WidgetTester tester, CatalogController catalog) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(412, 1300);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(home: CatalogScreen(catalog: catalog)),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpSchedule(
  WidgetTester tester, {
  required CatalogController catalog,
  List<ScheduleLesson> lessons = const [],
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(412, 1300);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: ScheduleScreen(
        schedule: ScheduleController(lessons: lessons),
        catalog: catalog,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Экран базы: добавление преподавателя', (tester) async {
    final catalog = CatalogController.inMemory();
    await _pumpCatalog(tester, catalog);

    await tester.tap(find.byTooltip('Добавить преподавателя'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Мария Петрова');
    // Кнопка «Сохранить» включается после ввода — нужен кадр.
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    expect(find.text('Мария Петрова'), findsOneWidget);
    expect(catalog.teachers.single.name, 'Мария Петрова');
  });

  testWidgets('Экран базы: предмет с селектами преподавателя и кабинета', (
    tester,
  ) async {
    final catalog = seeded();
    await _pumpCatalog(tester, catalog);

    await tester.tap(find.byTooltip('Добавить предмет'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Физика');

    // Селект преподавателя: первый из двух String?-селектов.
    await tester.tap(find.byType(DropdownButtonFormField<String?>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Иванов И.И.').last);
    await tester.pumpAndSettle();

    // Селект кабинета: второй.
    await tester.tap(find.byType(DropdownButtonFormField<String?>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('201').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    // Предмет в списке с подписью «преподаватель · кабинет».
    expect(find.text('Физика'), findsOneWidget);
    // У «Математика» и «Физика» одинаковые преподаватель и кабинет —
    // подпись у обеих плиток.
    expect(find.text('Иванов И.И. · 201'), findsNWidgets(2));
    final subject = catalog.subjectByName('Физика')!;
    expect(catalog.teacherById(subject.teacherId)?.name, 'Иванов И.И.');
    expect(catalog.roomById(subject.roomId)?.name, '201');
  });

  testWidgets('Экран базы: удаление преподавателя снимает ссылку у предмета', (
    tester,
  ) async {
    final catalog = seeded();
    await _pumpCatalog(tester, catalog);
    expect(find.text('Иванов И.И. · 201'), findsOneWidget);

    // Удалить преподавателя (первый раздел) и подтвердить.
    await tester.tap(find.byTooltip('Удалить').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить'));
    await tester.pumpAndSettle();

    // Предмет остался, но без преподавателя: ссылка снята, кабинет на месте.
    expect(find.text('Математика'), findsOneWidget);
    final math = catalog.subjectByName('Математика')!;
    expect(math.teacherId, isNull);
    expect(catalog.roomById(math.roomId)?.name, '201');
  });

  testWidgets('Диалог пары: предмет из базы подставляет преподавателя и кабинет', (
    tester,
  ) async {
    final catalog = seeded();
    await _pumpSchedule(tester, catalog: catalog);

    await tester.tap(find.byTooltip('Добавить пару'));
    await tester.pumpAndSettle();

    // Открыть селект предмета и выбрать «Математика».
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Математика').last);
    await tester.pumpAndSettle();

    // Преподаватель и кабинет подставились из предмета.
    expect(find.text('Иванов И.И.'), findsOneWidget);
    expect(find.text('201'), findsOneWidget);
  });

  testWidgets('Диалог пары: старая пара без записи в базе сохраняет строки', (
    tester,
  ) async {
    final catalog = seeded();
    const oldLesson = ScheduleLesson(
      id: 'lesson-old',
      weekday: 1,
      startMinutes: 9 * 60,
      endMinutes: 10 * 60 + 30,
      subject: 'Химия',
      teacher: 'Петров П.П.',
      room: '12',
    );
    await _pumpSchedule(
      tester,
      catalog: catalog,
      lessons: const [oldLesson],
    );

    // Сегодня суббота — пара живёт на вкладке понедельника.
    await tester.tap(find.text('пн'));
    await tester.pumpAndSettle();

    // Меню карточки пары → «Изменить».
    await tester.tap(find.byTooltip('Действия'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Изменить'));
    await tester.pumpAndSettle();

    // Названия не из базы остаются в селектах (внутри диалога; карточка
    // пары за ним показывает те же строки).
    final dialog = find.byType(AlertDialog);
    expect(
      find.descendant(of: dialog, matching: find.text('Химия')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('Петров П.П.')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: dialog, matching: find.text('12')),
      findsOneWidget,
    );

    // Выбор предмета из базы — подставляется преподаватель из базы.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Математика').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();

    final saved = tester.widget<ScheduleScreen>(
      find.byType(ScheduleScreen),
    );
    final controller = saved.schedule;
    final lesson = controller.lessons.single;
    expect(lesson.subject, 'Математика');
    expect(lesson.teacher, 'Иванов И.И.');
    expect(lesson.room, '201');
  });

  testWidgets('Диалог пары: кнопка «+» добавляет преподавателя в базу', (
    tester,
  ) async {
    final catalog = seeded();
    await _pumpSchedule(tester, catalog: catalog);

    await tester.tap(find.byTooltip('Добавить пару'));
    await tester.pumpAndSettle();

    // Три кнопки «+»: предмет, преподаватель, кабинет. Нужна вторая.
    await tester.tap(find.byIcon(Icons.add_circle_outline_rounded).at(1));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Сидорова А.А.');
    // Кнопка «Добавить» включается после ввода — нужен кадр.
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();

    // Преподаватель добавился в базу и выбран в селекте.
    expect(catalog.teacherByName('Сидорова А.А.'), isNotNull);
    expect(find.text('Сидорова А.А.'), findsOneWidget);
  });

  testWidgets('Вставленный документ пополняет базу', (tester) async {
    final catalog = CatalogController.inMemory();
    await _pumpSchedule(tester, catalog: catalog);

    await tester.tap(find.byTooltip('Вставить документ с расписанием'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField),
      '09:00–10:30 Химия, каб. 5, Сидорова А.А.',
    );
    // Кнопка «Вставить» включается после ввода — нужен кадр.
    await tester.pumpAndSettle();
    await tester.tap(find.text('Вставить'));
    await tester.pumpAndSettle();

    final subject = catalog.subjectByName('Химия');
    expect(subject, isNotNull);
    expect(
      catalog.teacherById(subject!.teacherId)?.name,
      'Сидорова А.А.',
    );
    expect(catalog.roomById(subject.roomId)?.name, '5');
  });
}
