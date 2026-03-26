import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../model/external_delivery.dart';
import '../model/external_delivery_detail.dart';

class ExternalDeliveryRepository {
  ExternalDeliveryRepository({
    this.apiKey = ApiConstants.apiKey,
    this.apiSecret = ApiConstants.apiSecret,
  });

  final String apiKey;
  final String apiSecret;

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
    'total_stops',
    'completes_stops',
    'modified',
  ];

  static const Set<int> _okCodes = {200, 201};
  static const Duration _networkTimeout = Duration(seconds: 15);

  Future<List<String>> fetchStoreNames() async {
    final uri = Uri.parse(ApiConstants.externalDeliveryList).replace(
      queryParameters: {
        'fields': jsonEncode(['store_name']),
        'limit_page_length': '500',
        'order_by': 'store_name asc',
      },
    );

    _logApi('fetch_store_names request', uri.toString());
    final resp = await _get(
      uri,
      headers: {
        'Accept': 'application/json',
        'Authorization': 'token $apiKey:$apiSecret',
      },
    );

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
    String? storeName,
  }) async {
    final params = <String, String>{
      'fields': jsonEncode(_fields),
      'limit_start': '$limitStart',
      'limit_page_length': '$pageSize',
      'order_by': 'store_name asc, modified desc',
    };
    if (storeName != null && storeName.isNotEmpty) {
      params['filters'] = jsonEncode([
        ['External Delivery', 'store_name', '=', storeName],
      ]);
    }

    final uri = Uri.parse(
      ApiConstants.externalDeliveryList,
    ).replace(queryParameters: params);

    _logApi('external_delivery_list request', uri.toString());
    final resp = await _get(
      uri,
      headers: {
        'Accept': 'application/json',
        'Authorization': 'token $apiKey:$apiSecret',
      },
    );

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

  Future<ExternalDeliveryDetail> fetchDetail(String name) async {
    final uri = Uri.parse(
      '${ApiConstants.externalDeliveryList}/${Uri.encodeComponent(name)}',
    );
    _logApi('external_delivery_detail request', uri.toString());

    final resp = await _get(
      uri,
      headers: {
        'Accept': 'application/json',
        'Authorization': 'token $apiKey:$apiSecret',
      },
    );

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
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'token $apiKey:$apiSecret',
      },
      body: jsonEncode({'status': status}),
    );

    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }
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
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'token $apiKey:$apiSecret',
      },
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
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'token $apiKey:$apiSecret',
      },
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

    final resp = await _get(
      uri,
      headers: {
        'Accept': 'application/json',
        'Authorization': 'token $apiKey:$apiSecret',
      },
    );

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

    final resp = await _get(
      Uri.parse(url),
      headers: {
        'Accept': 'application/json',
        'Authorization': 'token $apiKey:$apiSecret',
      },
    );

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
      final resp = await _get(
        uri,
        headers: {
          'Accept': 'application/json',
          'Authorization': 'token $apiKey:$apiSecret',
        },
      );

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
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'Authorization': 'token $apiKey:$apiSecret',
      },
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

    if (newStatus.toLowerCase() == 'delivered' &&
        stop.deliveredAt.trim().isEmpty) {
      // Best-effort only: status update is already successful.
      // Some setups restrict direct writes to delivered_at.
      try {
        final deliveredAtResp = await _post(
          setValueUrl,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            'Authorization': 'token $apiKey:$apiSecret',
          },
          body: jsonEncode({
            'doctype': stopDocType,
            'name': stopName,
            'fieldname': 'delivered_at',
            'value': DateTime.now().toIso8601String(),
          }),
        );
        if (!_okCodes.contains(deliveredAtResp.statusCode)) {
          _logApi(
            'external_delivery_trip_stop_delivered_at_warn',
            _extractErrorMessage(deliveredAtResp),
          );
        }
      } catch (e) {
        _logApi('external_delivery_trip_stop_delivered_at_warn', e.toString());
      }
    }
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

  Future<http.Response> _get(Uri uri, {required Map<String, String> headers}) {
    _logApi('http', 'GET $uri');
    return http.get(uri, headers: headers).timeout(_networkTimeout);
  }

  Future<http.Response> _post(
    Uri uri, {
    required Map<String, String> headers,
    Object? body,
  }) {
    _logApi('http', 'POST $uri');
    return http
        .post(uri, headers: headers, body: body)
        .timeout(_networkTimeout);
  }

  Future<http.Response> _put(
    Uri uri, {
    required Map<String, String> headers,
    Object? body,
  }) {
    _logApi('http', 'PUT $uri');
    return http.put(uri, headers: headers, body: body).timeout(_networkTimeout);
  }
}
