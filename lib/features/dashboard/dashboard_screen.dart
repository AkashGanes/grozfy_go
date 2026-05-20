import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/app_toast.dart';
import '../notifications/providers/notification_providers.dart';
import '../profile/profile_completeness_sheet.dart';
import '../orders_by_location/repository/external_delivery_repository.dart';
import '../orders_by_location/ui/delivery_proof_sheet.dart';
import '../orders/my_orders_screen.dart';
import 'widgets/active_order_card.dart';
import 'widgets/availability_card.dart';
import 'widgets/available_deliveries_card.dart';
import 'widgets/batch_pickup_card.dart';
import 'widgets/current_location_card.dart';
import 'widgets/dashboard_greeting_header.dart';
import 'widgets/profile_progress_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  bool _licenseDialogShowing = false;
  bool _isNavigating = false;
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
                Navigator.of(context).pushNamed(AppRoutes.kycDocuments);
              },
              child: const Text('Upload Now'),
            ),
          ],
        ),
      ),
    ).then((_) => _licenseDialogShowing = false);
  }

  Future<void> _confirmAndLogout() async {
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
                    onPressed: () => Navigator.of(dialogContext).pop(false),
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
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('Log out'),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await _app.logout();
    if (!mounted) return;
    Navigator.of(context)
        .pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final partnerName = app.profile?.fullName.trim().isNotEmpty == true
        ? app.profile!.fullName.split(' ').first
        : 'Partner';

    return AppShell(
      title: '',
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
        if (_isNavigating) return;
        setState(() => _isNavigating = true);
        if (index == 1) {
          Navigator.of(context)
              .push(NoAnimRoute(builder: (_) => const MyOrdersScreen()))
              .whenComplete(() {
                if (mounted) setState(() => _isNavigating = false);
              });
        } else if (index == 2) {
          Navigator.of(context)
              .push(NoAnimRoute(builder: (_) => const MoreScreen()))
              .whenComplete(() {
                if (mounted) setState(() => _isNavigating = false);
              });
        } else {
          setState(() => _isNavigating = false);
        }
      },
      header: Consumer(
        builder: (context, ref, _) {
          final unreadCount = ref
              .watch(unreadNotificationCountProvider)
              .maybeWhen(data: (v) => v, orElse: () => 0);
          return DashboardGreetingHeader(
            name: partnerName,
            avatarInitial: partnerName.isNotEmpty ? partnerName[0] : '?',
            hasUnreadNotifications: unreadCount > 0,
            onNotificationsTap: () =>
                Navigator.of(context).pushNamed(AppRoutes.notifications),
            onLogoutTap: _confirmAndLogout,
            onAvatarTap: () =>
                Navigator.of(context).pushNamed(AppRoutes.profile),
          );
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProfileProgressCard(
            completeness: app.profileCompleteness,
            progressTitle: app.t('profile_progress'),
            subtitleBuilder: (c, t) => c == t
                ? "You're good to go. Ride & earn!"
                : 'Your profile is $c/$t complete. Keep going!',
            progressLabel: (c, t) => '$c of $t completed',
            tapToCompleteLabel: app.t('tap_to_complete'),
            pendingLabel: app.t('pending'),
            verifiedLabel: app.t('verified'),
            itemLabel: (item) => app.t(item.name),
            onTapComplete: () => showProfileCompletenessSheet(context),
            onItemTap: (item) {
              if (item.route != null) {
                Navigator.of(context).pushNamed(item.route!);
              }
            },
          ),
          const SizedBox(height: 14),
          AvailabilityCard(
            title: app.t('availability'),
            isOnline: app.isOnline,
            onlineLabel: 'Online',
            offlineLabel: 'Offline',
            onlineDescription: app.t('online_status'),
            offlineDescription: app.t('offline_status'),
            syncing: app.availabilitySyncing,
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
          if (!app.canGoOnline && !app.isKycComplete) ...[
            const SizedBox(height: 10),
            _KycWarningBanner(
              message: app.t('kyc_warning'),
              actionLabel: app.t('complete'),
              onTap: () =>
                  Navigator.of(context).pushNamed(AppRoutes.kycDocuments),
            ),
          ],
          const SizedBox(height: 14),
          CurrentLocationCard(
            title: app.t('current_location'),
            changeLabel: app.hasSelectedLocation ? 'Change' : 'Select',
            address: _firstLine(app.currentLocationLabel) ??
                app.t('location_not_selected'),
            subAddress: _restLines(app.currentLocationLabel) ?? '',
            latitude: app.currentLatitude,
            longitude: app.currentLongitude,
            hasLocation: app.hasSelectedLocation,
            onChangeTap: () =>
                Navigator.of(context).pushNamed(AppRoutes.currentLocation),
          ),
          const SizedBox(height: 14),
          BatchPickupCard(
            heading: app.t('batch_pickup'),
            title: app.t('multi_order_pickup'),
            subtitle: app.t('pick_up_multiple'),
            selectOrdersLabel: app.t('select_orders'),
            viewTripsLabel: app.t('view_trips'),
            onSelectOrders: () =>
                Navigator.of(context).pushNamed(AppRoutes.ordersByLocation),
            onViewTrips: () => Navigator.of(context)
                .pushNamed(AppRoutes.externalDeliveryTripList),
          ),
          const SizedBox(height: 14),
          AvailableDeliveriesCard(
            heading: app.t('available_deliveries'),
            viewAllLabel: app.t('view_all'),
            title: app.t('external_deliveries'),
            subtitle: app.t('external_deliveries_desc'),
            actionLabel: app.t('view_deliveries'),
            onViewAll: () =>
                Navigator.of(context).pushNamed(AppRoutes.ordersByLocation),
            onAction: () =>
                Navigator.of(context).pushNamed(AppRoutes.ordersByLocation),
          ),
          const SizedBox(height: 14),
          _ActiveOrderSection(app: app),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String? _firstLine(String? input) {
    if (input == null) return null;
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final parts = trimmed.split(RegExp(r'[,\n]'));
    return parts.first.trim().isEmpty ? trimmed : parts.first.trim();
  }

  String? _restLines(String? input) {
    if (input == null) return null;
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;
    final parts = trimmed.split(RegExp(r'[,\n]'));
    if (parts.length <= 1) return null;
    return parts.sublist(1).map((p) => p.trim()).where((p) => p.isNotEmpty)
        .join(', ');
  }
}

class _KycWarningBanner extends StatelessWidget {
  const _KycWarningBanner({
    required this.message,
    required this.actionLabel,
    required this.onTap,
  });

  final String message;
  final String actionLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: AppTheme.mango.withValues(alpha: 0.12),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppTheme.mango),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
          TextButton(onPressed: onTap, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _ActiveOrderSection extends StatelessWidget {
  const _ActiveOrderSection({required this.app});
  final AppController app;

  @override
  Widget build(BuildContext context) {
    if (app.isFetchingActiveOrder) {
      return _placeholder(
        context,
        const SizedBox(
          height: 20,
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 12),
              Text('Loading active order...'),
            ],
          ),
        ),
      );
    }

    final order = app.activeOrder;
    if (order == null) {
      return _placeholder(
        context,
        Row(
          children: [
            Expanded(child: Text(app.t('no_active_order'))),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pushNamed(AppRoutes.orderListing),
              child: Text(app.t('browse_nearby')),
            ),
          ],
        ),
      );
    }

    final transition = _nextTransition(order.orderStatus, app);

    return ActiveOrderCard(
      heading: app.t('active_order'),
      statusLabel: app.orderStatusLabel(order.orderStatus),
      trackOrderLabel: app.t('track_order'),
      orderId: order.orderId,
      address: Formatters.stripHtml(
        order.drop.isNotEmpty ? order.drop : order.deliveryAddress,
        preserveLineBreaks: true,
      ),
      meta: ActiveOrderMeta(
        date: _formatDate(order.acceptedAt),
        time: _formatTime(order.acceptedAt),
        phone: order.customerPhone.isNotEmpty
            ? order.customerPhone
            : (order.contactNumber.isNotEmpty ? order.contactNumber : null),
        email: app.profile?.email,
      ),
      actions: [
        ActiveOrderAction(
          label: app.t('view_order'),
          icon: Icons.receipt_long_outlined,
          onTap: () => Navigator.of(context)
              .pushNamed(AppRoutes.orderDetails, arguments: order),
        ),
        ActiveOrderAction(
          label: app.t('navigate'),
          icon: Icons.navigation_rounded,
          onTap: () =>
              Navigator.of(context).pushNamed(AppRoutes.navigation),
        ),
        ActiveOrderAction(
          label: app.t('open_maps'),
          icon: Icons.map_outlined,
          onTap: () => _openInMaps(context, order, app),
        ),
        ActiveOrderAction(
          label: app.t('track_order'),
          icon: Icons.local_shipping_outlined,
          onTap: () => Navigator.of(context).pushNamed(
            AppRoutes.orderTracking,
            arguments: order,
          ),
        ),
      ],
      onTrackOrder: () => Navigator.of(context).pushNamed(
        AppRoutes.orderTracking,
        arguments: order,
      ),
      primaryActionLabel: transition?.label,
      onPrimaryAction: transition == null
          ? null
          : () => _runTransition(context, app, order, transition),
    );
  }

  Widget _placeholder(BuildContext context, Widget body) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            app.t('active_order'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: isDark
                  ? const Color(0xFFF2F4F7)
                  : const Color(0xFF101828),
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1B1E2A) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: body,
        ),
      ],
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
        return (
          label: app.t('mark_picked_up'),
          next: OrderStatus.pickedUp,
        );
      case OrderStatus.pickedUp:
        return (
          label: app.t('start_delivery'),
          next: OrderStatus.outForDelivery,
        );
      case OrderStatus.outForDelivery:
        return (
          label: app.t('mark_delivered'),
          next: OrderStatus.delivered,
        );
      case OrderStatus.pending:
      case OrderStatus.rejected:
      case OrderStatus.delivered:
      case OrderStatus.cancelled:
        return null;
    }
  }

  Future<void> _runTransition(
    BuildContext context,
    AppController app,
    DeliveryOrder order,
    ({String label, OrderProgressStatus next}) transition,
  ) async {
    final navigator = Navigator.of(context);

    if (transition.next == OrderStatus.delivered) {
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
    if (!context.mounted) return;
    if (error != null) {
      AppToast.show(context, error);
      return;
    }
    if (transition.next == OrderStatus.delivered) {
      AppToast.show(context, app.t('order_delivered'));
      navigator.pushNamedAndRemoveUntil(
        AppRoutes.dashboard,
        (route) => false,
      );
    } else {
      navigator.pushNamed(AppRoutes.orderStatus);
    }
  }

  Future<void> _openInMaps(
    BuildContext context,
    DeliveryOrder order,
    AppController app,
  ) async {
    final double lat = order.latitude;
    final double lng = order.longitude;

    if (Platform.isAndroid) {
      final Uri androidUri = Uri.parse('google.navigation:q=$lat,$lng&mode=d');
      if (await canLaunchUrl(androidUri)) {
        await launchUrl(androidUri, mode: LaunchMode.externalApplication);
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
    final bool launched =
        await launchUrl(webUri, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    if (!launched) {
      showInfoSnack(context, app.t('unable_open_maps'));
    }
  }

  String? _formatDate(DateTime? d) {
    if (d == null) return null;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String? _formatTime(DateTime? d) {
    if (d == null) return null;
    final h = d.hour;
    final period = h >= 12 ? 'PM' : 'AM';
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final minute = d.minute.toString().padLeft(2, '0');
    return '$hour12:$minute $period';
  }
}

