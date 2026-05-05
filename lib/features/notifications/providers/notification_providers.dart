import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/repositories/notification_repository.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/state/providers.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  // Use ref.read so we don't rebuild the repository (and re-fetch) on every
  // AppController notifyListeners() call (GPS ticks, online toggles, etc.).
  final app = ref.read(appControllerProvider);
  return NotificationRepository(app);
});

/// Cache: keeps the last successful fetch result so we don't spam the server.
List<NotificationLog> _cachedNotifications = const [];
DateTime? _lastFetchTime;
bool _isFetching = false;
const _minFetchInterval = Duration(seconds: 30);

final notificationsProvider = FutureProvider<List<NotificationLog>>((
  ref,
) async {
  final repository = ref.watch(notificationRepositoryProvider);

  // Throttle: don't fetch if we already fetched recently
  final now = DateTime.now();
  if (_lastFetchTime != null &&
      now.difference(_lastFetchTime!) < _minFetchInterval) {
    return _cachedNotifications;
  }

  // Prevent concurrent fetches
  if (_isFetching) return _cachedNotifications;
  _isFetching = true;

  try {
    final result = await repository.getNotifications();
    _cachedNotifications = result;
    _lastFetchTime = now;
    return result;
  } catch (_) {
    // On failure, return cached data instead of retrying immediately
    return _cachedNotifications;
  } finally {
    _isFetching = false;
  }
});

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
