// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/attendance_controller.dart';
import '../../data/cloud_settings.dart';
import 'cloud_exceptions.dart';
import 'google_auth_service.dart';
import 'google_sheets_sync_service.dart';
import 'oauth/oauth_models.dart';
import 'sheets_api.dart';

/// Управляет подключением к Google Таблице и фоновой синхронизацией.
class CloudSyncController extends ChangeNotifier {
  CloudSyncController({
    required this.attendance,
    required this.auth,
    required SheetsApi sheetsApi,
    required CloudSettingsStore settingsStore,
    required bool isWeb,
  }) : _api = sheetsApi,
       _settingsStore = settingsStore,
       _isWeb = isWeb,
       _sync = GoogleSheetsSyncService(sheetsApi) {
    attendance.addListener(_onAttendanceChanged);
    auth.addListener(_onAuthChanged);
  }

  final AttendanceController attendance;
  final GoogleAuthService auth;
  final SheetsApi _api;
  final CloudSettingsStore _settingsStore;
  final GoogleSheetsSyncService _sync;
  final bool _isWeb;

  CloudSettings _settings = const CloudSettings();
  bool _initialized = false;
  bool _busy = false;
  bool _pending = false;
  bool _applyingRemote = false;
  String? _error;
  DateTime? _lastSyncAt;
  SyncResult? _lastResult;
  Timer? _debounce;

  CloudSettings get settings => _settings;

  bool get isWeb => _isWeb;

  bool get isConfigured => _settings.hasSpreadsheet;

  bool get isSignedIn => auth.isSignedIn;

  bool get isBusy => _busy;

  bool get hasPendingChanges => _pending;

  String? get error => _error;

  DateTime? get lastSyncAt => _lastSyncAt;

  SyncResult? get lastResult => _lastResult;

  String? get spreadsheetId => _settings.spreadsheetId;

  String get spreadsheetUrl => _settings.spreadsheetUrl;

  bool get autoSync => _settings.autoSync;

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

    _busy = true;
    notifyListeners();
    try {
      await auth.restore();
      if (isConfigured && isSignedIn && autoSync) {
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
      if (isConfigured && autoSync) {
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

      if (autoSync) {
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
      sheetTitle: _settings.sheetTitle,
      session: attendance.session,
    );
    _lastResult = result;
    _lastSyncAt = DateTime.now();
    _pending = false;
    _error = null;
    notifyListeners();
  }

  Future<void> _pull() async {
    final spreadsheetId = _settings.spreadsheetId;
    if (spreadsheetId == null) return;

    final merged = await _sync.pull(
      spreadsheetId: spreadsheetId,
      sheetTitle: _settings.sheetTitle,
      local: attendance.session,
    );
    _applyingRemote = true;
    try {
      attendance.replaceSession(merged);
    } finally {
      _applyingRemote = false;
    }
    _lastSyncAt = DateTime.now();
    _error = null;
    notifyListeners();
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

    if (!autoSync || !isConfigured || !isSignedIn) return;
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
