import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/localization/localized_text.dart';
import '../../../core/services/secure_token_storage.dart';
import '../model/cod_handover.dart';
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

  static const String _prefLanguageCode = 'language_code';
  static final Uri _refreshTokenUri = Uri.parse(
    '${ApiConstants.erpBaseUrl}/api/method/frappe.integrations.oauth2.get_token',
  );

  static const String _prefDriverName = 'driver_name';

  // Cached per-instance so the 100+ calls in downloadAllTripsAtTripStart
  // don't each re-read SharedPreferences + keychain. Invalidated on token refresh.
  Map<String, String>? _cachedHeaders;

  Future<String> _getLoggedInDriver() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_prefDriverName)?.trim() ?? '';
    return name.isNotEmpty ? name : ApiConstants.defaultExternalDeliveryDriver;
  }

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

  /// Refreshes the session token using Frappe's OAuth2 get_token endpoint.
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

      _logApi('refresh_token', 'POST $_refreshTokenUri');
      final resp = await http
          .post(
            _refreshTokenUri,
            headers: {
              'Accept': 'application/json',
              'Accept-Language': await _languageHeader(),
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
      await SecureTokenStorage.write(SecureTokenStorage.accessToken, newToken);
      if (newType != null && newType.isNotEmpty) {
        await SecureTokenStorage.write(SecureTokenStorage.tokenType, newType);
      }
      if (newRefresh != null && newRefresh.isNotEmpty) {
        await SecureTokenStorage.write(
          SecureTokenStorage.refreshToken,
          newRefresh,
        );
      }
      _cachedHeaders = null;
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
    'store_name',
    'store_url',
    'customer_name',
    'status',
    'delivery_address',
    'failure_reason_code',
    'delivery_notes',
  ];

  // Fields fetched via frappe.desk.reportview.get for the listing screen.
  // That endpoint is used by the Frappe desk itself and is not subject to the
  // in_list_view field restriction that rejects grand_total on the REST API.
  // Fields confirmed to be queryable via frappe.desk.reportview.get.
  // pickup_address / payment_mode / grand_total are restricted by the server
  // and must stay out — Frappe rejects the whole request on the first bad field.
  static const List<String> _enrichedFields = [
    'name',
    'creation',
    'modified',
    'store_name',
    'store_url',
    'customer_name',
    'status',
    'contact_mobile',
    'latitude',
    'longitude',
    'delivery_address',
    'payment_method',
    'payment_mode',
    'grand_total',
    'cod_amount_to_collect',
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
  static const Duration _fileUploadTimeout = Duration(seconds: 60);
  static const String _returnInitiatedStatus = 'Return Initiated';
  static const String _returnedStatus = 'Returned';

  Future<List<String>> fetchStoreNames() async {
    final uri = Uri.parse(ApiConstants.externalDeliveryList).replace(
      queryParameters: {
        'fields': jsonEncode(['store_name']),
        'filters': jsonEncode([
          ['External Delivery', 'status', '=', 'Pending'],
        ]),
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
    String? orderBy,
    List<List<dynamic>>? filters,
    List<List<dynamic>>? orFilters,
  }) async {
    // When a single store is selected, store_name is constant for every row,
    // so sorting by it is wasted server work. Order by `modified` alone — an
    // indexed column — which the DB can satisfy from the index. The grouped
    // sort (store_name asc) is only needed for the "All Stores" view, where the
    // UI groups rows under per-store headers.
    final String effectiveOrderBy = orderBy ??
        (storeName != null && storeName.isNotEmpty
            ? 'modified desc'
            : 'store_name asc, modified desc');
    final List<List<dynamic>> effectiveFilters = <List<dynamic>>[
      if (filters != null) ...filters,
      if (storeName != null && storeName.isNotEmpty)
        <dynamic>['External Delivery', 'store_name', '=', storeName],
    ];

    // Request the delivery coordinates so the screen can apply the
    // delivery-radius filter. These fields may be rejected by the server's
    // in_list_view restriction (it rejects the whole request on the first bad
    // field), so fall back to the base fields once — the radius filter then
    // simply no-ops for this page rather than the list failing to load.
    final List<String> geoFields = <String>[
      ..._fields,
      'latitude',
      'longitude',
    ];

    Future<http.Response> requestWith(List<String> fields) async {
      final params = <String, String>{
        'fields': jsonEncode(fields),
        'limit_start': '$limitStart',
        'limit_page_length': '$limitPageLength',
        'order_by': effectiveOrderBy,
      };
      if (effectiveFilters.isNotEmpty) {
        params['filters'] = jsonEncode(effectiveFilters);
      }
      if (orFilters != null && orFilters.isNotEmpty) {
        params['or_filters'] = jsonEncode(orFilters);
      }
      final uri = Uri.parse(
        ApiConstants.externalDeliveryList,
      ).replace(queryParameters: params);
      _logApi('external_delivery_list request', uri.toString());
      return _get(uri, headers: await _authHeaders());
    }

    // Time the round-trip so slow loads can be attributed to the server vs the
    // app. Look for "external_delivery_list timing" in the logs.
    final Stopwatch sw = Stopwatch()..start();
    http.Response resp = await requestWith(geoFields);
    // 417 is Frappe's typical "invalid field" response; retry without geo on any
    // 4xx that isn't an auth failure, so a missing column never breaks the list.
    if (resp.statusCode != 200 &&
        resp.statusCode != 401 &&
        resp.statusCode != 403) {
      _logApi(
        'external_delivery_list geo fallback',
        'status=${resp.statusCode}; retrying without latitude/longitude',
      );
      resp = await requestWith(_fields);
    }
    final int networkMs = sw.elapsedMilliseconds;

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
    final List<ExternalDelivery> result = data
        .map((row) => ExternalDelivery.fromJson(row as Map<String, dynamic>))
        .toList();
    _logApi(
      'external_delivery_list timing',
      'network=${networkMs}ms parse+total=${sw.elapsedMilliseconds}ms '
          'rows=${result.length} storeFilter=${storeName ?? "ALL"}',
    );
    return result;
  }

  /// Fetches the driver's **available** (Pending) deliveries filtered by their
  /// configured delivery radius, via the custom `list_available_deliveries`
  /// method. Unlike [fetchPage] — which hits the generic REST list and is
  /// radius-blind — the server here filters by the driver's selected radius and
  /// returns the *full* set in a single call, each row carrying a
  /// server-computed `distance_km`.
  ///
  /// [storeName] and [filters] (the same status/date/customer Frappe clauses the
  /// list screen already builds) are forwarded so those filters keep working
  /// server-side. Expected response envelope, mirroring the other custom driver
  /// endpoints (e.g. `list_pickup_pool`):
  ///
  /// ```json
  /// { "message": [ { "name": ..., "store_name": ..., "distance_km": 1.8, ... } ] }
  /// ```
  Future<List<ExternalDelivery>> fetchAvailableDeliveries({
    String? storeName,
    List<List<dynamic>>? filters,
  }) async {
    final driver = await _getLoggedInDriver();
    final params = <String, String>{'driver': driver};
    if (storeName != null && storeName.isNotEmpty) {
      params['store_name'] = storeName;
    }
    if (filters != null && filters.isNotEmpty) {
      params['filters'] = jsonEncode(filters);
    }

    final uri = Uri.parse(
      ApiConstants.listAvailableDeliveries,
    ).replace(queryParameters: params);
    _logApi('list_available_deliveries request', uri.toString());

    final sw = Stopwatch()..start();
    final resp = await _get(uri, headers: await _authHeaders());
    final int networkMs = sw.elapsedMilliseconds;

    if (resp.statusCode == 401) {
      throw Exception('401: Invalid API credentials.');
    }
    if (resp.statusCode == 403) {
      throw Exception('403: Access denied. Check API permissions.');
    }
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final message = decoded['message'];
    if (message is! List) return <ExternalDelivery>[];

    final result = message
        .whereType<Map<String, dynamic>>()
        .map(ExternalDelivery.fromJson)
        .toList();

    // The list UI inserts a StoreHeader whenever store_name changes between
    // consecutive rows, so rows must be grouped by store. A custom method's
    // ordering isn't guaranteed, so enforce the same order the generic path used
    // (store_name asc, then modified desc). distance_km is parsed onto the model
    // but intentionally not used for ordering.
    result.sort((a, b) {
      final byStore = a.storeName.compareTo(b.storeName);
      if (byStore != 0) return byStore;
      return b.modified.compareTo(a.modified);
    });

    _logApi(
      'list_available_deliveries timing',
      'network=${networkMs}ms rows=${result.length} '
          'storeFilter=${storeName ?? "ALL"}',
    );
    return result;
  }

  /// Fetches a full page of order details in a single HTTP call using the
  /// Frappe desk reportview endpoint. This endpoint is used by the Frappe UI
  /// itself and is not subject to the in_list_view field restriction that the
  /// REST list API enforces, allowing fields like grand_total to be included.
  ///
  /// Response format: {"message": {"keys": [...], "values": [[...], ...]}}
  Future<List<ExternalDeliveryDetail>> fetchPageEnriched({
    int limitStart = 0,
    int limitPageLength = pageSize,
    String orderBy = 'modified desc',
    List<List<dynamic>> filters = const [],
    List<List<dynamic>> orFilters = const [],
  }) async {
    final uri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/method/frappe.desk.reportview.get',
    );

    _logApi('fetch_enriched_list request', uri.toString());
    final body = <String, String>{
      'doctype': 'External Delivery',
      'fields': jsonEncode(_enrichedFields),
      'filters': jsonEncode(filters),
      'order_by': orderBy,
      'start': '$limitStart',
      'page_length': '$limitPageLength',
      'with_comment_count': '0',
    };
    if (orFilters.isNotEmpty) {
      body['or_filters'] = jsonEncode(orFilters);
    }
    final resp = await _post(
      uri,
      headers: {
        ...await _authHeaders(),
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
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

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final result = decoded['message'] as Map<String, dynamic>?;
    if (result == null) throw Exception('Unexpected reportview response');

    final keys = (result['keys'] as List<dynamic>).cast<String>();
    final values = (result['values'] as List<dynamic>).cast<List<dynamic>>();

    return values.map((row) {
      final m = <String, dynamic>{
        for (int i = 0; i < keys.length && i < row.length; i++)
          keys[i]: row[i],
      };
      return ExternalDeliveryDetail.fromJson(m);
    }).toList();
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

  /// Fetches active orders for the logged-in driver via their trip stops.
  /// Uses External Delivery Trip (driver filter permitted) → stop names
  /// → parallel detail fetches. Typically 1 active trip with a few stops.
  Future<List<ExternalDeliveryDetail>> fetchActiveOrdersForDriver() async {
    final driver = await _getLoggedInDriver();

    // 1. Get driver's submitted trips that are NOT completed
    final tripUri = Uri.parse(ApiConstants.externalDeliveryTripList).replace(
      queryParameters: {
        'fields': jsonEncode(['name', 'status', 'docstatus']),
        'filters': jsonEncode([
          ['External Delivery Trip', 'driver', '=', driver],
          ['External Delivery Trip', 'docstatus', '=', '1'],
          ['External Delivery Trip', 'status', '!=', 'Completed'],
        ]),
        'limit_page_length': '10',
        'order_by': 'modified desc',
      },
    );
    _logApi('fetch_active_trips request', tripUri.toString());
    final tripResp = await _get(tripUri, headers: await _authHeaders());
    if (!_okCodes.contains(tripResp.statusCode)) {
      throw Exception(_extractErrorMessage(tripResp));
    }
    final tripRows = (jsonDecode(tripResp.body)['data']) as List;
    if (tripRows.isEmpty) return [];

    // 2. Fetch trip details for each active trip in parallel (usually just 1)
    final tripNames = tripRows
        .map((row) => (row as Map<String, dynamic>)['name']?.toString() ?? '')
        .where((name) => name.isNotEmpty)
        .toList();

    final tripResults = await Future.wait(
      tripNames.map((name) async {
        try {
          return await fetchTripDetails(name);
        } catch (_) {
          return null;
        }
      }),
    );

    final allStopNames = <String>[];
    for (final trip in tripResults.whereType<ExternalDeliveryTrip>()) {
      for (final stop in trip.stops) {
        if (stop.externalDelivery.isNotEmpty) {
          allStopNames.add(stop.externalDelivery);
        }
      }
    }
    if (allStopNames.isEmpty) return [];

    // 3. Fetch delivery details in parallel
    final results = await Future.wait(
      allStopNames.map((name) async {
        try {
          return await fetchDetail(name);
        } catch (_) {
          return null;
        }
      }),
    );

    const _inactiveStatuses = {
      'delivered', 'cancelled', 'returned', 'canceled', 'return initiated', 'failed',
    };

    // 4. Keep only orders that are still in progress
    return results
        .whereType<ExternalDeliveryDetail>()
        .where((d) => !_inactiveStatuses.contains(d.status.trim().toLowerCase()))
        .toList();
  }

  /// Fetches past orders for the logged-in driver directly from
  /// `External Delivery` using the `driver` field added in the backend.
  Future<int> fetchPastOrdersCountForDriver() async {
    final driver = await _getLoggedInDriver();
    final uri = Uri.parse(ApiConstants.externalDeliveryList).replace(
      queryParameters: {
        'fields': jsonEncode(['name']),
        'filters': jsonEncode([
          ['External Delivery', 'driver', '=', driver],
          [
            'External Delivery',
            'status',
            'in',
            <String>[
              'Delivered',
              'Cancelled',
              'Failed',
              'Returned',
              'Return Initiated',
            ],
          ],
        ]),
        'limit_page_length': '0',
      },
    );
    final resp = await _get(uri, headers: await _authHeaders());
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }
    final data = (jsonDecode(resp.body)['data']) as List;
    return data.length;
  }

  Future<List<ExternalDelivery>> fetchPastOrdersForDriver({
    int limitStart = 0,
    int limitPageLength = 20,
  }) async {
    final driver = await _getLoggedInDriver();
    final uri = Uri.parse(ApiConstants.externalDeliveryList).replace(
      queryParameters: {
        'fields': jsonEncode(_fields),
        'filters': jsonEncode([
          ['External Delivery', 'driver', '=', driver],
          [
            'External Delivery',
            'status',
            'in',
            <String>[
              'Delivered',
              'Cancelled',
              'Failed',
              'Returned',
              'Return Initiated',
            ],
          ],
        ]),
        'limit_start': '$limitStart',
        'limit_page_length': '$limitPageLength',
        'order_by': 'modified desc',
      },
    );
    _logApi('fetch_past_orders request', uri.toString());
    final resp = await _get(uri, headers: await _authHeaders());
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }

    final data = (jsonDecode(resp.body)['data']) as List;
    return data
        .map((row) => ExternalDelivery.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Fetches active orders for the logged-in driver directly from
  /// `External Delivery` using the backend `driver` field.
  Future<List<ExternalDelivery>> fetchActiveOrdersForDriverDirect() async {
    final driver = await _getLoggedInDriver();
    final uri = Uri.parse(ApiConstants.externalDeliveryList).replace(
      queryParameters: {
        'fields': jsonEncode(_fields),
        'filters': jsonEncode([
          ['External Delivery', 'driver', '=', driver],
          [
            'External Delivery',
            'status',
            'in',
            <String>[
              'Accepted',
              'Added to Trip',
              'Reached Pickup',
              'Picked Up',
              'Out for Delivery',
            ],
          ],
        ]),
        'limit_page_length': '20',
        'order_by': 'modified desc',
      },
    );
    _logApi('fetch_active_orders request', uri.toString());
    final resp = await _get(uri, headers: await _authHeaders());
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }

    final data = (jsonDecode(resp.body)['data']) as List;
    return data
        .map((row) => ExternalDelivery.fromJson(row as Map<String, dynamic>))
        .toList();
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

  /// Returns total delivered orders for the logged-in driver.
  /// Total delivered orders for the logged-in driver, in a single API call.
  ///
  /// Counts `External Delivery` records with `driver = <me>` and
  /// `status = 'Delivered'` — the same order-level source of truth that
  /// [fetchPastOrdersForDriver] filters on, so the number matches what the
  /// driver sees in their orders list.
  ///
  /// NOTE: This previously fetched *every* trip and then the *full detail of
  /// every trip* (one HTTP GET each) just to count delivered stops — an N+1
  /// that fired 50+ serial requests and saturated the network. The order
  /// doctype already carries `driver` + `status`, so one filtered list call
  /// gives the same count. We request only `name` and read `data.length`.
  Future<int> fetchDeliveredCountForDriver() async {
    final driver = await _getLoggedInDriver();
    final uri = Uri.parse(ApiConstants.externalDeliveryList).replace(
      queryParameters: {
        'fields': jsonEncode(['name']),
        'filters': jsonEncode([
          ['External Delivery', 'driver', '=', driver],
          ['External Delivery', 'status', '=', 'Delivered'],
        ]),
        'limit_page_length': '0',
      },
    );
    final resp = await _get(uri, headers: await _authHeaders());
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }
    final data = (jsonDecode(resp.body)['data']) as List;
    return data.length;
  }

  /// Fetches multiple External Delivery records in ONE API call using Frappe's
  /// `"name","in",[...]` filter, instead of one HTTP request per order.
  /// Processes up to 500 names per page to stay within URL-length limits.
  /// Does NOT resolve delivery addresses — use for bulk prefetch/caching only.
  Future<List<ExternalDeliveryDetail>> fetchOrdersBatch(
    List<String> names,
  ) async {
    if (names.isEmpty) return [];
    const maxPerPage = 500;
    final all = <ExternalDeliveryDetail>[];
    final headers = await _authHeaders();
    for (int i = 0; i < names.length; i += maxPerPage) {
      final end = (i + maxPerPage).clamp(0, names.length);
      final chunk = names.sublist(i, end);
      final uri = Uri.parse(ApiConstants.externalDeliveryList).replace(
        queryParameters: {
          'fields': jsonEncode([
            'name', 'store_name', 'store_url', 'customer_name', 'status',
            'contact_mobile', 'delivery_address', 'pickup_address',
            'latitude', 'longitude', 'geolocation', 'payment_mode',
            'grand_total', 'creation', 'modified', 'proof_photo',
            'failure_reason_code', 'delivery_notes',
          ]),
          'filters': jsonEncode([['name', 'in', chunk]]),
          'limit_page_length': '${chunk.length}',
        },
      );
      _logApi('fetch_orders_batch request (${chunk.length})', uri.toString());
      final resp = await _get(uri, headers: headers);
      if (!_okCodes.contains(resp.statusCode)) {
        throw Exception(_extractErrorMessage(resp));
      }
      final data = (jsonDecode(resp.body)['data']) as List;
      all.addAll(
        data.map((row) => ExternalDeliveryDetail.fromJson(row as Map<String, dynamic>)),
      );
    }
    return all;
  }

  Future<ExternalDeliveryDetail> fetchDetail(
    String name, {
    bool resolveAddress = true,
  }) async {
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
    _logApi(
      'fetchDetail_cod_fields',
      'payment_method=${data['payment_method']} '
      'payment_mode=${data['payment_mode']} '
      'mode_of_payment=${data['mode_of_payment']} '
      'cod_amount_to_collect=${data['cod_amount_to_collect']} '
      'grand_total=${data['grand_total']} '
      'amount=${data['amount']} '
      'total=${data['total']} '
      'total_amount=${data['total_amount']}',
    );
    _logApi('fetchDetail_all_keys', data.keys.join(', '));
    if (resolveAddress) {
      final addressName = data['delivery_address']?.toString();
      if (addressName != null && addressName.isNotEmpty) {
        final resolved = await _fetchAddressText(addressName);
        if (resolved != null) {
          data['delivery_address'] = resolved;
        }
      }
    }

    return ExternalDeliveryDetail.fromJson(data);
  }

  /// Sends a driver location ping. The [recordedAt] timestamp is the moment
  /// the ping was *captured* on device, not when it was flushed — the server
  /// uses it as the idempotency key so retries from the offline queue don't
  /// double-write.
  Future<void> sendLocationPing({
    required double latitude,
    required double longitude,
    required DateTime recordedAt,
  }) async {
    final driver = await _getLoggedInDriver();
    final uri = Uri.parse(ApiConstants.driverLocationPing);
    _logApi(
      'driver_location_ping request',
      'POST $uri driver=$driver lat=$latitude lng=$longitude at=$recordedAt',
    );
    final resp = await _post(
      uri,
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'driver': driver,
        'latitude': latitude,
        'longitude': longitude,
        'recorded_at': recordedAt.toUtc().toIso8601String(),
      }),
    );
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }
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

  Future<String> createTripForOrders(
    List<ExternalDelivery> orders,
  ) async {
    if (orders.isEmpty) {
      throw Exception('No orders provided for trip creation');
    }

    // 'docstatus': 1 + status 'Scheduled' — same pattern as the working
    // single-order path (createTripByOrderName) — so a multi-order batch
    // trip is born Submitted instead of Draft. Frappe defaults docstatus
    // to 0 on insert when omitted, which is what left these trips Draft
    // (and invisible to fetchActiveOrdersForDriver's docstatus=1 filter).
    final createPayload = {
      'driver': await _getLoggedInDriver(),
      'status': 'Scheduled',
      'docstatus': 1,
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

    return (createdDoc['name'] ?? '').toString();
  }

  Future<String> createTripForOrderName(String orderName) async {
    final createPayload = {
      'driver': await _getLoggedInDriver(),
      'status': 'Draft',
      'trip_date': DateTime.now().toIso8601String().split('T').first,
      'stops': [
        {'external_delivery': orderName},
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

    return (createdDoc['name'] ?? '').toString();
  }

  Future<String> createTripForOrder(ExternalDelivery order) async {
    final createPayload = {
      'driver': await _getLoggedInDriver(),
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

    return (createdDoc['name'] ?? '').toString();
  }

  /// Stamps the logged-in driver's name on the External Delivery order record.
  /// Called after order acceptance so the order is queryable by driver even
  /// when SharedPreferences are cleared (e.g. after logout/login).
  Future<void> setDriverOnOrder(String orderName, String driverName) {
    _logApi('set_driver_on_order', 'order=$orderName driver=$driverName');
    return _setDocValue(
      doctype: 'External Delivery',
      name: orderName,
      fieldname: 'driver',
      value: driverName,
    );
  }

  /// Returns the first in-progress [ExternalDeliveryTrip] for [driverName].
  /// [driverName] is passed in explicitly so callers don't depend on
  /// SharedPreferences being flushed yet (avoids a race on login restore).
  Future<ExternalDeliveryTrip?> fetchFirstActiveTripWithOrders(
    String driverName,
  ) async {
    // Terminal stop statuses — anything else means the stop (and trip) is active.
    const terminalStopStatuses = {
      'delivered', 'failed', 'returned', 'return initiated', 'cancelled',
    };

    final tripUri = Uri.parse(ApiConstants.externalDeliveryTripList).replace(
      queryParameters: {
        'fields': jsonEncode(['name', 'status']),
        'filters': jsonEncode([
          ['External Delivery Trip', 'driver', '=', driverName],
          ['External Delivery Trip', 'status', 'not in', ['Completed', 'Cancelled']],
        ]),
        'limit_page_length': '5',
        'order_by': 'modified desc',
      },
    );
    _logApi('fetch_first_active_trip request', tripUri.toString());
    final tripResp = await _get(tripUri, headers: await _authHeaders());
    if (!_okCodes.contains(tripResp.statusCode)) return null;

    final tripRows = (jsonDecode(tripResp.body)['data']) as List?;
    if (tripRows == null || tripRows.isEmpty) return null;

    for (final row in tripRows) {
      final tripName = (row as Map<String, dynamic>)['name']?.toString() ?? '';
      if (tripName.isEmpty) continue;
      try {
        final trip = await fetchTripDetails(tripName);
        // Return this trip if any stop is not yet in a terminal state.
        final hasActiveStop = trip.stops.any(
          (s) => !terminalStopStatuses.contains(s.status.trim().toLowerCase()),
        );
        if (hasActiveStop) return trip;
      } catch (_) {}
    }
    return null;
  }

  /// Returns a map of orderId → tripName for all active trips assigned to
  /// [driverName]. Covers all active trips (not just the first one) so every
  /// in-progress order can be linked to its trip after a logout/login.
  Future<Map<String, String>> fetchActiveTripOrderMap(
    String driverName,
  ) async {
    const terminalStopStatuses = {
      'delivered', 'failed', 'returned', 'return initiated', 'cancelled',
    };

    final tripUri = Uri.parse(ApiConstants.externalDeliveryTripList).replace(
      queryParameters: {
        'fields': jsonEncode(['name', 'status']),
        'filters': jsonEncode([
          ['External Delivery Trip', 'driver', '=', driverName],
          ['External Delivery Trip', 'status', 'not in', ['Completed', 'Cancelled']],
        ]),
        'limit_page_length': '20',
        'order_by': 'modified desc',
      },
    );
    final tripResp = await _get(tripUri, headers: await _authHeaders());
    if (!_okCodes.contains(tripResp.statusCode)) return {};

    final tripRows = (jsonDecode(tripResp.body)['data']) as List?;
    if (tripRows == null || tripRows.isEmpty) return {};

    final Map<String, String> orderToTrip = {};
    for (final row in tripRows) {
      final tripName = (row as Map<String, dynamic>)['name']?.toString() ?? '';
      if (tripName.isEmpty) continue;
      try {
        final trip = await fetchTripDetails(tripName);
        for (final stop in trip.stops) {
          final orderId = stop.externalDelivery.trim();
          if (orderId.isNotEmpty &&
              !terminalStopStatuses.contains(
                stop.status.trim().toLowerCase(),
              )) {
            orderToTrip[orderId] = tripName;
          }
        }
      } catch (_) {}
    }
    return orderToTrip;
  }

  /// Creates a single-stop trip using only the order name string.
  /// Used by the order acceptance flow in [AppController]. Sends docstatus=1
  /// and status=Scheduled in the create payload so the trip is born Submitted.
  Future<String> createTripByOrderName(String orderName) async {
    final createPayload = <String, dynamic>{
      'driver': await _getLoggedInDriver(),
      'status': 'Scheduled',
      'docstatus': 1,
      'trip_date': DateTime.now().toIso8601String().split('T').first,
      'stops': <Map<String, String>>[
        {'external_delivery': orderName},
      ],
    };

    _logApi(
      'external_delivery_trip_create request',
      'POST ${ApiConstants.externalDeliveryTripList} order=$orderName',
    );

    final createResp = await _post(
      Uri.parse(ApiConstants.externalDeliveryTripList),
      headers: <String, String>{
        ...await _authHeaders(),
        'Content-Type': 'application/json',
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

    return (createdDoc['name'] ?? '').toString();
  }

  Future<List<ExternalDeliveryTripSummary>> fetchTripPage({
    int limitStart = 0,
  }) async {
    final driver = await _getLoggedInDriver();
    final uri = Uri.parse(ApiConstants.externalDeliveryTripList).replace(
      queryParameters: {
        'fields': jsonEncode(_tripFields),
        'filters': jsonEncode([
          ['External Delivery Trip', 'driver', '=', driver],
        ]),
        'limit_start': '$limitStart',
        'limit_page_length': '$pageSize',
        'order_by': 'modified desc',
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
    final uri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/method/frappe.desk.form.load.getdoc',
    ).replace(queryParameters: {
      'doctype': 'External Delivery Trip',
      'name': tripName,
    });
    _logApi('external_delivery_trip_details request', 'GET $uri');

    final resp = await _get(uri, headers: await _authHeaders());

    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }

    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final docs = decoded['docs'];
    if (docs is! List || docs.isEmpty) {
      throw Exception('Trip details not found: $tripName');
    }
    return ExternalDeliveryTrip.fromJson(docs[0] as Map<String, dynamic>);
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

  /// Variant of [updateTripStopStatus] that doesn't need an in-memory
  /// stop object — used by the offline sync queue, which only persists
  /// raw doctype + name + parent + status. Skips the side-effects
  /// (delivered_at stamp, completes_stops increment) — those are best
  /// left to the live update path; the eventual cache refresh from
  /// fetchTripDetails will pick up the server's authoritative values.
  Future<void> setStopStatusRaw({
    required String stopDocType,
    required String stopName,
    required String parentTripName,
    required String newStatus,
  }) async {
    if (stopDocType.isEmpty || stopName.isEmpty) {
      throw Exception('Missing stop doctype/name for status sync');
    }
    final setValueUrl = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/method/frappe.client.set_value',
    );
    _logApi(
      'queued_stop_status_flush',
      'doctype=$stopDocType name=$stopName status=$newStatus',
    );
    final resp = await _post(
      setValueUrl,
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'doctype': stopDocType,
        'name': stopName,
        'fieldname': 'status',
        'value': newStatus,
      }),
    );
    if (!_okCodes.contains(resp.statusCode)) {
      // Dump full response body so the server traceback (exc / exc_type)
      // is visible when set_value is rejected — needed to chase down
      // server-side hooks/workflows triggered by stop status updates.
      _logApi(
        'queued_stop_status_flush_error',
        'code=${resp.statusCode} body=${resp.body}',
      );
      throw Exception(_extractErrorMessage(resp));
    }
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

  /// Looks up the trip stop for [deliveryId] inside [tripId] and updates its
  /// status. Used when the driver advances order status outside the trip screen.
  Future<void> updateTripStopStatusByDelivery({
    required String tripId,
    required String deliveryId,
    required String newStatus,
  }) async {
    final trip = await fetchTripDetails(tripId);
    final stop = trip.stops.firstWhere(
      (s) => s.externalDelivery.trim() == deliveryId.trim(),
      orElse: () =>
          throw Exception('Stop not found for delivery $deliveryId in trip $tripId'),
    );
    await updateTripStopStatus(stop: stop, newStatus: newStatus);
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

  /// Uploads a proof photo and writes its URL to the [proof_photo] field of
  /// the External Delivery document. Returns the remote file URL on success,
  /// or null on failure (best-effort — callers must not throw on null).
  Future<String?> uploadProofPhoto({
    required String orderName,
    required String filePath,
  }) async {
    try {
      final uri = Uri.parse(
        '${ApiConstants.erpBaseUrl}/api/method/upload_file',
      );

      Future<http.Response> doUpload(Map<String, String> headers) async {
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
        return http.Response.fromStream(
          await req.send().timeout(_fileUploadTimeout),
        );
      }

      _logApi('upload_proof_photo request', 'POST $uri order=$orderName');
      http.Response? resp;
      try {
        resp = await doUpload(await _authHeaders());
        _logApi(
          'upload_proof_photo response',
          '${resp.statusCode} body=${resp.body}',
        );
      } on TimeoutException catch (e) {
        _logApi('upload_proof_photo_warn', e.toString());
        final String? recovered = await _recoverProofPhotoUrl(orderName);
        if (recovered != null) {
          try {
            await _setDocValue(
              doctype: 'External Delivery',
              name: orderName,
              fieldname: 'proof_photo',
              value: recovered,
            );
          } catch (setError) {
            _logApi('upload_proof_photo_set_warn', setError.toString());
          }
          return recovered;
        }
        return null;
      }

      // Retry once on auth failure with a refreshed token.
      if (_isAuthFailure(resp.statusCode) && await _refreshSession()) {
        resp = await doUpload(await _authHeaders());
        _logApi(
          'upload_proof_photo retry response',
          '${resp.statusCode} body=${resp.body}',
        );
      }

      if (!_okCodes.contains(resp.statusCode)) {
        _logApi('upload_proof_photo_warn', _extractErrorMessage(resp));
        return null;
      }

      // Frappe may return file_url as a nested map OR as a plain string
      // depending on the version. Handle both.
      final String? fileUrl = _extractFileUrl(resp.body);
      if (fileUrl == null || fileUrl.isEmpty) {
        _logApi(
          'upload_proof_photo_warn',
          'no file_url in response body: ${resp.body}',
        );
        return null;
      }

      // upload_file creates the File document (visible in Attachments) but
      // does NOT always write back to the parent field. Use set_value — the
      // most reliable single-field update — to explicitly set proof_photo.
      try {
        await _setDocValue(
          doctype: 'External Delivery',
          name: orderName,
          fieldname: 'proof_photo',
          value: fileUrl,
        );
        _logApi('upload_proof_photo', 'proof_photo field set → $fileUrl');
      } catch (e) {
        _logApi('upload_proof_photo_set_warn', e.toString());
      }

      return fileUrl;
    } catch (e) {
      _logApi('upload_proof_photo_warn', e.toString());
      return null;
    }
  }

  Future<String?> _recoverProofPhotoUrl(String orderName) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      final String? url = await _fetchLatestAttachedFileUrl(
        orderName: orderName,
        attachedField: 'proof_photo',
      );
      if (url != null && url.isNotEmpty) {
        return url;
      }
      await Future<void>.delayed(Duration(seconds: attempt + 1));
    }
    return null;
  }

  Future<String?> _fetchLatestAttachedFileUrl({
    required String orderName,
    required String attachedField,
  }) async {
    final uri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/resource/File',
    ).replace(
      queryParameters: {
        'fields': jsonEncode(<String>['file_url']),
        'filters': jsonEncode([
          ['File', 'attached_to_doctype', '=', 'External Delivery'],
          ['File', 'attached_to_name', '=', orderName],
          ['File', 'attached_to_field', '=', attachedField],
        ]),
        'limit_page_length': '1',
        'order_by': 'creation desc',
      },
    );

    final resp = await _get(uri, headers: await _authHeaders());
    if (!_okCodes.contains(resp.statusCode)) {
      return null;
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) return null;
    final data = decoded['data'];
    if (data is! List || data.isEmpty) return null;
    final first = data.first;
    if (first is! Map<String, dynamic>) return null;
    final String value = first['file_url']?.toString().trim() ?? '';
    return value.isEmpty ? null : value;
  }

  /// Parses the file URL from a Frappe upload_file response body.
  /// Frappe v13 returns `{"message": "/files/..."}` (string).
  /// Frappe v14+ returns `{"message": {"file_url": "/files/...", ...}}` (map).
  String? _extractFileUrl(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) return null;
      final message = decoded['message'];
      if (message is Map<String, dynamic>) {
        final v = message['file_url']?.toString() ?? '';
        return v.trim().isEmpty ? null : v;
      }
      if (message is String) {
        return message.trim().isEmpty ? null : message;
      }
    } catch (_) {}
    return null;
  }

  Future<void> clearProofPhoto({required String orderName}) async {
    try {
      await _updateExternalDeliveryFields(orderName, {'proof_photo': ''});
    } catch (e) {
      _logApi('clear_proof_photo_put_warn', e.toString());
      await _setDocValue(
        doctype: 'External Delivery',
        name: orderName,
        fieldname: 'proof_photo',
        value: '',
      );
    }
  }

  /// Convenience wrapper for [processFailedDeliveryReturn] that resolves the
  /// trip stop by [tripId] + [deliveryId] so callers don't need the stop object.
  Future<ReturnProcessResult> processFailedDeliveryReturnByIds({
    required String tripId,
    required String deliveryId,
    required String reason,
    String? reasonCode,
    String? photoPath,
    bool shouldCreateReturnTrip = false,
  }) async {
    final trip = await fetchTripDetails(tripId);
    final stop = trip.stops.firstWhere(
      (s) => s.externalDelivery.trim() == deliveryId.trim(),
      orElse: () =>
          throw Exception('Stop not found for delivery $deliveryId in trip $tripId'),
    );
    return processFailedDeliveryReturn(
      stop: stop,
      orderName: deliveryId,
      reason: reason,
      reasonCode: reasonCode,
      photoPath: photoPath,
      shouldCreateReturnTrip: shouldCreateReturnTrip,
    );
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
    String? reasonCode,
    String? photoPath,
    bool shouldCreateReturnTrip = false,
  }) async {
    final String languageCode = await _languageCode();

    await _setTripStopFailed(stop: stop, reasonCode: reasonCode);
    await _tryMarkParentTripFailed(stop);

    await _updateExternalDeliveryFields(orderName, {
      'status': 'Failed',
      'delivery_notes': reason,
      'store_notified': 1,
      if (reasonCode != null && reasonCode.isNotEmpty)
        'failure_reason_code': reasonCode,
    });

    if (photoPath != null && photoPath.isNotEmpty) {
      await uploadProofPhoto(orderName: orderName, filePath: photoPath);
    }

    if (!shouldCreateReturnTrip) {
      return ReturnProcessResult(
        success: true,
        orderUpdated: true,
        tripCreated: false,
        tripSubmitted: false,
        tripName: null,
        message: LocalizedText.t(languageCode, 'delivery_failed'),
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
        message:
            '${LocalizedText.t(languageCode, 'return_trip')} already exists: $existingTripName',
      );
    }

    final tripName = await createReturnTrip(orderName: orderName);
    return ReturnProcessResult(
      success: true,
      orderUpdated: true,
      tripCreated: true,
      tripSubmitted: true,
      tripName: tripName,
      message:
          '${LocalizedText.t(languageCode, 'return_trip')} created: $tripName',
    );
  }

  /// Creates a return trip to the store for the given order. Returns the
  /// new trip name. Lands in Draft — the doctype is not submittable.
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
      'driver': await _getLoggedInDriver(),
      'status': 'Draft',
      'trip_date': DateTime.now().toIso8601String().split('T').first,
      'trip_notes': LocalizedText.returnTripMarker(orderName),
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

    return (createdDoc['name'] ?? '').toString();
  }

  Future<String> _languageCode() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String code = (prefs.getString(_prefLanguageCode) ?? 'en').trim();
    return code.isEmpty ? 'en' : code;
  }

  /// Public entry point for marking [trip] fully Completed. Reused by the
  /// return-to-store flow (via [_completeTrip] below) and by the trip-details
  /// screen's auto-completion once every stop has reached a terminal status.
  Future<void> completeTrip(ExternalDeliveryTrip trip) => _completeTrip(trip);

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

  /// Confirms a recall return at the store:
  /// 1. Sets the trip stop status to 'Returned'.
  /// 2. Explicitly sets the External Delivery record status to 'Returned'
  ///    and store_notified=1, overriding any generic server-side hook that
  ///    would otherwise mark the delivery as 'Failed'.
  Future<void> confirmRecallReturn({
    required ExternalDeliveryTripStop stop,
    required String orderName,
  }) async {
    await updateTripStopStatus(stop: stop, newStatus: _returnedStatus);
    await _updateExternalDeliveryFields(orderName, {
      'status': _returnedStatus,
      'store_notified': 1,
    });
  }

  Future<Map<String, dynamic>> confirmRecallReceivedAtStore({
    required String externalDelivery,
  }) async {
    final uri = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/method/grozfy_go.grozfy_go.api.driver.confirm_recall_received_at_store',
    );
    _logApi(
      'confirm_recall request',
      'POST $uri external_delivery=$externalDelivery',
    );
    final resp = await _post(
      uri,
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({'external_delivery': externalDelivery}),
    );
    _logApi(
      'confirm_recall response',
      'code=${resp.statusCode} body=${resp.body}',
    );
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }
    final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
    final message = decoded['message'];
    return message is Map<String, dynamic> ? message : {};
  }

  /// Sets status=Failed and failure_reason_code in one frappe.client.set_value
  /// call using the dict fieldname syntax so the backend's validation passes.
  Future<void> _setTripStopFailed({
    required ExternalDeliveryTripStop stop,
    String? reasonCode,
  }) async {
    final stopName = (stop.rawFields['name'] ?? '').toString().trim();
    final stopDocType = (stop.rawFields['doctype'] ?? '').toString().trim();
    if (stopName.isEmpty || stopDocType.isEmpty) {
      throw Exception('Stop row metadata not found for status update.');
    }

    final setValueUrl = Uri.parse(
      '${ApiConstants.erpBaseUrl}/api/method/frappe.client.set_value',
    );
    final fields = <String, dynamic>{'status': 'Failed'};
    if (reasonCode != null && reasonCode.isNotEmpty) {
      fields['failure_reason_code'] = reasonCode;
    }
    _logApi(
      'external_delivery_trip_stop_status_update request',
      'POST $setValueUrl doctype=$stopDocType name=$stopName fields=$fields',
    );
    final resp = await _post(
      setValueUrl,
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode({
        'doctype': stopDocType,
        'name': stopName,
        'fieldname': fields,
      }),
    );
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
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
            LocalizedText.returnTripMarker(orderName),
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
    debugPrint('[API] $tag => $value');
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

  /// Records COD collection on an External Delivery via a single PUT.
  /// Sets cod_collected=1, [codCollectionMode] ('Cash', 'UPI', or 'Not Collected'),
  /// and optionally [codUpiReference]. Status is managed server-side.
  Future<void> markDeliveredWithCod(
    String orderName, {
    required String codCollectionMode,
    String? codUpiReference,
  }) async {
    final uri = Uri.parse(
      '${ApiConstants.externalDeliveryList}/${Uri.encodeComponent(orderName)}',
    );
    final payload = <String, dynamic>{
      'cod_collected': 1,
      'cod_collection_mode': codCollectionMode,
    };
    if (codUpiReference != null && codUpiReference.trim().isNotEmpty) {
      payload['cod_upi_reference'] = codUpiReference.trim();
    }
    _logApi('mark_delivered_with_cod', 'PUT $uri mode=$codCollectionMode');
    final resp = await _put(
      uri,
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }
  }

  Future<void> markOrderFailed({
    required String orderName,
    required String reason,
    String reasonCode = '',
    String? photoPath,
  }) async {
    await _updateExternalDeliveryFields(orderName, {
      'status': 'Failed',
      'delivery_notes': reason,
      'store_notified': 1,
      if (reasonCode.isNotEmpty) 'failure_reason_code': reasonCode,
    });
    if (photoPath != null && photoPath.isNotEmpty) {
      await uploadProofPhoto(orderName: orderName, filePath: photoPath);
    }
  }

  /// Fetches the [CodHandover] doc for [tripName].
  /// Returns null if no COD handover exists for this trip.
  Future<CodHandover?> fetchCodHandover(String tripName) async {
    final driver = await _getLoggedInDriver();
    final codHandoverList = '${ApiConstants.erpBaseUrl}/api/resource/COD%20Handover';
    final uri = Uri.parse(codHandoverList).replace(
      queryParameters: {
        'fields': jsonEncode([
          'name',
          'delivery_trip',
          'cod_cash_expected',
          'cod_cash_actual',
          'status',
          'notes',
        ]),
        'filters': jsonEncode([
          ['COD Handover', 'delivery_trip', '=', tripName],
          ['COD Handover', 'driver', '=', driver],
        ]),
        'limit_page_length': '1',
      },
    );
    _logApi('fetch_cod_handover', 'GET $uri trip=$tripName driver=$driver');
    final resp = await _get(uri, headers: await _authHeaders());
    if (!_okCodes.contains(resp.statusCode)) return null;
    final rows = (jsonDecode(resp.body)['data']) as List?;
    if (rows == null || rows.isEmpty) return null;
    return CodHandover.fromJson(rows.first as Map<String, dynamic>);
  }

  /// Saves the driver's actual cash-in-hand to the [CodHandover] doc.
  Future<void> submitCodHandover({
    required String name,
    required double actualAmount,
    String? notes,
  }) async {
    final codHandoverList = '${ApiConstants.erpBaseUrl}/api/resource/COD%20Handover';
    final uri = Uri.parse(
      '$codHandoverList/${Uri.encodeComponent(name)}',
    );
    final payload = <String, dynamic>{
      'cod_cash_actual': actualAmount,
      'status': 'Submitted',
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    };
    _logApi('submit_cod_handover', 'PUT $uri name=$name amount=$actualAmount');
    final resp = await _put(
      uri,
      headers: {...await _authHeaders(), 'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }
  }

  static const String _codHandoverBase =
      '${ApiConstants.erpBaseUrl}/api/resource/COD%20Handover';

  static const List<String> _codHandoverFields = [
    'name',
    'delivery_trip',
    'cod_cash_expected',
    'cod_cash_actual',
    'status',
    'notes',
    'driver',
    'creation',
    'modified',
  ];

  /// Fetches a paginated list of [CodHandover] records for the logged-in driver.
  /// Pass [statusFilter] ('Pending', 'Submitted', 'Discrepancy') to filter by status.
  Future<List<CodHandover>> fetchCodHandoverList({
    int limitStart = 0,
    int limitPageLength = 20,
    String? statusFilter,
  }) async {
    final driver = await _getLoggedInDriver();
    final filters = <List<dynamic>>[
      ['COD Handover', 'driver', '=', driver],
      if (statusFilter != null && statusFilter.isNotEmpty)
        ['COD Handover', 'status', '=', statusFilter],
    ];
    final uri = Uri.parse(_codHandoverBase).replace(
      queryParameters: {
        'fields': jsonEncode(_codHandoverFields),
        'filters': jsonEncode(filters),
        'limit_start': '$limitStart',
        'limit_page_length': '$limitPageLength',
        'order_by': 'modified desc',
      },
    );
    _logApi('fetch_cod_handover_list', 'GET $uri limitStart=$limitStart');
    final resp = await _get(uri, headers: await _authHeaders());
    if (resp.statusCode == 401) throw Exception('401: Invalid API credentials.');
    if (resp.statusCode == 403) throw Exception('403: Access denied.');
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }
    final rows = (jsonDecode(resp.body)['data']) as List;
    return rows
        .map((r) => CodHandover.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Fetches a single [CodHandover] by document [name] for the detail screen.
  Future<CodHandover> fetchCodHandoverDetail(String name) async {
    final uri = Uri.parse(
      '$_codHandoverBase/${Uri.encodeComponent(name)}',
    );
    _logApi('fetch_cod_handover_detail', 'GET $uri name=$name');
    final resp = await _get(uri, headers: await _authHeaders());
    if (!_okCodes.contains(resp.statusCode)) {
      throw Exception(_extractErrorMessage(resp));
    }
    final data = (jsonDecode(resp.body)['data']) as Map<String, dynamic>;
    return CodHandover.fromJson(data);
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

  Future<String> _languageHeader() async {
    final prefs = await SharedPreferences.getInstance();
    final String language = (prefs.getString(_prefLanguageCode) ?? 'en').trim();
    return language.isEmpty ? 'en' : language;
  }

  bool _isAuthFailure(int statusCode) => statusCode == 401 || statusCode == 403;
}
