import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../notifications/providers/notification_providers.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/profile_completeness_indicator.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    return AppShell(
      title: app.t('dashboard'),
      subtitle: app.profile?.fullName ?? 'Delivery Partner',
      actions: [
        Consumer(
          builder: (context, ref, _) {
            final unreadCount = ref
                .watch(unreadNotificationCountProvider)
                .maybeWhen(data: (v) => v, orElse: () => 0);
            return Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_none_rounded),
                  onPressed: () {
                    Navigator.of(context).pushNamed(AppRoutes.notifications);
                  },
                ),
                if (unreadCount > 0)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        '$unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.logout_rounded),
          onPressed: () async {
            await app.logout();
            if (!context.mounted) {
              return;
            }
            Navigator.of(
              context,
            ).pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
          },
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProfileCompletenessIndicator(
            completeness: app.profileCompleteness,
            onItemTap: (item) {
              if (item.route != null) {
                Navigator.of(context).pushNamed(item.route!);
              }
            },
          ),
          const SizedBox(height: 12),
          FrostCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Availability',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Switch(
                      value: app.isOnline,
                      onChanged: (bool value) {
                        final String? error = app.setOnline(value);
                        if (error != null) {
                          showInfoSnack(context, error);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  app.isOnline
                      ? 'Online and receiving order requests'
                      : 'Offline, no new orders will be assigned',
                  style: const TextStyle(color: Colors.black54),
                ),
                if (!app.canGoOnline && !app.isKycComplete) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: AppTheme.mango.withValues(alpha: 0.12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Complete KYC + bank + permissions before going online.',
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(
                              context,
                            ).pushNamed(AppRoutes.kycDocuments);
                          },
                          child: const Text('Complete'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          FrostCard(
            child: Row(
              children: [
                const Icon(Icons.my_location_rounded),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current Location',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        app.currentLocationLabel ?? 'Location not selected yet',
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pushNamed(AppRoutes.currentLocation);
                  },
                  child: Text(app.hasSelectedLocation ? 'Change' : 'Select'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const SectionLabel('Earnings Summary'),
          FrostCard(
            child: Column(
              children: [
                Row(
                  children: [
                    StatTile(
                      label: 'Today',
                      value: 'Rs. ${app.earnings.today.toStringAsFixed(0)}',
                    ),
                    const SizedBox(width: 10),
                    StatTile(
                      label: 'This Week',
                      value: 'Rs. ${app.earnings.week.toStringAsFixed(0)}',
                      color: AppTheme.mint,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    StatTile(
                      label: 'Total',
                      value: 'Rs. ${app.earnings.total.toStringAsFixed(0)}',
                      color: AppTheme.nightBlue,
                    ),
                    const SizedBox(width: 10),
                    StatTile(
                      label: 'Pending Payout',
                      value:
                          'Rs. ${app.earnings.pendingPayout.toStringAsFixed(0)}',
                      color: AppTheme.mango,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const SectionLabel('Performance Metrics'),
          FrostCard(
            child: Column(
              children: [
                Row(
                  children: [
                    StatTile(
                      label: 'Rating',
                      value:
                          '${app.performance.rating.toStringAsFixed(1)} star',
                    ),
                    const SizedBox(width: 10),
                    StatTile(
                      label: 'Acceptance',
                      value:
                          '${app.performance.acceptanceRate.toStringAsFixed(1)}%',
                      color: AppTheme.nightBlue,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    StatTile(
                      label: 'Completion',
                      value:
                          '${app.performance.completionRate.toStringAsFixed(1)}%',
                      color: AppTheme.mint,
                    ),
                    const SizedBox(width: 10),
                    StatTile(
                      label: 'Total Deliveries',
                      value: '${app.performance.totalDeliveries}',
                      color: AppTheme.mango,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SectionLabel('Available Deliveries'),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pushNamed(AppRoutes.deliveryList);
                },
                child: const Text('View All'),
              ),
            ],
          ),
          FrostCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.local_shipping,
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'External Deliveries',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'View and manage deliveries from ERPNext',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushNamed(AppRoutes.deliveryList);
                    },
                    icon: const Icon(Icons.list_alt),
                    label: const Text('View Deliveries'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const SectionLabel('Active Order'),
          FrostCard(
            child: app.activeOrder == null
                ? Row(
                    children: [
                      const Expanded(child: Text('No active order right now.')),
                      TextButton(
                        onPressed: () {
                          app.generateIncomingOrder();
                          Navigator.of(
                            context,
                          ).pushNamed(AppRoutes.orderRequest);
                        },
                        child: const Text('Get Request'),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${app.activeOrder!.orderId} · ${app.activeOrder!.orderStatus.label}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(app.activeOrder!.drop),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.of(
                                  context,
                                ).pushNamed(AppRoutes.orderDetails);
                              },
                              child: const Text('View Order'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.of(
                                  context,
                                ).pushNamed(AppRoutes.navigation);
                              },
                              child: const Text('Quick Navigate'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 14),
          const SectionLabel('Notifications'),
          FrostCard(
            child: Column(
              children: [
                Consumer(
                  builder: (context, ref, _) {
                    final async = ref.watch(recentNotificationsProvider);
                    return async.when(
                      data: (items) {
                        final overrides =
                            ref.watch(notificationReadOverridesProvider);
                        final List<Widget> rows = <Widget>[
                          ...items.take(2).map((notification) {
                            final effectiveRead = notification.read ||
                                overrides.contains(notification.name);
                            return _NotificationRow(
                              title: notification.subject,
                              message: notification.message,
                              time: notification.creation,
                              isUnread: !effectiveRead,
                              onTap: () {
                                Navigator.of(
                                  context,
                                ).pushNamed(AppRoutes.notifications);
                              },
                            );
                          }),
                          ...app.notices.take(4).map((notice) {
                            return _NotificationRow(
                              title: notice.title,
                              message: notice.message,
                              time: notice.time,
                            );
                          }),
                        ];

                        if (rows.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Text(
                              'No notifications yet.',
                              style: TextStyle(color: Colors.black54),
                            ),
                          );
                        }

                        return Column(children: rows);
                      },
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4),
                          ),
                        ),
                      ),
                      error: (err, _) => Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Unable to load notifications.',
                              style: TextStyle(color: Colors.black54),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              ref.invalidate(recentNotificationsProvider);
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const SectionLabel('Quick Access'),
          FrostCard(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _quickButton(
                  context,
                  'My Profile',
                  Icons.person_outline_rounded,
                  route: AppRoutes.profile,
                ),
                _quickButton(
                  context,
                  'Earnings History',
                  Icons.receipt_long_rounded,
                ),
                _quickButton(
                  context,
                  'Documents',
                  Icons.file_copy_outlined,
                  route: AppRoutes.kycDocuments,
                ),
                _quickButton(
                  context,
                  'Vehicle',
                  Icons.two_wheeler_rounded,
                  route: AppRoutes.vehicleDetails,
                ),
                _quickButton(
                  context,
                  'Bank Details',
                  Icons.account_balance_outlined,
                  route: AppRoutes.bankSetup,
                ),
                _quickButton(
                  context,
                  'Orders by Location',
                  Icons.list_alt_rounded,
                  route: AppRoutes.ordersByLocation,
                ),
                _quickButton(
                  context,
                  'Available Orders',
                  Icons.local_shipping_outlined,
                  route: AppRoutes.orderListing,
                ),
                _quickButton(
                  context,
                  'External Trips',
                  Icons.local_shipping_outlined,
                  route: AppRoutes.externalDeliveryTripList,
                ),
                _quickButton(context, 'Support', Icons.support_agent_rounded),
                _quickButton(
                  context,
                  'Settings',
                  Icons.settings_outlined,
                  route: AppRoutes.settings,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () {
              app.generateIncomingOrder();
              Navigator.of(context).pushNamed(AppRoutes.orderRequest);
            },
            icon: const Icon(Icons.local_shipping_rounded),
            label: const Text('Simulate Incoming Order'),
          ),
        ],
      ),
    );
  }

  static Widget _quickButton(
    BuildContext context,
    String label,
    IconData icon, {
    String? route,
  }) {
    return SizedBox(
      width: 150,
      child: OutlinedButton.icon(
        onPressed: () {
          if (route != null) {
            Navigator.of(context).pushNamed(route);
            return;
          }
          showInfoSnack(context, '$label module can be expanded next');
        },
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }

  static String _timeAgo(DateTime time) {
    final Duration diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) {
      return 'just now';
    }
    if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    }
    if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    }
    return '${diff.inDays}d ago';
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({
    required this.title,
    required this.message,
    required this.time,
    this.isUnread,
    this.onTap,
  });

  final String title;
  final String message;
  final DateTime? time;
  final bool? isUnread;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final trimmedTitle = title.trim();
    final trimmedMessage = message.trim();

    final bool showUnread = isUnread ?? false;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10, top: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(Icons.notifications_active_outlined, size: 18),
                  ),
                  if (showUnread)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppTheme.oceanBlue,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trimmedTitle.isEmpty ? 'Notification' : trimmedTitle,
                      style: TextStyle(
                        fontWeight: showUnread ? FontWeight.w800 : FontWeight.w700,
                        color:
                            showUnread ? AppTheme.nightBlue : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (trimmedMessage.isNotEmpty)
                      Text(
                        trimmedMessage,
                        style: TextStyle(
                          color: showUnread ? Colors.black87 : Colors.black54,
                        ),
                      ),
                    if (time != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        DashboardScreen._timeAgo(time!),
                        style: const TextStyle(
                          color: Colors.black45,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
