import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/notification_repository.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/state/providers.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  final app = ref.watch(appControllerProvider);
  return NotificationRepository(app);
});

final notificationsProvider = FutureProvider.autoDispose<List<NotificationLog>>(
  (ref) async {
    final repository = ref.watch(notificationRepositoryProvider);
    final notifications = await repository.getNotifications();
    return notifications
        .where(
          (n) => (n.subject.trim().isNotEmpty || n.message.trim().isNotEmpty),
        )
        .toList();
  },
);

final unreadNotificationCountProvider = StateProvider<int>((ref) {
  final notifications = ref.watch(notificationsProvider).value ?? [];
  return notifications.where((n) => !n.read).length;
});

final totalUnreadCountProvider = StateProvider<int>((ref) {
  final unreadNotifications = ref.watch(unreadNotificationCountProvider);
  final app = ref.watch(appControllerProvider);
  return unreadNotifications + app.unreadNoticeCount;
});
