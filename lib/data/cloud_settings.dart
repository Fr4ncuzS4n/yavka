import 'package:shared_preferences/shared_preferences.dart';

/// Настройки подключения к Google Таблице на Google Диске.
class CloudSettings {
  const CloudSettings({
    this.spreadsheetId,
    this.sheetTitle = 'Посещаемость',
    this.autoSync = true,
    this.clientId,
    this.clientSecret,
    this.webClientId,
  });

  /// ID таблицы из ссылки `docs.google.com/spreadsheets/d/<ID>/edit`.
  final String? spreadsheetId;

  /// Название листа внутри таблицы.
  final String sheetTitle;

  /// Автоматически отправлять отметки после изменения.
  final bool autoSync;

  /// OAuth Client ID для Android/iOS/Linux/Windows (тип «Desktop app»).
  final String? clientId;

  /// OAuth Client Secret для Android/iOS/Linux/Windows.
  final String? clientSecret;

  /// OAuth Client ID для web (тип «Web application»).
  final String? webClientId;

  bool get hasSpreadsheet =>
      spreadsheetId != null && spreadsheetId!.trim().isNotEmpty;

  String get spreadsheetUrl => hasSpreadsheet
      ? 'https://docs.google.com/spreadsheets/d/$spreadsheetId/edit'
      : '';

  CloudSettings copyWith({
    String? spreadsheetId,
    String? sheetTitle,
    bool? autoSync,
    String? clientId,
    String? clientSecret,
    String? webClientId,
    bool clearSpreadsheet = false,
    bool clearClientSecret = false,
  }) => CloudSettings(
    spreadsheetId: clearSpreadsheet
        ? null
        : (spreadsheetId ?? this.spreadsheetId),
    sheetTitle: sheetTitle ?? this.sheetTitle,
    autoSync: autoSync ?? this.autoSync,
    clientId: clientId ?? this.clientId,
    clientSecret: clearClientSecret
        ? null
        : (clientSecret ?? this.clientSecret),
    webClientId: webClientId ?? this.webClientId,
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
  static const _sheetTitleKey = 'yavka.cloud.sheet_title';
  static const _autoSyncKey = 'yavka.cloud.auto_sync';
  static const _clientIdKey = 'yavka.cloud.client_id';
  static const _clientSecretKey = 'yavka.cloud.client_secret';
  static const _webClientIdKey = 'yavka.cloud.web_client_id';

  final SharedPreferences _preferences;

  @override
  Future<CloudSettings> load() async {
    final spreadsheetId = _preferences.getString(_spreadsheetIdKey);
    final sheetTitle = _preferences.getString(_sheetTitleKey);
    return CloudSettings(
      spreadsheetId: spreadsheetId == null || spreadsheetId.trim().isEmpty
          ? null
          : spreadsheetId.trim(),
      sheetTitle: sheetTitle == null || sheetTitle.trim().isEmpty
          ? 'Посещаемость'
          : sheetTitle.trim(),
      autoSync: _preferences.getBool(_autoSyncKey) ?? true,
      clientId: _preferences.getString(_clientIdKey),
      clientSecret: _preferences.getString(_clientSecretKey),
      webClientId: _preferences.getString(_webClientIdKey),
    );
  }

  @override
  Future<void> save(CloudSettings settings) async {
    await Future.wait([
      if (settings.spreadsheetId == null)
        _preferences.remove(_spreadsheetIdKey)
      else
        _preferences.setString(_spreadsheetIdKey, settings.spreadsheetId!),
      _preferences.setString(_sheetTitleKey, settings.sheetTitle),
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
    ]);
  }
}
