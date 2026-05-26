import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/services/secure_token_storage.dart';
import '../model/pickup_job.dart';

class PickupJobClaimResult {
  const PickupJobClaimResult({
    required this.success,
    required this.deliveryTrip,
    this.error,
  });

  final bool success;
  final String deliveryTrip;
  final String? error;
}

class PickupJobRepository {
  PickupJobRepository();

  static const String _prefLanguageCode = 'language_code';
  static const Set<int> _okCodes = {200, 201};
  static const Duration _networkTimeout = Duration(seconds: 15);
  static const Duration _fileUploadTimeout = Duration(seconds: 60);

  static final Uri _refreshTokenUri = Uri.parse(
    '${ApiConstants.erpBaseUrl}/api/method/frappe.integrations.oauth2.get_token',
  );

  // ── Pool ──────────────────────────────────────────────────────────────────

  Future<List<PickupJob>> fetchPool({int limit = 50}) async {
    final uri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/method/grozfy_go.grozfy_go.api.driver.list_pickup_pool',
    ).replace(queryParameters: {'limit': '$limit'});

    _logApi('list_pickup_pool request', uri.toString());
    final resp = await _get(uri, headers: await _authHeaders());
    _logApi('list_pickup_pool response', 'code=${resp.statusCode}');

    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final message = decoded['message'];
    if (message is! List) return [];
    return message
        .whereType<Map<String, dynamic>>()
        .map(PickupJob.fromJson)
        .toList();
  }

  // ── Claim ─────────────────────────────────────────────────────────────────

  Future<PickupJobClaimResult> acceptJob(String pickupJob) async {
    final uri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/method/grozfy_go.grozfy_go.api.driver.accept_pickup_job',
    );
    _logApi('accept_pickup_job request', 'POST $uri pickup_job=$pickupJob');
    final resp = await _post(
      uri,
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({'pickup_job': pickupJob}),
    );
    _logApi('accept_pickup_job response',
        'code=${resp.statusCode} body=${resp.body}');

    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final message = decoded['message'];
    final data = message is Map<String, dynamic> ? message : <String, dynamic>{};

    return PickupJobClaimResult(
      success: data['success'] == true,
      deliveryTrip: (data['delivery_trip'] ?? '').toString(),
      error: data['error']?.toString(),
    );
  }

  // ── Mark picked up ────────────────────────────────────────────────────────

  Future<void> markPickedUp(String pickupJob, {String? proofPhotoPath}) async {
    String? photoUrl;
    if (proofPhotoPath != null && proofPhotoPath.isNotEmpty) {
      photoUrl = await _uploadPhoto(
        pickupJob: pickupJob,
        filePath: proofPhotoPath,
      );
    }

    final uri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/method/grozfy_go.grozfy_go.api.driver.mark_pickup_picked_up',
    );
    final body = <String, dynamic>{'pickup_job': pickupJob};
    if (photoUrl != null) body['proof_photo'] = photoUrl;

    _logApi('mark_pickup_picked_up request', 'POST $uri job=$pickupJob');
    final resp = await _post(
      uri,
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    _logApi('mark_pickup_picked_up response',
        'code=${resp.statusCode} body=${resp.body}');

    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }
  }

  // ── Confirm drop at store ─────────────────────────────────────────────────

  Future<Map<String, dynamic>> confirmCompleted(String pickupJob) async {
    final uri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/method/grozfy_go.grozfy_go.api.driver.confirm_pickup_completed',
    );
    _logApi(
        'confirm_pickup_completed request', 'POST $uri job=$pickupJob');
    final resp = await _post(
      uri,
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({'pickup_job': pickupJob}),
    );
    _logApi('confirm_pickup_completed response',
        'code=${resp.statusCode} body=${resp.body}');

    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final message = decoded['message'];
    return message is Map<String, dynamic> ? message : {};
  }

  // ── Fetch single job (for detail screen refresh) ──────────────────────────

  Future<PickupJob> fetchJob(String name) async {
    final uri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/resource/Pickup%20Job/${Uri.encodeComponent(name)}',
    );
    _logApi('fetch_pickup_job request', uri.toString());
    final resp = await _get(uri, headers: await _authHeaders());
    _logApi('fetch_pickup_job response', 'code=${resp.statusCode}');
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }
    final data = (jsonDecode(resp.body)['data']) as Map<String, dynamic>;
    return PickupJob.fromJson(data);
  }

  // ── Photo upload ──────────────────────────────────────────────────────────

  Future<String?> _uploadPhoto({
    required String pickupJob,
    required String filePath,
  }) async {
    final uri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/method/upload_file',
    );
    _logApi('upload_pickup_photo request', 'POST $uri job=$pickupJob');
    try {
      final req = http.MultipartRequest('POST', uri)
        ..headers.addAll(await _authHeaders())
        ..fields['doctype'] = 'Pickup Job'
        ..fields['docname'] = pickupJob
        ..fields['fieldname'] = 'proof_photo'
        ..fields['is_private'] = '0'
        ..files.add(
          await http.MultipartFile.fromPath(
            'file',
            filePath,
            filename: 'pickup_${pickupJob}_proof.jpg',
          ),
        );
      final resp = await http.Response.fromStream(
        await req.send().timeout(_fileUploadTimeout),
      );
      _logApi('upload_pickup_photo response',
          'code=${resp.statusCode} body=${resp.body}');
      if (!_okCodes.contains(resp.statusCode)) return null;
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final fileUrl = (decoded['message']?['file_url'] ??
              decoded['file_url'] ??
              '')
          .toString();
      return fileUrl.isNotEmpty ? fileUrl : null;
    } catch (_) {
      return null;
    }
  }

  // ── Auth + HTTP helpers ───────────────────────────────────────────────────

  Future<Map<String, String>> _authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token =
        await SecureTokenStorage.read(SecureTokenStorage.accessToken);
    final tokenType =
        (await SecureTokenStorage.read(SecureTokenStorage.tokenType) ?? 'token')
            .trim();
    final language =
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
      final refreshToken =
          await SecureTokenStorage.read(SecureTokenStorage.refreshToken);
      final clientId =
          await SecureTokenStorage.read(SecureTokenStorage.clientId);
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
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final newToken = data['access_token']?.toString();
      if (newToken == null || newToken.trim().isEmpty) return false;
      await SecureTokenStorage.write(SecureTokenStorage.accessToken, newToken);
      final newType = data['token_type']?.toString();
      final newRefresh = data['refresh_token']?.toString();
      if (newType != null && newType.isNotEmpty) {
        await SecureTokenStorage.write(SecureTokenStorage.tokenType, newType);
      }
      if (newRefresh != null && newRefresh.isNotEmpty) {
        await SecureTokenStorage.write(
            SecureTokenStorage.refreshToken, newRefresh);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<http.Response> _get(Uri uri,
      {required Map<String, String> headers}) async {
    _logApi('http', 'GET $uri');
    final resp =
        await http.get(uri, headers: headers).timeout(_networkTimeout);
    if (_isAuthFailure(resp.statusCode) && await _refreshSession()) {
      return http.get(uri, headers: await _authHeaders()).timeout(_networkTimeout);
    }
    return resp;
  }

  Future<http.Response> _post(Uri uri,
      {required Map<String, String> headers, Object? body}) async {
    _logApi('http', 'POST $uri');
    final resp = await http
        .post(uri, headers: headers, body: body)
        .timeout(_networkTimeout);
    if (_isAuthFailure(resp.statusCode) && await _refreshSession()) {
      final refreshedHeaders = {
        ...await _authHeaders(),
        if (headers.containsKey('Content-Type'))
          'Content-Type': headers['Content-Type']!,
      };
      return http
          .post(uri, headers: refreshedHeaders, body: body)
          .timeout(_networkTimeout);
    }
    return resp;
  }

  bool _isAuthFailure(int code) => code == 401 || code == 403;

  void _logApi(String tag, String value) {
    final line = '[PickupJob] $tag => $value';
    debugPrint(line);
    // ignore: avoid_print
    print(line);
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
}
