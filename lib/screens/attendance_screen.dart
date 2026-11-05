import 'package:flutter/material.dart';

import '../models/attendance_status.dart';

/// Экран быстрой отметки посещаемости.
///
/// Содержит 4 кнопки: «Пришёл», «Непришёл», «Опоздал», «По уважительной».
/// Скелет: разметка и базовое управление состоянием уже на месте,
/// дальше — списки студентов, логика и интеграции.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  AttendanceStatus? _status;
  bool _absentArmed = false;

  void _mark(AttendanceStatus status) {
    setState(() {
      _status = status;
      _absentArmed = false;
    });
  }

  Future<void> _markAbsent() async {
    if (!mounted) return;

    // Первое нажатие — запоминаем намерение, второе — подтверждаем.
    if (!_absentArmed) {
      setState(() => _absentArmed = true);
      return;
    }

    // Подтверждение отсутствия: выбираем время (по умолчанию — текущее).
    final now = TimeOfDay(hour: DateTime.now().hour, minute: DateTime.now().minute);
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: now,
    );

    if (!mounted) return;

    setState(() {
      _status = AttendanceStatus.absent;
      _absentArmed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Явка')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Text(
                    'Отметка: ${_status!.label}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ElevatedButton(
                onPressed: () => _mark(AttendanceStatus.came),
                child: const Text('Пришёл'),
              ),
              const SizedBox(height: 12.0),
              ElevatedButton(
                onPressed: () => _markAbsent(),
                child: Text(_absentArmed ? 'Подтвердить отсутствие' : 'Непришёл'),
              ),
              const SizedBox(height: 12.0),
              ElevatedButton(
                onPressed: () => _mark(AttendanceStatus.late),
                child: const Text('Опоздал'),
              ),
              const SizedBox(height: 12.0),
              ElevatedButton(
                onPressed: () => _mark(AttendanceStatus.excused),
                child: const Text('По уважительной'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
