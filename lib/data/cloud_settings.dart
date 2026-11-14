import 'package:shared_preferences/shared_preferences.dart';

/// Настройки подключения к Google Таблице на Google Диске.
class CloudSettings {
  const CloudSettings({
    this.spreadsheetId,
    this.sheetYear,
    this.sheetMonth,
    this.autoSync = true,
    this.clientId,
    this.clientSecret,
    this.webClientId,
    this.displayName = '',
  });

  /// ID таблицы из ссылки `docs.google.com/spreadsheets/d/<ID>/edit`.
  final String? spreadsheetId;

  /// Выбранный месяц листа посещаемости (год и месяц отдельно),
  /// чтобы хранить настройки в SharedPreferences.
  final int? sheetYear;
  final int? sheetMonth;

  /// Автоматически отправлять отметки после изменения.
  final bool autoSync;

  /// OAuth Client ID для Android/iOS/Linux/Windows (тип «Desktop app»).
  final String? clientId;

  /// OAuth Client Secret для Android/iOS/Linux/Windows.
  final String? clientSecret;

  /// OAuth Client ID для web (тип «Web application»).
  final String? webClientId;

  /// Имя для уведомлений: как пользователя увидят те, кто пользуется
  /// той же таблицей.
  final String displayName;

  bool get hasSpreadsheet =>
      spreadsheetId != null && spreadsheetId!.trim().isNotEmpty;

  String get spreadsheetUrl => hasSpreadsheet
      ? 'https://docs.google.com/spreadsheets/d/$spreadsheetId/edit'
      : '';

  /// Месяц листа, если он выбран и корректен.
  DateTime? get selectedSheetMonth {
    final year = sheetYear;
    final month = sheetMonth;
    if (year == null || month == null || month < 1 || month > 12) return null;
    return DateTime(year, month);
  }

  CloudSettings copyWith({
    String? spreadsheetId,
    int? sheetYear,
    int? sheetMonth,
    bool? autoSync,
    String? clientId,
    String? clientSecret,
    String? webClientId,
    String? displayName,
    bool clearSpreadsheet = false,
    bool clearClientSecret = false,
  }) => CloudSettings(
    spreadsheetId: clearSpreadsheet
        ? null
        : (spreadsheetId ?? this.spreadsheetId),
    sheetYear: sheetYear ?? this.sheetYear,
    sheetMonth: sheetMonth ?? this.sheetMonth,
    autoSync: autoSync ?? this.autoSync,
    clientId: clientId ?? this.clientId,
    clientSecret: clearClientSecret
        ? null
        : (clientSecret ?? this.clientSecret),
    webClientId: webClientId ?? this.webClientId,
    displayName: displayName ?? this.displayName,
  );
}

/// Хранилище настроек облачной синхронизации.
abstract interface class CloudSettingsStore {
  Future<CloudSettings> load();

  Future<void> save(CloudSettings settings);
}

/// Настройки в памяти — для тестов.
class MemoryCloudSettingsStore implements CloudSettingsStore {
  MemoryCloudSettingsStore([this._settings = const CloudSettings()]);

  CloudSettings _settings;

  @override
  Future<CloudSettings> load() async => _settings;

  @override
  Future<void> save(CloudSettings settings) async => _settings = settings;
}

/// Настройки в SharedPreferences.
class SharedPreferencesCloudSettingsStore implements CloudSettingsStore {
  SharedPreferencesCloudSettingsStore(this._preferences);

  static const _spreadsheetIdKey = 'yavka.cloud.spreadsheet_id';
  static const _sheetYearKey = 'yavka.cloud.sheet_year';
  static const _sheetMonthKey = 'yavka.cloud.sheet_month';
  static const _autoSyncKey = 'yavka.cloud.auto_sync';
  static const _clientIdKey = 'yavka.cloud.client_id';
  static const _clientSecretKey = 'yavka.cloud.client_secret';
  static const _webClientIdKey = 'yavka.cloud.web_client_id';
  static const _displayNameKey = 'yavka.cloud.display_name';

  final SharedPreferences _preferences;

  @override
  Future<CloudSettings> load() async {
    final spreadsheetId = _preferences.getString(_spreadsheetIdKey);
    return CloudSettings(
      spreadsheetId: spreadsheetId == null || spreadsheetId.trim().isEmpty
          ? null
          : spreadsheetId.trim(),
      sheetYear: _preferences.getInt(_sheetYearKey),
      sheetMonth: _preferences.getInt(_sheetMonthKey),
      autoSync: _preferences.getBool(_autoSyncKey) ?? true,
      clientId: _preferences.getString(_clientIdKey),
      clientSecret: _preferences.getString(_clientSecretKey),
      webClientId: _preferences.getString(_webClientIdKey),
      displayName: _preferences.getString(_displayNameKey) ?? '',
    );
  }

  @override
  Future<void> save(CloudSettings settings) async {
    await Future.wait([
      if (settings.spreadsheetId == null)
        _preferences.remove(_spreadsheetIdKey)
      else
        _preferences.setString(_spreadsheetIdKey, settings.spreadsheetId!),
      if (settings.sheetYear == null)
        _preferences.remove(_sheetYearKey)
      else
        _preferences.setInt(_sheetYearKey, settings.sheetYear!),
      if (settings.sheetMonth == null)
        _preferences.remove(_sheetMonthKey)
      else
        _preferences.setInt(_sheetMonthKey, settings.sheetMonth!),
      _preferences.setBool(_autoSyncKey, settings.autoSync),
      if (settings.clientId == null)
        _preferences.remove(_clientIdKey)
      else
        _preferences.setString(_clientIdKey, settings.clientId!),
      if (settings.clientSecret == null)
        _preferences.remove(_clientSecretKey)
      else
        _preferences.setString(_clientSecretKey, settings.clientSecret!),
      if (settings.webClientId == null)
        _preferences.remove(_webClientIdKey)
      else
        _preferences.setString(_webClientIdKey, settings.webClientId!),
      _preferences.setString(_displayNameKey, settings.displayName),
    ]);
  }
}
