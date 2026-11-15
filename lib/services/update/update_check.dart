import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Свежая версия, найденная в релизах GitHub.
@immutable
class AvailableUpdate {
  const AvailableUpdate({required this.version, required this.downloadUrl});

  /// Версия без приставки «v»: «1.2.0».
  final String version;

  /// Файл сборки для этой платформы или страница релиза.
  final String downloadUrl;
}

/// Имя файла сборки в релизе для платформы.
///
/// Названия повторяют файлы, которые прикладывает релизный workflow.
/// Для web возвращается `null`: веб-версия всегда свежая, она
/// обновляется вместе с сайтом.
String? releaseAssetNameFor(TargetPlatform platform) => switch (platform) {
  TargetPlatform.linux => 'yavka-linux-x64.zip',
  TargetPlatform.windows => 'yavka-windows-x64.zip',
  TargetPlatform.android => 'yavka-android.apk',
  _ => null,
};

/// Сравнение версий вида «1.2.3» (приставка «v» и «+сборка» не мешают).
/// Результат > 0 — [a] новее [b], < 0 — старее, 0 — совпадают.
int compareVersions(String a, String b) {
  final partsA = _versionParts(a);
  final partsB = _versionParts(b);
  for (var i = 0; i < partsA.length && i < partsB.length; i++) {
    final comparison = partsA[i].compareTo(partsB[i]);
    if (comparison != 0) return comparison;
  }
  return partsA.length.compareTo(partsB.length);
}

List<int> _versionParts(String version) {
  var clean = version.trim().toLowerCase();
  if (clean.startsWith('v')) clean = clean.substring(1);
  clean = clean.split('+').first; // номер сборки не участвует
  final parts = <int>[];
  for (final piece in clean.split('.')) {
    final number = int.tryParse(piece);
    if (number == null) break;
    parts.add(number);
  }
  return parts;
}

/// Проверка обновлений: последний релиз на GitHub против своей версии.
///
/// Работает тихо: без сети или при ошибке просто не показывает ничего.
/// Проверяется не чаще раза в час, принудительно — [check].
class UpdateController extends ChangeNotifier {
  // ignore: prefer_initializing_formals — приватные поля нельзя передать
  // именованным initializing formal'ом, подавляем построчно.
  UpdateController({
    required Future<String?> Function() currentVersion,
    http.Client? client,
    String owner = 'Fr4ncuzS4n',
    String repo = 'yavka',
    DateTime Function()? now,
  }) : _currentVersion = currentVersion, // ignore: prefer_initializing_formals
       _client = client ?? http.Client(),
       _owner = owner, // ignore: prefer_initializing_formals
       _repo = repo, // ignore: prefer_initializing_formals
       _now = now ?? (() => DateTime.now());

  final Future<String?> Function() _currentVersion;
  final http.Client _client;
  final String _owner;
  final String _repo;
  final DateTime Function() _now;

  /// Запросы к GitHub не чаще раза в час — при каждом запуске
  /// приложения проверять без нужды нельзя.
  static const _throttle = Duration(hours: 1);

  AvailableUpdate? _available;
  bool _checking = false;
  DateTime? _checkedAt;

  /// Найденное обновление; `null` — всё свежее или проверка не удалась.
  AvailableUpdate? get available => _available;

  bool get isChecking => _checking;

  /// Проверяет последний релиз. [force] — не смотреть на паузу в час.
  Future<void> check({bool force = false}) async {
    if (_checking) return;
    final checkedAt = _checkedAt;
    if (!force &&
        checkedAt != null &&
        _now().difference(checkedAt) < _throttle) {
      return;
    }

    _checking = true;
    notifyListeners();
    try {
      final current = await _currentVersion();
      if (current == null || current.isEmpty) return;

      final response = await _client
          .get(
            Uri.https('api.github.com', '/repos/$_owner/$_repo/releases/latest'),
            headers: {
              'Accept': 'application/vnd.github+json',
              'User-Agent': 'yavka-app',
            },
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return;

      final update = _parseRelease(response.body, current);
      if (update != null) {
        _available = update;
        notifyListeners();
      }
    } catch (_) {
      // Нет сети или GitHub недоступен — обновление не показываем.
    } finally {
      _checking = false;
      _checkedAt = _now();
      notifyListeners();
    }
  }

  /// Разбирает ответ GitHub API; `null` — обновления нет.
  AvailableUpdate? _parseRelease(String body, String currentVersion) {
    Map<String, Object?> json;
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      json = Map<String, Object?>.from(decoded);
    } catch (_) {
      return null;
    }

    final tag = json['tag_name']?.toString() ?? '';
    if (compareVersions(tag, currentVersion) <= 0) return null;
    final version = tag.startsWith('v') ? tag.substring(1) : tag;

    final releasePage =
        'https://github.com/$_owner/$_repo/releases/latest';
    final assetName = releaseAssetNameFor(defaultTargetPlatform);
    if (assetName == null) {
      // Web: своя версия приходит вместе с сайтом, файл не нужен.
      return AvailableUpdate(version: version, downloadUrl: releasePage);
    }

    final assets = json['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is! Map) continue;
        final name = asset['name']?.toString().toLowerCase() ?? '';
        if (name != assetName) continue;
        final url = asset['browser_download_url']?.toString() ?? '';
        if (url.isNotEmpty) {
          return AvailableUpdate(version: version, downloadUrl: url);
        }
      }
    }

    // Сборки для платформы в релизе ещё нет — ведём на страницу
    // релиза, файл там появится, когда сборка дойдёт.
    return AvailableUpdate(version: version, downloadUrl: releasePage);
  }
}
