import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/state/app_controller.dart';

class NotificationRepository {
  final AppController _app;
  bool _usingBroadcastFeed = false;
  static const String _broadcastReadIdsPref = 'broadcast_notification_read_ids';

  NotificationRepository(this._app);

  Future<List<NotificationLog>> getNotifications({
    int limit = 20,
    int offset = 0,
  }) async {
    if (!_app.isLoggedIn) return [];

    final List<NotificationLog> broadcastItems = await _getBroadcastNotifications(
      limit: limit,
      offset: offset,
    );
    if (broadcastItems.isNotEmpty) {
      _usingBroadcastFeed = true;
      return broadcastItems;
    }

    _usingBroadcastFeed = false;
    try {
      final queryParams = {
        'fields': '["*"]',
        'order_by': 'creation desc',
        'limit_page_length': '$limit',
        'limit_start': '$offset',
      };

      final String baseUrl = ApiConstants.erpBaseUrl;
      final Uri baseUri = Uri.parse('$baseUrl/api/resource/Notification Log');
      final Uri uri = baseUri.replace(queryParameters: queryParams);

      final response = await _app.authorizedGet(uri);
      final List<dynamic> data = response['data'] ?? [];

      debugPrint("Fetched ${data.length} notifications from ERPNext");

      return data.map((json) => NotificationLog.fromJson(json)).toList();
    } catch (e) {
      debugPrint("Error fetching notifications: $e");
      return [];
    }
  }

  Future<void> markAsRead(String name) async {
    if (!_app.isLoggedIn) return;

    if (_usingBroadcastFeed) {
      await _markBroadcastAsRead(name);
      return;
    }

    try {
      final Uri uri = Uri.parse(
        '${ApiConstants.erpBaseUrl}/api/resource/Notification Log/$name',
      );
      await _app.authorizedPutJson(uri, {'read': 1});
    } catch (e) {
      debugPrint("Error marking notification as read: $e");
    }
  }

  Future<void> markAllAsRead() async {
    if (!_app.isLoggedIn) return;
    // In a real app, this might be a custom server-side method for efficiency
  }

  Future<List<NotificationLog>> _getBroadcastNotifications({
    required int limit,
    required int offset,
  }) async {
    try {
      final queryParams = {
        'fields':
            '["name","title","message","doctype_ref","docname_ref","creation","type"]',
        'order_by': 'creation desc',
        'limit_page_length': '$limit',
        'limit_start': '$offset',
      };

      final String baseUrl = ApiConstants.erpBaseUrl;
      final Uri baseUri = Uri.parse(
        '$baseUrl/api/resource/Broadcast Notification',
      );
      final Uri uri = baseUri.replace(queryParameters: queryParams);

      final response = await _app.authorizedGet(uri);
      final List<dynamic> data = response['data'] ?? [];
      if (data.isEmpty) return const <NotificationLog>[];

      final readIds = await _loadBroadcastReadIds();
      final items = data
          .whereType<Map>()
          .map((raw) => raw.cast<String, dynamic>())
          .map(
            (json) => NotificationLog.fromBroadcastJson(
              json,
              read: readIds.contains((json['name'] ?? '').toString()),
            ),
          )
          .toList();

      debugPrint("Fetched ${items.length} broadcast notifications");
      return items;
    } catch (e) {
      debugPrint("Broadcast Notification fetch skipped: $e");
      return const <NotificationLog>[];
    }
  }

  Future<Set<String>> _loadBroadcastReadIds() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_broadcastReadIdsPref) ?? const <String>[];
    return ids.toSet();
  }

  Future<void> _markBroadcastAsRead(String name) async {
    final prefs = await SharedPreferences.getInstance();
    final existing =
        prefs.getStringList(_broadcastReadIdsPref) ?? const <String>[];
    final readIds = existing.toSet();
    readIds.add(name);
    await prefs.setStringList(_broadcastReadIdsPref, readIds.toList());
  }
}
