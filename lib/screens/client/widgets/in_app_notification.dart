// lib/client/widgets/in_app_notification.dart
// Minimal in-app notification model + NotificationService used by HomeWidget.
// Replace/extend with your real notification classes when ready.

import 'dart:async';

typedef NotificationTapCallback = void Function();

enum InAppNotificationType { success, error, warning, info }

class InAppNotificationModel {
  final String id;
  final String title;
  final String message;
  final InAppNotificationType type;
  final NotificationTapCallback? onTap;

  InAppNotificationModel({
    required this.id,
    required this.title,
    required this.message,
    this.type = InAppNotificationType.info,
    this.onTap,
  });
}

/// Simple singleton NotificationService with a stream you can listen to.
/// Use `NotificationService.instance.post(...)` to send a notification.
class NotificationService {
  NotificationService._internal();

  static final NotificationService instance = NotificationService._internal();

  final StreamController<InAppNotificationModel> _controller =
      StreamController.broadcast();

  Stream<InAppNotificationModel> get stream => _controller.stream;

  void post(InAppNotificationModel n) {
    _controller.add(n);
  }

  /// Convenience helper to generate a notification id and post quickly.
  void postQuick({
    required String title,
    required String message,
    InAppNotificationType type = InAppNotificationType.info,
    NotificationTapCallback? onTap,
  }) {
    final n = InAppNotificationModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      message: message,
      type: type,
      onTap: onTap,
    );
    post(n);
  }

  void dispose() {
    _controller.close();
  }
}
