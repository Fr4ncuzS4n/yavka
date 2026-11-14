import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/catalog.dart';

/// Локальное хранилище базы (преподаватели, кабинеты, предметы).
abstract interface class CatalogStore {
  Future<CatalogData> load();

  Future<void> save(CatalogData data);
}

/// База в памяти — используется в тестах и как запасной вариант.
class MemoryCatalogStore implements CatalogStore {
  MemoryCatalogStore([CatalogData? data]) : _data = data;

  CatalogData? _data;

  @override
  Future<CatalogData> load() async => _data ?? const CatalogData();

  @override
  Future<void> save(CatalogData data) async => _data = data;
}

/// База в SharedPreferences (все платформы).
///
/// Вся база хранится одним JSON-объектом под одним ключом: предметы
/// ссылаются на преподавателей и кабинеты по идентификаторам, поэтому
/// читать и писать их нужно вместе — иначе легко получить предмет,
/// указывающий на несуществующего преподавателя.
class SharedPreferencesCatalogStore implements CatalogStore {
  SharedPreferencesCatalogStore(this._preferences);

  static const _key = 'yavka.catalog.v1';

  final SharedPreferences _preferences;

  @override
  Future<CatalogData> load() async {
    final raw = _preferences.getString(_key);
    if (raw == null || raw.isEmpty) return const CatalogData();
    try {
      return CatalogData.fromJson(jsonDecode(raw));
    } catch (_) {
      // Повреждённое хранилище не должно мешать работе приложения.
      return const CatalogData();
    }
  }

  @override
  Future<void> save(CatalogData data) async {
    await _preferences.setString(_key, jsonEncode(data.toJson()));
  }
}
