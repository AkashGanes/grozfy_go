import 'package:flutter/foundation.dart';

/// How urgently the running build needs to be replaced.
enum AppUpdateRequirement {
  /// Nothing to show. Also the verdict used for every failure path — see
  /// [AppVersionStatus.upToDate].
  upToDate,

  /// Newer build exists, this one still works. Dismissible prompt.
  optional,

  /// This build is below the supported floor. Hard block.
  mandatory,
}

/// The server's verdict on the build currently running on this device.
///
/// Every parse path in here is deliberately biased towards
/// [AppUpdateRequirement.upToDate]: a malformed payload, an unknown field
/// encoding or a missing floor must never lock a driver out of the app. The
/// only way to reach [AppUpdateRequirement.mandatory] is an explicit,
/// well-formed instruction from the backend (or an explicit build floor the
/// running build sits below).
@immutable
class AppVersionStatus {
  const AppVersionStatus({
    required this.requirement,
    this.latestVersion = '',
    this.minSupportedBuild = 0,
    this.recommendedBuild = 0,
    this.storeUrl = '',
    this.title = '',
    this.message = '',
    this.releaseNotes = const <String>[],
    this.checkedAt,
  });

  /// The safe verdict. Returned whenever the app cannot positively establish
  /// that the running build is unsupported — no network, no cache, HTTP error,
  /// unparseable body, or a backend that hasn't deployed the endpoint yet.
  const AppVersionStatus.upToDate()
    : requirement = AppUpdateRequirement.upToDate,
      latestVersion = '',
      minSupportedBuild = 0,
      recommendedBuild = 0,
      storeUrl = '',
      title = '',
      message = '',
      releaseNotes = const <String>[],
      checkedAt = null;

  final AppUpdateRequirement requirement;

  /// Marketing version of the newest build in the store, for display only.
  final String latestVersion;

  /// Builds below this are unsupported. 0 means "no floor configured".
  final int minSupportedBuild;

  /// Builds below this get the dismissible prompt. 0 means "no recommendation".
  final int recommendedBuild;

  /// Validated store deep link — see [_sanitizeStoreUrl]. Empty when the
  /// backend sent nothing usable, in which case the UI falls back to support.
  final String storeUrl;

  final String title;
  final String message;
  final List<String> releaseNotes;

  /// When this verdict was obtained from the server. Null for
  /// [AppVersionStatus.upToDate] and for verdicts that never round-tripped
  /// through the cache.
  final DateTime? checkedAt;

  bool get isMandatory => requirement == AppUpdateRequirement.mandatory;
  bool get isOptional => requirement == AppUpdateRequirement.optional;

  /// True when the driver must be prevented from using the app.
  bool get isBlocking => isMandatory;

  /// True when there is something to show the driver at all.
  bool get hasUpdate => requirement != AppUpdateRequirement.upToDate;

  /// Parses the `message` envelope of `check_app_version`.
  ///
  /// [currentBuild] is the build number running on this device. It is only
  /// consulted when the backend omits the explicit `update_required` /
  /// `update_available` booleans — the server's own verdict always wins, so
  /// policy can change without an app release.
  factory AppVersionStatus.fromJson(
    Map<String, dynamic> json, {
    int currentBuild = 0,
    DateTime? checkedAt,
  }) {
    final int minSupportedBuild = _readInt(json['min_supported_build']);
    final int recommendedBuild = _readInt(json['recommended_build']);

    final bool? serverRequired = _readBoolOrNull(json['update_required']);
    final bool? serverAvailable = _readBoolOrNull(json['update_available']);

    // A build floor only bites when we actually know our own build number.
    // currentBuild == 0 means PackageInfo was unavailable, so we cannot
    // compare and must not block.
    final bool derivedRequired =
        currentBuild > 0 &&
        minSupportedBuild > 0 &&
        currentBuild < minSupportedBuild;
    final bool derivedAvailable =
        currentBuild > 0 &&
        recommendedBuild > 0 &&
        currentBuild < recommendedBuild;

    final bool mandatory = serverRequired ?? derivedRequired;
    final bool optional = serverAvailable ?? derivedAvailable;

    final AppUpdateRequirement requirement = mandatory
        ? AppUpdateRequirement.mandatory
        : (optional
              ? AppUpdateRequirement.optional
              : AppUpdateRequirement.upToDate);

    return AppVersionStatus(
      requirement: requirement,
      latestVersion: _readString(json['latest_version']),
      minSupportedBuild: minSupportedBuild,
      recommendedBuild: recommendedBuild,
      storeUrl: _sanitizeStoreUrl(_readString(json['store_url'])),
      title: _readString(json['title']),
      message: _readString(json['message']),
      releaseNotes: _readStringList(json['release_notes']),
      checkedAt: checkedAt,
    );
  }

