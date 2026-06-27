import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import '../screens/client/widgets/in_app_notification.dart';

class FcmInAppBridge {
  static bool _started = false;

  static Future<void> start() async {
    if (_started) return;
    _started = true;

    try {
      // Safe to call; on Android it won’t hurt
      await FirebaseMessaging.instance.requestPermission();

      // Foreground push messages
      FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
        final title = msg.notification?.title ?? 'Notification';
        final body = msg.notification?.body ?? 'You have a new update';

        if (kDebugMode) {
          debugPrint('[FCM] onMessage title="$title" body="$body" data=${msg.data}');
        }

        NotificationService.instance.postQuick(
          title: title,
          message: body,
          type: InAppNotificationType.info,
          onTap: () {
            // Optional: decide navigation based on msg.data later
          },
        );
      });

      // When user taps a notification (app opened from tray)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage msg) {
        final title = msg.notification?.title ?? 'Opened from notification';
        final body = msg.notification?.body ?? '';

        NotificationService.instance.postQuick(
          title: title,
          message: body.isEmpty ? 'Opened from notification' : body,
          type: InAppNotificationType.info,
          onTap: () {
            // Optional: navigate based on msg.data
          },
        );
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[FCM] bridge start error: $e');
    }
  }
}
