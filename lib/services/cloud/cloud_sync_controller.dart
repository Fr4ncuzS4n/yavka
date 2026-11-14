// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/attendance_controller.dart';
import '../../data/cloud_settings.dart';
import '../../data/notification_controller.dart';
import '../../models/attendance_session.dart';
import '../../models/student.dart';
import '../../models/sync_notification.dart';
import 'cloud_exceptions.dart';
import 'google_auth_service.dart';
import 'month_grid_sync_service.dart';
import 'oauth/oauth_models.dart';
import 'sheets_api.dart';

/// Управляет подключением к Google Таблице и фоновой синхронизацией.
///
/// Отметки живут в листе месяца (например «Ноябрь 2026»): приложение
/// находит лист по месяцу, к которому относится отметка, а выбор месяца —
/// выпадающим списком в настройках облака.
class CloudSyncController extends ChangeNotifier {
  CloudSyncController({
    required this.attendance,
    required this.auth,
    required SheetsApi sheetsApi,
    required CloudSettingsStore settingsStore,
    required bool isWeb,
    NotificationController? notifications,
  }) : _api = sheetsApi,
       _settingsStore = settingsStore,
       _isWeb = isWeb,
       _notifications = notifications,
       _sync = MonthGridSyncService(sheetsApi) {
    attendance.addListener(_onAttendanceChanged);
    auth.addListener(_onAuthChanged);
  }

  final AttendanceController attendance;
  final GoogleAuthService auth;
  final SheetsApi _api;
  final CloudSettingsStore _settingsStore;
  final MonthGridSyncService _sync;
  final NotificationController? _notifications;
  final bool _isWeb;

  CloudSettings _settings = const CloudSettings();
  DateTime _selectedMonth = _monthOf(DateTime.now());
  bool _initialized = false;
  bool _busy = false;
  bool _pending = false;
  bool _applyingRemote = false;
  String? _error;
  DateTime? _lastSyncAt;
  GridSyncResult? _lastResult;
  Timer? _debounce;

  CloudSettings get settings => _settings;

  bool get isWeb => _isWeb;

  bool get isConfigured => _settings.hasSpreadsheet;

  bool get isSignedIn => auth.isSignedIn;

  bool get isBusy => _busy;

  bool get hasPendingChanges => _pending;

  String? get error => _error;

  DateTime? get lastSyncAt => _lastSyncAt;

  GridSyncResult? get lastResult => _lastResult;

  String? get spreadsheetId => _settings.spreadsheetId;

  String get spreadsheetUrl => _settings.spreadsheetUrl;

  bool get autoSync => _settings.autoSync;

  /// Месяц, с которым работает синхронизация.
  DateTime get selectedMonth => _selectedMonth;

  DateTime get _monthOfAttendance => _monthOf(attendance.session.date);

  static DateTime _monthOf(DateTime date) => DateTime(date.year, date.month);

  bool _hasAutoSyncInvolved() =>
      isConfigured && isSignedIn && autoSync;

  /// Уведомления о отметках на парах (если переданы при создании).
  NotificationController? get notifications => _notifications;

  /// Имя для уведомлений: как пользователя видят другие при чтении
  /// уведомлений из таблицы.
  String get displayName => _settings.displayName;

  /// Сохраняет имя, которым подписываются уведомления о отметках на парах.
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
    _loadMonthFromSettings();
    auth.configure(_configFromSettings());

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

