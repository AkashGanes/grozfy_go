import 'package:flutter/foundation.dart';
import 'dart:convert';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/state/app_controller.dart';

class NotificationRepository {
  final AppController _app;
  NotificationRepository(this._app);

  String? _notificationUser() {
    final String? email = _app.profile?.email?.trim();
    if (email != null && email.isNotEmpty) return email;

    final String? loggedUser = _app.loggedUser?.trim();
    if (loggedUser == null || loggedUser.isEmpty) return null;

    // Notification Log `for_user` is typically stored as email.
    if (loggedUser.contains('@')) return loggedUser;

    return null;
  }

  Future<int> _getCount(List<List<dynamic>> filters) async {
    final queryParams = {
      'doctype': 'Notification Log',
      'filters': jsonEncode(filters),
    };

    final String baseUrl = ApiConstants.erpBaseUrl;
    final Uri baseUri = Uri.parse('$baseUrl/api/method/frappe.client.get_count');
    final Uri uri = baseUri.replace(queryParameters: queryParams);

    final response = await _app.authorizedGet(uri);
    final dynamic message = response['message'];
    if (message is num) return message.toInt();
    if (message is String) return int.tryParse(message) ?? 0;
    return 0;
  }

  Future<int> getUnreadCount() async {
    if (!_app.isLoggedIn) return 0;

    try {
      final String? loggedUser = _notificationUser();
      if (loggedUser == null || loggedUser.isEmpty) return 0;

      return await _getCount([
        ['for_user', '=', loggedUser],
        ['read', '=', 0],
      ]);
    } catch (e) {
      debugPrint("Error fetching unread notification count: $e");
      return 0;
    }
  }

  Future<({int all, int unread, int read})> getNotificationCounts() async {
    if (!_app.isLoggedIn) return (all: 0, unread: 0, read: 0);

    try {
      final String? loggedUser = _notificationUser();
      if (loggedUser == null || loggedUser.isEmpty) {
        return (all: 0, unread: 0, read: 0);
      }

      final results = await Future.wait<int>([
        _getCount([
          ['for_user', '=', loggedUser],
        ]),
        _getCount([
          ['for_user', '=', loggedUser],
          ['read', '=', 0],
        ]),
        _getCount([
          ['for_user', '=', loggedUser],
          ['read', '=', 1],
        ]),
      ]);

      return (all: results[0], unread: results[1], read: results[2]);
    } catch (e) {
      debugPrint("Error fetching notification counts: $e");
      return (all: 0, unread: 0, read: 0);
    }
  }

  Future<List<NotificationLog>> getNotifications({
    int limit = 50,
    int offset = 0,
    int? read,
  }) async {
    if (!_app.isLoggedIn) return [];

    try {
      final String? loggedUser = _notificationUser();
      if (loggedUser == null || loggedUser.isEmpty) return [];

      final filters = [
        ['for_user', '=', loggedUser],
        if (read != null) ['read', '=', read],
      ];

      final queryParams = {
        'doctype': 'Notification Log',
        'fields': jsonEncode(<String>[
          'name',
          'subject',
          'document_type',
          'document_name',
          'email_content',
          'read',
          'creation',
          'for_user',
        ]),
        'filters': jsonEncode(filters),
        'order_by': 'creation desc',
        'limit_page_length': limit.toString(),
        'limit_start': offset.toString(),
      };

      final String baseUrl = ApiConstants.erpBaseUrl;
      final Uri baseUri = Uri.parse('$baseUrl/api/method/frappe.client.get_list');
      final Uri uri = baseUri.replace(queryParameters: queryParams);

      final response = await _app.authorizedGet(uri);
      final List<dynamic> data = (response['message'] as List<dynamic>?) ?? [];

      debugPrint("Fetched ${data.length} notifications from Notification Log");

      return data.map((json) => NotificationLog.fromJson(json)).toList();
    } catch (e) {
      debugPrint("Error fetching notifications: $e");
      return [];
    }
  }

  Future<bool> markAsRead(String name) async {
    if (!_app.isLoggedIn) return false;

    try {
      final Uri uri = Uri.parse(
        '${ApiConstants.erpBaseUrl}/api/method/frappe.desk.doctype.notification_log.notification_log.mark_as_read',
      );
      await _app.authorizedPostJson(uri, <String, dynamic>{'docname': name});
      return true;
    } catch (e) {
      debugPrint("Error marking notification as read: $e");
      return false;
    }
  }

  Future<bool> markAllAsRead() async {
    if (!_app.isLoggedIn) return false;

    try {
      final Uri uri = Uri.parse(
        '${ApiConstants.erpBaseUrl}/api/method/frappe.desk.doctype.notification_log.notification_log.mark_all_as_read',
      );
      await _app.authorizedPostJson(uri, const <String, dynamic>{});
      return true;
    } catch (e) {
      debugPrint("Error marking all notifications as read: $e");
      return false;
    }
  }
}
