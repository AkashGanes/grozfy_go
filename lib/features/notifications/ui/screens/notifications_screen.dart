import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';

import '../../../../core/navigation/app_routes.dart';
import '../../../../core/utils/formatters.dart';
import '../../providers/notification_providers.dart';
import '../../../../core/models/app_models.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/app_shell.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  static const int _pageSize = 50;

  late final PagingController<int, NotificationLog> _pagingController;

  @override
  void initState() {
    super.initState();
    _pagingController = PagingController<int, NotificationLog>(firstPageKey: 0)
      ..addPageRequestListener(_fetchPage);
  }

  int? _readFilterFor(NotificationListFilter filter) {
    switch (filter) {
      case NotificationListFilter.all:
        return null;
      case NotificationListFilter.unread:
        return 0;
      case NotificationListFilter.read:
        return 1;
    }
  }

  Future<void> _fetchPage(int offset) async {
    try {
      final filter = ref.read(notificationListFilterProvider);
      final repo = ref.read(notificationRepositoryProvider);
      final items = await repo.getNotifications(
        limit: _pageSize,
        offset: offset,
        read: _readFilterFor(filter),
      );

      final currentOverrides = ref.read(notificationReadOverridesProvider);
      if (currentOverrides.isNotEmpty) {
        final readNames = items.where((n) => n.read).map((n) => n.name).toSet();
        if (readNames.isNotEmpty) {
          final pruned = Set<String>.from(currentOverrides)
            ..removeAll(readNames);
          if (pruned.length != currentOverrides.length) {
            ref.read(notificationReadOverridesProvider.notifier).state = pruned;
          }
        }
      }

      // Bail if the screen was popped while we were awaiting — touching a
      // disposed PagingController throws.
      if (!mounted) return;

      final isLastPage = items.length < _pageSize;
      if (isLastPage) {
        _pagingController.appendLastPage(items);
      } else {
        _pagingController.appendPage(items, offset + items.length);
      }
    } catch (e) {
      if (!mounted) return;
      _pagingController.error = e;
    }
  }

  Future<void> _refresh() async {
    ref.invalidate(notificationsProvider);
    ref.invalidate(notificationCountsProvider);
    ref.invalidate(unreadNotificationCountProvider);
    ref.invalidate(recentNotificationsProvider);
    _pagingController.refresh();
  }

  Future<void> _markAllAsReadAction(BuildContext context) async {
    final overrideNotifier = ref.read(notificationReadOverridesProvider.notifier);
    final currentOverrides = Set<String>.from(overrideNotifier.state);
    final loaded = _pagingController.itemList ?? const <NotificationLog>[];
    final toAdd = loaded
        .where((n) => !n.read && !currentOverrides.contains(n.name))
        .map((n) => n.name)
        .where((name) => name.isNotEmpty)
        .toSet();

    if (toAdd.isNotEmpty) {
      overrideNotifier.state = {...currentOverrides, ...toAdd};
    }

    final repo = ref.read(notificationRepositoryProvider);
    final ok = await repo.markAllAsRead();
    if (!ok) {
      // Roll back only the items we optimistically added, preserving any
      // other overrides that may have been added during the API call.
      final next = Set<String>.from(overrideNotifier.state)..removeAll(toAdd);
      overrideNotifier.state = next;
      if (context.mounted) {
        showInfoSnack(context, 'Failed to mark all notifications as read');
      }
      return;
    }

    await _refresh();
  }

  @override
  void dispose() {
    _pagingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(notificationListFilterProvider);
    final countsAsync = ref.watch(notificationCountsProvider);
    // Keep the overrides provider alive during paging controller loading state
    // so optimistic read state is not auto-disposed when tiles are removed.
    ref.watch(notificationReadOverridesProvider);

    final counts = countsAsync.valueOrNull;
    final int allCount = counts?.all ?? 0;
    final int unreadCount = counts?.unread ?? 0;
    final int readCount = counts?.read ?? 0;

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
                await _markAllAsReadAction(context);
            }
          },
          itemBuilder: (context) {
            return <PopupMenuEntry<_NotificationsMenuAction>>[
              PopupMenuItem<_NotificationsMenuAction>(
                value: _NotificationsMenuAction.markAllRead,
                enabled: unreadCount > 0,
                child: const Text('Mark all read'),
              ),
            ];
          },
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Row(
              children: [
                Expanded(
                  child: _NotificationFilterPill(
                    label: 'All',
                    count: allCount,
                    selected: filter == NotificationListFilter.all,
                    onTap: () {
                      ref.read(notificationListFilterProvider.notifier).state =
                          NotificationListFilter.all;
                      _pagingController.refresh();
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
                      _pagingController.refresh();
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
                      _pagingController.refresh();
                    },
                  ),
                ),
              ],
            ),
          ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0),
          const SizedBox(height: 10),
          _InboxSummaryBar(
            unreadCount: unreadCount,
          ).animate().fadeIn(duration: 260.ms).slideY(begin: 0.05, end: 0),
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
              color: AppTheme.oceanBlue,
              onRefresh: _refresh,
              child: PagedListView<int, NotificationLog>(
                pagingController: _pagingController,
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: EdgeInsets.zero,
                builderDelegate: PagedChildBuilderDelegate<NotificationLog>(
                  noItemsFoundIndicatorBuilder: (context) =>
                      _FilteredEmptyState(filter: filter),
                  firstPageProgressIndicatorBuilder: (context) => const Center(
                    child: CircularProgressIndicator(strokeWidth: 2.4),
                  ),
                  newPageProgressIndicatorBuilder: (context) => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ),
                  ),
                  firstPageErrorIndicatorBuilder: (context) => _ErrorState(
                    message: _pagingController.error?.toString() ?? 'Error',
                  ),
                  itemBuilder: (context, item, index) {
                    return _NotificationTile(
                      notification: item,
                      onChanged: () async {
                        await _refresh();
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InboxSummaryBar extends ConsumerWidget {
  const _InboxSummaryBar({required this.unreadCount});

  final int unreadCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String subtitle = unreadCount == 0
        ? 'All caught up'
        : '$unreadCount unread update${unreadCount > 1 ? 's' : ''}';

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.62),
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
                    Text(
                      'Inbox',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
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
                Text(
                  subtitle,
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _NotificationsMenuAction { markAllRead }

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
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color background = selected
        ? AppTheme.oceanBlue
        : scheme.surface.withValues(alpha: 0.6);
    final Color foreground = selected ? Colors.white : scheme.onSurface;
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

    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 54),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  final NotificationLog notification;
  final Future<void> Function()? onChanged;
  const _NotificationTile({required this.notification, this.onChanged});

  IconData _iconForNotification() {
    final doctype = (notification.refDoctype ?? '').toLowerCase();
    if (doctype.contains('trip')) return Icons.local_shipping_rounded;
    if (doctype.contains('delivery')) return Icons.inventory_2_rounded;
    if (doctype.contains('order')) return Icons.receipt_long_rounded;
    return Icons.notifications_none_rounded;
  }


  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overrides = ref.watch(notificationReadOverridesProvider);
    final bool effectiveRead =
        notification.read || overrides.contains(notification.name);
    final isUnread = !effectiveRead;
    final hasNavigationTarget =
        (notification.refDoctype ?? '').trim().isNotEmpty &&
        (notification.refName ?? '').trim().isNotEmpty;

    Future<void> handleTap() async {
      final overrideNotifier = ref.read(
        notificationReadOverridesProvider.notifier,
      );
      final bool shouldMarkRead =
          !notification.read &&
          !overrideNotifier.state.contains(notification.name);

      if (shouldMarkRead) {
        overrideNotifier.state = {...overrideNotifier.state, notification.name};
      }

      if (shouldMarkRead) {
        final ok = await ref
            .read(notificationRepositoryProvider)
            .markAsRead(notification.name);
        if (!ok) {
          final next = Set<String>.from(overrideNotifier.state)
            ..remove(notification.name);
          overrideNotifier.state = next;
          if (context.mounted) {
            showInfoSnack(context, 'Failed to mark notification as read');
          }
        }
        ref.invalidate(notificationsProvider);
        ref.invalidate(notificationCountsProvider);
        ref.invalidate(recentNotificationsProvider);
        await onChanged?.call();
      }

      final doctype = (notification.refDoctype ?? '').trim();
      final docname = (notification.refName ?? '').trim();
      if (doctype == 'External Delivery Trip' && docname.isNotEmpty) {
        if (!context.mounted) return;
        Navigator.of(
          context,
        ).pushNamed(AppRoutes.externalDeliveryTripDetails, arguments: docname);
      } else if (doctype == 'External Delivery' && docname.isNotEmpty) {
        if (!context.mounted) return;
        Navigator.of(context).pushNamed(AppRoutes.orderListing);
      }
    }

    final ColorScheme tileScheme = Theme.of(context).colorScheme;
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
                              color: tileScheme.onSurface,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          AppDateFormat.timeAgo(notification.creation),
                          style: TextStyle(
                            fontSize: 11,
                            color: tileScheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      notification.message,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tileScheme.onSurface.withValues(alpha: 0.6),
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
                Icon(
                  Icons.chevron_right_rounded,
                  color: tileScheme.onSurface.withValues(alpha: 0.4),
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
    final ColorScheme scheme = Theme.of(context).colorScheme;
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
            Text(
              'Unable to load notifications',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
