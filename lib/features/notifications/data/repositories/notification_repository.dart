import 'package:flutter/foundation.dart';
import '../../../../core/constants/api_constants.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/state/app_controller.dart';

class NotificationRepository {
  final AppController _app;
  NotificationRepository(this._app);

  Future<List<NotificationLog>> getNotifications({
    int limit = 20,
    int offset = 0,
  }) async {
    if (!_app.isLoggedIn) return [];

    try {
      final queryParams = {
        'fields': '["*"]',
        'filters': '[["for_user", "=", "${_app.loggedUser} "]]'.trim(),
        'order_by': 'creation desc',
        'limit_page_length': '$limit',
        'limit_start': '$offset',
      };

      final String baseUrl = ApiConstants.erpBaseUrl;
      final Uri baseUri = Uri.parse('$baseUrl/api/resource/Notification Log');
      final Uri uri = baseUri.replace(queryParameters: queryParams);

      final response = await _app.authorizedGet(uri);
      final List<dynamic> data = response['data'] ?? [];

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
