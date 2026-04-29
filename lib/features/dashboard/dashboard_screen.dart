import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../notifications/providers/notification_providers.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/profile_completeness_indicator.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();

  static String _timeAgo(DateTime time) {
    final Duration diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  static bool _shouldHideDashboardNotificationMessage(
    String title,
    String message,
  ) {
    final combined = '${title.trim()} ${message.trim()}'.toLowerCase();
    return combined.contains('assigned') && combined.contains('task');
  }
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  bool _licenseDialogShowing = false;
  late AppController _app;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app = AppScope.of(context);
    if (_app.licenseRequiresReupload && !_licenseDialogShowing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_licenseDialogShowing &&
            ModalRoute.of(context)?.isCurrent == true) {
          _showLicenseRemovedDialog();
        }
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _app.fetchLoggedInEmployeeDriverProfile(forceRefresh: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _showLicenseRemovedDialog() {
    _licenseDialogShowing = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: AppTheme.mango,
            size: 36,
          ),
          title: const Text('License Details Required'),
          content: const Text(
            'Your driving license is missing or expired. Please upload to continue.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                _licenseDialogShowing = false;
                Navigator.of(context).pushNamed(
                  AppRoutes.kycDocuments,
                  arguments: {'license_reupload': true},
                );
              },
              child: const Text('Upload License'),
            ),
          ],
        ),
      ),
    ).then((_) {
      _licenseDialogShowing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    return AppShell(
      title: app.t('dashboard'),
      subtitle: app.profile?.fullName ?? 'Delivery Partner',
      onRefresh: () async {
        await Future.wait([
          app.fetchLoggedInEmployeeDriverProfile(forceRefresh: true),
          app.hydrateVehicleFromBackend(forceRefresh: true),
          app.hydrateBankFromBackend(forceRefresh: true),
        ]);
      },
      showBottomNav: true,
      bottomNavIndex: 0,
      onBottomNavTap: (index) {
        if (index == 1) {
          Navigator.of(context).pushNamed(AppRoutes.myOrders);
        } else if (index == 2) {
          Navigator.of(context).pushNamed(AppRoutes.more);
        }
      },
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
            final bool? confirmed = await showDialog<bool>(
              context: context,
              builder: (dialogContext) {
                return AlertDialog(
                  title: const Text('Log out?'),
                  content: const Text(
                    'You will need to sign in again to continue.',
                  ),
                  actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  actions: [
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            child: const Text('Log out'),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            );
            if (confirmed != true) {
              return;
            }
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
                    if (app.availabilitySyncing)
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    const SizedBox(width: 8),
                    Switch(
                      value: app.isOnline,
                      onChanged: app.availabilitySyncing
                          ? null
                          : (bool value) async {
                              final String? error = await app.setOnline(value);
                              if (!context.mounted) return;
                              if (error != null) {
                                showInfoSnack(context, error);
                              }
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  app.availabilitySyncing
                      ? 'Syncing availability...'
                      : app.isOnline
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
          _DashboardLocationCard(app: app),
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
          const SectionLabel('Batch Pickup'),
          FrostCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.oceanBlue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.playlist_add_check,
                        color: AppTheme.oceanBlue,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Multi-Order Pickup',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Pick up multiple orders in one trip',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.grey),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(
                            context,
                          ).pushNamed(AppRoutes.ordersByLocation);
                        },
                        icon: const Icon(Icons.list_alt_rounded),
                        label: const Text('Select Orders'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(
                            context,
                          ).pushNamed(AppRoutes.externalDeliveryTripList);
                        },
                        icon: const Icon(Icons.route_rounded),
                        label: const Text('View Trips'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.mint,
                        ),
                      ),
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

  static String _dashboardNotificationMessage(String message) {
    String cleaned = message.trim();
    cleaned = cleaned.replaceAll(
      RegExp(
        r'you have been assigned a new task[\s:.-]*',
        caseSensitive: false,
      ),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'dear team[\s,:.-]*', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'assigned by[\s:.-]*[^\n\r]*', caseSensitive: false),
      '',
    );

    final lines = cleaned
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where(
          (line) => line.isNotEmpty && !line.toLowerCase().startsWith('from:'),
        )
        .toList();

    if (lines.isEmpty) {
      return cleaned;
    }

    return lines.join('\n');
  }

}

class _DashboardLocationCard extends StatelessWidget {
  const _DashboardLocationCard({required this.app});

  final AppController app;

  @override
  Widget build(BuildContext context) {
    final bool hasLocation =
        app.hasSelectedLocation &&
        app.currentLatitude != null &&
        app.currentLongitude != null;
    final LatLng center = hasLocation
        ? LatLng(app.currentLatitude!, app.currentLongitude!)
        : const LatLng(28.6139, 77.2090);

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        width: double.infinity,
        height: 184,
        child: Stack(
          children: [
            Positioned.fill(
              child: hasLocation
                  ? FlutterMap(
                      options: MapOptions(
                        initialCenter: center,
                        initialZoom: 15.5,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.none,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.lyncspace.grozfygo',
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: center,
                              width: 52,
                              height: 52,
                              child: const Icon(
                                Icons.location_pin,
                                size: 40,
                                color: AppTheme.nightBlue,
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.oceanBlue.withValues(alpha: 0.92),
                            AppTheme.nightBlue,
                          ],
                        ),
                      ),
                    ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.10),
                      Colors.black.withValues(alpha: 0.20),
                      Colors.black.withValues(alpha: 0.45),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).pushNamed(AppRoutes.currentLocation);
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: const Icon(
                                Icons.my_location_rounded,
                                color: Colors.white,
                              ),
                            ),
                            const Spacer(),
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.24),
                                ),
                              ),
                              child: TextButton(
                                onPressed: () {
                                  Navigator.of(
                                    context,
                                  ).pushNamed(AppRoutes.currentLocation);
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(0, 36),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: Text(
                                  app.hasSelectedLocation ? 'Change' : 'Select',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Current Location',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 18,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  app.currentLocationLabel ??
                                      'Location not selected yet',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.92),
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
    final hideMessage = DashboardScreen._shouldHideDashboardNotificationMessage(
      trimmedTitle,
      trimmedMessage,
    );

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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: showUnread
                            ? FontWeight.w800
                            : FontWeight.w700,
                        color: showUnread ? AppTheme.nightBlue : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (trimmedMessage.isNotEmpty && !hideMessage)
                      Text(
                        trimmedMessage,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: showUnread ? Colors.black87 : Colors.black54,
                          height: 1.35,
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
