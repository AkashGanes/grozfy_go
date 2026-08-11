import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/services/secure_token_storage.dart';
import '../model/sos_alert.dart';

/// Talks to the deployed SOS backend (`grozfy_go.grozfy_go.api.sos`).
///
/// Auth handling mirrors [DeliveryRadiusRepository] and the other feature
/// repositories: bearer headers from [SecureTokenStorage], one transparent
/// OAuth refresh on 401/403, Frappe error envelopes normalised into readable
/// messages.
///
/// Two deliberate differences from its siblings, both safety-driven:
///
///  * **No `_requireDriver()`.** The other repositories fail fast when the
///    `driver_name` pref is blank. `trigger_sos` takes no `driver` argument at
///    all — the backend resolves identity from the session user — and an
///    emergency must never be blocked because a profile hasn't finished
///    loading.
///  * **No retry.** The endpoint has no `alert_uuid` and no idempotency key,
///    so every call creates a row. An automatic retry would file duplicate
///    emergencies that ops cannot distinguish from a driver triggering twice.
///    Retrying is the driver's explicit choice, made in the UI.
class SosRepository {
  static const Duration _networkTimeout = Duration(seconds: 15);
  static const Set<int> _okCodes = {200, 201};
  static const String _prefLanguageCode = 'language_code';

  static final Uri _refreshTokenUri = Uri.parse(
    '${ApiConstants.erpBaseUrl}/api/method/frappe.integrations.oauth2.get_token',
  );

  Map<String, String>? _cachedHeaders;

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

  /// POSTs [jsonBody] to [uri].
  ///
  /// The 401/403 replay is the one exception to "no retry": Frappe rejects an
  /// expired token *before* the method body runs, so nothing was created and
  /// the replay cannot duplicate an alert.
  Future<http.Response> _post(Uri uri, {required String jsonBody}) async {
    final headers = {
      ...await _authHeaders(),
      'Content-Type': 'application/json',
    };
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

  void _throwForStatus(http.Response resp) {
    if (resp.statusCode == 401) {
      throw Exception('401: Session expired. Please sign in again.');
    }
    if (resp.statusCode == 403) {
      throw Exception('403: Access denied.');
    }
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }
  }

  void _log(String value) => debugPrint('[SOS] $value');

  Map<String, dynamic> _decodeBody(http.Response resp) {
    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid response format from server.');
    }
    return decoded;
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Raises an emergency alert at [latitude]/[longitude].
  ///
  /// [message] carries the encoded reasons + optional note (see
  /// [encodeSosMessage]); the backend has no separate reason field.
  ///
  /// Throws unless the server *positively confirms* the alert: a 200 whose body
  /// lacks `success: true` or a non-empty `sos_alert` docname is treated as a
  /// **failure**. Telling a driver in an emergency that help is coming when we
  /// cannot prove the record exists is the worst outcome this code can produce.
  Future<SosTriggerResult> triggerSos({
    required double latitude,
    required double longitude,
    String? message,
  }) async {
    final uri = Uri.parse(ApiConstants.triggerSos);
    final trimmedMessage = message?.trim() ?? '';
    final body = jsonEncode({
      'lat': latitude,
      'lng': longitude,
      if (trimmedMessage.isNotEmpty) 'message': trimmedMessage,
    });

    final resp = await _post(uri, jsonBody: body);
    _throwForStatus(resp);

    final data = _decodeBody(resp)['message'];
    if (data is! Map<String, dynamic>) {
      throw Exception('Alert not confirmed by server.');
    }

    final alertName = data['sos_alert']?.toString().trim() ?? '';
    if (data['success'] != true || alertName.isEmpty) {
      throw Exception('Alert not confirmed by server.');
    }

    return SosTriggerResult(
      alertName: alertName,
      driverResolution: SosDriverResolution.fromJson(
        data['driver_resolved_via'],
      ),
      deliveryTrip: _nullIfBlank(data['delivery_trip']?.toString()),
      externalDelivery: _nullIfBlank(data['external_delivery']?.toString()),
    );
  }

  static String? _nullIfBlank(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty || trimmed == 'null') return null;
    return trimmed;
  }
}
