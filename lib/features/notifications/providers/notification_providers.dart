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

final recentNotificationsProvider =
    FutureProvider.autoDispose<List<NotificationLog>>((ref) async {
      final repository = ref.watch(notificationRepositoryProvider);
      return await repository.getNotifications(limit: 2, offset: 0);
    });

final notificationCountsProvider =
    FutureProvider.autoDispose<({int all, int unread, int read})>((ref) async {
      final repository = ref.watch(notificationRepositoryProvider);
      return await repository.getNotificationCounts();
    });

enum NotificationListFilter { all, unread, read }

final notificationListFilterProvider =
    StateProvider.autoDispose<NotificationListFilter>(
      (ref) => NotificationListFilter.all,
    );

final notificationReadOverridesProvider =
    StateProvider.autoDispose<Set<String>>((ref) => <String>{});

final unreadNotificationCountProvider = FutureProvider.autoDispose<int>((ref) {
  final repository = ref.watch(notificationRepositoryProvider);
  return repository.getUnreadCount();
});
