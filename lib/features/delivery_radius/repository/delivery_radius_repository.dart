import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/services/secure_token_storage.dart';
import '../model/delivery_radius_settings.dart';

/// Talks to the Delivery Radius backend methods. Self-contained auth handling
/// mirrors the other feature repositories (e.g. CodSettlementRepository): build
/// bearer headers from [SecureTokenStorage], transparently refresh the OAuth
/// session once on 401/403, and normalise Frappe error envelopes into readable
/// messages.
class DeliveryRadiusRepository {
  static const Duration _networkTimeout = Duration(seconds: 15);
  static const Set<int> _okCodes = {200, 201};
  static const String _prefLanguageCode = 'language_code';
  static const String _prefDriverName = 'driver_name';

  static final Uri _refreshTokenUri = Uri.parse(
    '${ApiConstants.erpBaseUrl}/api/method/frappe.integrations.oauth2.get_token',
  );

  Map<String, String>? _cachedHeaders;

  /// The logged-in Driver docname, resolved the same way as every other custom
  /// grozfy call (location ping, stats, trip creation): from the `driver_name`
  /// pref that [AppController] persists after the driver profile loads.
  ///
  /// The backend identifies the driver from this value, NOT from the OAuth
  /// session user (which is a shared API user). Without it the server reports
  /// "No driver record for authenticated user".
  Future<String> _loggedInDriver() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefDriverName)?.trim() ?? '';
  }

  /// Resolves the driver and fails fast with a clear message if the profile
  /// hasn't loaded yet — better than letting the backend return its generic
  /// "No driver record" error.
  Future<String> _requireDriver() async {
    final driver = await _loggedInDriver();
    if (driver.isEmpty) {
      throw Exception('Driver profile not loaded yet. Please try again.');
    }
    return driver;
  }

  // ---------------------------------------------------------------------------
  // Auth headers + session refresh
  // ---------------------------------------------------------------------------

  Future<Map<String, String>> _authHeaders() async {
    return _cachedHeaders ??= await _buildAuthHeaders();
  }

  Future<Map<String, String>> _buildAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final String? token = await SecureTokenStorage.read(
      SecureTokenStorage.accessToken,
    );
    final String tokenType =
        (await SecureTokenStorage.read(SecureTokenStorage.tokenType) ?? 'token')
            .trim();
    final String language =
        prefs.getString(_prefLanguageCode)?.trim().isNotEmpty == true
        ? prefs.getString(_prefLanguageCode)!.trim()
        : 'en';
    if (token != null && token.isNotEmpty) {
      return {
        'Accept': 'application/json',
        'Accept-Language': language,
        'Authorization': '$tokenType $token',
      };
    }
    return {'Accept': 'application/json', 'Accept-Language': language};
  }

  Future<bool> _refreshSession() async {
    try {
      final String? refreshToken = await SecureTokenStorage.read(
        SecureTokenStorage.refreshToken,
      );
      final String? clientId = await SecureTokenStorage.read(
        SecureTokenStorage.clientId,
      );
      if (refreshToken == null || refreshToken.trim().isEmpty) return false;
      if (clientId == null || clientId.trim().isEmpty) return false;

      final resp = await http
          .post(
            _refreshTokenUri,
            headers: {
              'Accept': 'application/json',
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {
              'grant_type': 'refresh_token',
              'refresh_token': refreshToken,
              'client_id': clientId,
            },
          )
          .timeout(_networkTimeout);

      if (resp.statusCode < 200 || resp.statusCode >= 300) return false;

      final data = jsonDecode(resp.body) as Map<String, dynamic>?;
      final newToken = data?['access_token']?.toString();
      if (newToken == null || newToken.isEmpty) return false;

      await SecureTokenStorage.write(SecureTokenStorage.accessToken, newToken);
      final newType = data?['token_type']?.toString();
      if (newType != null && newType.isNotEmpty) {
        await SecureTokenStorage.write(SecureTokenStorage.tokenType, newType);
      }
      _cachedHeaders = null;
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _isAuthFailure(int statusCode) => statusCode == 401 || statusCode == 403;

  Future<http.Response> _get(Uri uri) async {
    final headers = await _authHeaders();
    _log('GET $uri');
    final resp = await http.get(uri, headers: headers).timeout(_networkTimeout);
    if (_isAuthFailure(resp.statusCode) && await _refreshSession()) {
      return http
          .get(uri, headers: await _authHeaders())
          .timeout(_networkTimeout);
    }
    return resp;
  }

  Future<http.Response> _post(Uri uri, {required String jsonBody}) async {
    final headers = {...await _authHeaders(), 'Content-Type': 'application/json'};
    _log('POST $uri');
    final resp = await http
        .post(uri, headers: headers, body: jsonBody)
        .timeout(_networkTimeout);
    if (_isAuthFailure(resp.statusCode) && await _refreshSession()) {
      final retryHeaders = {
        ...await _authHeaders(),
        'Content-Type': 'application/json',
      };
      return http
          .post(uri, headers: retryHeaders, body: jsonBody)
          .timeout(_networkTimeout);
    }
    return resp;
  }

  /// Pulls the most human-readable message out of a Frappe error body,
  /// preferring `_server_messages` (where validation errors live) over the
  /// generic `message`/`exception` fields.
  String _extractErrorMessage(http.Response resp) {
    final String base = 'Server error ${resp.statusCode}';
    Map<String, dynamic>? map;
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) map = decoded;
    } catch (_) {
      return base;
    }

    final serverMessages = map?['_server_messages'];
    if (serverMessages is String && serverMessages.isNotEmpty) {
      try {
        final outer = jsonDecode(serverMessages);
        if (outer is List && outer.isNotEmpty && outer.first is String) {
          final inner = jsonDecode(outer.first as String);
          if (inner is Map<String, dynamic>) {
            final msg = (inner['message'] ?? '').toString().trim();
            if (msg.isNotEmpty) return msg;
          }
        }
      } catch (_) {}
    }

    final message = map?['message'];
    if (message is String && message.trim().isNotEmpty) return message.trim();
    if (message is Map<String, dynamic>) {
      final nested = (message['message'] ?? '').toString().trim();
      if (nested.isNotEmpty) return nested;
    }

    final exception = (map?['exception'] ?? '').toString().trim();
    if (exception.isNotEmpty) return exception;

    return base;
  }

  /// Throws a categorisable [Exception] for any non-success status. Auth
  /// failures carry the `401`/`403` prefix the provider keys off to classify
  /// them as "unauthorized".
  void _throwForStatus(http.Response resp) {
    if (resp.statusCode == 401) {
      throw Exception('401: Invalid API credentials.');
    }
    if (resp.statusCode == 403) {
      throw Exception('403: Access denied.');
    }
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }
  }

  void _log(String value) => debugPrint('[DeliveryRadius] $value');

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Fetches the current delivery-radius configuration for the logged-in driver.
  Future<DeliveryRadiusSettings> getSettings() async {
    final driver = await _requireDriver();
    final uri = Uri.parse(
      ApiConstants.getDeliveryRadiusSettings,
    ).replace(queryParameters: {'driver': driver});
    final resp = await _get(uri);
    _throwForStatus(resp);

    final decoded = _decodeBody(resp);
    final data = decoded['message'];
    if (data is! Map<String, dynamic>) {
      throw Exception('Invalid response: missing delivery radius settings.');
    }
    return DeliveryRadiusSettings.fromJson(data);
  }

  /// Persists [selectedRadiusKm]. Returns the value the backend confirmed
  /// (falling back to the value sent when the response does not echo it).
  /// Throws with the backend validation message when the update is rejected.
  Future<double> updateRadius(double selectedRadiusKm) async {
    final driver = await _requireDriver();
    final uri = Uri.parse(ApiConstants.updateDeliveryRadius);
    // NOTE: the backend is asymmetric — get_delivery_radius *returns*
    // `selected_km`, but update_delivery_radius *expects* `selected_radius_km`.
    final body = jsonEncode({
      'driver': driver,
      'selected_radius_km': selectedRadiusKm,
    });
    final resp = await _post(uri, jsonBody: body);
    _throwForStatus(resp);

    // Prefer the value the backend echoes back so the UI reflects any
    // server-side clamping; otherwise trust the value we sent.
    try {
      final decoded = _decodeBody(resp);
      final data = decoded['message'] ?? decoded;
      if (data is Map<String, dynamic>) {
        final confirmed = DeliveryRadiusSettings.fromJson(data).selectedRadiusKm;
        if (confirmed != null) return confirmed;
      }
    } catch (_) {
      // A 2xx with an unparseable body still means the update succeeded.
    }
    return selectedRadiusKm;
  }

  Map<String, dynamic> _decodeBody(http.Response resp) {
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid response format from server.');
    }
    return decoded;
  }
}
