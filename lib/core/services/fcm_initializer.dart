import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'fcm_background_handler.dart';
import 'notification_navigation_handler.dart';
import '../utils/html_utils.dart';

import '../../features/notifications/providers/notification_providers.dart';
import '../state/providers.dart';

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
      debugPrint(
        'FCM received foreground notification: '
        'id=${message.messageId}, title=${message.notification?.title}, '
        'data=${message.data}',
      );
      debugPrint("FCM Foreground: ${message.notification?.title}");

      final isOnline = _container?.read(appControllerProvider).isOnline ?? false;
      if (!isOnline) {
        debugPrint('FCM Foreground: driver is offline, dropping notification');
        return;
      }

      _showForegroundNotify(message);

      // REAL-TIME REFRESH
      _container?.invalidate(notificationsProvider);
      _container?.invalidate(notificationCountsProvider);
      _container?.invalidate(unreadNotificationCountProvider);
      _container?.invalidate(recentNotificationsProvider);
    });

    // 5. Opened from Background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint(
        'FCM opened from background notification: '
        'id=${message.messageId}, title=${message.notification?.title}, '
        'data=${message.data}',
      );
      debugPrint("FCM Background Open: ${message.notification?.title}");
      NotificationNavigationHandler().handleMessage(message);
    });

    // 6. Opened from Terminated
    RemoteMessage? initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      debugPrint(
        'FCM opened from terminated notification: '
        'id=${initialMessage.messageId}, title=${initialMessage.notification?.title}, '
        'data=${initialMessage.data}',
      );
      debugPrint("FCM Terminated Open: ${initialMessage.notification?.title}");
      NotificationNavigationHandler().handleMessage(initialMessage);
    }
  }

  /// Clears every notification this app has posted to the system tray.
  /// Called when the driver goes Offline so stale order alerts don't linger
  /// where they could still be tapped or seen. The app only posts order/trip
  /// alerts via local notifications, so this is effectively order-scoped.
  Future<void> clearNotifications() async {
    try {
      await _localNotificationsPlugin.cancelAll();
    } catch (e) {
      debugPrint('FCM clearNotifications error: $e');
    }
  }

  void _showForegroundNotify(RemoteMessage message) {
    debugPrint(
      'FCM showing local notification: '
      'id=${message.messageId}, notification=${message.notification}, '
      'data=${message.data}',
    );
    final String rawTitle =
        (message.notification?.title ??
                message.data['title'] ??
                message.data['subject'] ??
                '')
            .toString();
    final String rawBody =
        (message.notification?.body ??
                message.data['body'] ??
                message.data['message'] ??
                '')
            .toString();

    final String title = HtmlUtils.stripHtml(rawTitle);
    final String body = HtmlUtils.stripHtmlPreserveLineBreaks(rawBody);
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
