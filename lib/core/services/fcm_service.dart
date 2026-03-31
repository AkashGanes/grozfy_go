import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../state/app_controller.dart';

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  Future<String?> getToken() async {
    return await _fcm.getToken();
  }

  Future<void> subscribe(AppController appController) async {
    if (!appController.isLoggedIn || appController.sessionToken == null) return;

    try {
      String? token = await getToken();
      if (token == null) return;

      debugPrint("Syncing FCM token with ERPNext...");

      await appController.updateFcmToken(token);

      // Subscribe to all_partners topic for broadcast notifications
      await _fcm.subscribeToTopic('all_partners');

      debugPrint("FCM Subscription successful (Topic: all_partners)");
    } catch (e) {
      debugPrint("FCM Subscription error: $e");
    }
  }

  Future<void> unsubscribe(AppController appController) async {
    if (!appController.isLoggedIn || appController.sessionToken == null) return;

    try {
      debugPrint("Unsubscribing FCM token from ERPNext...");
      // For now, we'll just clear the field on logout
      await appController.updateFcmToken("");
      await _fcm.unsubscribeFromTopic('all_partners');
      debugPrint("FCM Unsubscription successful");
    } catch (e) {
      debugPrint("FCM Unsubscription error: $e");
    }
  }
}
