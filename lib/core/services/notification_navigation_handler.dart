import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

class NotificationNavigationHandler {
  static final NotificationNavigationHandler _instance =
      NotificationNavigationHandler._internal();
  factory NotificationNavigationHandler() => _instance;
  NotificationNavigationHandler._internal();

  void handleMessage(RemoteMessage message) {
    debugPrint("Navigating from FCM Message: ${message.data}");
    // Extract payload and navigate
    // In a real app, you would use a Navigator key or Riverpod provider
  }

  void handlePayload(String payload) {
    debugPrint("Navigating from Local Payload: $payload");
    // Handle payload string
  }
}
