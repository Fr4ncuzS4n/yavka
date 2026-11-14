// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/attendance_controller.dart';
import '../../data/cloud_settings.dart';
import '../../data/schedule_controller.dart';
import '../../models/attendance_session.dart';
import '../../models/student.dart';
import 'cloud_exceptions.dart';
import 'google_auth_service.dart';
import 'journal_mapping.dart';
import 'journal_sync_service.dart';
import 'oauth/oauth_client_json.dart';
import 'oauth/oauth_models.dart';
import 'sheets_api.dart';

/// Управляет подключением к Google Таблице и синхронизацией.
///
/// Приложение подстраивается под существующий журнал и ничего в нём не
/// меняет: только отмечает ячейку пары цветом (и временем при опоздании).
/// Месяц подбирается из названия таблицы «МЕСЯЦ : ГОД», раскладка
/// журнала — из настройки, которую пользователь заполняет один раз.
class CloudSyncController extends ChangeNotifier {
  CloudSyncController({
    required this.attendance,
    required this.auth,
    required SheetsApi sheetsApi,
    required CloudSettingsStore settingsStore,
    required bool isWeb,
    ScheduleController? schedule,
  }) : _api = sheetsApi,
       _settingsStore = settingsStore,
       _isWeb = isWeb,
       _schedule = schedule,
       _sync = JournalSyncService(sheetsApi) {
    attendance.addListener(_onAttendanceChanged);
    auth.addListener(_onAuthChanged);
  }

  final AttendanceController attendance;
  final GoogleAuthService auth;
  final SheetsApi _api;
  final CloudSettingsStore _settingsStore;
  final JournalSyncService _sync;
  final ScheduleController? _schedule;
  final bool _isWeb;

  CloudSettings _settings = const CloudSettings();
  DateTime? _journalMonth;
  bool _initialized = false;
  bool _busy = false;
  bool _pending = false;
  bool _applyingRemote = false;
  String? _error;
  DateTime? _lastSyncAt;
  JournalSyncResult? _lastResult;
  Timer? _debounce;

  CloudSettings get settings => _settings;

  bool get isWeb => _isWeb;

  bool get isConfigured => _settings.hasSpreadsheet;

  bool get isSignedIn => auth.isSignedIn;

  bool get isBusy => _busy;

  bool get hasPendingChanges => _pending;

  String? get error => _error;

  DateTime? get lastSyncAt => _lastSyncAt;

  JournalSyncResult? get lastResult => _lastResult;

  String? get spreadsheetId => _settings.spreadsheetId;

  String get spreadsheetUrl => _settings.spreadsheetUrl;

  bool get autoSync => _settings.autoSync;

  /// Настройка журнала, если пользователь её уже заполнил.
  JournalMapping? get journalMapping => _settings.journalMapping;

  /// Нужна ли настройка журнала: таблица подключена, а раскладка нет.
  bool get needsJournalSetup => isConfigured && journalMapping == null;

  /// Месяц журнала, подобранный из названия таблицы. Известен после
  /// первой успешной синхронизации или настройки.
  DateTime? get journalMonth => _journalMonth;

  /// Расписание приложения: по нему считаются пары в днях.
  ScheduleController? get schedule => _schedule;

  bool _hasAutoSyncInvolved() =>
      isConfigured &&
      isSignedIn &&
      autoSync &&
      journalMapping != null;

  /// Сохраняет имя, которым подписываются уведомления о отметках.
  Future<void> setDisplayName(String value) async {
    final name = value.trim();
    if (name == _settings.displayName) return;
    _settings = _settings.copyWith(displayName: name);
    notifyListeners();
    try {
      await _settingsStore.save(_settings);
    } catch (error) {
      _error = _message(error);
      notifyListeners();
    }
  }