  /// Round-trips through SharedPreferences. Keys are the wire format's so a
  /// cached payload and a fresh one parse identically.
  Map<String, dynamic> toJson() => <String, dynamic>{
    'update_required': isMandatory,
    'update_available': isOptional,
    'min_supported_build': minSupportedBuild,
    'recommended_build': recommendedBuild,
    'latest_version': latestVersion,
    'store_url': storeUrl,
    'title': title,
    'message': message,
    'release_notes': releaseNotes,
  };

  AppVersionStatus copyWith({DateTime? checkedAt}) => AppVersionStatus(
    requirement: requirement,
    latestVersion: latestVersion,
    minSupportedBuild: minSupportedBuild,
    recommendedBuild: recommendedBuild,
    storeUrl: storeUrl,
    title: title,
    message: message,
    releaseNotes: releaseNotes,
    checkedAt: checkedAt ?? this.checkedAt,
  );

  // ---------------------------------------------------------------------------
  // Field readers — every one of them defaults to the harmless value.
  // ---------------------------------------------------------------------------

  /// Null when the field is absent or encoded in a way we don't recognise, so
  /// callers can fall back to comparing build numbers instead of treating an
  /// unknown encoding as `false`.
  static bool? _readBoolOrNull(dynamic raw) {
    if (raw == null) return null;
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    if (raw is String) {
      final String value = raw.trim().toLowerCase();
      if (value.isEmpty) return null;
      if (value == '1' || value == 'true' || value == 'yes') return true;
      if (value == '0' || value == 'false' || value == 'no') return false;
    }
    return null;
  }

  static int _readInt(dynamic raw) {
    if (raw is int) return raw < 0 ? 0 : raw;
    if (raw is num) return raw < 0 ? 0 : raw.toInt();
    if (raw is String) {
      final int parsed = int.tryParse(raw.trim()) ?? 0;
      return parsed < 0 ? 0 : parsed;
    }
    return 0;
  }

  static String _readString(dynamic raw) {
    if (raw == null) return '';
    return raw.toString().trim();
  }

  static List<String> _readStringList(dynamic raw) {
    if (raw is! List) return const <String>[];
    return raw
        .map((dynamic entry) => entry?.toString().trim() ?? '')
        .where((String entry) => entry.isNotEmpty)
        .toList(growable: false);
  }

  /// Only schemes that can actually open a store listing are allowed through.
  /// Anything else (a `javascript:` URL, a typo, a bare domain) becomes empty
  /// rather than being handed to `launchUrl`.
  static const Set<String> _allowedStoreSchemes = <String>{
    'https',
    'http',
    'market',
    'itms-apps',
    'itms-appss',
  };

  static String _sanitizeStoreUrl(String raw) {
    if (raw.isEmpty) return '';
    final Uri? uri = Uri.tryParse(raw);
    if (uri == null || !uri.hasScheme) return '';
    if (!_allowedStoreSchemes.contains(uri.scheme.toLowerCase())) return '';
    return raw;
  }

  @override
  String toString() =>
      'AppVersionStatus(${requirement.name}, latest: $latestVersion, '
      'minBuild: $minSupportedBuild, recommendedBuild: $recommendedBuild)';
}
