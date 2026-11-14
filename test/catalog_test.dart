// Тесты локальной базы: преподаватели, кабинеты, предметы, импорт/экспорт.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yavka/data/catalog_controller.dart';
import 'package:yavka/data/catalog_store.dart';
import 'package:yavka/models/schedule_lesson.dart';

ScheduleLesson lesson(
  String subject, {
  String? teacher,
  String? room,
}) => ScheduleLesson(
  id: 'lesson-$subject',
  weekday: 1,
  startMinutes: 9 * 60,
  subject: subject,
  teacher: teacher,
  room: room,
);

void main() {
  group('записи базы', () {
    test('добавление по алфавиту, повтор имени без дубликата', () {
      final catalog = CatalogController.inMemory();
      final first = catalog.addTeacher('Мария Петрова');
      catalog.addTeacher('Анна Смирнова');

      // Тот же человек с лишними пробелами и в другом регистре —
      // не новый преподаватель.
      expect(catalog.addTeacher('  мария   петрова ').id, first.id);
      expect(catalog.teachers.map((item) => item.name), [
        'Анна Смирнова',
        'Мария Петрова',
      ]);
      expect(catalog.teachers.length, 2);
    });

    test('кабинеты и предметы добавляются и сортируются', () {
      final catalog = CatalogController.inMemory();
      final room = catalog.addRoom('312');
      catalog.addRoom('201');
      final teacher = catalog.addTeacher('Иванов И.И.');
      catalog.addSubject('Математика', teacherId: teacher.id, roomId: room.id);

      expect(catalog.rooms.map((item) => item.name), ['201', '312']);
      final subject = catalog.subjects.single;
      expect(subject.name, 'Математика');
      expect(subject.teacherId, teacher.id);
      expect(subject.roomId, room.id);
    });

    test('переименование занятое имя не даёт', () {
      final catalog = CatalogController.inMemory();
      final first = catalog.addTeacher('Иванов И.И.');
      final second = catalog.addTeacher('Петров П.П.');

      expect(catalog.updateTeacher(second.id, 'Иванов И.И.'), isFalse);
      expect(catalog.updateTeacher(second.id, 'Сидоров С.С.'), isTrue);
      expect(catalog.teacherById(first.id)?.name, 'Иванов И.И.');
      expect(catalog.teacherById(second.id)?.name, 'Сидоров С.С.');

      expect(catalog.updateRoom('нет-такого', '201'), isFalse);
      expect(catalog.updateSubject('нет-такого', name: 'Физика', teacherId: null, roomId: null), isFalse);
    });

    test('удаление преподавателя снимает ссылку у предметов', () {
      final catalog = CatalogController.inMemory();
      final teacher = catalog.addTeacher('Иванов И.И.');
      catalog.addSubject('Математика', teacherId: teacher.id);
      catalog.addSubject('Физика');

      final cleared = catalog.removeTeacher(teacher.id);

      expect(cleared, 1);
      expect(catalog.teachers, isEmpty);
      expect(catalog.subjects.first.teacherId, isNull);
      expect(catalog.subjectByName('Физика'), isNotNull);
    });

    test('удаление кабинета снимает ссылку у предметов', () {
      final catalog = CatalogController.inMemory();
      final room = catalog.addRoom('201');
      catalog.addSubject('Математика', roomId: room.id);

      expect(catalog.removeRoom(room.id), 1);
      expect(catalog.subjects.single.roomId, isNull);
      expect(catalog.subjects.single.name, 'Математика');
    });

    test('удаление предмета не трогает преподавателя и кабинет', () {
      final catalog = CatalogController.inMemory();
      final teacher = catalog.addTeacher('Иванов И.И.');
      final room = catalog.addRoom('201');
      final subject = catalog.addSubject(
        'Математика',
        teacherId: teacher.id,
        roomId: room.id,
      );

      expect(catalog.removeSubject(subject.id), isTrue);
      expect(catalog.subjects, isEmpty);
      expect(catalog.teacherById(teacher.id), isNotNull);
      expect(catalog.roomById(room.id), isNotNull);
    });
  });

  group('хранилище', () {
    test('база сохраняется и загружается', () async {
      final store = MemoryCatalogStore();
      final catalog = CatalogController(store: store);
      await catalog.load();
      final teacher = catalog.addTeacher('Иванов И.И.');
      final room = catalog.addRoom('201');
      catalog.addSubject('Математика', teacherId: teacher.id, roomId: room.id);

      final again = CatalogController(store: store);
      await again.load();
      expect(again.subjects.single.name, 'Математика');
      expect(again.teacherById(again.subjects.single.teacherId)?.name,
          'Иванов И.И.');
      expect(again.roomById(again.subjects.single.roomId)?.name, '201');
    });

    test('SharedPreferences: вся база под одним ключом', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final store = SharedPreferencesCatalogStore(preferences);
      final catalog = CatalogController(store: store);
      await catalog.load();
      final teacher = catalog.addTeacher('Иванов И.И.');
      final room = catalog.addRoom('201');
      catalog.addSubject('Математика', teacherId: teacher.id, roomId: room.id);

      final raw = preferences.getString('yavka.catalog.v1');
      expect(raw, isNotNull);
      final saved = jsonDecode(raw!) as Map<String, Object?>;
      expect(saved['kind'], 'yavka.catalog');
      expect((saved['teachers'] as List).length, 1);
      expect((saved['rooms'] as List).length, 1);
      expect((saved['subjects'] as List).length, 1);

      // Новый контроллер на тех же настройках видит сохранённую базу.
      final again = CatalogController(store: store);
      await again.load();
      expect(again.subjects.single.teacherId, teacher.id);
      expect(again.roomById(again.subjects.single.roomId)?.name, '201');
    });

    test('повреждённое хранилище не роняет загрузку', () async {
      SharedPreferences.setMockInitialValues({'yavka.catalog.v1': '{['});
      final preferences = await SharedPreferences.getInstance();
      final catalog = CatalogController(
        store: SharedPreferencesCatalogStore(preferences),
      );

      await catalog.load();

      expect(catalog.teachers, isEmpty);
      expect(catalog.subjects, isEmpty);
    });
  });

  group('экспорт и импорт', () {
    test('экспорт содержит метку формата и все списки', () {
      final catalog = CatalogController.inMemory();
      final teacher = catalog.addTeacher('Иванов И.И.');
      final room = catalog.addRoom('201');
      catalog.addSubject('Математика', teacherId: teacher.id, roomId: room.id);

      final json = catalog.exportJson();
      final data = jsonDecode(json) as Map<String, Object?>;
      expect(data['kind'], 'yavka.catalog');
      expect(data['version'], 1);
      expect((data['teachers'] as List).single, {
        'id': teacher.id,
        'name': 'Иванов И.И.',
      });
      expect((data['rooms'] as List).single, {
        'id': room.id,
        'name': '201',
      });
      expect((data['subjects'] as List).single, {
        'id': catalog.subjects.single.id,
        'name': 'Математика',
        'teacherId': teacher.id,
        'roomId': room.id,
      });
    });

    test('импорт совмещает по именам и перекидывает ссылки', () {
      final catalog = CatalogController.inMemory();
      catalog.addTeacher('Иванов И.И.');
      catalog.addSubject('Математика');

      // Файл с чужими идентификаторами: преподаватель «Иванов И.И.» уже
      // есть, «Математика» уже есть, остальное добавится.
      final report = catalog.importJson(
        jsonEncode({
          'kind': 'yavka.catalog',
          'version': 1,
          'teachers': [
            {'id': 'x1', 'name': 'Иванов И.И.'},
            {'id': 'x2', 'name': 'Петров П.П.'},
          ],
          'rooms': [
            {'id': 'y1', 'name': '312'},
          ],
          'subjects': [
            {'id': 'z1', 'name': 'Математика', 'teacherId': 'x1'},
            {
              'id': 'z2',
              'name': 'Физика',
              'teacherId': 'x2',
              'roomId': 'y1',
            },
          ],
        }),
      );

      expect(report.teachersAdded, 1);
      expect(report.roomsAdded, 1);
      expect(report.subjectsAdded, 1);
      expect(report.alreadyInBase, 2);
      expect(report.message, contains('Добавлено'));

      // Дубликатов нет, ссылки предметов ведут на местных записей.
      expect(catalog.teachers.length, 2);
      expect(catalog.rooms.single.name, '312');
      final physics = catalog.subjectByName('Физика')!;
      expect(catalog.teacherById(physics.teacherId)?.name, 'Петров П.П.');
      expect(catalog.roomById(physics.roomId)?.name, '312');
      final math = catalog.subjectByName('Математика')!;
      expect(math.teacherId, isNull); // уже был в базе — не тронут
    });

    test('импорт дважды не создаёт дубликатов', () {
      final catalog = CatalogController.inMemory();
      final raw = jsonEncode({
        'kind': 'yavka.catalog',
        'version': 1,
        'teachers': [
          {'id': 'x1', 'name': 'Иванов И.И.'},
        ],
        'rooms': [],
        'subjects': [
          {'id': 'z1', 'name': 'Математика'},
        ],
      });

      final first = catalog.importJson(raw);
      expect(first.hasChanges, isTrue);

      final second = catalog.importJson(raw);
      expect(second.hasChanges, isFalse);
      expect(second.alreadyInBase, 2);
      expect(catalog.teachers.length, 1);
      expect(catalog.subjects.length, 1);
    });

    test('круг: экспорт → пустая база → импорт — то же самое', () {
      final source = CatalogController.inMemory();
      final teacher = source.addTeacher('Мария Петрова');
      final room = source.addRoom('312');
      source.addSubject('Химия', teacherId: teacher.id, roomId: room.id);
      final raw = source.exportJson();

      final target = CatalogController.inMemory();
      target.importJson(raw);

      expect(target.teachers.single.name, 'Мария Петрова');
      expect(target.rooms.single.name, '312');
      final subject = target.subjects.single;
      expect(subject.name, 'Химия');
      expect(target.teacherById(subject.teacherId)?.name, 'Мария Петрова');
      expect(target.roomById(subject.roomId)?.name, '312');
    });

    test('чужой файл объясняет, что не так', () {
      final catalog = CatalogController.inMemory();
      String messageOf(String raw) {
        try {
          catalog.importJson(raw);
        } on FormatException catch (error) {
          return error.message;
        }
        fail('Ожидали FormatException для файла: $raw');
      }

      expect(messageOf('{ поцарапанный'), contains('не похож на JSON'));
      expect(messageOf('[]'), contains('JSON-объектом'));
      expect(
        messageOf(jsonEncode({'kind': 'other', 'teachers': []})),
        contains('не файл базы'),
      );
      expect(
        messageOf(jsonEncode({'kind': 'yavka.catalog', 'version': 2})),
        contains('более новой версии'),
      );
    });
  });

  group('вставленный документ пополняет базу', () {
    test('новые предметы, преподаватели и кабинеты попадают в базу', () {
      final catalog = CatalogController.inMemory();

      final added = catalog.syncFromLessons([
        lesson(
          'Математика',
          teacher: 'Иванов И.И.',
          room: '201',
        ),
        lesson('Физика', room: '312'),
      ]);

      expect(added.teachers, 1);
      expect(added.rooms, 2);
      expect(added.subjects, 2);

      final math = catalog.subjectByName('Математика')!;
      expect(catalog.teacherById(math.teacherId)?.name, 'Иванов И.И.');
      expect(catalog.roomById(math.roomId)?.name, '201');
      final physics = catalog.subjectByName('Физика')!;
      expect(physics.teacherId, isNull);
      expect(catalog.roomById(physics.roomId)?.name, '312');
    });

    test('знакомому предмету проставляется нехватающая ссылка', () {
      final catalog = CatalogController.inMemory();
      catalog.addSubject('Математика');

      catalog.syncFromLessons([lesson('Математика', room: '201')]);

      final math = catalog.subjectByName('Математика')!;
      expect(math.roomId, isNotNull);
      expect(catalog.roomById(math.roomId)?.name, '201');
      expect(math.teacherId, isNull);
    });

    test('повторная вставка ничего не меняет', () {
      final catalog = CatalogController.inMemory();
      final lessons = [
        lesson('Математика', teacher: 'Иванов И.И.', room: '201'),
      ];

      catalog.syncFromLessons(lessons);
      final before = catalog.snapshot;

      final added = catalog.syncFromLessons(lessons);
      expect(added.teachers, 0);
      expect(added.rooms, 0);
      expect(added.subjects, 0);
      expect(catalog.snapshot, isNotNull);
      // Состав базы не изменился.
      expect(catalog.teachers.length, before.teachers.length);
      expect(catalog.subjects.length, before.subjects.length);
    });
  });
}
