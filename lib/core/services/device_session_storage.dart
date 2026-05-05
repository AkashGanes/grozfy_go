import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secure_token_storage.dart';

/// Persistent device-session storage for OEM-cleaner recovery.
///
/// On Android, OEMs like vivo / MIUI / OneUI's Smart Switch can wipe
/// the entire app data directory while the app is idle. When that
/// happens both `SecureTokenStorage` and `SharedPreferences` go with
/// it, and the user is forced to log in fresh. To survive that, we
/// persist the device session across THREE tiers:
///
///   1. `SecureTokenStorage` (encrypted, AndroidX EncryptedSharedPreferences
///      or iOS Keychain).
///   2. Plain `SharedPreferences` under separate keys — same
///      `/data/data/<pkg>/shared_prefs/` directory but a different
///      file than the secure-storage XML, which some OEM cleaners
///      treat differently.
///   3. A file in `getApplicationDocumentsDirectory()` —
///      `/data/data/<pkg>/app_flutter/` on Android — yet another
///      filesystem location with a different cleanup heuristic.
///
/// Reads return the first non-null value across the three tiers.
/// Writes always fan out to all three. Clears wipe all three. The
/// idea is that if one tier is wiped between sessions the others
/// can still hand back the credential, and the next successful
/// `setCredential` will repopulate the wiped tier.
///
/// The two values stored:
///
/// - `deviceId`: stable UUID v4 generated on first run, never
///   changes for the lifetime of this install.
/// - `deviceCredential`: rotating opaque token issued by the server.
///   Replaces every time the client exchanges it for fresh OAuth
///   tokens. Always treat the latest write as authoritative.
class DeviceSessionStorage {
  static const String _kDeviceId = 'device_session_id';
  static const String _kDeviceCredential = 'device_session_credential';
  static const String _fileName = 'device_session.txt';

  static String? _cachedDeviceId;

  /// Returns the persistent device UUID, generating + persisting one
  /// on first call. Cached in memory after first read.
  static Future<String> getOrCreateDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final String? existing = await _readFromAnyTier(_kDeviceId);
    if (existing != null && existing.isNotEmpty) {
      _cachedDeviceId = existing;
      // Re-fan-out so any wiped tier gets repopulated.
      await _writeToAllTiers(_kDeviceId, existing);
      return existing;
    }
    final String generated = _newUuidV4();
    _cachedDeviceId = generated;
    await _writeToAllTiers(_kDeviceId, generated);
    return generated;
  }

  static Future<String?> getCredential() async {
    return _readFromAnyTier(_kDeviceCredential);
  }

  static Future<void> setCredential(String credential) async {
    if (credential.isEmpty) return;
    await _writeToAllTiers(_kDeviceCredential, credential);
  }

  static Future<void> clearCredential() async {
    await _deleteFromAllTiers(_kDeviceCredential);
  }

  /// Wipe the device id too. Only call on full account reset; the
  /// device_id is meant to be stable for the install's lifetime.
  static Future<void> clearAll() async {
    _cachedDeviceId = null;
    await _deleteFromAllTiers(_kDeviceId);
    await _deleteFromAllTiers(_kDeviceCredential);
  }

  // ─── tiered IO ─────────────────────────────────────────────────

  static Future<String?> _readFromAnyTier(String key) async {
    try {
      final String? secure = await SecureTokenStorage.read(key);
      if (secure != null && secure.isNotEmpty) return secure;
    } catch (e) {
      debugPrint('[DeviceSessionStorage] secure read("$key") err: $e');
    }
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? plain = prefs.getString(key);
      if (plain != null && plain.isNotEmpty) return plain;
    } catch (e) {
      debugPrint('[DeviceSessionStorage] prefs read("$key") err: $e');
    }
    try {
      final File file = await _file();
      if (await file.exists()) {
        final Map<String, String> kv = _parseKv(await file.readAsString());
        final String? v = kv[key];
        if (v != null && v.isNotEmpty) return v;
      }
    } catch (e) {
      debugPrint('[DeviceSessionStorage] file read("$key") err: $e');
    }
    return null;
  }

  static Future<void> _writeToAllTiers(String key, String value) async {
    try {
      await SecureTokenStorage.write(key, value);
    } catch (e) {
      debugPrint('[DeviceSessionStorage] secure write("$key") err: $e');
    }
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (e) {
      debugPrint('[DeviceSessionStorage] prefs write("$key") err: $e');
    }
    try {
      final File file = await _file();
      final Map<String, String> kv = <String, String>{};
      if (await file.exists()) {
        kv.addAll(_parseKv(await file.readAsString()));
      }
      kv[key] = value;
      await file.writeAsString(_serializeKv(kv), flush: true);
    } catch (e) {
      debugPrint('[DeviceSessionStorage] file write("$key") err: $e');
    }
  }

  static Future<void> _deleteFromAllTiers(String key) async {
    try {
      await SecureTokenStorage.delete(key);
    } catch (_) {}
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
    try {
      final File file = await _file();
      if (await file.exists()) {
        final Map<String, String> kv = _parseKv(await file.readAsString());
        kv.remove(key);
        if (kv.isEmpty) {
          await file.delete();
        } else {
          await file.writeAsString(_serializeKv(kv), flush: true);
        }
      }
    } catch (_) {}
  }

  static Future<File> _file() async {
    final Directory dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Map<String, String> _parseKv(String content) {
    final Map<String, String> out = <String, String>{};
    for (final String line in content.split('\n')) {
      final int eq = line.indexOf('=');
      if (eq <= 0) continue;
      final String k = line.substring(0, eq).trim();
      final String v = line.substring(eq + 1).trim();
      if (k.isNotEmpty && v.isNotEmpty) out[k] = v;
    }
    return out;
  }

  static String _serializeKv(Map<String, String> kv) {
    final StringBuffer sb = StringBuffer();
    kv.forEach((String k, String v) {
      // Strip newlines defensively — values are random hex/UUIDs so
      // legitimate inputs never contain them.
      sb.writeln(
        '${k.replaceAll('\n', '')}=${v.replaceAll('\n', '')}',
      );
    });
    return sb.toString();
  }

  static String _newUuidV4() {
    // RFC 4122 v4 UUID using a cryptographically secure RNG. Avoids
    // pulling in the `uuid` package for one call.
    final Random rng = Random.secure();
    final List<int> bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3F) | 0x80; // RFC 4122 variant
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final String h = bytes.map(hex).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-'
        '${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }
}
