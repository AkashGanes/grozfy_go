import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../logging/app_logger.dart';

/// Secure storage for auth credentials. All seven keys here hold sensitive
/// material and must never live in plain SharedPreferences.
///
/// Android: uses `EncryptedSharedPreferences` (AndroidX Security) — survives
/// app updates and OEM key rotations far better than the raw Keystore. The
/// `resetOnError` flag drops a corrupt blob silently so callers see a clean
/// `null` instead of an exception (we'd lose the value either way; better
/// to fail to "logged out" than to crash).
///
/// iOS: `first_unlock_this_device` accessibility means the keychain entry is
/// readable as soon as the user has unlocked the phone once after boot,
/// without iCloud sync. Default would be `unlocked` which would fail any
/// background reads while the screen is locked.
///
/// Every read/write/delete is wrapped in try/catch and logged in debug
/// builds. We never want a flaky platform-side call to silently break the
/// auth flow — silent nulls are how we ended up with the cold-start
/// `AuthenticationError` regression.
class SecureTokenStorage {
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      resetOnError: true,
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const String accessToken = 'access_token';
  static const String refreshToken = 'refresh_token';
  static const String tokenType = 'token_type';
  static const String expiresIn = 'expires_in';
  static const String accessTokenExpiresAt = 'access_token_expires_at';
  static const String apiKey = 'api_key';
  static const String apiSecret = 'api_secret';
  static const String clientId = 'client_id';

  static const List<String> allKeys = <String>[
    accessToken,
    refreshToken,
    tokenType,
    expiresIn,
    accessTokenExpiresAt,
    apiKey,
    apiSecret,
    clientId,
  ];

  static Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e, st) {
      AppLogger.auth.error('read("$key") failed', error: e, stackTrace: st);
      return null;
    }
  }

  static Future<bool> write(String key, String value) async {
    try {
      await _storage.write(key: key, value: value);
      return true;
    } catch (e, st) {
      AppLogger.auth.error('write("$key") failed', error: e, stackTrace: st);
      return false;
    }
  }

  static Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (e, st) {
      AppLogger.auth.error('delete("$key") failed', error: e, stackTrace: st);
    }
  }

  static Future<void> deleteAll() async {
    for (final String key in allKeys) {
      await delete(key);
    }
  }

  /// One-time migration: move any of the seven auth keys already present in
  /// plain SharedPreferences into secure storage, then remove them from
  /// SharedPreferences. Safe to call on every boot. Failures during the
  /// secure-write are logged but don't block the migration — the value
  /// stays in SharedPreferences for the next attempt instead of being
  /// orphaned.
  static Future<void> migrateFromPreferences(SharedPreferences prefs) async {
    for (final String key in allKeys) {
      if (!prefs.containsKey(key)) continue;
      final Object? existing = prefs.get(key);
      if (existing == null) {
        await prefs.remove(key);
        continue;
      }
      final String stringified = existing.toString();
      if (stringified.isEmpty) {
        await prefs.remove(key);
        continue;
      }
      final String? already = await read(key);
      if (already != null && already.isNotEmpty) {
        // Secure storage already has a value — drop the plain copy.
        await prefs.remove(key);
        continue;
      }
      final bool wrote = await write(key, stringified);
      if (wrote) {
        await prefs.remove(key);
      } else {
        AppLogger.auth.warning(
          'Migration kept "$key" in prefs (secure write failed; will retry on next boot)',
        );
      }
    }
  }
}
