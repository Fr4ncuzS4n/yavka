import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yavka/services/update/update_check.dart';

/// Ответ GitHub API «последний релиз».
String releaseJson({
  String tag = 'v1.2.0',
  List<Map<String, String>> assets = const [],
}) => jsonEncode({
  'tag_name': tag,
  'assets': assets,
});

const asset = {
  'name': 'yavka-linux-x64.zip',
  'browser_download_url': 'https://github.com/Fr4ncuzS4n/yavka/releases/'
      'download/v1.2.0/yavka-linux-x64.zip',
};

void main() {
  group('compareVersions', () {
    test('новая версия больше', () {
      expect(compareVersions('1.2.0', '1.1.0'), greaterThan(0));
      expect(compareVersions('v1.2.0', '1.1.0'), greaterThan(0));
      expect(compareVersions('1.10.0', '1.9.9'), greaterThan(0));
      expect(compareVersions('2.0.0', '1.9.9'), greaterThan(0));
    });

    test('совпадают', () {
      expect(compareVersions('1.1.0', '1.1.0'), 0);
      expect(compareVersions('v1.1.0', '1.1.0'), 0);
      expect(compareVersions('1.1.0+2', '1.1.0+7'), 0);
    });

    test('старая версия меньше', () {
      expect(compareVersions('1.0.0', '1.1.0'), lessThan(0));
      expect(compareVersions('0.9.9', '1.0.0'), lessThan(0));
    });

    test('мусор в номере не ломает сравнение', () {
      expect(compareVersions('1.2.0', ''), greaterThan(0));
      expect(compareVersions('', '1.0.0'), lessThan(0));
    });
  });

  group('releaseAssetNameFor', () {
    for (final entry in {
      TargetPlatform.linux: 'yavka-linux-x64.zip',
      TargetPlatform.windows: 'yavka-windows-x64.zip',
      TargetPlatform.android: 'yavka-android.apk',
      TargetPlatform.iOS: null,
    }.entries) {
      test('${entry.key.name} → ${entry.value ?? 'null'}', () {
        debugDefaultTargetPlatformOverride = entry.key;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        expect(releaseAssetNameFor(entry.key), entry.value);
      });
    }
  });

  group('UpdateController', () {
    late MockClient client;
    late List<Uri> requests;

    UpdateController controller(String version) => UpdateController(
      currentVersion: () async => version,
      client: client,
    );

    setUp(() {
      requests = [];
      client = MockClient((request) async {
        requests.add(request.url);
        return http.Response(releaseJson(assets: [asset]), 200);
      });
    });

    test('находит обновление и файл под платформу', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final updates = controller('1.1.0');
      await updates.check();

      expect(requests.single.host, 'api.github.com');
      expect(
        requests.single.path,
        '/repos/Fr4ncuzS4n/yavka/releases/latest',
      );
      final update = updates.available;
      expect(update, isNotNull);
      expect(update!.version, '1.2.0');
      expect(
        update.downloadUrl,
        'https://github.com/Fr4ncuzS4n/yavka/releases/'
        'download/v1.2.0/yavka-linux-x64.zip',
      );
      expect(updates.isChecking, isFalse);
    });

    test('свежая версия не предлагает обновления', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      final updates = controller('1.2.0');
      await updates.check();

      expect(updates.available, isNull);
    });

    test('ошибка сети не бросает исключение', () async {
      client = MockClient((request) async {
        throw Exception('нет сети');
      });
      final updates = controller('1.1.0');

      await updates.check(); // не должен упасть

      expect(updates.available, isNull);
      expect(updates.isChecking, isFalse);
    });

    test('плохой ответ сервера — обновления нет', () async {
      client = MockClient((request) async => http.Response('', 404));
      final updates = controller('1.1.0');

      await updates.check();

      expect(updates.available, isNull);
    });

    test('битый JSON — обновления нет', () async {
      client = MockClient((request) async => http.Response('не JSON', 200));
      final updates = controller('1.1.0');

      await updates.check();

      expect(updates.available, isNull);
    });

    test('нет сборки под платформу — ведёт на страницу релиза', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      client = MockClient(
        (request) async => http.Response(
          releaseJson(
            tag: 'v1.2.0',
            assets: [asset], // только linux-файл
          ),
          200,
        ),
      );
      final updates = controller('1.1.0');
      await updates.check();

      expect(
        updates.available?.downloadUrl,
        'https://github.com/Fr4ncuzS4n/yavka/releases/latest',
      );
    });

    test('повторная проверка в течение часа не ходит в сеть', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      var clock = DateTime(2026, 1, 1);
      final updates = UpdateController(
        currentVersion: () async => '1.1.0',
        client: client,
        now: () => clock,
      );

      await updates.check();
      expect(requests, hasLength(1));

      clock = clock.add(const Duration(minutes: 30));
      await updates.check();
      expect(requests, hasLength(1)); // тише не стало

      clock = clock.add(const Duration(hours: 2));
      await updates.check();
      expect(requests, hasLength(2)); // час прошёл — снова проверила
    });

    test('force проверяет, не глядя на паузу', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      var clock = DateTime(2026, 1, 1);
      final updates = UpdateController(
        currentVersion: () async => '1.1.0',
        client: client,
        now: () => clock,
      );

      await updates.check();
      await updates.check(force: true);
      expect(requests, hasLength(2));
    });
  });
}
