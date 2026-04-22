import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/api_constants.dart';
import '../model/external_delivery.dart';
import '../model/external_delivery_detail.dart';

class ReturnProcessResult {
  const ReturnProcessResult({
    required this.success,
    required this.orderUpdated,
    required this.tripCreated,
    required this.tripSubmitted,
    this.tripName,
    required this.message,
  });

  final bool success;
  final bool orderUpdated;
  final bool tripCreated;
  final bool tripSubmitted;
  final String? tripName;
  final String message;
}

class ExternalDeliveryRepository {
  ExternalDeliveryRepository();

  static const String _prefAccessToken = 'access_token';
  static const String _prefTokenType = 'token_type';
  static const String _prefRefreshToken = 'refresh_token';
  static const String _prefClientId = 'client_id';
  static final Uri _refreshTokenUri = Uri.parse(
    '${ApiConstants.erpBaseUrl}/api/method/frappe.integrations.oauth2.get_token',
  );

  Future<Map<String, String>> _authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final String? token = prefs.getString(_prefAccessToken);
    final String tokenType = (prefs.getString(_prefTokenType) ?? 'token')
        .trim();
    if (token != null && token.isNotEmpty) {
      return {
        'Accept': 'application/json',
        'Authorization': '$tokenType $token',
      };
    }
    return {'Accept': 'application/json'};
  }

  /// Refreshes the session token using Frappe's OAuth2 get_token endpoint.
  Future<bool> _refreshSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? refreshToken = prefs.getString(_prefRefreshToken);
      final String? clientId = prefs.getString(_prefClientId);
      if (refreshToken == null || refreshToken.trim().isEmpty) return false;
      if (clientId == null || clientId.trim().isEmpty) return false;

      _logApi('refresh_token', 'POST $_refreshTokenUri');
      final resp = await http
          .post(
            _refreshTokenUri,
            headers: const {
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
      final String? newToken = data['access_token']?.toString();
      if (newToken == null || newToken.trim().isEmpty) return false;

      final String? newType = data['token_type']?.toString();
      final String? newRefresh = data['refresh_token']?.toString();
      await Future.wait(<Future<bool>>[
        prefs.setString(_prefAccessToken, newToken),
        if (newType != null && newType.isNotEmpty)
          prefs.setString(_prefTokenType, newType),
        if (newRefresh != null && newRefresh.isNotEmpty)
          prefs.setString(_prefRefreshToken, newRefresh),
      ]);
      _logApi('refresh_token', 'session refreshed successfully');
      return true;
    } catch (e) {
      _logApi('refresh_token error', e.toString());
      return false;
    }
  }

  static const int pageSize = 20;

  static const List<String> _fields = [
    'name',
    'creation',
    'modified',
    'store_url',
    'store_name',
    'customer_name',
    'status',
  ];
  static const List<String> _tripFields = [
    'name',
    'driver',
    'status',
    'docstatus',
    'trip_date',
    'trip_notes',
    'total_stops',
    'completes_stops',
    'modified',
  ];

  static const Set<int> _okCodes = {200, 201};
  static const Duration _networkTimeout = Duration(seconds: 15);
  static const String _returnInitiatedStatus = 'Return Initiated';
  static const String _returnedStatus = 'Returned';

  Future<List<String>> fetchStoreNames() async {
    final uri = Uri.parse(ApiConstants.externalDeliveryList).replace(
      queryParameters: {
        'fields': jsonEncode(['store_name']),
        'limit_page_length': '500',
        'order_by': 'store_name asc',
      },
    );

    _logApi('fetch_store_names request', uri.toString());
    final resp = await _get(uri, headers: await _authHeaders());

    _logApi('fetch_store_names response', '${resp.statusCode}');
    if (resp.statusCode != 200) return [];

    final data = (jsonDecode(resp.body)['data']) as List;
    final names =
        data
            .map(
              (r) =>
                  (r as Map<String, dynamic>)['store_name']?.toString() ?? '',
            )
            .where((s) => s.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return names;
  }

  Future<List<ExternalDelivery>> fetchPage({
    int limitStart = 0,
    int limitPageLength = pageSize,
    String? storeName,
    String orderBy = 'store_name asc, modified desc',
    List<List<dynamic>>? filters,
  }) async {
    final params = <String, String>{
      'fields': jsonEncode(_fields),
      'limit_start': '$limitStart',
      'limit_page_length': '$limitPageLength',
      'order_by': orderBy,
    };
    final List<List<dynamic>> effectiveFilters = <List<dynamic>>[
      if (filters != null) ...filters,
      if (storeName != null && storeName.isNotEmpty)
        <dynamic>['External Delivery', 'store_name', '=', storeName],
    ];
    if (effectiveFilters.isNotEmpty) {
      params['filters'] = jsonEncode(effectiveFilters);
    }

    final uri = Uri.parse(
      ApiConstants.externalDeliveryList,
    ).replace(queryParameters: params);

    _logApi('external_delivery_list request', uri.toString());
    final resp = await _get(uri, headers: await _authHeaders());

    if (resp.statusCode == 401) {
      throw Exception('401: Invalid API credentials.');
    }
    if (resp.statusCode == 403) {
      throw Exception('403: Access denied. Check API permissions.');
    }
    if (resp.statusCode != 200) {
      throw Exception(_extractErrorMessage(resp));
    }

    final data = (jsonDecode(resp.body)['data']) as List;
    return data
        .map((row) => ExternalDelivery.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<ExternalDelivery>> fetchActiveSummaries({
    int limitPageLength = 5,
  }) async {
    return fetchPage(
      limitStart: 0,
      limitPageLength: limitPageLength,
      orderBy: 'modified desc',
      filters: <List<dynamic>>[
        <dynamic>[
          'External Delivery',
          'status',
          'in',
          <String>[
            'Accepted',
            'Added to Trip',
            'Picked Up',
            'Out for Delivery',
          ],
        ],
      ],
    );
  }

  /// Fetches all External Delivery records with [status] using server-side
  /// filtering so no records are missed due to pagination limits.
  Future<List<ExternalDelivery>> fetchAllByStatus(String status) async {
    final params = <String, String>{
      'fields': jsonEncode(_fields),
      'filters': jsonEncode([
        ['External Delivery', 'status', '=', status],
      ]),
      'limit_page_length': '500',
      'order_by': 'creation desc',
    };

    final uri = Uri.parse(
      ApiConstants.externalDeliveryList,
    ).replace(queryParameters: params);

    _logApi('external_delivery_pending_list request', uri.toString());
    final resp = await _get(uri, headers: await _authHeaders());

    if (resp.statusCode == 401) {
      throw Exception('401: Invalid API credentials.');
    }
    if (resp.statusCode == 403) {
      throw Exception('403: Access denied. Check API permissions.');
    }
    if (resp.statusCode != 200) {
      throw Exception(_extractErrorMessage(resp));
    }

    final data = (jsonDecode(resp.body)['data']) as List;
    _logApi(
      'external_delivery_pending_list',
      'fetched ${data.length} records with status=$status',
    );
    return data
        .map((row) => ExternalDelivery.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<ExternalDeliveryDetail> fetchDetail(String name) async {
    final uri = Uri.parse(
      '${ApiConstants.externalDeliveryList}/${Uri.encodeComponent(name)}',
    );
    _logApi('external_delivery_detail request', uri.toString());

    final resp = await _get(uri, headers: await _authHeaders());

    if (resp.statusCode == 401) {
      throw Exception('401: Invalid API credentials.');
    }
    if (resp.statusCode == 403) {
      throw Exception('403: Access denied. Check API permissions.');
    }
    if (resp.statusCode != 200) {
      throw Exception(_extractErrorMessage(resp));
    }

    final data = (jsonDecode(resp.body)['data']) as Map<String, dynamic>;
    final addressName = data['delivery_address']?.toString();
    if (addressName != null && addressName.isNotEmpty) {
      final resolved = await _fetchAddressText(addressName);
      if (resolved != null) {
        data['delivery_address'] = resolved;
      }
    }

    return ExternalDeliveryDetail.fromJson(data);
  }

  Future<void> updateStatus(String name, String status) async {
    final uri = Uri.parse(
      '${ApiConstants.externalDeliveryList}/${Uri.encodeComponent(name)}',
    );
    _logApi('external_delivery_status_update request', '$uri status=$status');

    final resp = await _put(
      uri,
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({'status': status}),
    );

    if (!_okCodes.contains(resp.statusCode)) {
      _logApi(
        'external_delivery_status_update error',
        'code=${resp.statusCode} body=${resp.body}',
      );
      throw Exception(_extractErrorMessage(resp));
    }
  }

  Future<void> updateStatusViaSetValue(String name, String status) async {
    _logApi('external_delivery_set_value request', 'name=$name status=$status');
    final uri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/method/frappe.client.set_value',
    );
    final resp = await _post(
      uri,
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'doctype': 'External Delivery',
        'name': name,
        'fieldname': 'status',
        'value': status,
      }),
    );
    _logApi(
      'external_delivery_set_value response',
      'code=${resp.statusCode} body=${resp.body}',
    );
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }
  }

  Future<void> acceptOrderWithPartner(String name, String partnerMobile) async {
    final uri = Uri.parse(
      '${ApiConstants.externalDeliveryList}/${Uri.encodeComponent(name)}',
    );
    _logApi(
      'accept_order_with_partner request',
      'name=$name partner=$partnerMobile',
    );
    final resp = await _put(
      uri,
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'status': 'Accepted',
        'delivery_partner': partnerMobile,
        'driver': partnerMobile,
        'assigned_to': partnerMobile,
      }),
    );
    _logApi(
      'accept_order_with_partner response',
      'code=${resp.statusCode} body=${resp.body}',
    );
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }
  }

  Future<void> applyWorkflowAccept(String name) async {
    final detailUri = Uri.parse(
      '${ApiConstants.externalDeliveryList}/${Uri.encodeComponent(name)}',
    );
    final detailResp = await _get(detailUri, headers: await _authHeaders());
    if (!_okCodes.contains(detailResp.statusCode)) {
      throw Exception(_extractErrorMessage(detailResp));
    }
    final docData =
        (jsonDecode(detailResp.body)['data']) as Map<String, dynamic>;

    final uri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/method/frappe.model.workflow.apply_workflow',
    );
    _logApi('apply_workflow_accept request', 'name=$name');
    final resp = await _post(
      uri,
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({'doc': docData, 'action': 'Accept'}),
    );
    _logApi(
      'apply_workflow_accept response',
      'code=${resp.statusCode} body=${resp.body}',
    );
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }
  }

  Future<String> createAndSubmitTripForOrders(
    List<ExternalDelivery> orders,
  ) async {
    if (orders.isEmpty) {
      throw Exception('No orders provided for trip creation');
    }

    final createPayload = {
      'driver': ApiConstants.defaultExternalDeliveryDriver,
      'status': 'Draft',
      'trip_date': DateTime.now().toIso8601String().split('T').first,
      'stops': orders.map((o) => {'external_delivery': o.name}).toList(),
    };
    _logApi(
      'external_delivery_trip_create_batch request',
      'POST ${ApiConstants.externalDeliveryTripList} stops=${orders.length}',
    );

    final createResp = await _post(
      Uri.parse(ApiConstants.externalDeliveryTripList),
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode(createPayload),
    );

    if (!_okCodes.contains(createResp.statusCode)) {
      throw Exception(_extractErrorMessage(createResp));
    }

    final createData = jsonDecode(createResp.body) as Map<String, dynamic>;
    final createdDoc = createData['data'];
    if (createdDoc is! Map<String, dynamic>) {
      throw Exception('Trip create API returned unexpected response');
    }

    _logApi(
      'external_delivery_trip_submit request',
      'POST ${ApiConstants.frappeSubmitMethod} docname=${createdDoc['name']}',
    );
    final submitResp = await _post(
      Uri.parse(ApiConstants.frappeSubmitMethod),
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({'doc': createdDoc}),
    );

    if (!_okCodes.contains(submitResp.statusCode)) {
      throw Exception(_extractErrorMessage(submitResp));
    }

    final submitData = jsonDecode(submitResp.body) as Map<String, dynamic>;
    final submittedDoc = submitData['message'] ?? submitData['data'];
    if (submittedDoc is! Map<String, dynamic>) {
      throw Exception('Trip submit API returned unexpected response');
    }

    return (submittedDoc['name'] ?? createdDoc['name'] ?? '').toString();
  }

  Future<String> createAndSubmitTripForOrder(ExternalDelivery order) async {
    final createPayload = {
      'driver': ApiConstants.defaultExternalDeliveryDriver,
      'status': 'Draft',
      'trip_date': DateTime.now().toIso8601String().split('T').first,
      'stops': [
        {'external_delivery': order.name},
      ],
    };
    _logApi(
      'external_delivery_trip_create request',
      'POST ${ApiConstants.externalDeliveryTripList} body=$createPayload',
    );

    final createResp = await _post(
      Uri.parse(ApiConstants.externalDeliveryTripList),
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode(createPayload),
    );

    if (!_okCodes.contains(createResp.statusCode)) {
      throw Exception(_extractErrorMessage(createResp));
    }

    final createData = jsonDecode(createResp.body) as Map<String, dynamic>;
    final createdDoc = createData['data'];
    if (createdDoc is! Map<String, dynamic>) {
      throw Exception('Trip create API returned unexpected response');
    }

    _logApi(
      'external_delivery_trip_submit request',
      'POST ${ApiConstants.frappeSubmitMethod} docname=${createdDoc['name']}',
    );
    final submitResp = await _post(
      Uri.parse(ApiConstants.frappeSubmitMethod),
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({'doc': createdDoc}),
    );

    if (!_okCodes.contains(submitResp.statusCode)) {
      throw Exception(_extractErrorMessage(submitResp));
    }

    final submitData = jsonDecode(submitResp.body) as Map<String, dynamic>;
    final submittedDoc = submitData['message'] ?? submitData['data'];
    if (submittedDoc is! Map<String, dynamic>) {
      throw Exception('Trip submit API returned unexpected response');
    }

    return (submittedDoc['name'] ?? createdDoc['name'] ?? '').toString();
  }

  Future<List<ExternalDeliveryTripSummary>> fetchTripPage({
    int limitStart = 0,
  }) async {
    final uri = Uri.parse(ApiConstants.externalDeliveryTripList).replace(
      queryParameters: {
        'fields': jsonEncode(_tripFields),
        'limit_start': '$limitStart',
        'limit_page_length': '$pageSize',
        'order_by': 'driver asc, modified desc',
      },
    );
    _logApi('external_delivery_trip_list request', uri.toString());

    final resp = await _get(uri, headers: await _authHeaders());

    if (resp.statusCode == 401) {
      throw Exception('401: Invalid API credentials.');
    }
    if (resp.statusCode == 403) {
      throw Exception('403: Access denied. Check API permissions.');
    }
    if (resp.statusCode != 200) {
      throw Exception(_extractErrorMessage(resp));
    }

    final data = (jsonDecode(resp.body)['data']) as List;
    return data
        .map(
          (row) =>
              ExternalDeliveryTripSummary.fromJson(row as Map<String, dynamic>),
        )
        .toList();
  }

  Future<ExternalDeliveryTrip> fetchTripDetails(String tripName) async {
    final url =
        '${ApiConstants.externalDeliveryTripList}/${Uri.encodeComponent(tripName)}';
    _logApi('external_delivery_trip_details request', 'GET $url');

    final resp = await _get(Uri.parse(url), headers: await _authHeaders());

    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }

    final payload = jsonDecode(resp.body) as Map<String, dynamic>;
    final data = payload['data'];
    if (data is! Map<String, dynamic>) {
      throw Exception('Trip details API returned unexpected response');
    }
    return ExternalDeliveryTrip.fromJson(data);
  }

  Future<String?> _fetchAddressText(String addressName) async {
    final uri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/resource/Address/${Uri.encodeComponent(addressName)}',
    );
    _logApi('fetch_address request', uri.toString());

    try {
      final resp = await _get(uri, headers: await _authHeaders());

      if (resp.statusCode != 200) return null;

      final data = (jsonDecode(resp.body)['data']) as Map<String, dynamic>;
      final parts = <String>[
        if (_value(data['address_line1']) != null)
          _value(data['address_line1'])!,
        if (_value(data['address_line2']) != null)
          _value(data['address_line2'])!,
        if (_value(data['city']) != null) _value(data['city'])!,
        if (_value(data['state']) != null) _value(data['state'])!,
        if (_value(data['pincode']) != null) _value(data['pincode'])!,
        if (_value(data['country']) != null) _value(data['country'])!,
      ];

      return parts.isNotEmpty ? parts.join(', ') : null;
    } catch (_) {
      return null;
    }
  }

  String? _value(dynamic input) {
    if (input == null) return null;
    final text = input.toString().trim();
    return text.isEmpty ? null : text;
  }

  Future<void> updateTripStopStatus({
    required ExternalDeliveryTripStop stop,
    required String newStatus,
  }) async {
    final stopName = (stop.rawFields['name'] ?? '').toString().trim();
    final stopDocType = (stop.rawFields['doctype'] ?? '').toString().trim();
    if (stopName.isEmpty || stopDocType.isEmpty) {
      throw Exception('Stop row metadata not found for status update.');
    }

    final setValueUrl = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/method/frappe.client.set_value',
    );
    _logApi(
      'external_delivery_trip_stop_status_update request',
      'POST $setValueUrl doctype=$stopDocType name=$stopName status=$newStatus',
    );

    final statusResp = await _post(
      setValueUrl,
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'doctype': stopDocType,
        'name': stopName,
        'fieldname': 'status',
        'value': newStatus,
      }),
    );

    if (!_okCodes.contains(statusResp.statusCode)) {
      throw Exception(_extractErrorMessage(statusResp));
    }

    if (newStatus.toLowerCase() == 'delivered') {
      // Best-effort: stamp delivered_at and increment completes_stops on parent trip.
      final parentTripName = (stop.rawFields['parent'] ?? '').toString().trim();
      final authHeaders = {
        ...await _authHeaders(),
        'Content-Type': 'application/json',
      };

      if (stop.deliveredAt.trim().isEmpty) {
        try {
          await _post(
            setValueUrl,
            headers: authHeaders,
            body: jsonEncode({
              'doctype': stopDocType,
              'name': stopName,
              'fieldname': 'delivered_at',
              'value': DateTime.now().toIso8601String(),
            }),
          );
        } catch (e) {
          _logApi(
            'external_delivery_trip_stop_delivered_at_warn',
            e.toString(),
          );
        }
      }

      // Increment completes_stops on the parent trip
      if (parentTripName.isNotEmpty) {
        try {
          // Fetch current completes_stops value
          final tripUri = Uri.parse(
            '${ApiConstants.externalDeliveryTripList}/${Uri.encodeComponent(parentTripName)}',
          ).replace(queryParameters: {'fields': '["completes_stops"]'});
          final tripResp = await _get(tripUri, headers: authHeaders);
          if (_okCodes.contains(tripResp.statusCode)) {
            final tripData =
                (jsonDecode(tripResp.body)['data']) as Map<String, dynamic>;
            final current = (tripData['completes_stops'] as num?)?.toInt() ?? 0;
            await _post(
              setValueUrl,
              headers: authHeaders,
              body: jsonEncode({
                'doctype': 'External Delivery Trip',
                'name': parentTripName,
                'fieldname': 'completes_stops',
                'value': current + 1,
              }),
            );
            _logApi(
              'completes_stops_update',
              'trip=$parentTripName new=${current + 1}',
            );
          }
        } catch (e) {
          _logApi('completes_stops_update_warn', e.toString());
        }
      }
    }
  }

  /// Called when the delivery partner arrives back at the store with a
  /// returned order. Marks all stops as Delivered and sets trip status to
  /// Completed.
  Future<void> markReturnedToStore({required ExternalDeliveryTrip trip}) async {
    for (final stop in trip.stops) {
      final orderName = stop.externalDelivery.trim();
      if (orderName.isEmpty) {
        continue;
      }
      await _markOrderReturned(orderName);
      await _markStopReturned(stop);
    }

    await _completeTrip(trip);
  }

  /// Uploads a proof photo and attaches it to the [proof_photo] field of the
  /// External Delivery document. Returns the remote file URL on success, or
  /// null on failure (best-effort — callers must not throw on null).
  Future<String?> uploadProofPhoto({
    required String orderName,
    required String filePath,
  }) async {
    try {
      final uri = Uri.parse(
        '${ApiConstants.erpBaseUrl}/api/method/upload_file',
      );
      final headers = await _authHeaders();
      final req = http.MultipartRequest('POST', uri)
        ..headers.addAll(headers)
        ..fields['doctype'] = 'External Delivery'
        ..fields['docname'] = orderName
        ..fields['fieldname'] = 'proof_photo'
        ..fields['is_private'] = '0'
        ..files.add(
          await http.MultipartFile.fromPath(
            'file',
            filePath,
            filename: 'proof_$orderName.jpg',
          ),
        );

      _logApi('upload_proof_photo request', 'POST $uri order=$orderName');
      var streamed = await req.send().timeout(_networkTimeout);
      var resp = await http.Response.fromStream(streamed);
      _logApi('upload_proof_photo response', '${resp.statusCode}');

      // Retry with refreshed token on auth failure.
      if (_isAuthFailure(resp.statusCode) && await _refreshSession()) {
        final refreshedHeaders = await _authHeaders();
        final retryReq = http.MultipartRequest('POST', uri)
          ..headers.addAll(refreshedHeaders)
          ..fields['doctype'] = 'External Delivery'
          ..fields['docname'] = orderName
          ..fields['fieldname'] = 'proof_photo'
          ..fields['is_private'] = '0'
          ..files.add(
            await http.MultipartFile.fromPath(
              'file',
              filePath,
              filename: 'proof_$orderName.jpg',
            ),
          );
        streamed = await retryReq.send().timeout(_networkTimeout);
        resp = await http.Response.fromStream(streamed);
      }

      if (!_okCodes.contains(resp.statusCode)) {
        _logApi('upload_proof_photo_warn', _extractErrorMessage(resp));
        return null;
      }

      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final message = body['message'];
      if (message is Map<String, dynamic>) {
        return message['file_url']?.toString();
      }
      return null;
    } catch (e) {
      _logApi('upload_proof_photo_warn', e.toString());
      return null;
    }
  }

  /// Marks a delivery as failed:
  /// 1. Updates the trip stop status to 'Failed' and writes the reason to notes.
  /// 2. Updates the External Delivery document: status=Failed, delivery_notes,
  ///    store_notified=1.
  /// 3. Optionally uploads a proof photo (best-effort, never throws).
  Future<void> markFailedDelivery({
    required ExternalDeliveryTripStop stop,
    required String orderName,
    required String reason,
    String? photoPath,
  }) async {
    await processFailedDeliveryReturn(
      stop: stop,
      orderName: orderName,
      reason: reason,
      photoPath: photoPath,
      shouldCreateReturnTrip: false,
    );
  }

  Future<ReturnProcessResult> processFailedDeliveryReturn({
    required ExternalDeliveryTripStop stop,
    required String orderName,
    required String reason,
    String? photoPath,
    bool shouldCreateReturnTrip = true,
  }) async {
    await updateTripStopStatus(stop: stop, newStatus: 'Failed');
    await _tryMarkParentTripFailed(stop);
    await _tryWriteStopNotes(stop: stop, reason: reason);

    await _updateExternalDeliveryFields(orderName, {
      'status': shouldCreateReturnTrip ? _returnInitiatedStatus : 'Failed',
      'delivery_notes': reason,
      'store_notified': 1,
    });

    if (photoPath != null && photoPath.isNotEmpty) {
      await uploadProofPhoto(orderName: orderName, filePath: photoPath);
    }

    if (!shouldCreateReturnTrip) {
      return const ReturnProcessResult(
        success: true,
        orderUpdated: true,
        tripCreated: false,
        tripSubmitted: false,
        tripName: null,
        message: 'Delivery marked as failed.',
      );
    }

    final existingTripName = await _findExistingOpenReturnTrip(orderName);
    if (existingTripName != null) {
      return ReturnProcessResult(
        success: true,
        orderUpdated: true,
        tripCreated: false,
        tripSubmitted: false,
        tripName: existingTripName,
        message: 'Return trip already exists: $existingTripName',
      );
    }

    final tripName = await createReturnTrip(orderName: orderName);
    return ReturnProcessResult(
      success: true,
      orderUpdated: true,
      tripCreated: true,
      tripSubmitted: true,
      tripName: tripName,
      message: 'Return trip created: $tripName',
    );
  }

  /// Creates a return trip to the store for the given order and submits it.
  /// Returns the new trip name.
  Future<String> createReturnTrip({required String orderName}) async {
    final existingTripName = await _findExistingOpenReturnTrip(orderName);
    if (existingTripName != null) {
      _logApi(
        'create_return_trip reuse',
        'order=$orderName trip=$existingTripName',
      );
      return existingTripName;
    }

    final createPayload = {
      'driver': ApiConstants.defaultExternalDeliveryDriver,
      'status': 'Draft',
      'trip_date': DateTime.now().toIso8601String().split('T').first,
      'trip_notes': 'Return Trip for $orderName',
      'stops': [
        {'external_delivery': orderName},
      ],
    };
    _logApi(
      'create_return_trip request',
      'POST ${ApiConstants.externalDeliveryTripList} order=$orderName',
    );

    final createResp = await _post(
      Uri.parse(ApiConstants.externalDeliveryTripList),
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode(createPayload),
    );

    if (!_okCodes.contains(createResp.statusCode)) {
      throw Exception(_extractErrorMessage(createResp));
    }

    final createData = jsonDecode(createResp.body) as Map<String, dynamic>;
    final createdDoc = createData['data'];
    if (createdDoc is! Map<String, dynamic>) {
      throw Exception('Return trip create API returned unexpected response');
    }

    final submitResp = await _post(
      Uri.parse(ApiConstants.frappeSubmitMethod),
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({'doc': createdDoc}),
    );

    if (!_okCodes.contains(submitResp.statusCode)) {
      throw Exception(_extractErrorMessage(submitResp));
    }

    final submitData = jsonDecode(submitResp.body) as Map<String, dynamic>;
    final submittedDoc = submitData['message'] ?? submitData['data'];
    if (submittedDoc is! Map<String, dynamic>) {
      throw Exception('Return trip submit API returned unexpected response');
    }

    return (submittedDoc['name'] ?? createdDoc['name'] ?? '').toString();
  }

  Future<void> _completeTrip(ExternalDeliveryTrip trip) async {
    _logApi('mark_returned_to_store trip', 'trip=${trip.name}');
    await _setDocValue(
      doctype: 'External Delivery Trip',
      name: trip.name,
      fieldname: 'status',
      value: 'Completed',
    );
    await _setDocValue(
      doctype: 'External Delivery Trip',
      name: trip.name,
      fieldname: 'completes_stops',
      value: trip.stops.length,
    );

    try {
      await _setDocValue(
        doctype: 'External Delivery Trip',
        name: trip.name,
        fieldname: 'completed_at',
        value: DateTime.now().toIso8601String(),
      );
    } catch (e) {
      _logApi('mark_returned_to_store_completed_at_warn', e.toString());
    }
  }

  Future<void> _updateExternalDeliveryFields(
    String orderName,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse(
      '${ApiConstants.externalDeliveryList}/${Uri.encodeComponent(orderName)}',
    );
    _logApi('external_delivery_update request', '$uri body=$body');
    final resp = await _put(
      uri,
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }
  }

  Future<void> _markOrderReturned(String orderName) {
    return _updateExternalDeliveryFields(orderName, {
      'status': _returnedStatus,
      'store_notified': 1,
    });
  }

  Future<void> _markStopReturned(ExternalDeliveryTripStop stop) async {
    final stopName = (stop.rawFields['name'] ?? '').toString().trim();
    final stopDocType = (stop.rawFields['doctype'] ?? '').toString().trim();
    if (stopName.isEmpty || stopDocType.isEmpty) {
      return;
    }

    await _setDocValue(
      doctype: stopDocType,
      name: stopName,
      fieldname: 'status',
      value: _returnedStatus,
    );
  }

  Future<void> _tryMarkParentTripFailed(ExternalDeliveryTripStop stop) async {
    final parentTripName = (stop.rawFields['parent'] ?? '').toString().trim();
    if (parentTripName.isEmpty) {
      return;
    }

    try {
      await _setDocValue(
        doctype: 'External Delivery Trip',
        name: parentTripName,
        fieldname: 'status',
        value: 'Failed',
      );
    } catch (e) {
      _logApi('parent_trip_failed_warn', e.toString());
    }
  }

  Future<void> _tryWriteStopNotes({
    required ExternalDeliveryTripStop stop,
    required String reason,
  }) async {
    final stopName = (stop.rawFields['name'] ?? '').toString().trim();
    final stopDocType = (stop.rawFields['doctype'] ?? '').toString().trim();
    if (stopName.isEmpty || stopDocType.isEmpty) {
      return;
    }

    try {
      await _setDocValue(
        doctype: stopDocType,
        name: stopName,
        fieldname: 'notes',
        value: reason,
      );
    } catch (e) {
      _logApi('mark_failed_delivery_notes_warn', e.toString());
    }
  }

  Future<void> _setDocValue({
    required String doctype,
    required String name,
    required String fieldname,
    required Object value,
  }) async {
    final setValueUrl = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/method/frappe.client.set_value',
    );
    final resp = await _post(
      setValueUrl,
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'doctype': doctype,
        'name': name,
        'fieldname': fieldname,
        'value': value,
      }),
    );
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }
  }

  Future<String?> _findExistingOpenReturnTrip(String orderName) async {
    final uri = Uri.parse(ApiConstants.externalDeliveryTripList).replace(
      queryParameters: {
        'fields': jsonEncode(['name', 'status']),
        'filters': jsonEncode([
          [
            'External Delivery Trip',
            'trip_notes',
            '=',
            'Return Trip for $orderName',
          ],
          [
            'External Delivery Trip',
            'status',
            'not in',
            ['Completed', 'Cancelled'],
          ],
        ]),
        'limit_page_length': '1',
        'order_by': 'modified desc',
      },
    );
    final resp = await _get(uri, headers: await _authHeaders());
    if (!_okCodes.contains(resp.statusCode)) {
      return null;
    }

    final data = jsonDecode(resp.body)['data'];
    if (data is! List || data.isEmpty) {
      return null;
    }

    final first = data.first;
    if (first is! Map<String, dynamic>) {
      return null;
    }
    return _value(first['name']);
  }

  String _extractErrorMessage(http.Response resp) {
    String base = 'Server error ${resp.statusCode}';
    Map<String, dynamic>? map;
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) {
        map = decoded;
      }
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
    if (message is String && message.trim().isNotEmpty) {
      return message.trim();
    }
    if (message is Map<String, dynamic>) {
      final nested = (message['message'] ?? '').toString().trim();
      if (nested.isNotEmpty) return nested;
    }

    final exception = (map?['exception'] ?? '').toString().trim();
    if (exception.isNotEmpty) {
      return exception;
    }

    return base;
  }

  void _logApi(String tag, String value) {
    final String line = '[API] $tag => $value';
    debugPrint(line);
    // ignore: avoid_print
    print(line);
  }

  Future<http.Response> _get(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    _logApi('http', 'GET $uri');
    final resp = await http.get(uri, headers: headers).timeout(_networkTimeout);
    if (_isAuthFailure(resp.statusCode) && await _refreshSession()) {
      final refreshedHeaders = await _authHeaders();
      return http.get(uri, headers: refreshedHeaders).timeout(_networkTimeout);
    }
    return resp;
  }

  Future<http.Response> _post(
    Uri uri, {
    required Map<String, String> headers,
    Object? body,
  }) async {
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

  Future<http.Response> _put(
    Uri uri, {
    required Map<String, String> headers,
    Object? body,
  }) async {
    _logApi('http', 'PUT $uri');
    final resp = await http
        .put(uri, headers: headers, body: body)
        .timeout(_networkTimeout);
    if (_isAuthFailure(resp.statusCode) && await _refreshSession()) {
      final refreshedHeaders = {
        ...await _authHeaders(),
        if (headers.containsKey('Content-Type'))
          'Content-Type': headers['Content-Type']!,
      };
      return http
          .put(uri, headers: refreshedHeaders, body: body)
          .timeout(_networkTimeout);
    }
    return resp;
  }

  bool _isAuthFailure(int statusCode) => statusCode == 401 || statusCode == 403;
}
