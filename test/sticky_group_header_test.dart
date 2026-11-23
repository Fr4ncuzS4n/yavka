// Заголовок «Группа …» и счётчик отметок не уезжают при прокрутке списка.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:yavka/data/attendance_controller.dart';
import 'package:yavka/main.dart';
import 'package:yavka/models/attendance_session.dart';
import 'package:yavka/models/student.dart';
import 'package:yavka/screens/attendance_screen.dart';
import 'support/demo_roster.dart';

void main() {
  testWidgets('заголовок группы остаётся на экране при прокрутке списка', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(412, 600);
    addTearDown(tester.view.reset);

    final attendance = AttendanceController(
      session: AttendanceSession(
        groupName: demoGroupName,
        students: [
          for (var i = 1; i <= 40; i++)
            Student(id: '$i', fullName: 'Студент $i'),
        ],
        date: DateTime(2026, 11, 9),
      ),
    );
    await tester.pumpWidget(AppRoot(attendance: attendance));
    await tester.pumpAndSettle();

    final header = find.text('Группа $demoGroupName');
    expect(header, findsOneWidget);

    // Прокручиваем список к концу.
    for (var scroll = 0; scroll < 8; scroll++) {
      await tester.drag(find.byKey(kStudentListKey), const Offset(0, -400));
      await tester.pumpAndSettle();
    }

    // Первые строки ушли из вида, а заголовок остался на экране.
    expect(find.byKey(const ValueKey('student-1')), findsNothing);
    expect(header, findsOneWidget);
    final rect = tester.getRect(header);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(600));
  });
}
