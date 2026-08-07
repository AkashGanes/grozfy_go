import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:grozfy_go/core/models/app_version_status.dart';
import 'package:grozfy_go/core/services/app_version_service.dart';
import 'package:grozfy_go/core/state/app_controller.dart';

Future<PackageInfo> _packageInfo() async => PackageInfo(
  appName: 'Grozfy Go',
  packageName: 'com.grozfy.go',
  version: '1.0.1',
  buildNumber: '2',
);

String _body(Map<String, dynamic> message) =>
    jsonEncode(<String, dynamic>{'message': message});

/// Builds a controller whose version service talks to [responder], and reports
/// how many network calls were made.
({AppController controller, int Function() calls}) _harness(
  Map<String, dynamic> message,
) {
  var calls = 0;
  final client = MockClient((_) async {
    calls++;
    return http.Response(_body(message), 200);
  });

  final controller = AppController(
    appVersionService: AppVersionService(
      client: client,
      packageInfoLoader: _packageInfo,
      platformName: 'android',
    ),
  );

  return (controller: controller, calls: () => calls);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('starts unblocked before any check runs', () {
    final h = _harness(<String, dynamic>{'update_required': true});

    expect(h.controller.isUpdateBlocking, isFalse);
    expect(
      h.controller.versionStatus.requirement,
      AppUpdateRequirement.upToDate,
    );
    expect(h.calls(), 0);
  });

  test('a mandatory verdict blocks the app', () async {
    final h = _harness(<String, dynamic>{
      'update_required': true,
      'latest_version': '1.2.0',
    });

    await h.controller.checkAppVersion();

    expect(h.controller.isUpdateBlocking, isTrue);
    expect(h.controller.versionStatus.latestVersion, '1.2.0');
  });

  test('an optional verdict prompts without blocking', () async {
    final h = _harness(<String, dynamic>{'update_available': true});

    await h.controller.checkAppVersion();

    expect(h.controller.isUpdateBlocking, isFalse);
    expect(h.controller.shouldPromptOptionalUpdate, isTrue);
  });

  test('repeat checks are throttled, force bypasses the throttle', () async {
    final h = _harness(<String, dynamic>{'update_available': true});

    await h.controller.checkAppVersion();
    expect(h.calls(), 1);

    // Inside the 30-minute window — no second request.
    await h.controller.checkAppVersion();
    expect(h.calls(), 1);

    await h.controller.checkAppVersion(force: true);
    expect(h.calls(), 2);
  });

  test(
    'dismissing the optional prompt hides it and persists the snooze',
    () async {
      final h = _harness(<String, dynamic>{'update_available': true});
      await h.controller.checkAppVersion();
      expect(h.controller.shouldPromptOptionalUpdate, isTrue);

      await h.controller.dismissOptionalUpdate();

      expect(h.controller.shouldPromptOptionalUpdate, isFalse);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(AppVersionService.prefOptionalSnoozedAt),
        isNotNull,
      );
    },
  );

  test(
    'a snoozed optional update does not re-prompt on the next check',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        AppVersionService.prefOptionalSnoozedAt: DateTime.now()
            .toUtc()
            .toIso8601String(),
      });
      final h = _harness(<String, dynamic>{'update_available': true});

      await h.controller.checkAppVersion();

      expect(h.controller.shouldPromptOptionalUpdate, isFalse);
    },
  );

  test('a mandatory verdict ignores the optional snooze', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      AppVersionService.prefOptionalSnoozedAt: DateTime.now()
          .toUtc()
          .toIso8601String(),
    });
    final h = _harness(<String, dynamic>{'update_required': true});

    await h.controller.checkAppVersion();

    expect(h.controller.isUpdateBlocking, isTrue);
  });

  test(
    '"Later" on a mandatory verdict clears the block for this session',
    () async {
      final h = _harness(<String, dynamic>{'update_required': true});
      await h.controller.checkAppVersion();
      expect(h.controller.isUpdateBlocking, isTrue);

      h.controller.dismissMandatoryUpdate();

      expect(h.controller.isUpdateBlocking, isFalse);
      // The verdict itself is untouched — only its presentation was dismissed.
      expect(h.controller.versionStatus.isMandatory, isTrue);
    },
  );

  test(
    'a mandatory "Later" is never written to disk, so a relaunch re-prompts',
    () async {
      final h = _harness(<String, dynamic>{'update_required': true});
      await h.controller.checkAppVersion();
      h.controller.dismissMandatoryUpdate();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString(AppVersionService.prefOptionalSnoozedAt),
        isNull,
        reason: 'a mandatory dismissal must not borrow the optional snooze',
      );

      // A fresh controller is what a relaunch produces.
      final fresh = _harness(<String, dynamic>{'update_required': true});
      await fresh.controller.checkAppVersion();
      expect(fresh.controller.isUpdateBlocking, isTrue);
    },
  );

  test('a backend that 404s leaves the app usable', () async {
    final controller = AppController(
      appVersionService: AppVersionService(
        client: MockClient((_) async => http.Response('Not Found', 404)),
        packageInfoLoader: _packageInfo,
        platformName: 'android',
      ),
    );

    await controller.checkAppVersion();

    expect(controller.isUpdateBlocking, isFalse);
    expect(controller.shouldPromptOptionalUpdate, isFalse);
  });

  test('notifies listeners when a blocking verdict arrives', () async {
    final h = _harness(<String, dynamic>{'update_required': true});
    var notified = 0;
    h.controller.addListener(() => notified++);

    await h.controller.checkAppVersion();

    expect(notified, greaterThan(0));
  });
}
