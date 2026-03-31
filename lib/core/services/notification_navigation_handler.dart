import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../../main.dart';
import '../navigation/app_routes.dart';

class NotificationNavigationHandler {
  static final NotificationNavigationHandler _instance =
      NotificationNavigationHandler._internal();
  factory NotificationNavigationHandler() => _instance;
  NotificationNavigationHandler._internal();

  void handleMessage(RemoteMessage message) {
    debugPrint("Navigating from FCM Message: ${message.data}");
    _navigateToTarget(message.data['doctype'], message.data['docname']);
  }

  void handlePayload(String payload) {
    debugPrint("Navigating from Local Payload: $payload");
    // Handle payload if needed, e.g., if it's JSON
  }

  void _navigateToTarget(String? doctype, String? docname) {
    if (doctype == 'External Delivery' || doctype == 'External Delivery Trip') {
      navigatorKey.currentState?.pushNamed(
        AppRoutes
            .notifications, // For now, go to history. Expand to details later.
      );
    }
  }
}
