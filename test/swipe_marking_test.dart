// Тесты свайпов по строке студента на Android:
// влево — «Пришёл», вправо — «Опоздал». На других платформах свайпов нет.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yavka/data/attendance_controller.dart';
import 'package:yavka/main.dart';
import 'package:yavka/models/attendance_session.dart';
import 'package:yavka/models/attendance_status.dart';
import 'support/demo_roster.dart';

final kMonday = DateTime(2026, 11, 9);

Future<AttendanceController> _pumpApp(
  WidgetTester tester, {
  Size size = const Size(412, 1200),
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final attendance = AttendanceController(
    session: AttendanceSession(
      groupName: demoGroupName,
      students: demoStudents.take(3).toList(),
      date: kMonday,
    ),
  );
  await tester.pumpWidget(AppRoot(attendance: attendance));
  await tester.pumpAndSettle();
  return attendance;
}

void main() {
  testWidgets('свайп влево — «Пришёл» смахнутому студенту', (tester) async {
    final attendance = await _pumpApp(tester);

    // Смахиваем вторую строку, хотя выбрана первая: отметка должна
    // относиться именно к Марии.
    await tester.drag(
      find.byKey(const ValueKey('student-2')),
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();

    expect(attendance.entryFor('2')?.status, AttendanceStatus.came);
    expect(attendance.entryFor('1'), isNull);
    expect(find.text('Отметить: Мария Соколова'), findsOneWidget);
  });

  testWidgets('свайп вправо — «Опоздал» смахнутому студенту', (tester) async {
    final attendance = await _pumpApp(tester);

    await tester.drag(
      find.byKey(const ValueKey('student-2')),
      const Offset(120, 0),
    );
    await tester.pumpAndSettle();

    final entry = attendance.entryFor('2');
    expect(entry?.status, AttendanceStatus.late);
    // У опоздания есть время — оно уходит в журнал.
    expect(entry?.markedAt.hour, isNotNull);
    expect(attendance.entryFor('1'), isNull);
  });

  testWidgets('короткий сдвиг не ставит отметку, тап по-прежнему выбирает', (
    tester,
  ) async {
    final attendance = await _pumpApp(tester);

    await tester.drag(
      find.byKey(const ValueKey('student-2')),
      const Offset(-20, 0),
    );
    await tester.pumpAndSettle();
    expect(attendance.entryFor('2'), isNull);

    await tester.tap(find.byKey(const ValueKey('student-2')));
    await tester.pumpAndSettle();
    expect(find.text('Отметить: Мария Соколова'), findsOneWidget);
  });

  testWidgets('на десктопе свайпы не отметили студента', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final attendance = await _pumpApp(tester, size: const Size(1280, 900));

    await tester.drag(
      find.byKey(const ValueKey('student-2')),
      const Offset(-120, 0),
    );
    await tester.pumpAndSettle();

    expect(attendance.entryFor('2'), isNull);
  });
}
