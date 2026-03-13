import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../core/constants/api_constants.dart';
import '../model/external_delivery.dart';

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

  static const Set<int> _okCodes = {200, 201};

  Future<List<ExternalDelivery>> fetchPage({int limitStart = 0}) async {
    final uri = Uri.parse(ApiConstants.externalDeliveryList).replace(
      queryParameters: {
        'fields': jsonEncode(_fields),
        'limit_start': '$limitStart',
        'limit_page_length': '$pageSize',
        'order_by': 'store_name asc, modified desc',
      },
    );

    _logApi('external_delivery_list request', uri.toString());
    final resp = await http.get(uri, headers: {
      'Accept': 'application/json',
      'Authorization': 'token $apiKey:$apiSecret',
    });

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

    final createResp = await http.post(
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
    final submitResp = await http.post(
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

  Future<ExternalDeliveryTrip> fetchTripDetails(String tripName) async {
    final url =
        '${ApiConstants.externalDeliveryTripList}/${Uri.encodeComponent(tripName)}';
    _logApi('external_delivery_trip_details request', 'GET $url');

    final resp = await http.get(
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
    debugPrint('[API] $tag => $value');
  }
}
