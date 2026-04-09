import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import '../state/app_controller.dart';

class FCMService {
  static final FCMService _instance = FCMService._internal();
  factory FCMService() => _instance;
  FCMService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  StreamSubscription<String>? _tokenRefreshSub;

  Future<String?> getToken() async {
    return await _fcm.getToken();
  }

  Future<void> subscribe(AppController appController) async {
    if (!appController.isLoggedIn || appController.sessionToken == null) return;

    try {
      final String? token = await getToken();
      if (token == null) return;

      debugPrint("Syncing FCM token with ERPNext...");
      await appController.updateFcmToken(token);
      await _fcm.subscribeToTopic('all_partners');
      _bindTokenRefresh(appController);
      debugPrint("FCM token sync successful");
    } catch (e) {
      debugPrint("FCM Subscription error: $e");
    }
  }

  Future<void> unsubscribe(AppController appController) async {
    if (!appController.isLoggedIn || appController.sessionToken == null) return;

    try {
      debugPrint("Unsubscribing FCM token from ERPNext...");
      // Clear user token on logout to stop targeted push delivery.
      await appController.updateFcmToken("");
      await _fcm.unsubscribeFromTopic('all_partners');
      await _tokenRefreshSub?.cancel();
      _tokenRefreshSub = null;
      debugPrint("FCM Unsubscription successful");
    } catch (e) {
      debugPrint("FCM Unsubscription error: $e");
    }
  }

  void _bindTokenRefresh(AppController appController) {
    _tokenRefreshSub?.cancel();
    _tokenRefreshSub = _fcm.onTokenRefresh.listen((String token) async {
      try {
        await appController.updateFcmToken(token);
        debugPrint("FCM token refresh synced");
      } catch (e) {
        debugPrint("FCM token refresh sync error: $e");
      }
    });
  }
}
