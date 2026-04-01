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
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'This channel is used for important notifications.',
      importance: Importance.max,
    );

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

    final androidNotifications = _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidNotifications?.createNotificationChannel(channel);
    await androidNotifications?.requestNotificationsPermission();

    await _fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
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
    final String title =
        (message.notification?.title ??
                message.data['title'] ??
                message.data['subject'] ??
                '')
            .toString();
    final String body =
        (message.notification?.body ??
                message.data['body'] ??
                message.data['message'] ??
                '')
            .toString();
    if (title.isEmpty && body.isEmpty) return;

    final String doctype =
        (message.data['doctype'] ?? message.data['type'] ?? '').toString();
    final String docname =
        (message.data['docname'] ?? message.data['doc_name'] ?? '').toString();

    final payload = jsonEncode(<String, String>{
      'doctype': doctype,
      'docname': docname,
    });

    _localNotificationsPlugin.show(
      message.messageId.hashCode,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'high_importance_channel',
          'High Importance Notifications',
          channelDescription:
              'This channel is used for important notifications.',
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: payload,
    );
  }
}
