import 'package:flutter/material.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    if (!app.isKycComplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(AppRoutes.kycDocuments, (route) => false);
      });
    }

    return AppShell(
      title: app.t('dashboard'),
      subtitle: app.profile?.fullName ?? 'Delivery Partner',
      actions: [
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
                if (!app.canGoOnline) ...[
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
                        '${app.activeOrder!.id} · ${app.activeOrder!.status.label}',
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
              children: app.notices.take(4).map((notice) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.notifications_active_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              notice.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(notice.message),
                            const SizedBox(height: 1),
                            Text(
                              _timeAgo(notice.time),
                              style: const TextStyle(
                                color: Colors.black45,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
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
                  'Orders by Location',
                  Icons.list_alt_rounded,
                  route: AppRoutes.ordersByLocation,
                ),
                _quickButton(
                  context,
                  'External Trips',
                  Icons.local_shipping_outlined,
                  route: AppRoutes.externalDeliveryTripList,
                ),
                _quickButton(context, 'Support', Icons.support_agent_rounded),
                _quickButton(context, 'Settings', Icons.settings_outlined),
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
