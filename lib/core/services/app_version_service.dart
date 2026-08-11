import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/api_constants.dart';
import '../models/app_version_status.dart';

/// Asks the backend whether the build running on this device is still
/// supported.
///
/// The whole class is built around one rule: **a driver must never be locked
/// out by a failure.** Every error path — no network, timeout, HTTP 500, the
/// 404 returned before the endpoint is deployed, a body we cannot parse, a
/// platform channel that is unavailable — resolves to
/// [AppVersionStatus.upToDate].
///
/// The one concession to that rule is the expiring cache. A successful verdict
/// is persisted, and if a later check fails we re-apply the cached verdict for
/// up to [cacheTtl]. That stops "turn on airplane mode to skip the update"
/// without ever becoming permanent: once the cache ages out, a device that
/// cannot reach the backend is unblocked. A device that has never had a
/// successful check — a fresh install — is never blocked.
class AppVersionService {
  AppVersionService({
    http.Client? client,
    Future<PackageInfo> Function()? packageInfoLoader,
    String? platformName,
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
       _platformName = platformName ?? _defaultPlatformName(),
       _clock = clock ?? DateTime.now;

  final http.Client _client;
  final Future<PackageInfo> Function() _packageInfoLoader;
  final String _platformName;
  final DateTime Function() _clock;

  /// Deliberately shorter than the app's usual 15s network timeout: this call
  /// sits in front of the splash screen and on the resume path, so it must
  /// never be what a driver is waiting on.
  static const Duration requestTimeout = Duration(seconds: 6);

  /// How long a successful verdict stays usable once checks start failing.
  static const Duration cacheTtl = Duration(hours: 24);

  /// How long "Later" suppresses the optional prompt.
  static const Duration optionalSnooze = Duration(hours: 24);

  static const String prefVerdict = 'app_version_verdict';
  static const String prefCheckedAt = 'app_version_checked_at';
  static const String prefOptionalSnoozedAt = 'app_version_optional_snoozed_at';

  static String _defaultPlatformName() {
    try {
      return Platform.isIOS ? 'ios' : 'android';
    } catch (_) {
      // No dart:io platform (tests, web). Android is the only shipping
      // target today and the server treats an unknown platform as
      // unconstrained anyway.
      return 'android';
    }
  }

  /// Runs the check. Never throws.
  Future<AppVersionStatus> check() async {
    final _RunningBuild? build = await _resolveRunningBuild();
    if (build == null || build.buildNumber <= 0) {
      // Without our own build number there is nothing to compare and nothing
      // the server could safely tell us, so don't even make the call.
      return const AppVersionStatus.upToDate();
    }

    final Uri uri = Uri.parse(ApiConstants.appVersionCheck).replace(
      queryParameters: <String, String>{
        'platform': _platformName,
        'version': build.version,
        'build_number': build.buildNumber.toString(),
      },
    );

    http.Response response;
    try {
      response = await _client
          .get(uri, headers: const <String, String>{'Accept': 'application/json'})
          .timeout(requestTimeout);
    } catch (error) {
      // Offline, DNS failure, timeout, TLS error — all indistinguishable and
      // all non-authoritative.
      debugPrint('[AppVersion] check failed to reach backend: $error');
      return _cachedVerdict();
    }

    if (response.statusCode != 200) {
      // 404 is the expected response until the backend method is deployed.
      debugPrint('[AppVersion] check returned HTTP ${response.statusCode}');
      return _cachedVerdict();
    }

    final Map<String, dynamic>? message = _readMessageEnvelope(response.body);
    if (message == null) {
      debugPrint('[AppVersion] check returned an unreadable body');
      return _cachedVerdict();
    }

    final DateTime now = _clock();
    final AppVersionStatus status = AppVersionStatus.fromJson(
      message,
      currentBuild: build.buildNumber,
      checkedAt: now,
    );

    await _persist(status, now);
    return status;
  }

  /// Whether the dismissible prompt is due, honouring the driver's last
  /// "Later". Mandatory blocks never consult this.
  Future<bool> shouldShowOptionalPrompt() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(prefOptionalSnoozedAt);
      if (raw == null || raw.isEmpty) return true;

      final DateTime? snoozedAt = DateTime.tryParse(raw);
      if (snoozedAt == null) return true;

      return _elapsedSince(snoozedAt) >= optionalSnooze;
    } catch (error) {
      debugPrint('[AppVersion] could not read snooze state: $error');
      return true;
    }
  }

