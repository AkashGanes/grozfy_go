import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Secure storage for auth credentials. Wraps `flutter_secure_storage` which
/// uses the Android Keystore / iOS Keychain. All seven keys here hold
/// sensitive material and must never live in plain SharedPreferences.
class SecureTokenStorage {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static const String accessToken = 'access_token';
  static const String refreshToken = 'refresh_token';
  static const String tokenType = 'token_type';
  static const String expiresIn = 'expires_in';
  static const String apiKey = 'api_key';
  static const String apiSecret = 'api_secret';
  static const String clientId = 'client_id';

  static const List<String> allKeys = <String>[
    accessToken,
    refreshToken,
    tokenType,
    expiresIn,
    apiKey,
    apiSecret,
    clientId,
  ];

  static Future<String?> read(String key) => _storage.read(key: key);

  static Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  static Future<void> delete(String key) => _storage.delete(key: key);

  static Future<void> deleteAll() async {
    for (final String key in allKeys) {
      await _storage.delete(key: key);
    }
  }

  /// One-time migration: move any of the seven auth keys already present in
  /// plain SharedPreferences into secure storage, then remove them from
  /// SharedPreferences. Safe to call on every boot.
  static Future<void> migrateFromPreferences(SharedPreferences prefs) async {
    for (final String key in allKeys) {
      if (!prefs.containsKey(key)) continue;
      final Object? existing = prefs.get(key);
      if (existing == null) {
        await prefs.remove(key);
        continue;
      }
      final String stringified = existing.toString();
      if (stringified.isNotEmpty) {
        final String? already = await _storage.read(key: key);
        if (already == null || already.isEmpty) {
          await _storage.write(key: key, value: stringified);
        }
      }
      await prefs.remove(key);
    }
  }
}
