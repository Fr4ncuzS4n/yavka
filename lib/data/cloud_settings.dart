import 'package:shared_preferences/shared_preferences.dart';

import '../services/cloud/journal_mapping.dart';

/// Настройки подключения к Google Таблице на Google Диске.
class CloudSettings {
  const CloudSettings({
    this.spreadsheetId,
    this.autoSync = true,
    this.clientId,
    this.clientSecret,
    this.webClientId,
    this.displayName = '',
    this.journalTabTitle,
    this.journalDayRow,
    this.journalFioColumn,
    this.journalFirstStudentRow,
    this.journalPairRow,
    this.journalLastStudentRow,
  });

  /// ID таблицы из ссылки `docs.google.com/spreadsheets/d/<ID>/edit`.
  final String? spreadsheetId;

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

  /// Настройка журнала: где что находится в таблице.
  ///
  /// Месяц отдельно не выбирается — он подбирается из названия таблицы
  /// или листа «МЕСЯЦ : ГОД», поэтому меняется вместе со ссылкой.
  final String? journalTabTitle;
  final int? journalDayRow;
  final int? journalFioColumn;
  final int? journalFirstStudentRow;

  /// Строка с номерами пар («ПАРА», 0-based); null — не задана.
  final int? journalPairRow;

  /// Последняя строка студентов (0-based); null — до конца листа.
  final int? journalLastStudentRow;

  bool get hasSpreadsheet =>
      spreadsheetId != null && spreadsheetId!.trim().isNotEmpty;

  String get spreadsheetUrl => hasSpreadsheet
      ? 'https://docs.google.com/spreadsheets/d/$spreadsheetId/edit'
      : '';

  /// Настройка журнала, если она заполнена целиком.
  JournalMapping? get journalMapping {
    final tabTitle = journalTabTitle;
    final dayRow = journalDayRow;
    final fioColumn = journalFioColumn;
    final firstStudentRow = journalFirstStudentRow;
    if (tabTitle == null ||
        tabTitle.trim().isEmpty ||
        dayRow == null ||
        fioColumn == null ||
        firstStudentRow == null) {
      return null;
    }
    try {
      return JournalMapping(
        tabTitle: tabTitle,
        dayRow: dayRow,
        fioColumn: fioColumn,
        firstStudentRow: firstStudentRow,
        pairRow: journalPairRow,
        lastStudentRow: journalLastStudentRow,
      );
    } on FormatException {
      return null;
    }
  }

  CloudSettings copyWith({
    String? spreadsheetId,
    bool? autoSync,
    String? clientId,
    String? clientSecret,
    String? webClientId,
    String? displayName,
    String? journalTabTitle,
    int? journalDayRow,
    int? journalFioColumn,
    int? journalFirstStudentRow,
    int? journalPairRow,
    int? journalLastStudentRow,
    bool clearSpreadsheet = false,
    bool clearClientSecret = false,
    bool clearJournal = false,
  }) => CloudSettings(
    spreadsheetId: clearSpreadsheet
        ? null
        : (spreadsheetId ?? this.spreadsheetId),
    autoSync: autoSync ?? this.autoSync,
    clientId: clientId ?? this.clientId,
    clientSecret: clearClientSecret
        ? null
        : (clientSecret ?? this.clientSecret),
    webClientId: webClientId ?? this.webClientId,
    displayName: displayName ?? this.displayName,
    journalTabTitle: clearJournal
        ? null
        : (journalTabTitle ?? this.journalTabTitle),
    journalDayRow: clearJournal ? null : (journalDayRow ?? this.journalDayRow),
    journalFioColumn: clearJournal
        ? null
        : (journalFioColumn ?? this.journalFioColumn),
    journalFirstStudentRow: clearJournal
        ? null
        : (journalFirstStudentRow ?? this.journalFirstStudentRow),
    journalPairRow: clearJournal ? null : (journalPairRow ?? this.journalPairRow),
    journalLastStudentRow: clearJournal
        ? null
        : (journalLastStudentRow ?? this.journalLastStudentRow),
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
  static const _autoSyncKey = 'yavka.cloud.auto_sync';
  static const _clientIdKey = 'yavka.cloud.client_id';
  static const _clientSecretKey = 'yavka.cloud.client_secret';
  static const _webClientIdKey = 'yavka.cloud.web_client_id';
  static const _displayNameKey = 'yavka.cloud.display_name';
  static const _journalTabKey = 'yavka.cloud.journal_tab';
  static const _journalDayRowKey = 'yavka.cloud.journal_day_row';
  static const _journalFioColumnKey = 'yavka.cloud.journal_fio_column';
  static const _journalFirstStudentRowKey =
      'yavka.cloud.journal_first_student_row';
  static const _journalPairRowKey = 'yavka.cloud.journal_pair_row';
  static const _journalLastStudentRowKey =
      'yavka.cloud.journal_last_student_row';

  final SharedPreferences _preferences;

  @override
  Future<CloudSettings> load() async {
    final spreadsheetId = _preferences.getString(_spreadsheetIdKey);
    return CloudSettings(
      spreadsheetId: spreadsheetId == null || spreadsheetId.trim().isEmpty
          ? null
          : spreadsheetId.trim(),
      autoSync: _preferences.getBool(_autoSyncKey) ?? true,
      clientId: _preferences.getString(_clientIdKey),
      clientSecret: _preferences.getString(_clientSecretKey),
      webClientId: _preferences.getString(_webClientIdKey),
      displayName: _preferences.getString(_displayNameKey) ?? '',
      journalTabTitle: _preferences.getString(_journalTabKey),
      journalDayRow: _preferences.getInt(_journalDayRowKey),
      journalFioColumn: _preferences.getInt(_journalFioColumnKey),
      journalFirstStudentRow: _preferences.getInt(
        _journalFirstStudentRowKey,
      ),
      journalPairRow: _preferences.getInt(_journalPairRowKey),
      journalLastStudentRow: _preferences.getInt(_journalLastStudentRowKey),
    );
  }

  @override
  Future<void> save(CloudSettings settings) async {
    await Future.wait([
      if (settings.spreadsheetId == null)
        _preferences.remove(_spreadsheetIdKey)
      else
        _preferences.setString(_spreadsheetIdKey, settings.spreadsheetId!),
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
      if (settings.journalTabTitle == null)
        _preferences.remove(_journalTabKey)
      else
        _preferences.setString(_journalTabKey, settings.journalTabTitle!),
      if (settings.journalDayRow == null)
        _preferences.remove(_journalDayRowKey)
      else
        _preferences.setInt(_journalDayRowKey, settings.journalDayRow!),
      if (settings.journalFioColumn == null)
        _preferences.remove(_journalFioColumnKey)
      else
        _preferences.setInt(_journalFioColumnKey, settings.journalFioColumn!),
      if (settings.journalFirstStudentRow == null)
        _preferences.remove(_journalFirstStudentRowKey)
      else
        _preferences.setInt(
          _journalFirstStudentRowKey,
          settings.journalFirstStudentRow!,
        ),
      if (settings.journalPairRow == null)
        _preferences.remove(_journalPairRowKey)
      else
        _preferences.setInt(_journalPairRowKey, settings.journalPairRow!),
      if (settings.journalLastStudentRow == null)
        _preferences.remove(_journalLastStudentRowKey)
      else
        _preferences.setInt(
          _journalLastStudentRowKey,
          settings.journalLastStudentRow!,
        ),
    ]);
  }
}
