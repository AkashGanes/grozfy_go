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
  static const String _prefActivePickupJob = 'active_pickup_job';
  static const String _prefActivePickupTrip = 'active_pickup_trip';
  static const Set<int> _okCodes = {200, 201};
  static const Duration _networkTimeout = Duration(seconds: 15);
  static const Duration _fileUploadTimeout = Duration(seconds: 60);

  static final Uri _refreshTokenUri = Uri.parse(
    '${ApiConstants.erpBaseUrl}/api/method/frappe.integrations.oauth2.get_token',
  );

  // ── Active job tracking (SharedPreferences) ──────────────────────────────

  Future<void> saveActiveJob(String jobName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefActivePickupJob, jobName.trim());
  }

  Future<void> saveActiveTrip(String tripName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefActivePickupTrip, tripName.trim());
  }

  Future<String?> loadActiveTrip() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_prefActivePickupTrip)?.trim() ?? '';
    return v.isEmpty ? null : v;
  }

  Future<void> clearActiveJob() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefActivePickupJob);
    await prefs.remove(_prefActivePickupTrip);
  }

  /// Reads the stored job name, fetches its current status from ERPNext,
  /// and returns it only if it is still in progress.
  /// Clears storage automatically when the job is terminal or missing.
  Future<PickupJob?> loadActivePickupJob() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_prefActivePickupJob)?.trim() ?? '';
    if (name.isEmpty) return null;

    try {
      final job = await fetchJob(name);
      final statusNorm = job.status.trim().toLowerCase();
      const terminalStatuses = {
        'received at store',
        'failed',
        'cancelled',
        'pending',
        'offered',
      };
      if (terminalStatuses.contains(statusNorm)) {
        await clearActiveJob();
        return null;
      }
      return job;
    } catch (_) {
      // Job no longer accessible (deleted / permission removed).
      await clearActiveJob();
      return null;
    }
  }

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

  // ── Mark en route (sets pickup stop → En Route; server flips job → Scheduled)

  Future<void> markPickupEnRoute({
    required String pickupJobName,
    required String tripName,
  }) async {
    // Fetch the parent trip to locate the stop row name.
    final tripUri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/resource/External%20Delivery%20Trip/${Uri.encodeComponent(tripName)}',
    );
    _logApi('mark_enroute_fetch request', 'GET trip=$tripName');
    final tripResp = await _get(tripUri, headers: await _authHeaders());
    if (!_okCodes.contains(tripResp.statusCode)) {
      throw Exception(_extractErrorMessage(tripResp));
    }

    final tripData =
        (jsonDecode(tripResp.body)['data']) as Map<String, dynamic>;
    final rawStops = tripData['pickup_stops'];
    if (rawStops is! List || rawStops.isEmpty) {
      throw Exception('No pickup_stops found in trip $tripName');
    }

    String? stopName;
    for (final s in rawStops) {
      if (s is! Map<String, dynamic>) continue;
      if ((s['pickup_job'] ?? '').toString().trim() == pickupJobName) {
        stopName = (s['name'] ?? '').toString().trim();
        break;
      }
    }
    if (stopName == null || stopName.isEmpty) {
      throw Exception('Stop for $pickupJobName not found in trip $tripName');
    }

    final setValueUri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/method/frappe.client.set_value',
    );
    _logApi('mark_enroute_update request',
        'POST stop=$stopName → En Route');
    final resp = await _post(
      setValueUri,
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'doctype': 'External Delivery Trip Pickup Stop',
        'name': stopName,
        'fieldname': 'status',
        'value': 'En Route',
      }),
    );
    _logApi('mark_enroute_update response',
        'code=${resp.statusCode} body=${resp.body}');
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }
  }

  // ── Verify return OTP ─────────────────────────────────────────────────────

  Future<void> verifyReturnOtp({
    required String pickupJob,
    required String otp,
  }) async {
    final uri = Uri.parse(ApiConstants.verifyReturnOtp);
    _logApi('verify_return_otp request', 'POST $uri pickup_job=$pickupJob');
    final resp = await _post(
      uri,
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({'pickup_job': pickupJob, 'otp': otp}),
    );
    _logApi('verify_return_otp response',
        'code=${resp.statusCode} body=${resp.body}');
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }
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

  // ── Mark pickup job as failed ─────────────────────────────────────────────

  Future<void> markPickupFailed(
    String pickupJob, {
    required String reasonCode,
    String notes = '',
    String? proofPhotoPath,
    String? tripName,
  }) async {
    // Upload proof photo if provided (best effort)
    String? photoUrl;
    if (proofPhotoPath != null && proofPhotoPath.isNotEmpty) {
      photoUrl = await _uploadPhoto(
        pickupJob: pickupJob,
        filePath: proofPhotoPath,
      );
    }

    final setValueUri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/method/frappe.client.set_value',
    );

    final fieldMap = <String, dynamic>{
      'status': 'Failed',
      'failure_reason_code': reasonCode,
    };
    if (notes.isNotEmpty) fieldMap['notes'] = notes;
    if (photoUrl != null) fieldMap['proof_photo'] = photoUrl;

    _logApi('mark_pickup_failed request',
        'POST job=$pickupJob reasonCode=$reasonCode');
    final jobResp = await _post(
      setValueUri,
      headers: {
        ...await _authHeaders(),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'doctype': 'Pickup Job',
        'name': pickupJob,
        'fieldname': fieldMap,
      }),
    );
    _logApi('mark_pickup_failed response',
        'code=${jobResp.statusCode} body=${jobResp.body}');

    if (!_okCodes.contains(jobResp.statusCode)) {
      throw Exception(_extractErrorMessage(jobResp));
    }

    // Update the trip stop (best effort — failure should not block the driver)
    if (tripName != null && tripName.isNotEmpty) {
      try {
        await _markPickupTripStopFailed(
          tripName: tripName,
          pickupJobName: pickupJob,
          reasonCode: reasonCode,
        );
      } catch (e) {
        debugPrint('[PickupJob] trip stop failure update error: $e');
      }
    }
  }

  Future<void> _markPickupTripStopFailed({
    required String tripName,
    required String pickupJobName,
    required String reasonCode,
  }) async {
    final tripUri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/resource/External%20Delivery%20Trip/${Uri.encodeComponent(tripName)}',
    );
    _logApi('pickup_stop_fail_fetch request', 'GET trip=$tripName');
    final tripResp = await _get(tripUri, headers: await _authHeaders());
    if (!_okCodes.contains(tripResp.statusCode)) return;

    final tripData =
        (jsonDecode(tripResp.body)['data']) as Map<String, dynamic>?;
    final rawStops = tripData?['pickup_stops'];
    if (rawStops is! List || rawStops.isEmpty) return;

    String? stopName;
    for (final s in rawStops) {
      if (s is! Map<String, dynamic>) continue;
      if ((s['pickup_job'] ?? '').toString().trim() == pickupJobName) {
        stopName = (s['name'] ?? '').toString().trim();
        break;
      }
    }
    if (stopName == null || stopName.isEmpty) return;

    final setValueUri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/method/frappe.client.set_value',
    );
    _logApi('pickup_stop_fail_update request',
        'POST name=$stopName → Failed, reasonCode=$reasonCode');
    final stopResp = await _post(
      setValueUri,
      headers: {
        ...await _authHeaders(),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'doctype': 'External Delivery Trip Pickup Stop',
        'name': stopName,
        'fieldname': {
          'status': 'Failed',
          'failure_reason_code': reasonCode,
        },
      }),
    );
    _logApi('pickup_stop_fail_update response',
        'code=${stopResp.statusCode} body=${stopResp.body}');
  }

  // ── Update trip stop status after drop-at-store ──────────────────────────

  Future<void> updatePickupTripStopCompleted({
    required String tripName,
    required String pickupJobName,
  }) async {
    // Fetch the parent trip document — driver has read permission on this,
    // unlike direct child-table queries which Frappe blocks with PermissionError.
    final tripUri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/resource/External%20Delivery%20Trip/${Uri.encodeComponent(tripName)}',
    );
    _logApi('pickup_trip_fetch request', 'GET trip=$tripName');
    final tripResp = await _get(tripUri, headers: await _authHeaders());
    _logApi('pickup_trip_fetch response',
        'code=${tripResp.statusCode} body=${tripResp.body}');

    if (!_okCodes.contains(tripResp.statusCode)) {
      throw Exception(_extractErrorMessage(tripResp));
    }

    final tripData =
        (jsonDecode(tripResp.body)['data']) as Map<String, dynamic>;
    final rawStops = tripData['pickup_stops'];
    if (rawStops is! List || rawStops.isEmpty) {
      throw Exception('No pickup_stops in trip $tripName');
    }

    // Find the child row for this pickup job.
    String? stopName;
    for (final s in rawStops) {
      if (s is! Map<String, dynamic>) continue;
      final pj = (s['pickup_job'] ?? '').toString().trim();
      if (pj == pickupJobName) {
        stopName = (s['name'] ?? '').toString().trim();
        break;
      }
    }

    if (stopName == null || stopName.isEmpty) {
      final keys = rawStops.isNotEmpty && rawStops.first is Map
          ? (rawStops.first as Map).keys.join(', ')
          : 'unknown';
      throw Exception(
          'Stop for $pickupJobName not found. Stop fields: $keys');
    }

    final setValueUri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/method/frappe.client.set_value',
    );
    _logApi('pickup_stop_status_update request',
        'POST name=$stopName → Received at Store');
    final statusResp = await _post(
      setValueUri,
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'doctype': 'External Delivery Trip Pickup Stop',
        'name': stopName,
        'fieldname': 'status',
        'value': 'Received at Store',
      }),
    );
    _logApi('pickup_stop_status_update response',
        'code=${statusResp.statusCode} body=${statusResp.body}');

    if (!_okCodes.contains(statusResp.statusCode)) {
      throw Exception(_extractErrorMessage(statusResp));
    }
  }

  // ── Fetch single job via getdoc (full document, all fields) ──────────────

  Future<PickupJob> fetchJob(String name) async {
    final uri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/method/frappe.desk.form.load.getdoc',
    ).replace(queryParameters: {
      'doctype': 'Pickup Job',
      'name': name,
    });
    _logApi('fetch_pickup_job request', uri.toString());
    final resp = await _get(uri, headers: await _authHeaders());
    _logApi('fetch_pickup_job response',
        'code=${resp.statusCode} body=${resp.body}');
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final docs = decoded['docs'];
    if (docs is! List || docs.isEmpty) {
      throw Exception('Pickup Job not found: $name');
    }
    final data = docs[0] as Map<String, dynamic>;
    return PickupJob.fromJson(data);
  }

  // ── Fetch pickup stop row from the associated delivery trip ──────────────

  /// Finds the External Delivery Trip for [pickupJobName] and returns
  /// `(stopData, errorMessage)`.  stopData is null when not found or on error.
  Future<(Map<String, dynamic>?, String?)> fetchPickupTripStop({
    required String pickupJobName,
    String? hintTripName,
  }) async {
    try {
      // Step 1 – resolve trip name
      String? tripName = (hintTripName?.trim().isNotEmpty == true)
          ? hintTripName
          : null;
      tripName ??= await _findTripNameForPickupJob(pickupJobName);

      if (tripName == null || tripName.isEmpty) {
        final msg = 'No delivery trip found for $pickupJobName';
        _logApi('fetch_pickup_trip_stop', msg);
        return (null, msg);
      }

      // Step 2 – fetch full trip document
      final uri = Uri.parse(
        '${ApiConstants.externalDeliveryTripList}/${Uri.encodeComponent(tripName)}',
      );
      _logApi('fetch_pickup_trip_stop request', 'GET trip=$tripName');
      final resp = await _get(uri, headers: await _authHeaders());
      _logApi('fetch_pickup_trip_stop response',
          'code=${resp.statusCode} body=${resp.body}');

      if (!_okCodes.contains(resp.statusCode)) {
        return (null, 'Trip fetch failed (${resp.statusCode}): ${_extractErrorMessage(resp)}');
      }

      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        return (null, 'Unexpected trip response format');
      }

      final rawStops = data['pickup_stops'];
      if (rawStops is! List) {
        return (null, 'No pickup_stops in trip $tripName');
      }

      for (final s in rawStops) {
        if (s is! Map<String, dynamic>) continue;
        if ((s['pickup_job'] ?? '').toString().trim() == pickupJobName) {
          return ({
            ...s,
            '_trip_name': tripName,
            '_trip_status': (data['status'] ?? '').toString(),
            '_trip_date': (data['trip_date'] ?? '').toString(),
            '_trip_driver': (data['driver'] ?? '').toString(),
            '_trip_total_stops': data['total_stops'],
            '_trip_completed_stops': data['completes_stops'],
          }, null);
        }
      }
      return (null, 'Stop for $pickupJobName not found in trip $tripName');
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      _logApi('fetch_pickup_trip_stop error', msg);
      return (null, msg);
    }
  }

  /// Queries the External Delivery Trip list filtering by the child table field
  /// `pickup_job` to find which trip contains [pickupJobName].
  Future<String?> _findTripNameForPickupJob(String pickupJobName) async {
    final uri = Uri.parse(ApiConstants.externalDeliveryTripList).replace(
      queryParameters: {
        'filters': jsonEncode([
          [
            'External Delivery Trip Pickup Stop',
            'pickup_job',
            '=',
            pickupJobName,
          ],
        ]),
        'fields': jsonEncode(['name']),
        'limit': '1',
      },
    );
    _logApi('find_trip_for_pickup_job request', uri.toString());
    try {
      final resp = await _get(uri, headers: await _authHeaders());
      _logApi('find_trip_for_pickup_job response',
          'code=${resp.statusCode} body=${resp.body}');
      if (!_okCodes.contains(resp.statusCode)) return null;
      final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
      final data = decoded['data'];
      if (data is! List || data.isEmpty) return null;
      final n = (data[0]['name'] ?? '').toString().trim();
      return n.isEmpty ? null : n;
    } catch (_) {
      return null;
    }
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
