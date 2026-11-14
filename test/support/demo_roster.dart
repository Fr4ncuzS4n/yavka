import 'package:yavka/models/student.dart';

/// Демонстрационная группа — только для тестов интерфейса.
///
/// В само приложение примерные студенты больше не заливаются: список
/// группы берётся из журнала Google Таблицы.
const String demoGroupName = 'БИТ-24-03';

const List<Student> demoStudents = [
  Student(id: '1', fullName: 'Алексей Морозов'),
  Student(id: '2', fullName: 'Мария Соколова'),
  Student(id: '3', fullName: 'Дмитрий Волков'),
  Student(id: '4', fullName: 'Анна Кузнецова'),
  Student(id: '5', fullName: 'Никита Попов'),
  Student(id: '6', fullName: 'София Лебедева'),
  Student(id: '7', fullName: 'Артём Новиков'),
  Student(id: '8', fullName: 'Екатерина Фёдорова'),
  Student(id: '9', fullName: 'Максим Егоров'),
  Student(id: '10', fullName: 'Полина Павлова'),
];
