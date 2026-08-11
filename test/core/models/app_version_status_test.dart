import 'package:flutter_test/flutter_test.dart';
import 'package:grozfy_go/core/models/app_version_status.dart';

void main() {
  group('AppVersionStatus.fromJson — server verdict', () {
    test('parses a mandatory update with all fields', () {
      final s = AppVersionStatus.fromJson({
        'update_required': true,
        'update_available': true,
        'min_supported_build': 5,
        'recommended_build': 7,
        'latest_version': '1.2.0',
        'store_url': 'https://play.google.com/store/apps/details?id=x',
        'title': 'Update required',
        'message': 'This version is no longer supported.',
        'release_notes': ['Faster sync', 'COD fixes'],
      }, currentBuild: 2);

      expect(s.requirement, AppUpdateRequirement.mandatory);
      expect(s.isBlocking, isTrue);
      expect(s.hasUpdate, isTrue);
      expect(s.minSupportedBuild, 5);
      expect(s.recommendedBuild, 7);
      expect(s.latestVersion, '1.2.0');
      expect(s.title, 'Update required');
      expect(s.releaseNotes, ['Faster sync', 'COD fixes']);
    });

    test('mandatory wins over optional when both are set', () {
      final s = AppVersionStatus.fromJson({
        'update_required': true,
        'update_available': true,
      }, currentBuild: 2);

      expect(s.requirement, AppUpdateRequirement.mandatory);
      expect(s.isOptional, isFalse);
    });

    test('parses an optional update', () {
      final s = AppVersionStatus.fromJson({
        'update_required': false,
        'update_available': true,
        'recommended_build': 7,
      }, currentBuild: 2);

      expect(s.requirement, AppUpdateRequirement.optional);
      expect(s.isBlocking, isFalse);
      expect(s.hasUpdate, isTrue);
    });

    test('server verdict overrides the build comparison in both directions',
        () {
      // Build is below the floor, but the server says it is fine.
      final allowed = AppVersionStatus.fromJson({
        'update_required': false,
        'min_supported_build': 9,
      }, currentBuild: 2);
      expect(allowed.requirement, AppUpdateRequirement.upToDate);

      // Build is above the floor, but the server blocks it anyway.
      final blocked = AppVersionStatus.fromJson({
        'update_required': true,
        'min_supported_build': 1,
      }, currentBuild: 9);
      expect(blocked.requirement, AppUpdateRequirement.mandatory);
    });

    test('reads booleans from 1/0, "1"/"0" and "true"/"false"', () {
      for (final dynamic truthy in <dynamic>[1, '1', 'true', 'TRUE', 'yes']) {
        expect(
          AppVersionStatus.fromJson({'update_required': truthy}).isMandatory,
          isTrue,
          reason: 'expected $truthy to be truthy',
        );
      }
      for (final dynamic falsey in <dynamic>[0, '0', 'false', 'no']) {
        expect(
          AppVersionStatus.fromJson({'update_required': falsey}).isMandatory,
          isFalse,
          reason: 'expected $falsey to be falsey',
        );
      }
    });
  });

  group('AppVersionStatus.fromJson — build-number fallback', () {
    test('derives mandatory when the build is below the floor', () {
      final s = AppVersionStatus.fromJson({
        'min_supported_build': 3,
      }, currentBuild: 2);

      expect(s.requirement, AppUpdateRequirement.mandatory);
    });

    test('build equal to the floor is supported', () {
      final s = AppVersionStatus.fromJson({
        'min_supported_build': 2,
      }, currentBuild: 2);

      expect(s.requirement, AppUpdateRequirement.upToDate);
    });

    test('derives optional when below the recommended build only', () {
      final s = AppVersionStatus.fromJson({
        'min_supported_build': 1,
        'recommended_build': 7,
      }, currentBuild: 2);

      expect(s.requirement, AppUpdateRequirement.optional);
    });

    test('min_supported_build of 0 means no floor, not "block everything"', () {
      final s = AppVersionStatus.fromJson({
        'min_supported_build': 0,
      }, currentBuild: 2);

      expect(s.requirement, AppUpdateRequirement.upToDate);
    });

    test('a negative floor is clamped to no floor', () {
      final s = AppVersionStatus.fromJson({
        'min_supported_build': -5,
      }, currentBuild: 2);

      expect(s.minSupportedBuild, 0);
      expect(s.requirement, AppUpdateRequirement.upToDate);
    });

    test('unknown build number never blocks, however high the floor', () {
      final s = AppVersionStatus.fromJson({
        'min_supported_build': 999,
      }, currentBuild: 0);

      expect(s.requirement, AppUpdateRequirement.upToDate);
    });
  });

  group('AppVersionStatus.fromJson — malformed payloads fail open', () {
    test('an empty payload is up to date', () {
      final s = AppVersionStatus.fromJson(<String, dynamic>{}, currentBuild: 2);

      expect(s.requirement, AppUpdateRequirement.upToDate);
      expect(s.storeUrl, isEmpty);
      expect(s.releaseNotes, isEmpty);
    });

    test('garbage field types do not block', () {
      final s = AppVersionStatus.fromJson({
        'update_required': <String, dynamic>{'nested': 'object'},
        'min_supported_build': 'not-a-number',
        'release_notes': 'not-a-list',
      }, currentBuild: 2);

      expect(s.requirement, AppUpdateRequirement.upToDate);
      expect(s.minSupportedBuild, 0);
      expect(s.releaseNotes, isEmpty);
    });

    test('an unrecognised boolean encoding falls back to build comparison', () {
      final s = AppVersionStatus.fromJson({
        'update_required': 'maybe',
        'min_supported_build': 5,
      }, currentBuild: 2);

      expect(s.requirement, AppUpdateRequirement.mandatory);
    });

    test('numeric strings are still read as build numbers', () {
      final s = AppVersionStatus.fromJson({
        'min_supported_build': '5',
      }, currentBuild: 2);

      expect(s.minSupportedBuild, 5);
      expect(s.requirement, AppUpdateRequirement.mandatory);
    });
  });

  group('store URL sanitisation', () {
    test('keeps https, market and itms-apps links', () {
      const List<String> allowed = <String>[
        'https://play.google.com/store/apps/details?id=com.grozfy.go',
        'market://details?id=com.grozfy.go',
        'itms-apps://apps.apple.com/app/id123',
      ];
      for (final String url in allowed) {
        expect(
          AppVersionStatus.fromJson({'store_url': url}).storeUrl,
          url,
          reason: '$url should be preserved',
        );
      }
    });

    test('drops unsupported schemes and unparseable values', () {
      const List<String> rejected = <String>[
        'javascript:alert(1)',
        'play.google.com/store',
        '',
      ];
      for (final String url in rejected) {
        expect(
          AppVersionStatus.fromJson({'store_url': url}).storeUrl,
          isEmpty,
          reason: '$url should be dropped',
        );
      }
    });
  });

  group('cache round-trip', () {
    test('toJson/fromJson preserves the verdict and its fields', () {
      final original = AppVersionStatus.fromJson({
        'update_required': true,
        'min_supported_build': 5,
        'recommended_build': 7,
        'latest_version': '1.2.0',
        'store_url': 'https://play.google.com/store/apps/details?id=x',
        'title': 'Update required',
        'message': 'Please update.',
        'release_notes': ['One', 'Two'],
      }, currentBuild: 2);

      final DateTime at = DateTime.utc(2026, 8, 6, 10);
      final restored = AppVersionStatus.fromJson(
        original.toJson(),
        currentBuild: 2,
        checkedAt: at,
      );

      expect(restored.requirement, original.requirement);
      expect(restored.minSupportedBuild, 5);
      expect(restored.recommendedBuild, 7);
      expect(restored.latestVersion, '1.2.0');
      expect(restored.storeUrl, original.storeUrl);
      expect(restored.title, 'Update required');
      expect(restored.message, 'Please update.');
      expect(restored.releaseNotes, ['One', 'Two']);
      expect(restored.checkedAt, at);
    });

    test('an optional verdict survives the round trip as optional', () {
      final original = AppVersionStatus.fromJson({
        'update_available': true,
      }, currentBuild: 2);

      final restored = AppVersionStatus.fromJson(original.toJson());

      expect(restored.requirement, AppUpdateRequirement.optional);
    });
  });

  test('the up-to-date constant carries no update', () {
    const s = AppVersionStatus.upToDate();

    expect(s.requirement, AppUpdateRequirement.upToDate);
    expect(s.isBlocking, isFalse);
    expect(s.hasUpdate, isFalse);
    expect(s.checkedAt, isNull);
  });
}
