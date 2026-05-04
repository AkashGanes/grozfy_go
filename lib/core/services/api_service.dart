import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_models.dart';
import 'secure_token_storage.dart';

class ApiService {
  static const String baseUrl = 'http://209.182.232.35:8004';
  static const String _prefSid = 'sid';
  static final Uri _refreshTokenUri = Uri.parse(
    '$baseUrl/api/method/frappe.integrations.oauth2.get_token',
  );
  static const List<String> _deliveryFields = <String>[
    'name',
    'store_name',
    'customer_name',
    'status',
    'creation',
    'modified',
  ];

  String? _sessionToken;
  String? _sid;
  String? _tokenType;

  void setSessionToken(String? token) {
    _sessionToken = token;
  }

  void setSID(String? sid) {
    _sid = sid;
  }

  void setTokenType(String? tokenType) {
    _tokenType = tokenType;
  }

  Future<List<ExternalDeliveryOrder>> getExternalDeliveries({
    int start = 0,
    int pageLength = 50,
    List<List<dynamic>>? filters,
  }) async {
    try {
      final queryParams = <String, String>{
        'fields': jsonEncode(_deliveryFields),
        'order_by': 'modified desc',
        'limit_start': start.toString(),
        'limit_page_length': pageLength.toString(),
        if (filters != null && filters.isNotEmpty)
          'filters': jsonEncode(filters),
      };

      final uri = _resourceUri(
        doctype: 'External Delivery',
        queryParams: queryParams,
      );

      debugPrint('[ApiService] Request URL: $uri');

      final response = await _sendWithAuthRetry(
        (headers) => http.get(uri, headers: headers),
      );

      debugPrint('[ApiService] Response Status: ${response.statusCode}');
      debugPrint('[ApiService] Response Body: ${response.body}');

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = _decodeJsonMap(response.body);
        final List<dynamic> rows = _extractRows(data);

        if (rows.isNotEmpty) {
          return rows
              .map((json) {
                final Map<String, dynamic>? normalizedRow =
                    _normalizeDeliveryRow(json);
                if (normalizedRow != null) {
                  return ExternalDeliveryOrder.fromJson(normalizedRow);
                }
                return null;
              })
              .whereType<ExternalDeliveryOrder>()
              .toList();
        }

        return [];
      } else {
        final Map<String, dynamic> payload = _decodeJsonMap(response.body);
        final String? details = _extractServerError(payload);
        throw Exception(
          details ??
              'Failed to load deliveries: ${response.statusCode} - ${response.body}',
        );
      }
    } catch (e) {
      debugPrint('[ApiService] Error fetching deliveries: $e');
      rethrow;
    }
  }

  Future<ExternalDeliveryOrder?> getExternalDelivery(String name) async {
    try {
      final uri = _resourceUri(doctype: 'External Delivery', name: name);
      final response = await _sendWithAuthRetry(
        (headers) => http.get(uri, headers: headers),
      );
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = _decodeJsonMap(response.body);
        final dynamic doc = data['data'] ?? data['message'];
        if (doc is Map<String, dynamic>) {
          return ExternalDeliveryOrder.fromJson(doc);
        }
      }
      return null;
    } catch (e) {
      debugPrint('[ApiService] Error fetching delivery $name: $e');
      return null;
    }
  }

  Future<bool> updateDeliveryStatus(String deliveryName, String status) async {
    try {
      final body = jsonEncode({'status': status});

      final uri = _resourceUri(
        doctype: 'External Delivery',
        name: deliveryName,
      );

      final response = await _sendWithAuthRetry(
        (headers) => http.put(uri, headers: headers, body: body),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[ApiService] Error updating delivery status: $e');
      return false;
    }
  }


  Future<http.Response> _sendWithAuthRetry(
    Future<http.Response> Function(Map<String, String> headers) request,
  ) async {
    final List<Map<String, String>> headerCandidates =
        await _buildHeaderCandidates();

    late http.Response response;
    for (int i = 0; i < headerCandidates.length; i++) {
      try {
        response = await request(
          headerCandidates[i],
        ).timeout(const Duration(seconds: 30));
      } on TimeoutException {
        debugPrint('[ApiService] Request timed out (attempt ${i + 1})');
        if (i == headerCandidates.length - 1) {
          throw Exception('Request timed out. Check your internet connection.');
        }
        continue;
      }

      final bool isLastCandidate = i == headerCandidates.length - 1;
      if (!_isAuthFailure(response.statusCode) || isLastCandidate) {
        // Last candidate also failed with auth error — try refreshing.
        if (_isAuthFailure(response.statusCode) && isLastCandidate) {
          if (await _refreshSession()) {
            final List<Map<String, String>> refreshedHeaders =
                await _buildHeaderCandidates();
            if (refreshedHeaders.isNotEmpty) {
              try {
                final http.Response retryResp = await request(
                  refreshedHeaders.first,
                ).timeout(const Duration(seconds: 30));
                return retryResp;
              } on TimeoutException {
                // Fall through and return the original failed response.
              }
            }
          }
        }
        return response;
      }
    }

    return response;
  }

  /// Refreshes the session token using Frappe's OAuth2 get_token endpoint.
  Future<bool> _refreshSession() async {
    try {
      final String? refreshToken =
          await SecureTokenStorage.read(SecureTokenStorage.refreshToken);
      final String? clientId =
          await SecureTokenStorage.read(SecureTokenStorage.clientId);
      if (refreshToken == null || refreshToken.trim().isEmpty) return false;
      if (clientId == null || clientId.trim().isEmpty) return false;

      debugPrint('[ApiService] Attempting token refresh');
      final http.Response response = await http
          .post(
            _refreshTokenUri,
            headers: const <String, String>{
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: <String, String>{
              'grant_type': 'refresh_token',
              'refresh_token': refreshToken,
              'client_id': clientId,
            },
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[ApiService] Token refresh failed: ${response.statusCode}');
        return false;
      }

      final Map<String, dynamic> data = _decodeJsonMap(response.body);

      final String? newToken =
          _nullIfBlank(data['access_token']?.toString());
      if (newToken == null) return false;

      _sessionToken = newToken;
      final String? newType = _nullIfBlank(data['token_type']?.toString());
      if (newType != null) _tokenType = newType;
      final String? newRefresh =
          _nullIfBlank(data['refresh_token']?.toString());

      await SecureTokenStorage.write(
        SecureTokenStorage.accessToken,
        newToken,
      );
      if (newType != null) {
        await SecureTokenStorage.write(SecureTokenStorage.tokenType, newType);
      }
      if (newRefresh != null) {
        await SecureTokenStorage.write(
          SecureTokenStorage.refreshToken,
          newRefresh,
        );
      }

      debugPrint('[ApiService] Token refreshed successfully');
      return true;
    } catch (e) {
      debugPrint('[ApiService] Token refresh error: $e');
      return false;
    }
  }

  Future<List<Map<String, String>>> _buildHeaderCandidates() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    final String? token = _sessionToken ??
        await SecureTokenStorage.read(SecureTokenStorage.accessToken);
    final String? sid = _sid ?? prefs.getString(_prefSid);
    final String tokenType = (_tokenType ??
            await SecureTokenStorage.read(SecureTokenStorage.tokenType) ??
            '')
        .trim();

    final Map<String, String> baseHeaders = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (sid != null && sid.isNotEmpty) 'Cookie': 'sid=$sid',
    };

    if (token == null || token.isEmpty) {
      return <Map<String, String>>[baseHeaders];
    }

    final Map<String, String> bearerHeaders = <String, String>{
      ...baseHeaders,
      'Authorization': 'Bearer $token',
    };
    final Map<String, String> tokenHeaders = <String, String>{
      ...baseHeaders,
      'Authorization': 'token $token',
    };

    if (tokenType.toLowerCase() == 'token') {
      return <Map<String, String>>[tokenHeaders, bearerHeaders];
    }
    return <Map<String, String>>[bearerHeaders, tokenHeaders];
  }

  Uri _resourceUri({
    required String doctype,
    String? name,
    Map<String, String>? queryParams,
  }) {
    final Uri baseUri = Uri.parse(baseUrl);
    final List<String> pathSegments = <String>[
      ...baseUri.pathSegments.where((segment) => segment.isNotEmpty),
      'api',
      'resource',
      doctype,
      if (name != null && name.isNotEmpty) name,
    ];

    return baseUri.replace(
      pathSegments: pathSegments,
      queryParameters: queryParams,
    );
  }

  List<dynamic> _extractRows(Map<String, dynamic> payload) {
    final dynamic dataNode = payload['data'];
    if (dataNode is List) {
      return dataNode;
    }

    final dynamic messageNode = payload['message'];
    if (messageNode is List) {
      return messageNode;
    }
    if (messageNode is Map) {
      final dynamic nestedData = messageNode['data'];
      if (nestedData is List) {
        return nestedData;
      }
    }

    return const <dynamic>[];
  }

  Map<String, dynamic>? _normalizeDeliveryRow(dynamic row) {
    if (row is Map<String, dynamic>) {
      return row;
    }

    if (row is Map) {
      return row.map((key, value) => MapEntry(key.toString(), value));
    }

    if (row is List) {
      final Map<String, dynamic> mapped = <String, dynamic>{};
      final int count = row.length < _deliveryFields.length
          ? row.length
          : _deliveryFields.length;
      for (int i = 0; i < count; i++) {
        mapped[_deliveryFields[i]] = row[i];
      }
      return mapped;
    }

    return null;
  }

  Map<String, dynamic> _decodeJsonMap(String raw) {
    if (raw.trim().isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  bool _isAuthFailure(int statusCode) => statusCode == 401 || statusCode == 403;

  String? _extractServerError(Map<String, dynamic> payload) {
    final String? explicitError = _nullIfBlank(
      payload['_error_message']?.toString(),
    );
    if (explicitError != null) {
      return explicitError;
    }

    final String? fromServerMessages = _extractFromServerMessages(
      payload['_server_messages'],
    );
    if (fromServerMessages != null) {
      return fromServerMessages;
    }

    final String? message = _nullIfBlank(payload['message']?.toString());
    if (message != null) {
      return message;
    }

    final String? exception = _nullIfBlank(payload['exception']?.toString());
    if (exception != null) {
      return exception;
    }

    final String? excType = _nullIfBlank(payload['exc_type']?.toString());
    if (excType != null) {
      return excType;
    }

    return null;
  }

  String? _extractFromServerMessages(dynamic raw) {
    if (raw == null) {
      return null;
    }

    if (raw is String && raw.trim().isEmpty) {
      return null;
    }

    try {
      final dynamic decoded = raw is String ? jsonDecode(raw) : raw;
      if (decoded is! List) {
        return _nullIfBlank(decoded?.toString());
      }

      for (final dynamic entry in decoded) {
        if (entry is String) {
          final String? fromString = _nullIfBlank(entry);
          if (fromString != null) {
            return fromString;
          }
          continue;
        }

        if (entry is Map<String, dynamic>) {
          final String? message = _nullIfBlank(entry['message']?.toString());
          if (message != null) {
            return message;
          }
          final String? title = _nullIfBlank(entry['title']?.toString());
          if (title != null) {
            return title;
          }
        }
      }
    } catch (_) {
      return _nullIfBlank(raw.toString());
    }

    return null;
  }

  String? _nullIfBlank(String? value) {
    final String trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }
}
