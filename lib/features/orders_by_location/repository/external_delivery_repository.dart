import 'dart:convert';

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

  Future<List<ExternalDelivery>> fetchPage({int limitStart = 0}) async {
    final uri = Uri.parse(ApiConstants.externalDeliveryList).replace(
      queryParameters: {
        'fields': jsonEncode(_fields),
        'limit_start': '$limitStart',
        'limit_page_length': '$pageSize',
        'order_by': 'store_name asc, modified desc',
      },
    );

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
      throw Exception('Server error ${resp.statusCode}');
    }

    final data = (jsonDecode(resp.body)['data']) as List;
    return data
        .map((row) => ExternalDelivery.fromJson(row as Map<String, dynamic>))
        .toList();
  }
}