  /// Загружает настройки, восстанавливает вход и (если включена
  /// автосинхронизация) подтягивает отметки из таблицы.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      _settings = await _settingsStore.load();
    } catch (_) {
      // Настройки по умолчанию — приложение продолжит работать локально.
    }
    auth.configure(_configFromSettings());

    if (!_hasAutoSyncInvolved()) {
      notifyListeners();
      return;
    }

    _busy = true;
    notifyListeners();
    try {
      await auth.restore();
      if (_hasAutoSyncInvolved()) {
        await _pull();
        await _push();
      }
    } catch (error) {
      _error = _message(error);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> signIn() async {
    await _run(() async {
      auth.configure(_configFromSettings());
      await auth.signIn();
      if (_hasAutoSyncInvolved()) {
        await _pull();
        await _push();
      }
    });
  }

  Future<void> signOut() async {
    await _run(auth.signOut);
  }

  /// Подключает существующую таблицу по ссылке или ID.
  ///
  /// Подходит, если пользователь — редактор, а владелец таблицы другой.
  /// Приложение не создаёт таблицы: существующий журнал не меняется.
  Future<void> connectSpreadsheet(String linkOrId) async {
    await _run(() async {
      _requireSignedIn();
      final id = parseSpreadsheetId(linkOrId);
      if (id == null) {
        throw const CloudSyncException(
          'Не удалось распознать ссылку. Вставьте ссылку на Google Таблицу '
          'вида https://docs.google.com/spreadsheets/d/…/edit или её ID.',
        );
      }

      // Проверяем доступ до сохранения настроек.
      await _api.getSpreadsheet(id);

      _settings = _settings.copyWith(spreadsheetId: id);
      await _saveSettings();
      _pending = false;
      _journalMonth = null;
      notifyListeners();

      if (_hasAutoSyncInvolved()) {
        await _pull();
        await _push();
      }
    });
  }

  Future<void> disconnectSpreadsheet() async {
    await _run(() async {
      _settings = _settings.copyWith(clearSpreadsheet: true);
      await _saveSettings();
      _pending = false;
      _lastSyncAt = null;
      _lastResult = null;
      _journalMonth = null;
      notifyListeners();
    });
  }

  Future<void> setAutoSync(bool value) async {
    _settings = _settings.copyWith(autoSync: value);
    notifyListeners();
    try {
      await _settingsStore.save(_settings);
    } catch (error) {
      _error = _message(error);
      notifyListeners();
    }
  }

  /// Листы подключённой таблицы — для выбора листа журнала в настройке.
  Future<List<SheetTab>> fetchTabs() async {
    _requireSignedIn();
    final id = _settings.spreadsheetId;
    if (id == null) {
      throw const CloudSyncException('Сначала подключите таблицу.');
    }
    final meta = await _api.getSpreadsheet(id);
    return meta.tabs;
  }

  /// Пробная настройка журнала: снимает раскладку и сверяет с
  /// расписанием, ничего не сохраняя.
  Future<JournalSnapshot> previewJournal({
    required String tabTitle,
    required int dayRow,
    required int fioColumn,
    required int firstStudentRow,
    int? pairRow,
    int? lastStudentRow,
  }) async {
    _requireSignedIn();
    final id = _settings.spreadsheetId;
    if (id == null) {
      throw const CloudSyncException('Сначала подключите таблицу.');
    }
    final mapping = JournalMapping(
      tabTitle: tabTitle,
      dayRow: dayRow,
      fioColumn: fioColumn,
      firstStudentRow: firstStudentRow,
      pairRow: pairRow,
      lastStudentRow: lastStudentRow,
    );
    return _sync.snapshot(
      spreadsheetId: id,
      mapping: mapping,
      schedule: _schedule,
    );
  }

  /// Сохраняет настройку журнала и сразу подтягивает данные.
  Future<void> saveJournalMapping(JournalMapping mapping) async {
    await _run(() async {
      _settings = _settings.copyWith(
        journalTabTitle: mapping.tabTitle,
        journalDayRow: mapping.dayRow,
        journalFioColumn: mapping.fioColumn,
        journalFirstStudentRow: mapping.firstStudentRow,
        journalPairRow: mapping.pairRow,
        journalLastStudentRow: mapping.lastStudentRow,
      );
      await _saveSettings();
      notifyListeners();

      if (_hasAutoSyncInvolved()) {
        await _pull();
        await _push();
      }
    });
  }

  /// Сбрасывает настройку журнала (например, при смене раскладки).
  Future<void> resetJournalMapping() async {
    await _run(() async {
      _settings = _settings.copyWith(clearJournal: true);
      await _saveSettings();
      _journalMonth = null;
      _lastSyncAt = null;
      _lastResult = null;
      notifyListeners();
    });
  }

  /// Сохраняет OAuth Client ID/Secret, введённые в настройках.
  Future<void> saveOAuthConfig({
    String? clientId,
    String? clientSecret,
    String? webClientId,
  }) async {
    _settings = _settings.copyWith(
      clientId: clientId,
      clientSecret: clientSecret,
      webClientId: webClientId,
      clearClientSecret: clientSecret != null && clientSecret.trim().isEmpty,
    );
    auth.configure(_configFromSettings());
    notifyListeners();
    try {
      await _settingsStore.save(_settings);
    } catch (error) {
      _error = _message(error);
      notifyListeners();
    }
  }

  /// Регистрирует OAuth-клиент из JSON-файла, скачанного из
  /// Google Cloud Console.
  ///
  /// Заполняются только те поля, которые есть в файле: значения,
  /// введённые раньше, остаются.
  Future<void> applyOAuthClientFile(OAuthClientFile client) =>
      saveOAuthConfig(
        clientId: client.clientId,
        clientSecret: client.clientSecret,
        webClientId: client.webClientId,
      );

  Future<void> syncNow() async {
    await _run(() async {
      _requireConfigured();
      _requireSignedIn();
      _requireJournalSetup();
      await _pull();
      await _push();
    });
  }

  Future<void> pullNow() async {
    await _run(() async {
      _requireConfigured();
      _requireSignedIn();
      _requireJournalSetup();
      await _pull();
    });
  }

  GoogleOAuthConfig _configFromSettings() =>
      GoogleOAuthConfig.fromSettings(_settings, isWeb: _isWeb);

  Future<void> _push() async {
    final spreadsheetId = _settings.spreadsheetId;
    final mapping = _settings.journalMapping;
    if (spreadsheetId == null || mapping == null) return;

    final snapshot = await _sync.snapshot(
      spreadsheetId: spreadsheetId,
      mapping: mapping,
      schedule: _schedule,
    );
    _requireMonth(snapshot);
    _requireConsistency(snapshot);
    final month = snapshot.month!;
    _journalMonth = month;

    // В журнал уходят все отмеченные дни месяца, а не только сегодняшний:
    // задним числом тоже можно отмечать.
    var sessions = attendance.sessionsInMonth(month);
    if (sessions.isEmpty &&
        _isSameMonth(attendance.session.date, month)) {
      sessions = [attendance.session];
    }

    final result = await _sync.push(
      spreadsheetId: spreadsheetId,
      mapping: mapping,
      sessions: sessions,
      schedule: _schedule,
    );
    _lastResult = result;
    _lastSyncAt = DateTime.now();
    _pending = false;
    _error = null;
    notifyListeners();
  }

  Future<void> _pull() async {
    final spreadsheetId = _settings.spreadsheetId;
    final mapping = _settings.journalMapping;
    if (spreadsheetId == null || mapping == null) return;

    final snapshot = await _sync.snapshot(
      spreadsheetId: spreadsheetId,
      mapping: mapping,
      schedule: _schedule,
    );
    _requireMonth(snapshot);
    _requireConsistency(snapshot);
    final month = snapshot.month!;
    _journalMonth = month;

    final roster = await _sync.read(
      spreadsheetId: spreadsheetId,
      mapping: mapping,
      month: month,
      schedule: _schedule,
    );

    _applyingRemote = true;
    try {
      // Список группы выравнивается по журналу: студенты вне диапазона
      // строк журнала уходят из списка вместе со своими отметками.
      attendance.alignRoster(roster.students);
      final known = attendance.students;
      attendance.mergeRemote([
        for (final day in roster.entries.entries)
          for (final item in day.value.entries)
            AttendanceRecord(
              groupName: attendance.session.groupName,
              date: DateTime(month.year, month.month, day.key),
              student: _resolveStudent(item.key, known),
              entry: item.value,
            ),
      ]);
    } finally {
      _applyingRemote = false;
    }

    _lastSyncAt = DateTime.now();
    _error = null;
    notifyListeners();
  }

  /// Отметки из журнала подписаны ФИО; ключ отметки может нести пару
  /// («ФИО|mon-1»), поэтому берём часть до «|» и подставляем студента
  /// из списка группы, чтобы отметки легли в уже знакомые ключи.
  Student _resolveStudent(String entryKey, List<Student> students) {
    final fullName = entryKey.split('|').first.trim();
    for (final student in students) {
      if (student.id == fullName) return student;
    }
    for (final student in students) {
      if (student.fullName.toLowerCase() == fullName.toLowerCase()) {
        return student;
      }
    }
    return Student(id: fullName, fullName: fullName);
  }

  bool _isSameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;

  void _requireMonth(JournalSnapshot snapshot) {
    if (snapshot.month != null) return;
    throw const CloudSyncException(
      'Не удалось определить месяц. Назовите таблицу или лист '
      '«МЕСЯЦ : ГОД», например «Ноябрь : 2026».',
    );
  }

  /// Синхронизация запрещена, пока таблица не сходится с расписанием:
  /// отметки попадут не в те колонки.
  void _requireConsistency(JournalSnapshot snapshot) {
    if (snapshot.check.ok) return;
    throw CloudSyncException(snapshot.check.issues.first.message);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await action();
    } catch (error) {
      _error = _message(error);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _saveSettings() async {
    try {
      await _settingsStore.save(_settings);
    } catch (error) {
      throw CloudSyncException('Не удалось сохранить настройки: $error');
    }
  }

  void _requireConfigured() {
    if (!isConfigured) {
      throw const CloudSyncException(
        'Сначала подключите Google Таблицу на экране Google Диска.',
      );
    }
  }

  void _requireSignedIn() {
    if (!isSignedIn) {
      throw const CloudSyncException('Сначала войдите в аккаунт Google.');
    }
  }

  void _requireJournalSetup() {
    if (journalMapping != null) return;
    throw const CloudSyncException(
      'Сначала настройте журнал: объясните приложению, где числа дней, '
      'ФИО и пары. Кнопка «Настроить журнал» на экране Google Диска.',
    );
  }

  void _onAttendanceChanged() {
    if (_applyingRemote) return;

    _pending = true;
    notifyListeners();

    if (!_hasAutoSyncInvolved()) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 1500), () {
      unawaited(syncNow());
    });
  }

  void _onAuthChanged() {
    notifyListeners();
  }

  String _message(Object error) {
    if (error is CloudSyncException) return error.message;
    if (error is OAuthException) return error.message;
    return 'Не удалось синхронизировать: $error';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    attendance.removeListener(_onAttendanceChanged);
    auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}

/// Достаёт ID таблицы из ссылки Google Диска или из «голого» ID.
String? parseSpreadsheetId(String input) {
  final text = input.trim();
  if (text.isEmpty) return null;

  final fromUrl = RegExp(r'/spreadsheets/d/([a-zA-Z0-9_-]+)').firstMatch(text);
  if (fromUrl != null) return fromUrl.group(1);

  final asId = RegExp(r'^[a-zA-Z0-9_-]{20,}$').firstMatch(text);
  return asId?.group(0);
}
