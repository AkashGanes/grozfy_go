import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'fcm_background_handler.dart';
import 'notification_navigation_handler.dart';

import '../../features/notifications/providers/notification_providers.dart';

class FCMInitializer {
  static final FCMInitializer _instance = FCMInitializer._internal();
  factory FCMInitializer() => _instance;
  FCMInitializer._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  ProviderContainer? _container;

  Future<void> init(ProviderContainer container) async {
    _container = container;
    // 1. Request Permissions
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('FCM Initializer: Permission granted');
    }

    // 2. Set Background Handler
    FirebaseMessaging.onBackgroundMessage(fcmBackgroundHandler);

    // 3. Setup Local Notifications
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );

    await _localNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        if (response.payload != null) {
          NotificationNavigationHandler().handlePayload(response.payload!);
        }
      },
    );

    // 4. Foreground Message Handler
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint("FCM Foreground: ${message.notification?.title}");
      _showForegroundNotify(message);

      // REAL-TIME REFRESH
      _container?.invalidate(notificationsProvider);
    });

    // 5. Opened from Background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint("FCM Background Open: ${message.notification?.title}");
      NotificationNavigationHandler().handleMessage(message);
    });

    // 6. Opened from Terminated
    RemoteMessage? initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      debugPrint("FCM Terminated Open: ${initialMessage.notification?.title}");
      NotificationNavigationHandler().handleMessage(initialMessage);
    }
  }

  void _showForegroundNotify(RemoteMessage message) {
    if (message.notification == null) return;

    final payload = jsonEncode(<String, String>{
      'doctype': (message.data['doctype'] ?? '').toString(),
      'docname': (message.data['docname'] ?? '').toString(),
    });

    _localNotificationsPlugin.show(
      message.notification.hashCode,
      message.notification!.title,
      message.notification!.body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: payload,
    );
  }
}