  void _loadMonthFromSettings() {
    final stored = _settings.selectedSheetMonth;
    if (stored != null) {
      _selectedMonth = DateTime(stored.year, stored.month);
    } else {
      _selectedMonth = _monthOfAttendance;
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
      notifyListeners();

      if (_hasAutoSyncInvolved()) {
        await _pull();
        await _push();
      }
    });
  }

  /// Создаёт новую таблицу и подключает её.
  Future<void> createSpreadsheet() async {
    await _run(() async {
      _requireSignedIn();
      final title = 'Явка — ${attendance.session.groupName}';
      final meta = await _api.createSpreadsheet(title);
      _settings = _settings.copyWith(spreadsheetId: meta.id);
      await _saveSettings();
      _pending = false;
      notifyListeners();

      await _pull();
      await _push();
    });
  }

  Future<void> disconnectSpreadsheet() async {
    await _run(() async {
      _settings = _settings.copyWith(clearSpreadsheet: true);
      await _saveSettings();
      _pending = false;
      _lastSyncAt = null;
      _lastResult = null;
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

  /// Выбирает месяц журнала (выпадающий список в настройках облака).
  Future<void> selectMonth(DateTime month) async {
    final normalized = DateTime(month.year, month.month);
    if (normalized == _selectedMonth) return;

    _selectedMonth = normalized;
    _error = null;
    notifyListeners();
    try {
      await _settingsStore.save(
        _settings.copyWith(sheetYear: normalized.year, sheetMonth: normalized.month),
      );
    } catch (error) {
      _error = _message(error);
      notifyListeners();
    }

    if (!_hasAutoSyncInvolved()) return;
    await _run(() async {
      await _pull();
      await _push();
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

  Future<void> syncNow() async {
    await _run(() async {
      _requireConfigured();
      _requireSignedIn();
      await _pull();
      await _push();
    });
  }

  Future<void> pullNow() async {
    await _run(() async {
      _requireConfigured();
      _requireSignedIn();
      await _pull();
    });
  }

  GoogleOAuthConfig _configFromSettings() =>
      GoogleOAuthConfig.fromSettings(_settings, isWeb: _isWeb);

  Future<void> _push() async {
    final spreadsheetId = _settings.spreadsheetId;
    if (spreadsheetId == null) return;

    final result = await _sync.push(
      spreadsheetId: spreadsheetId,
      month: _selectedMonth,
      session: attendance.session,
    );
    _lastResult = result;
    _lastSyncAt = DateTime.now();
    _pending = false;
    _error = null;

    // Уведомляем всех, кто пользуется таблицей: отмеченные пары
    // уходят в лист «Уведомления».
    await _flushLessonNotifications(spreadsheetId);

    notifyListeners();
  }

  Future<void> _flushLessonNotifications(String spreadsheetId) async {
    final notifications = _notifications;
    if (notifications == null) return;
    final outbox = notifications.drainOutbox();
    if (outbox.isEmpty) return;
    try {
      await _sync.pushNotifications(
        spreadsheetId: spreadsheetId,
        notifications: [
          for (final item in outbox) _asNotification(item),
        ],
      );
    } catch (_) {
      // Отправка не удалась — возвращаем уведомления в отложенные,
      // чтобы они ушли при следующей синхронизации.
      notifications.restoreOutbox(outbox);
      rethrow;
    }
  }

  SyncNotification _asNotification(PendingLessonMark item) {
    final author = _settings.displayName.trim().isEmpty
        ? 'Староста'
        : _settings.displayName.trim();
    return SyncNotification(
      id: '${item.id}|${item.count}',
      createdAt: DateTime.now(),
      author: author,
      groupName: item.groupName,
      lessonTitle: item.lessonTitle,
      message:
          'Отметка на паре «${item.lessonTitle}» (${item.lessonTime}): '
          '${item.count} ${_pluralMark(item.count)}',
    );
  }

  static String _pluralMark(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return 'отметка';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'отметки';
    }
    return 'отметок';
  }

  Future<void> _pull() async {
    final spreadsheetId = _settings.spreadsheetId;
    if (spreadsheetId == null) return;

    final remote = await _sync.read(spreadsheetId, _selectedMonth);
    _applyingRemote = true;
    try {
      if (remote != null) {
        attendance.replaceSession(
          _mergedToday(attendance.session, remote, _selectedMonth),
        );
      }
    } finally {
      _applyingRemote = false;
    }

    // Подтягиваем уведомления других пользователей таблицы.
    final notifications = _notifications;
    if (notifications != null) {
      final remote = await _sync.pullNotifications(
        spreadsheetId: spreadsheetId,
        groupName: attendance.session.groupName,
      );
      notifications.addRemote(remote);
    }

    _lastSyncAt = DateTime.now();
    _error = null;
    notifyListeners();
  }

  /// Вбирает в текущую сессию отметки листа месяца за её день.
  AttendanceSession _mergedToday(
    AttendanceSession local,
    MonthSheetState remote,
    DateTime month,
  ) {
    final day = local.date.day;
    final byStudent = remote.entries[day];
    var merged = local.withRoster(remote.students);
    if (byStudent == null || byStudent.isEmpty) {
      return merged;
    }
    final records = <AttendanceRecord>[];
    byStudent.forEach((studentId, entry) {
      final student = remote.students.firstWhere(
        (item) => item.id == studentId,
        orElse: () => Student(id: studentId, fullName: studentId),
      );
      records.add(
        AttendanceRecord(
          groupName: merged.groupName,
          date: merged.date,
          student: student,
          entry: entry,
        ),
      );
    });
    return merged.mergeRemote(records);
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
