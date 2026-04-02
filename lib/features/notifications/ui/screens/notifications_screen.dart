import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/navigation/app_routes.dart';
import '../../providers/notification_providers.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_shell.dart';
import '../../../orders_by_location/model/external_delivery.dart';
import '../../../orders_by_location/repository/external_delivery_repository.dart';
import '../../../orders_by_location/ui/order_location_detail_screen.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);
    final overrides = ref.watch(notificationReadOverridesProvider);

    return AppShell(
      title: 'Notifications',
      subtitle: 'Delivery updates and alerts',
      scrollable: false,
      actions: [
        PopupMenuButton<_NotificationsMenuAction>(
          tooltip: 'More',
          icon: const Icon(Icons.more_vert_rounded),
          onSelected: (value) async {
            switch (value) {
              case _NotificationsMenuAction.markAllRead:
                final cached = notificationsAsync.valueOrNull;
                final List<NotificationLog> current =
                    cached ?? await ref.read(notificationsProvider.future);
                if (!context.mounted) return;
                await _markAllAsReadAction(context, ref, current);
            }
          },
          itemBuilder: (context) {
            final count = notificationsAsync.maybeWhen(
              data: (notifications) => notifications
                  .where((n) => !(n.read || overrides.contains(n.name)))
                  .length,
              orElse: () => 0,
            );
            return <PopupMenuEntry<_NotificationsMenuAction>>[
              PopupMenuItem<_NotificationsMenuAction>(
                value: _NotificationsMenuAction.markAllRead,
                enabled: count > 0,
                child: const Text('Mark all read'),
              ),
            ];
          },
        ),
      ],
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overrides = ref.watch(notificationReadOverridesProvider);
    final filter = ref.watch(notificationListFilterProvider);

    final unreadNotifications = notifications
        .where((n) => !(n.read || overrides.contains(n.name)))
        .toList();
    final readNotifications = notifications
        .where((n) => (n.read || overrides.contains(n.name)))
        .toList();

    final int unreadCount = unreadNotifications.length;
    final int readCount = readNotifications.length;

    final List<NotificationLog> visibleNotifications = switch (filter) {
      NotificationListFilter.all => notifications,
      NotificationListFilter.unread => unreadNotifications,
      NotificationListFilter.read => readNotifications,
    };

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              Expanded(
                child: _NotificationFilterPill(
                  label: 'All',
                  count: notifications.length,
                  selected: filter == NotificationListFilter.all,
                  onTap: () {
                    ref.read(notificationListFilterProvider.notifier).state =
                        NotificationListFilter.all;
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NotificationFilterPill(
                  label: 'Unread',
                  count: unreadCount,
                  selected: filter == NotificationListFilter.unread,
                  onTap: () {
                    ref.read(notificationListFilterProvider.notifier).state =
                        NotificationListFilter.unread;
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _NotificationFilterPill(
                  label: 'Read',
                  count: readCount,
                  selected: filter == NotificationListFilter.read,
                  onTap: () {
                    ref.read(notificationListFilterProvider.notifier).state =
                        NotificationListFilter.read;
                  },
                ),
              ),
            ],
          ),
        ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0),
        const SizedBox(height: 10),
        _InboxSummaryBar(unreadCount: unreadCount)
            .animate()
            .fadeIn(duration: 260.ms)
            .slideY(begin: 0.05, end: 0),
        const SizedBox(height: 12),
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.oceanBlue,
            onRefresh: () => _refresh(ref),
            child: visibleNotifications.isEmpty
                ? _FilteredEmptyState(filter: filter)
                : ListView.builder(
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: EdgeInsets.zero,
                    itemCount: visibleNotifications.length,
                    itemBuilder: (context, index) {
                      final notification = visibleNotifications[index];
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

class _InboxSummaryBar extends ConsumerWidget {
  const _InboxSummaryBar({required this.unreadCount});

  final int unreadCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(notificationListFilterProvider);
    final bool unreadOnly = filter == NotificationListFilter.unread;

    final String subtitle = unreadCount == 0
        ? 'All caught up'
        : '$unreadCount unread update${unreadCount > 1 ? 's' : ''}';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100A1D3A),
            blurRadius: 16,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.notifications_active_rounded,
                      size: 16,
                      color: AppTheme.oceanBlue.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Inbox',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.nightBlue,
                      ),
                    ),
                    if (unreadCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.oceanBlue.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '$unreadCount',
                          style: TextStyle(
                            color: AppTheme.oceanBlue.withValues(alpha: 0.95),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Unread only',
                style: TextStyle(
                  color: unreadOnly
                      ? AppTheme.oceanBlue.withValues(alpha: 0.95)
                      : Colors.black54,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Transform.scale(
                scale: 0.86,
                child: Switch.adaptive(
                  value: unreadOnly,
                  onChanged: (value) {
                    if (unreadCount == 0 && value) return;
                    ref.read(notificationListFilterProvider.notifier).state =
                        value
                            ? NotificationListFilter.unread
                            : NotificationListFilter.all;
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _NotificationsMenuAction { markAllRead }

Future<void> _markAllAsReadAction(
  BuildContext context,
  WidgetRef ref,
  List<NotificationLog> notifications,
) async {
  final overrides = ref.read(notificationReadOverridesProvider);
  final unread = notifications
      .where((n) => !(n.read || overrides.contains(n.name)))
      .toList();
  if (unread.isEmpty) return;

  final overrideNotifier = ref.read(notificationReadOverridesProvider.notifier);
  final unreadIds = unread.map((n) => n.name).toSet();
  overrideNotifier.state = {...overrideNotifier.state, ...unreadIds};

  final repo = ref.read(notificationRepositoryProvider);
  final ok = await repo.markAllAsRead();
  if (!ok) {
    final next = Set<String>.from(overrideNotifier.state)..removeAll(unreadIds);
    overrideNotifier.state = next;
    ref.invalidate(notificationsProvider);
    if (context.mounted) {
      showInfoSnack(context, 'Failed to mark all notifications as read');
    }
    return;
  }

  overrideNotifier.state = <String>{};
  ref.invalidate(notificationsProvider);
}

class _NotificationFilterPill extends StatelessWidget {
  const _NotificationFilterPill({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color background = selected
        ? AppTheme.oceanBlue
        : Colors.white.withValues(alpha: 0.6);
    final Color foreground = selected ? Colors.white : AppTheme.nightBlue;
    final Color badgeBackground = selected
        ? Colors.white.withValues(alpha: 0.18)
        : AppTheme.oceanBlue.withValues(alpha: 0.12);
    final Color badgeForeground = selected
        ? Colors.white
        : AppTheme.oceanBlue.withValues(alpha: 0.95);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: AnimatedContainer(
          duration: 180.ms,
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x1A0A1D3A),
                      blurRadius: 14,
                      offset: Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBackground,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: badgeForeground,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilteredEmptyState extends StatelessWidget {
  const _FilteredEmptyState({required this.filter});

  final NotificationListFilter filter;

  @override
  Widget build(BuildContext context) {
    final (title, subtitle) = switch (filter) {
      NotificationListFilter.all => (
          'No notifications yet',
          'New delivery updates will appear here',
        ),
      NotificationListFilter.unread => (
          'No unread notifications',
          'You are all caught up',
        ),
      NotificationListFilter.read => (
          'No read notifications',
          'Read notifications will appear here',
        ),
    };

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 54),
        Center(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.nightBlue,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            subtitle,
            style: const TextStyle(color: Colors.black45),
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
    final overrides = ref.watch(notificationReadOverridesProvider);
    final bool effectiveRead = notification.read || overrides.contains(notification.name);
    final isUnread = !effectiveRead;
    final hasNavigationTarget =
        (notification.refDoctype ?? '').trim().isNotEmpty &&
        (notification.refName ?? '').trim().isNotEmpty;

    Future<void> handleTap() async {
      final overrideNotifier = ref.read(notificationReadOverridesProvider.notifier);
      final bool shouldMarkRead = !notification.read &&
          !overrideNotifier.state.contains(notification.name);

      if (shouldMarkRead) {
        overrideNotifier.state = {...overrideNotifier.state, notification.name};
      }

      if (shouldMarkRead) {
        final ok = await ref
            .read(notificationRepositoryProvider)
            .markAsRead(notification.name);
        final next = Set<String>.from(overrideNotifier.state)
          ..remove(notification.name);
        overrideNotifier.state = next;
        ref.invalidate(notificationsProvider);
        if (!ok && context.mounted) {
          showInfoSnack(context, 'Failed to mark notification as read');
        }
      }

      final doctype = (notification.refDoctype ?? '').trim();
      final docname = (notification.refName ?? '').trim();
      if (doctype == 'External Delivery Trip' && docname.isNotEmpty) {
        if (!context.mounted) return;
        Navigator.of(context).pushNamed(
          AppRoutes.externalDeliveryTripDetails,
          arguments: docname,
        );
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
              ] else if (hasNavigationTarget) ...[
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.black38,
                ),
              ],
            ],
          ),
        ),
      ),
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
