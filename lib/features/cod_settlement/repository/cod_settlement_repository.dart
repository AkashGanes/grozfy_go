import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/services/secure_token_storage.dart';
import '../model/daily_driver_settlement.dart';

class SubmitBankTransferResult {
  const SubmitBankTransferResult({
    required this.success,
    this.status,
    this.remainingBalance,
    this.carryForwardToTomorrow,
    required this.message,
  });

  final bool success;
  final String? status;
  final double? remainingBalance;
  final double? carryForwardToTomorrow;
  final String message;
}

class CodSettlementRepository {
  static const Duration _networkTimeout = Duration(seconds: 15);
  static const Set<int> _okCodes = {200, 201};
  static const String _prefLanguageCode = 'language_code';

  static final Uri _refreshTokenUri = Uri.parse(
    '${ApiConstants.erpBaseUrl}/api/method/frappe.integrations.oauth2.get_token',
  );

  Map<String, String>? _cachedHeaders;

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

  bool _isAuthFailure(int statusCode) =>
      statusCode == 401 || statusCode == 403;

  Future<http.Response> _get(Uri uri) async {
    final headers = await _authHeaders();
    _log('GET $uri');
    final resp = await http.get(uri, headers: headers).timeout(_networkTimeout);
    if (_isAuthFailure(resp.statusCode) && await _refreshSession()) {
      return http.get(uri, headers: await _authHeaders()).timeout(_networkTimeout);
    }
    return resp;
  }

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

  String _extractErrorMessage(http.Response resp) {
    String base = 'Server error ${resp.statusCode}';
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

  void _log(String value) => debugPrint('[CodSettlement] $value');

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  Future<DailyDriverSettlement> getDriverSettlementToday() async {
    final uri = Uri.parse(ApiConstants.driverSettlementToday);
    final resp = await _get(uri);

    if (resp.statusCode == 401) throw Exception('401: Invalid API credentials.');
    if (resp.statusCode == 403) throw Exception('403: Access denied.');
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = decoded['message'] as Map<String, dynamic>?;
    if (data == null) throw Exception('Unexpected response format.');

    return DailyDriverSettlement.fromJson(data);
  }

  Future<SubmitBankTransferResult> submitBankTransfer({
    required String settlementName,
    required double amountTransferred,
    required String bankTransferReference,
  }) async {
    final uri = Uri.parse(ApiConstants.submitBankTransfer);
    final body = jsonEncode({
      'settlement_name': settlementName,
      'amount_transferred': amountTransferred,
      'bank_transfer_reference': bankTransferReference,
    });

    final resp = await _post(uri, jsonBody: body);

    if (resp.statusCode == 401) throw Exception('401: Invalid API credentials.');
    if (resp.statusCode == 403) throw Exception('403: Access denied.');
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = decoded['message'] as Map<String, dynamic>? ?? decoded;

    return SubmitBankTransferResult(
      success: data['success'] == true,
      status: data['status']?.toString(),
      remainingBalance: (data['remaining_balance'] as num?)?.toDouble(),
      carryForwardToTomorrow:
          (data['carry_forward_to_tomorrow'] as num?)?.toDouble(),
      message: data['message']?.toString() ?? '',
    );
  }
}