  Future<void> snoozeOptionalPrompt() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        prefOptionalSnoozedAt,
        _clock().toUtc().toIso8601String(),
      );
    } catch (error) {
      debugPrint('[AppVersion] could not persist snooze state: $error');
    }
  }

  /// Drops the cached verdict and the snooze.
  ///
  /// Deliberately *not* called on logout: the verdict is about the build
  /// installed on this device, not about the signed-in driver, so clearing it
  /// at logout would turn "log out, go offline, log back in" into a way around
  /// a mandatory block. Exists for tests and for a future "reset app data"
  /// affordance.
  Future<void> clearCache() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(prefVerdict);
      await prefs.remove(prefCheckedAt);
      await prefs.remove(prefOptionalSnoozedAt);
    } catch (error) {
      debugPrint('[AppVersion] could not clear cache: $error');
    }
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<_RunningBuild?> _resolveRunningBuild() async {
    try {
      final PackageInfo info = await _packageInfoLoader();
      return _RunningBuild(
        version: info.version.trim(),
        buildNumber: int.tryParse(info.buildNumber.trim()) ?? 0,
      );
    } catch (error) {
      // No platform channel (widget tests, unsupported host).
      debugPrint('[AppVersion] could not read package info: $error');
      return null;
    }
  }

  /// Frappe wraps whitelisted method results in `{"message": {...}}`.
  Map<String, dynamic>? _readMessageEnvelope(String body) {
    if (body.trim().isEmpty) return null;
    try {
      final dynamic decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;
      final dynamic message = decoded['message'];
      if (message is Map<String, dynamic>) return message;
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist(AppVersionStatus status, DateTime checkedAt) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefVerdict, jsonEncode(status.toJson()));
      await prefs.setString(
        prefCheckedAt,
        checkedAt.toUtc().toIso8601String(),
      );
    } catch (error) {
      // A verdict we cannot cache is still a verdict we can act on now.
      debugPrint('[AppVersion] could not cache verdict: $error');
    }
  }

  /// The last successful verdict, if it is still inside [cacheTtl]. Anything
  /// else — no cache, unreadable cache, expired cache — is up to date.
  Future<AppVersionStatus> _cachedVerdict() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? rawVerdict = prefs.getString(prefVerdict);
      final String? rawCheckedAt = prefs.getString(prefCheckedAt);
      if (rawVerdict == null ||
          rawVerdict.isEmpty ||
          rawCheckedAt == null ||
          rawCheckedAt.isEmpty) {
        return const AppVersionStatus.upToDate();
      }

      final DateTime? checkedAt = DateTime.tryParse(rawCheckedAt);
      if (checkedAt == null) return const AppVersionStatus.upToDate();

      if (_elapsedSince(checkedAt) >= cacheTtl) {
        // Stale. A device that cannot reach the backend for a day gets the
        // benefit of the doubt rather than a permanent block.
        return const AppVersionStatus.upToDate();
      }

      final dynamic decoded = jsonDecode(rawVerdict);
      if (decoded is! Map<String, dynamic>) {
        return const AppVersionStatus.upToDate();
      }

      return AppVersionStatus.fromJson(decoded, checkedAt: checkedAt);
    } catch (error) {
      debugPrint('[AppVersion] could not read cached verdict: $error');
      return const AppVersionStatus.upToDate();
    }
  }

  /// A timestamp in the future means the device clock moved backwards since it
  /// was written; treat that as "just now" rather than as instantly expired.
  Duration _elapsedSince(DateTime timestamp) {
    final Duration elapsed = _clock().toUtc().difference(timestamp.toUtc());
    return elapsed.isNegative ? Duration.zero : elapsed;
  }
}

@immutable
class _RunningBuild {
  const _RunningBuild({required this.version, required this.buildNumber});

  final String version;
  final int buildNumber;
}
