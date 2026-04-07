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
    return await repository.getNotifications();
  },
);

enum NotificationListFilter { all, unread, read }

final notificationListFilterProvider =
    StateProvider.autoDispose<NotificationListFilter>(
      (ref) => NotificationListFilter.all,
    );

final notificationReadOverridesProvider =
    StateProvider.autoDispose<Set<String>>((ref) => <String>{});

final unreadNotificationCountProvider = Provider.autoDispose<int>((ref) {
  final notifications = ref.watch(notificationsProvider).value ?? const [];
  return notifications.where((n) => !n.read).length;
});
