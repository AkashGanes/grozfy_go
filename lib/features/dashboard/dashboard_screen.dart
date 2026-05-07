import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import '../notifications/providers/notification_providers.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/theme/context_colors.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/profile_completeness_indicator.dart';
import '../orders_by_location/repository/external_delivery_repository.dart';
import '../orders_by_location/ui/delivery_proof_sheet.dart';

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
        if (mounted &&
            !_licenseDialogShowing &&
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
                    Expanded(
                      child: Text(
                        app.t('availability'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
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
                      ? app.t('syncing_availability')
                      : app.isOnline
                      ? app.t('online_status')
                      : app.t('offline_status'),
                  style: TextStyle(color: context.textSecondary),
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
                        Expanded(child: Text(app.t('kyc_warning'))),
                        TextButton(
                          onPressed: () {
                            Navigator.of(
                              context,
                            ).pushNamed(AppRoutes.kycDocuments);
                          },
                          child: Text(app.t('complete')),
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
          /* SectionLabel(app.t('earnings_summary')),
          FrostCard(
            child: Column(
              children: [
                Row(
                  children: [
                    StatTile(
                      label: app.t('today'),
                      value: 'Rs. ${app.earnings.today.toStringAsFixed(0)}',
                    ),
                    const SizedBox(width: 10),
                    StatTile(
                      label: app.t('this_week'),
                      value: 'Rs. ${app.earnings.week.toStringAsFixed(0)}',
                      color: AppTheme.mint,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    StatTile(
                      label: app.t('total'),
                      value: 'Rs. ${app.earnings.total.toStringAsFixed(0)}',
                      color: context.scheme.primary,
                    ),
                    const SizedBox(width: 10),
                    StatTile(
                      label: app.t('pending_payout'),
                      value:
                          'Rs. ${app.earnings.pendingPayout.toStringAsFixed(0)}',
                      color: AppTheme.mango,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14), */
          /* SectionLabel(app.t('performance_metrics')),
          FrostCard(
            child: Column(
              children: [
                Row(
                  children: [
                    StatTile(
                      label: app.t('rating'),
                      value:
                          '${app.performance.rating.toStringAsFixed(1)} star',
                    ),
                    const SizedBox(width: 10),
                    StatTile(
                      label: app.t('acceptance'),
                      value:
                          '${app.performance.acceptanceRate.toStringAsFixed(1)}%',
                      color: context.scheme.primary,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    StatTile(
                      label: app.t('completion'),
                      value:
                          '${app.performance.completionRate.toStringAsFixed(1)}%',
                      color: AppTheme.mint,
                    ),
                    const SizedBox(width: 10),
                    StatTile(
                      label: app.t('total_deliveries'),
                      value: '${app.performance.totalDeliveries}',
                      color: AppTheme.mango,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14), */
          SectionLabel(app.t('batch_pickup')),
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.t('multi_order_pickup'),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            app.t('pick_up_multiple'),
                            style: TextStyle(
                              color: context.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: context.iconMuted),
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
                        label: Text(app.t('select_orders')),
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
                        label: Text(app.t('view_trips')),
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
              SectionLabel(app.t('available_deliveries')),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pushNamed(AppRoutes.ordersByLocation);
                },
                child: Text(app.t('view_all')),
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.t('external_deliveries'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            app.t('external_deliveries_desc'),
                            style: TextStyle(
                              color: context.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: context.iconMuted),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pushNamed(AppRoutes.ordersByLocation);
                    },
                    icon: const Icon(Icons.list_alt),
                    label: Text(app.t('view_deliveries')),
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
          SectionLabel(app.t('active_order')),
          FrostCard(
            child: app.isFetchingActiveOrder
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Text(app.t('loading_active_order')),
                      ],
                    ),
                  )
                : app.activeOrder == null
                ? Row(
                    children: [
                      Expanded(child: Text(app.t('no_active_order'))),
                      TextButton(
                        onPressed: () {
                          Navigator.of(
                            context,
                          ).pushNamed(AppRoutes.orderListing);
                        },
                        child: Text(app.t('browse_nearby')),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${app.activeOrder!.orderId} · ${app.orderStatusLabel(app.activeOrder!.orderStatus)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        Formatters.stripHtml(
                          app.activeOrder!.drop,
                          preserveLineBreaks: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _ActiveOrderActions(order: app.activeOrder!),
                    ],
                  ),
          ),
          /* const SizedBox(height: 14),
          SectionLabel(app.t('notifications')),
          FrostCard(
            child: Column(
              children: [
                Consumer(
                  builder: (context, ref, _) {
                    final async = ref.watch(recentNotificationsProvider);
                    return async.when(
                      data: (items) {
                        final overrides = ref.watch(
                          notificationReadOverridesProvider,
                        );
                        final List<Widget> rows = <Widget>[
                          ...items.take(2).map((notification) {
                            final effectiveRead =
                                notification.read ||
                                overrides.contains(notification.name);
                            return _NotificationRow(
                              title: notification.subject,
                              message: _dashboardNotificationMessage(
                                notification.message,
                              ),
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
                          return Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              'No notifications yet.',
                              style: TextStyle(color: context.textSecondary),
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
                          Expanded(
                            child: Text(
                              'Unable to load notifications.',
                              style: TextStyle(color: context.textSecondary),
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
          const SizedBox(height: 14), */
          /* SectionLabel(app.t('quick_access')),
          FrostCard(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _quickButton(
                  context,
                  app.t('my_profile'),
                  Icons.person_outline_rounded,
                  route: AppRoutes.profile,
                ),
                _quickButton(
                  context,
                  app.t('earnings_history'),
                  Icons.receipt_long_rounded,
                ),
                _quickButton(
                  context,
                  app.t('documents'),
                  Icons.file_copy_outlined,
                  route: AppRoutes.kycDocuments,
                ),
                _quickButton(
                  context,
                  app.t('vehicle'),
                  Icons.two_wheeler_rounded,
                  route: AppRoutes.vehicleDetails,
                ),
                _quickButton(
                  context,
                  app.t('bank_details'),
                  Icons.account_balance_outlined,
                  route: AppRoutes.bankSetup,
                ),
                _quickButton(
                  context,
                  app.t('orders_by_location'),
                  Icons.list_alt_rounded,
                  route: AppRoutes.ordersByLocation,
                ),
                _quickButton(
                  context,
                  app.t('available_orders'),
                  Icons.local_shipping_outlined,
                  route: AppRoutes.orderListing,
                ),
                _quickButton(
                  context,
                  app.t('external_trips'),
                  Icons.local_shipping_outlined,
                  route: AppRoutes.externalDeliveryTripList,
                ),
                _quickButton(
                  context,
                  app.t('support'),
                  Icons.support_agent_rounded,
                ),
                _quickButton(
                  context,
                  app.t('settings'),
                  Icons.settings_outlined,
                  route: AppRoutes.settings,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12), */
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

class _ActiveOrderActions extends StatelessWidget {
  const _ActiveOrderActions({required this.order});

  final DeliveryOrder order;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final List<Widget> rows = <Widget>[
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                Navigator.of(
                  context,
                ).pushNamed(AppRoutes.orderDetails, arguments: order);
              },
              child: Text(app.t('view_order')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pushNamed(AppRoutes.navigation);
              },
              child: Text(app.t('navigate')),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                final double lat = order.latitude;
                final double lng = order.longitude;

                if (Platform.isAndroid) {
                  final Uri androidUri = Uri.parse(
                    'google.navigation:q=$lat,$lng&mode=d',
                  );
                  if (await canLaunchUrl(androidUri)) {
                    await launchUrl(
                      androidUri,
                      mode: LaunchMode.externalApplication,
                    );
                    return;
                  }
                }

                if (Platform.isIOS) {
                  final Uri googleMapsIos = Uri.parse(
                    'comgooglemaps://?daddr=$lat,$lng&directionsmode=driving',
                  );
                  if (await canLaunchUrl(googleMapsIos)) {
                    await launchUrl(googleMapsIos);
                    return;
                  }
                  final Uri appleMaps = Uri.parse('maps:?daddr=$lat,$lng');
                  if (await canLaunchUrl(appleMaps)) {
                    await launchUrl(appleMaps);
                    return;
                  }
                }

                final Uri webUri = Uri.parse(
                  'https://www.google.com/maps/dir/?api=1'
                  '&destination=$lat,$lng'
                  '&travelmode=driving',
                );
                final bool launched = await launchUrl(
                  webUri,
                  mode: LaunchMode.externalApplication,
                );
                if (!context.mounted) return;
                if (!launched) {
                  showInfoSnack(context, app.t('unable_open_maps'));
                }
              },
              child: Text(app.t('open_maps')),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                Navigator.of(context).pushNamed(AppRoutes.orderTracking);
              },
              child: Text(app.t('track_order')),
            ),
          ),
        ],
      ),
    ];

    final ({String label, OrderProgressStatus next})? transition =
        _nextTransition(order.orderStatus, app);
    if (transition != null) {
      rows.add(const SizedBox(height: 10));
      rows.add(
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final navigator = Navigator.of(context);

              if (transition.next == OrderProgressStatus.delivered) {
                final photoPath = await showDeliveryProofSheet(context);
                if (!context.mounted) return;

                if (photoPath != null) {
                  await ExternalDeliveryRepository().uploadProofPhoto(
                    orderName: order.orderId,
                    filePath: photoPath,
                  );
                  if (!context.mounted) return;
                }
              }

              final error = await app.updateOrderStatus(transition.next);
              if (!context.mounted) {
                return;
              }
              if (error != null) {
                messenger.showSnackBar(SnackBar(content: Text(error)));
                return;
              }
              if (transition.next == OrderProgressStatus.delivered) {
                messenger.showSnackBar(
                  SnackBar(content: Text(app.t('order_delivered'))),
                );
                navigator.pushNamedAndRemoveUntil(
                  AppRoutes.dashboard,
                  (route) => false,
                );
              } else {
                navigator.pushNamed(AppRoutes.orderStatus);
              }
            },
            child: Text(transition.label),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }

  ({String label, OrderProgressStatus next})? _nextTransition(
    OrderProgressStatus current,
    AppController app,
  ) {
    switch (current) {
      case OrderStatus.accepted:
        return (
          label: app.t('mark_reached_pickup'),
          next: OrderStatus.reachedPickup,
        );
      case OrderStatus.reachedPickup:
        return (label: app.t('mark_picked_up'), next: OrderStatus.pickedUp);
      case OrderStatus.pickedUp:
        return (
          label: app.t('start_delivery'),
          next: OrderStatus.outForDelivery,
        );
      case OrderStatus.outForDelivery:
        return (label: app.t('mark_delivered'), next: OrderStatus.delivered);
      case OrderStatus.pending:
      case OrderStatus.rejected:
      case OrderStatus.delivered:
      case OrderStatus.cancelled:
        return null;
    }
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
    final bool isDark = context.isDark;

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
                          urlTemplate: isDark
                              ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                              : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          subdomains: isDark
                              ? const ['a', 'b', 'c', 'd']
                              : const [],
                          userAgentPackageName: 'com.lyncspace.grozfygo',
                        ),
                        if (!isDark)
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
            if (isDark && hasLocation) ...[
              Positioned.fill(
                child: IgnorePointer(
                  child: ColoredBox(
                    color: context.scheme.surface.withValues(alpha: 0.55),
                  ),
                ),
              ),
              const Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: Icon(
                      Icons.location_pin,
                      size: 40,
                      color: AppTheme.mint,
                    ),
                  ),
                ),
              ),
            ],
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
                        const Spacer(),
                        Text(
                          app.t('current_location'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          app.currentLocationLabel ??
                              app.t('location_not_selected'),
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
                        color: showUnread ? context.scheme.primary : context.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (trimmedMessage.isNotEmpty && !hideMessage)
                      Text(
                        trimmedMessage,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.scheme.onSurface.withValues(alpha: showUnread ? 0.85 : 0.6),
                          height: 1.35,
                        ),
                      ),
                    if (time != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        DashboardScreen._timeAgo(time!),
                        style: TextStyle(
                          color: context.textTertiary,
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
