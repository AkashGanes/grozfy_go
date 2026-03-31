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
}
