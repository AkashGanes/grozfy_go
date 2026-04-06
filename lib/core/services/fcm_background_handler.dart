import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';

@pragma('vm:entry-point')
Future<void> fcmBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");

  // Create the notification channel (important for Android 8+)
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel', // id
    'High Importance Notifications', // title
    description:
        'This channel is used for important notifications.', // description
    importance: Importance.max,
  );

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);

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
  if (title.isEmpty && body.isEmpty) {
    return;
  }

  final payload = jsonEncode(<String, String>{
    'doctype': (message.data['doctype'] ?? '').toString(),
    'docname': (message.data['docname'] ?? '').toString(),
  });

  flutterLocalNotificationsPlugin.show(
    message.messageId.hashCode,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    ),
    payload: payload,
  );
}
