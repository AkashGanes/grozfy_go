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

  Future<List<ExternalDelivery>> fetchPage({int limitStart = 0}) async {
    final uri = Uri.parse(ApiConstants.externalDeliveryList).replace(
      queryParameters: {
        'fields': jsonEncode(_fields),
        'limit_start': '$limitStart',
        'limit_page_length': '$pageSize',
        'order_by': 'store_name asc, modified desc',
      },
    );

    debugPrint('[API] fetchPage → GET $uri');

    final resp = await http.get(uri, headers: {
      'Accept': 'application/json',
      'Authorization': 'token $apiKey:$apiSecret',
    });

    debugPrint('[API] fetchPage ← ${resp.statusCode}');

    if (resp.statusCode == 401) {
      throw Exception('401: Invalid API credentials.');
    }
    if (resp.statusCode == 403) {
      throw Exception('403: Access denied. Check API permissions.');
    }
    if (resp.statusCode != 200) {
      throw Exception('Server error ${resp.statusCode}');
    }

    final data = (jsonDecode(resp.body)['data']) as List;
    debugPrint('[API] fetchPage   ${data.length} records');
    return data
        .map((row) => ExternalDelivery.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<ExternalDeliveryDetail> fetchDetail(String name) async {
    final uri = Uri.parse(
      '${ApiConstants.externalDeliveryList}/${Uri.encodeComponent(name)}',
    );

    debugPrint('[API] fetchDetail → GET $uri');

    final resp = await http.get(uri, headers: {
      'Accept': 'application/json',
      'Authorization': 'token $apiKey:$apiSecret',
    });

    debugPrint('[API] fetchDetail ← ${resp.statusCode}');

    if (resp.statusCode == 401) throw Exception('401: Invalid API credentials.');
    if (resp.statusCode == 403) throw Exception('403: Access denied. Check API permissions.');
    if (resp.statusCode != 200) throw Exception('Server error ${resp.statusCode}');

    final data = (jsonDecode(resp.body)['data']) as Map<String, dynamic>;

    // delivery_address is a Link to Address doctype — resolve the actual text
    final addressName = data['delivery_address']?.toString();
    if (addressName != null && addressName.isNotEmpty) {
      final resolved = await _fetchAddressText(addressName);
      // Replace with resolved text, or null so UI shows "Address not available"
      data['delivery_address'] = resolved;
    }

    return ExternalDeliveryDetail.fromJson(data);
  }

  Future<String?> _fetchAddressText(String addressName) async {
    final uri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/resource/Address/${Uri.encodeComponent(addressName)}',
    );

    debugPrint('[API] fetchAddress → GET $uri');

    try {
      final resp = await http.get(uri, headers: {
        'Accept': 'application/json',
        'Authorization': 'token $apiKey:$apiSecret',
      });

      debugPrint('[API] fetchAddress ← ${resp.statusCode}');

      if (resp.statusCode != 200) return null;

      final d = (jsonDecode(resp.body)['data']) as Map<String, dynamic>;

      // Build readable address from Address fields
      final parts = <String>[
        if (_v(d['address_line1']) != null) _v(d['address_line1'])!,
        if (_v(d['address_line2']) != null) _v(d['address_line2'])!,
        if (_v(d['city']) != null) _v(d['city'])!,
        if (_v(d['state']) != null) _v(d['state'])!,
        if (_v(d['pincode']) != null) _v(d['pincode'])!,
        if (_v(d['country']) != null) _v(d['country'])!,
      ];

      return parts.isNotEmpty ? parts.join(', ') : null;
    } catch (_) {
      return null;
    }
  }

  String? _v(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }
}
