import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:grozfy_go/core/models/app_version_status.dart';
import 'package:grozfy_go/core/services/app_version_service.dart';

/// The build the fake device is running throughout these tests.
const int kCurrentBuild = 2;

Future<PackageInfo> Function() _packageInfo({
  String version = '1.0.1',
  String buildNumber = '$kCurrentBuild',
}) {
  return () async => PackageInfo(
    appName: 'Grozfy Go',
    packageName: 'com.grozfy.go',
    version: version,
    buildNumber: buildNumber,
  );
}

Future<PackageInfo> Function() get _brokenPackageInfo =>
    () async => throw Exception('no platform channel');

String _body(Map<String, dynamic> message) =>
    jsonEncode(<String, dynamic>{'message': message});

AppVersionService _service({
  required http.Client client,
  Future<PackageInfo> Function()? packageInfo,
  DateTime Function()? clock,
  String platformName = 'android',
}) {
  return AppVersionService(
    client: client,
    packageInfoLoader: packageInfo ?? _packageInfo(),
    platformName: platformName,
    clock: clock,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('request shape', () {
    test('sends platform, version and build number', () async {
      http.Request? seen;
      final client = MockClient((http.Request request) async {
        seen = request;
        return http.Response(_body(<String, dynamic>{}), 200);
      });

      await _service(client: client, platformName: 'ios').check();

      expect(seen, isNotNull);
      expect(seen!.url.queryParameters['platform'], 'ios');
      expect(seen!.url.queryParameters['version'], '1.0.1');
      expect(seen!.url.queryParameters['build_number'], '2');
    });
  });

  group('successful checks', () {
    test('returns the mandatory verdict the server sends', () async {
      final client = MockClient(
        (_) async => http.Response(
          _body(<String, dynamic>{
            'update_required': true,
            'min_supported_build': 5,
            'latest_version': '1.2.0',
            'store_url': 'https://play.google.com/store/apps/details?id=x',
          }),
          200,
        ),
      );

      final status = await _service(client: client).check();

      expect(status.requirement, AppUpdateRequirement.mandatory);
      expect(status.latestVersion, '1.2.0');
      expect(status.checkedAt, isNotNull);
    });

    test('returns up to date when the build meets the floor', () async {
      final client = MockClient(
        (_) async => http.Response(
          _body(<String, dynamic>{'min_supported_build': 2}),
          200,
        ),
      );

      final status = await _service(client: client).check();

      expect(status.requirement, AppUpdateRequirement.upToDate);
    });

    test('caches a successful verdict for later failures', () async {
      final client = MockClient(
        (_) async => http.Response(
          _body(<String, dynamic>{'update_required': true}),
          200,
        ),
      );

      await _service(client: client).check();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AppVersionService.prefVerdict), isNotNull);
      expect(prefs.getString(AppVersionService.prefCheckedAt), isNotNull);
    });
  });

  group('failures fail open', () {
    test('404 (endpoint not deployed) is up to date', () async {
      final client = MockClient((_) async => http.Response('Not Found', 404));

      final status = await _service(client: client).check();

      expect(status.requirement, AppUpdateRequirement.upToDate);
    });

    test('HTTP 500 is up to date', () async {
      final client = MockClient((_) async => http.Response('boom', 500));

      final status = await _service(client: client).check();

      expect(status.requirement, AppUpdateRequirement.upToDate);
    });

    test('a network error is up to date', () async {
      final client = MockClient(
        (_) async => throw const SocketExceptionStub(),
      );

      final status = await _service(client: client).check();

      expect(status.requirement, AppUpdateRequirement.upToDate);
    });

    test('a timeout is up to date', () async {
      final client = MockClient((_) async {
        await Future<void>.delayed(
          AppVersionService.requestTimeout + const Duration(seconds: 2),
        );
        return http.Response(
          _body(<String, dynamic>{'update_required': true}),
          200,
        );
      });

      final status = await _service(client: client).check();

      expect(status.requirement, AppUpdateRequirement.upToDate);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a malformed 200 body is up to date', () async {
      final client = MockClient((_) async => http.Response('<html>', 200));

      final status = await _service(client: client).check();

      expect(status.requirement, AppUpdateRequirement.upToDate);
    });

    test('a 200 with no message envelope is up to date', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode(<String, dynamic>{}), 200),
      );

      final status = await _service(client: client).check();

      expect(status.requirement, AppUpdateRequirement.upToDate);
    });

    test('unreadable package info skips the call entirely', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return http.Response(
          _body(<String, dynamic>{'update_required': true}),
          200,
        );
      });

      final status = await _service(
        client: client,
        packageInfo: _brokenPackageInfo,
      ).check();

      expect(status.requirement, AppUpdateRequirement.upToDate);
      expect(called, isFalse);
    });

    test('a non-numeric build number skips the call entirely', () async {
      var called = false;
      final client = MockClient((_) async {
        called = true;
        return http.Response(
          _body(<String, dynamic>{'update_required': true}),
          200,
        );
      });

      final status = await _service(
        client: client,
        packageInfo: _packageInfo(buildNumber: 'dev'),
      ).check();

      expect(status.requirement, AppUpdateRequirement.upToDate);
      expect(called, isFalse);
    });
  });

  group('24-hour cache', () {
    /// Seeds a cached mandatory verdict written [age] ago.
    Future<void> seedBlockingCache(Duration age, DateTime now) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppVersionService.prefVerdict: jsonEncode(<String, dynamic>{
          'update_required': true,
          'min_supported_build': 5,
          'latest_version': '1.2.0',
        }),
        AppVersionService.prefCheckedAt: now
            .subtract(age)
            .toUtc()
            .toIso8601String(),
      });
    }

    final DateTime now = DateTime.utc(2026, 8, 6, 12);

    test('offline with no cache does not block (fresh install)', () async {
      final client = MockClient(
        (_) async => throw const SocketExceptionStub(),
      );

      final status = await _service(
        client: client,
        clock: () => now,
      ).check();

      expect(status.requirement, AppUpdateRequirement.upToDate);
    });

    test('offline with a 2-hour-old block re-applies the block', () async {
      await seedBlockingCache(const Duration(hours: 2), now);
      final client = MockClient(
        (_) async => throw const SocketExceptionStub(),
      );

      final status = await _service(
        client: client,
        clock: () => now,
      ).check();

      expect(status.requirement, AppUpdateRequirement.mandatory);
      expect(status.latestVersion, '1.2.0');
    });

    test('offline with a 48-hour-old block does not block', () async {
      await seedBlockingCache(const Duration(hours: 48), now);
      final client = MockClient(
        (_) async => throw const SocketExceptionStub(),
      );

      final status = await _service(
        client: client,
        clock: () => now,
      ).check();

      expect(status.requirement, AppUpdateRequirement.upToDate);
    });

    test('the cache expires exactly at the TTL boundary', () async {
      await seedBlockingCache(AppVersionService.cacheTtl, now);
      final client = MockClient(
        (_) async => throw const SocketExceptionStub(),
      );

      final status = await _service(
        client: client,
        clock: () => now,
      ).check();

      expect(status.requirement, AppUpdateRequirement.upToDate);
    });

    test('a cache timestamp in the future is treated as fresh', () async {
      await seedBlockingCache(const Duration(hours: -6), now);
      final client = MockClient(
        (_) async => throw const SocketExceptionStub(),
      );

      final status = await _service(
        client: client,
        clock: () => now,
      ).check();

      expect(status.requirement, AppUpdateRequirement.mandatory);
    });

    test('an unreadable cache does not block', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppVersionService.prefVerdict: 'not json',
        AppVersionService.prefCheckedAt: now.toUtc().toIso8601String(),
      });
      final client = MockClient(
        (_) async => throw const SocketExceptionStub(),
      );

      final status = await _service(
        client: client,
        clock: () => now,
      ).check();

      expect(status.requirement, AppUpdateRequirement.upToDate);
    });

    test('a fresh success overwrites a cached block', () async {
      await seedBlockingCache(const Duration(hours: 1), now);
      final client = MockClient(
        (_) async => http.Response(
          _body(<String, dynamic>{'update_required': false}),
          200,
        ),
      );

      final service = _service(client: client, clock: () => now);
      final status = await service.check();
      expect(status.requirement, AppUpdateRequirement.upToDate);

      // And the cleared verdict is what a subsequent failure sees.
      final offline = _service(
        client: MockClient((_) async => throw const SocketExceptionStub()),
        clock: () => now,
      );
      expect(
        (await offline.check()).requirement,
        AppUpdateRequirement.upToDate,
      );
    });
  });

  group('optional prompt snooze', () {
    final DateTime now = DateTime.utc(2026, 8, 6, 12);

    test('shows by default', () async {
      final service = _service(
        client: MockClient((_) async => http.Response('', 404)),
        clock: () => now,
      );

      expect(await service.shouldShowOptionalPrompt(), isTrue);
    });

    test('is suppressed for 24 hours after a dismissal', () async {
      final service = _service(
        client: MockClient((_) async => http.Response('', 404)),
        clock: () => now,
      );

      await service.snoozeOptionalPrompt();
      expect(await service.shouldShowOptionalPrompt(), isFalse);

      final later = _service(
        client: MockClient((_) async => http.Response('', 404)),
        clock: () => now.add(const Duration(hours: 23)),
      );
      expect(await later.shouldShowOptionalPrompt(), isFalse);

      final muchLater = _service(
        client: MockClient((_) async => http.Response('', 404)),
        clock: () => now.add(const Duration(hours: 25)),
      );
      expect(await muchLater.shouldShowOptionalPrompt(), isTrue);
    });

    test('clearCache resets the snooze and the verdict', () async {
      final service = _service(
        client: MockClient((_) async => http.Response('', 404)),
        clock: () => now,
      );
      await service.snoozeOptionalPrompt();

      await service.clearCache();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AppVersionService.prefOptionalSnoozedAt), isNull);
      expect(prefs.getString(AppVersionService.prefVerdict), isNull);
      expect(await service.shouldShowOptionalPrompt(), isTrue);
    });
  });
}

/// Stands in for a `dart:io` SocketException without importing it, so these
/// tests stay platform agnostic.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();

  @override
  String toString() => 'SocketExceptionStub: connection failed';
}
