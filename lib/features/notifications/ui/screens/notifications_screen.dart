import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/notification_providers.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_shell.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);

    return AppShell(
      title: 'Notifications',
      subtitle: 'Delivery updates and alerts',
      scrollable: false,
      child: notificationsAsync.when(
        data: (notifications) =>
            _NotificationsBody(notifications: notifications).animate().fadeIn(),
        loading: () => const _LoadingState(),
        error: (err, stack) => _ErrorState(message: err.toString()),
      ),
    );
  }
}

class _NotificationsBody extends ConsumerWidget {
  const _NotificationsBody({required this.notifications});

  final List<NotificationLog> notifications;

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(notificationsProvider);
    await ref.read(notificationsProvider.future);
  }

  Future<void> _markAllAsRead(WidgetRef ref) async {
    final unread = notifications.where((n) => !n.read).toList();
    if (unread.isEmpty) return;
    final repo = ref.read(notificationRepositoryProvider);
    await Future.wait(unread.map((n) => repo.markAsRead(n.name)));
    ref.invalidate(notificationsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = notifications.where((n) => !n.read).length;
    return Column(
      children: [
        FrostCard(
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.oceanBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.notifications_active_rounded,
                  color: AppTheme.oceanBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Inbox',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.nightBlue,
                      ),
                    ),
                    Text(
                      unreadCount == 0
                          ? 'All caught up'
                          : '$unreadCount unread update${unreadCount > 1 ? 's' : ''}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: unreadCount == 0 ? null : () => _markAllAsRead(ref),
                child: const Text('Mark all read'),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0),
        const SizedBox(height: 12),
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.oceanBlue,
            onRefresh: () => _refresh(ref),
            child: notifications.isEmpty
                ? const _EmptyState()
                : ListView.builder(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: EdgeInsets.zero,
                    itemCount: notifications.length,
                    itemBuilder: (context, index) {
                      final notification = notifications[index];
                      return _NotificationTile(notification: notification)
                          .animate()
                          .fadeIn(
                            delay: Duration(milliseconds: (index * 50).clamp(0, 300)),
                            duration: 220.ms,
                          )
                          .slideY(begin: 0.08, end: 0);
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  final NotificationLog notification;
  const _NotificationTile({required this.notification});

  IconData _iconForNotification() {
    final doctype = (notification.refDoctype ?? '').toLowerCase();
    if (doctype.contains('trip')) return Icons.local_shipping_rounded;
    if (doctype.contains('delivery')) return Icons.inventory_2_rounded;
    if (doctype.contains('order')) return Icons.receipt_long_rounded;
    return Icons.notifications_none_rounded;
  }

  String _timeAgo() {
    final date = notification.creation;
    if (date == null) return 'Just now';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUnread = !notification.read;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FrostCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            await ref
                .read(notificationRepositoryProvider)
                .markAsRead(notification.name);
            ref.invalidate(notificationsProvider);
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isUnread
                      ? AppTheme.mango.withValues(alpha: 0.18)
                      : AppTheme.oceanBlue.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _iconForNotification(),
                  color: isUnread ? AppTheme.mango : AppTheme.oceanBlue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.subject,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isUnread
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                              color: AppTheme.nightBlue,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _timeAgo(),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black45,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      notification.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black54,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUnread) ...[
                const SizedBox(width: 8),
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: AppTheme.oceanBlue,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 54),
        Center(
          child: Text(
            'No notifications yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.nightBlue,
            ),
          ),
        ),
        SizedBox(height: 6),
        Center(
          child: Text(
            'New delivery updates will appear here',
            style: TextStyle(color: Colors.black45),
          ),
        ),
      ],
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: 5,
      itemBuilder: (context, index) {
        return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FrostCard(
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.oceanBlue.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 12,
                            width: 160,
                            decoration: BoxDecoration(
                              color: AppTheme.oceanBlue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            height: 10,
                            width: 230,
                            decoration: BoxDecoration(
                              color: AppTheme.oceanBlue.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
            .animate(onPlay: (controller) => controller.repeat())
            .shimmer(duration: (1000 + (index * 120)).ms);
      },
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: FrostCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: AppTheme.mango.withValues(alpha: 0.9),
              size: 40,
            ),
            const SizedBox(height: 12),
            const Text(
              'Unable to load notifications',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: AppTheme.nightBlue,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}
