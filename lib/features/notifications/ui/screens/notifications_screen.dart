import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/navigation/app_routes.dart';
import '../../providers/notification_providers.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_shell.dart';
import '../../../../core/state/app_scope.dart';
import '../../../orders_by_location/model/external_delivery.dart';
import '../../../orders_by_location/repository/external_delivery_repository.dart';
import '../../../orders_by_location/ui/order_location_detail_screen.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);
    final app = AppScope.of(context);

    return AppShell(
      title: 'Notifications',
      subtitle: 'Delivery updates and alerts',
      scrollable: false,
      child: notificationsAsync.when(
        data: (notifications) => _NotificationsBody(
          notifications: notifications,
          systemNotices: app.notices,
        ).animate().fadeIn(),
        loading: () => const _LoadingState(),
        error: (err, stack) => _ErrorState(message: err.toString()),
      ),
    );
  }
}

class _NotificationsBody extends ConsumerWidget {
  const _NotificationsBody({
    required this.notifications,
    required this.systemNotices,
  });

  final List<NotificationLog> notifications;
  final List<AppNotice> systemNotices;

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
    final unreadCount =
        notifications.where((n) => !n.read).length + systemNotices.length;
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
                onPressed: unreadCount == 0 ? null : () {},
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
            child: (notifications.isEmpty && systemNotices.isEmpty)
                ? const _EmptyState()
                : CustomScrollView(
                    slivers: [
                      if (systemNotices.isNotEmpty) ...[
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                            child: Text(
                              'SYSTEM NOTICES',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: AppColors.outline,
                                letterSpacing: 1,
                              ),
                            ),
                          ),
                        ),
                        SliverList(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final notice = systemNotices[index];
                            return _SystemNoticeTile(notice: notice)
                                .animate()
                                .fadeIn(
                                  delay: Duration(milliseconds: index * 50),
                                )
                                .slideY(begin: 0.08, end: 0);
                          }, childCount: systemNotices.length),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 12)),
                      ],
                      SliverList(
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final notification = notifications[index];
                          return _NotificationTile(notification: notification)
                              .animate()
                              .fadeIn(
                                delay: Duration(
                                  milliseconds:
                                      ((index + systemNotices.length) * 50)
                                          .clamp(0, 300),
                                ),
                                duration: 220.ms,
                              )
                              .slideY(begin: 0.08, end: 0);
                        }, childCount: notifications.length),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _SystemNoticeTile extends StatelessWidget {
  final AppNotice notice;
  const _SystemNoticeTile({required this.notice});

  String _timeAgo() {
    final now = DateTime.now();
    final diff = now.difference(notice.time);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${notice.time.day.toString().padLeft(2, '0')}/${notice.time.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    Color indicatorColor = AppColors.primary;
    final titleLower = notice.title.toLowerCase();
    if (titleLower.contains('rain') ||
        titleLower.contains('forecast') ||
        titleLower.contains('payout') ||
        titleLower.contains('successful')) {
      indicatorColor = AppColors.outlineVariant;
    } else if (titleLower.contains('policy') ||
        titleLower.contains('alert') ||
        titleLower.contains('update')) {
      indicatorColor = AppColors.error;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FrostCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: indicatorColor.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.info_outline_rounded,
                color: indicatorColor,
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
                          notice.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
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
                    notice.message,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
    final hasNavigationTarget =
        (notification.refDoctype ?? '').trim().isNotEmpty &&
        (notification.refName ?? '').trim().isNotEmpty;

    Future<void> handleTap() async {
      await ref
          .read(notificationRepositoryProvider)
          .markAsRead(notification.name);
      ref.invalidate(notificationsProvider);

      final doctype = (notification.refDoctype ?? '').trim();
      final docname = (notification.refName ?? '').trim();
      if (doctype == 'External Delivery Trip' && docname.isNotEmpty) {
        if (!context.mounted) return;
        Navigator.of(
          context,
        ).pushNamed(AppRoutes.externalDeliveryTripDetails, arguments: docname);
      } else if (doctype == 'External Delivery' && docname.isNotEmpty) {
        if (!context.mounted) return;
        final repository = ExternalDeliveryRepository();
        final order = ExternalDelivery(
          name: docname,
          storeUrl: '',
          storeName: '',
          customerName: '',
          status: '',
          creation: '',
          modified: '',
        );
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                OrderLocationDetailScreen(order: order, repository: repository),
          ),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: FrostCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: handleTap,
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
                            notification.subject.isNotEmpty
                                ? notification.subject
                                : notification.type ?? 'Notification',
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
                      notification.message.isNotEmpty
                          ? notification.message
                          : 'You have a new notification',
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
              ] else if (hasNavigationTarget) ...[
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, color: Colors.black38),
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
