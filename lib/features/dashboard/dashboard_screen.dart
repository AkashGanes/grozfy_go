import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
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
import '../orders_by_location/model/external_delivery.dart';
import '../orders_by_location/repository/external_delivery_repository.dart';
import '../orders_by_location/ui/delivery_proof_sheet.dart';
import '../orders_by_location/ui/recall_interstitial_sheet.dart';
import '../orders_by_location/ui/trip_stop_map_screen.dart';
import '../orders/my_orders_screen.dart';
import 'widgets/active_order_card.dart';
import 'widgets/availability_card.dart';
import 'widgets/available_deliveries_card.dart';
import 'widgets/batch_pickup_card.dart';
import 'widgets/current_location_card.dart';
import 'widgets/dashboard_greeting_header.dart';
import 'widgets/profile_progress_card.dart';
import '../stats/widgets/daily_summary_card.dart';

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
            avatarLocalPath: app.profileImagePath,
            avatarUrl: app.serverProfileImageUrl,
            avatarAuthHeaders: app.buildAuthHeaders(),
            hasUnreadNotifications: unreadCount > 0,
            onNotificationsTap: () =>
                Navigator.of(context).pushNamed(AppRoutes.notifications),
            onAvatarTap: () =>
                Navigator.of(context).pushNamed(AppRoutes.profile),
          );
        },
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (app.profileCompleteness.percentage < 1.0) ...[
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
          ],
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
          const DailySummaryCard(),
          const SizedBox(height: 14),
          _ActiveOrderSection(app: app),
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

// ── Active order section — polls for recall status ────────────────────────────

class _ActiveOrderSection extends StatefulWidget {
  const _ActiveOrderSection({required this.app});
  final AppController app;

  @override
  State<_ActiveOrderSection> createState() => _ActiveOrderSectionState();
}

class _ActiveOrderSectionState extends State<_ActiveOrderSection> {
  static const Color _recallOrange = Color(0xFFE65100);

  Timer? _pollTimer;
  String? _lastPolledOrderId;
  _RecallData? _recallData;

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _maybeStartPolling();
  }

  @override
  void didUpdateWidget(_ActiveOrderSection old) {
    super.didUpdateWidget(old);
    final newId = widget.app.activeOrder?.orderId;
    if (newId != _lastPolledOrderId) {
      setState(() => _recallData = null);
      _maybeStartPolling();
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _maybeStartPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    final order = widget.app.activeOrder;
    if (order == null) return;
    _lastPolledOrderId = order.orderId;
    _pollForRecall();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _pollForRecall(),
    );
  }

  // ── Recall detection — checks trip stops first, then order status ─────────────

  static bool _isRecallPending(String status) =>
      status.trim().toLowerCase().replaceAll('_', ' ') == 'recall pending';

  Future<void> _pollForRecall() async {
    final order = widget.app.activeOrder;
    if (order == null || !mounted) return;

    _RecallData? found;

    // Primary: scan the active trip's stops for this order's recall status.
    final tripId = widget.app.activeTripId;
    if (tripId != null && tripId.isNotEmpty) {
      try {
        final trip =
            await ExternalDeliveryRepository().fetchTripDetails(tripId);
        if (!mounted) return;

        ExternalDeliveryTripStop? recallStop;
        for (final s in trip.stops) {
          if (s.externalDelivery == order.orderId &&
              _isRecallPending(s.status)) {
            recallStop = s;
            break;
          }
        }

        if (recallStop != null) {
          final storeAddress =
              (recallStop.rawFields['drop_address'] ?? '').toString().trim();
          found = _RecallData(
            customerName: recallStop.customer,
            customerPhone: recallStop.mobile,
            storeName: order.storeName,
            storeAddress: storeAddress.isNotEmpty
                ? storeAddress
                : order.storeAddress,
            itemCount: 0, // enriched below
          );
          // Enrich with item count from detail (best-effort).
          try {
            final detail = await ExternalDeliveryRepository()
                .fetchDetail(order.orderId, resolveAddress: false);
            found = _RecallData(
              customerName: recallStop.customer.isNotEmpty
                  ? recallStop.customer
                  : detail.customerName,
              customerPhone: recallStop.mobile.isNotEmpty
                  ? recallStop.mobile
                  : (detail.contactMobile ?? ''),
              storeName: detail.storeName.isNotEmpty
                  ? detail.storeName
                  : order.storeName,
              storeAddress: storeAddress.isNotEmpty
                  ? storeAddress
                  : (detail.pickupAddress ?? order.storeAddress),
              itemCount: detail.items.length,
            );
          } catch (_) {}
        }
      } catch (_) {}
    }

    // Fallback: check the order record's own status field.
    if (found == null) {
      try {
        final detail = await ExternalDeliveryRepository()
            .fetchDetail(order.orderId, resolveAddress: false);
        if (!mounted) return;
        if (_isRecallPending(detail.status)) {
          found = _RecallData(
            customerName: detail.customerName,
            customerPhone: detail.contactMobile ?? '',
            storeName: detail.storeName,
            storeAddress: detail.pickupAddress ?? order.storeAddress,
            itemCount: detail.items.length,
          );
        }
      } catch (_) {}
    }

    if (!mounted) return;
    if (found != null && _recallData == null) {
      setState(() => _recallData = found);
      await _showRecallInterstitial(found);
    } else if (found == null && _recallData != null) {
      setState(() => _recallData = null);
    }
  }

  // ── Interstitial ─────────────────────────────────────────────────────────────

  Future<void> _showRecallInterstitial(_RecallData data) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RecallInterstitialSheet(
        customerName: data.customerName,
        storeName: data.storeName,
      ),
    );
  }

  // ── Confirm recall flow ───────────────────────────────────────────────────────

  Future<void> _handleConfirmRecall(DeliveryOrder order) async {
    final data = _recallData;
    if (data == null) return;

    final customerLabel = data.customerName.isNotEmpty
        ? data.customerName
        : 'this customer';
    final bodyText = data.itemCount > 0
        ? '${data.itemCount} item${data.itemCount == 1 ? '' : 's'} for $customerLabel — confirm return to store?'
        : 'Returning items for $customerLabel — confirm?';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.store_rounded, color: _recallOrange),
            SizedBox(width: 8),
            Text(
              'Confirm Recall',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ],
        ),
        content: Text(bodyText),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _recallOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    showInfoSnack(context, 'Recall confirmed — items returned to store.');
    setState(() => _recallData = null);
    widget.app.clearActiveOrder();
  }

  Future<void> _navigateToStore(String address) async {
    if (address.isEmpty || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TripStopMapScreen(address: address, stopNumber: 0),
      ),
    );
  }

  Future<void> _launchCall(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final app = widget.app;

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

    // ── Recall mode ───────────────────────────────────────────────────────────
    if (_recallData != null) {
      return _buildRecallCard(order, _recallData!);
    }

    // ── Normal mode ───────────────────────────────────────────────────────────
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
          onTap: () => Navigator.of(context).pushNamed(AppRoutes.navigation),
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

  // ── Recall card ───────────────────────────────────────────────────────────────

  Widget _buildRecallCard(DeliveryOrder order, _RecallData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10, right: 4),
          child: Row(
            children: [
              const Text(
                'Active Order',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _recallOrange,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: _recallOrange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: _recallOrange.withValues(alpha: 0.35)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 11, color: _recallOrange),
                    SizedBox(width: 4),
                    Text(
                      'RECALLED',
                      style: TextStyle(
                        color: _recallOrange,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
                color: _recallOrange.withValues(alpha: 0.55), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: _recallOrange.withValues(alpha: 0.14),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  color: _recallOrange,
                  child: Row(
                    children: [
                      const Icon(Icons.u_turn_left_rounded,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'RECALL — RETURN TO STORE',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                                letterSpacing: 0.5,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Customer cancelled. Bring the items back.',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Customer Cancelled',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                )
                    .animate(onPlay: (c) => c.repeat(reverse: true))
                    .shimmer(
                      duration: 2000.ms,
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.receipt_long_outlined,
                              size: 14, color: Colors.black45),
                          const SizedBox(width: 7),
                          Text(
                            order.orderId,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: Color(0xFF1B1E2A),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (data.customerName.isNotEmpty) ...[
                        _infoRow(Icons.person_outline, data.customerName),
                        const SizedBox(height: 5),
                      ],
                      if (data.customerPhone.isNotEmpty) ...[
                        _callRow(data.customerPhone),
                        const SizedBox(height: 5),
                      ],
                      if (data.storeName.isNotEmpty) ...[
                        _infoRow(Icons.store_outlined, data.storeName),
                        const SizedBox(height: 5),
                      ],
                      if (data.storeAddress.isNotEmpty) ...[
                        _infoRow(
                          Icons.location_on_outlined,
                          data.storeAddress,
                          label: 'Return to',
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: () => _navigateToStore(data.storeAddress),
                          child: Container(
                            width: double.infinity,
                            padding:
                                const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              color:
                                  _recallOrange.withValues(alpha: 0.07),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _recallOrange.withValues(alpha: 0.3),
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.store_rounded,
                                    size: 15, color: _recallOrange),
                                SizedBox(width: 6),
                                Text(
                                  'Navigate to Store',
                                  style: TextStyle(
                                    color: _recallOrange,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      const Divider(height: 1, color: Color(0xFFFFCC80)),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _recallOrange,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          onPressed: () => _handleConfirmRecall(order),
                          icon: const Icon(Icons.store_rounded, size: 18),
                          label: const Text(
                            'Confirm Recall at Store',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        )
            .animate()
            .fadeIn(duration: 300.ms)
            .slideY(begin: 0.05, end: 0, duration: 300.ms),
      ],
    );
  }

  Widget _infoRow(IconData icon, String text, {String? label}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: Colors.black38),
        ),
        const SizedBox(width: 7),
        if (label != null)
          Text(
            '$label: ',
            style: const TextStyle(
              color: Colors.black38,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        Expanded(
          child: Text(text,
              style:
                  const TextStyle(color: Color(0xFF1B1E2A), fontSize: 13)),
        ),
      ],
    );
  }

  Widget _callRow(String phone) {
    return Row(
      children: [
        const Icon(Icons.phone_outlined, size: 14, color: Colors.black38),
        const SizedBox(width: 7),
        Expanded(
          child: Text(phone,
              style:
                  const TextStyle(color: Color(0xFF1B1E2A), fontSize: 13)),
        ),
        GestureDetector(
          onTap: () => _launchCall(phone),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.call_rounded,
                    size: 13, color: Color(0xFF2E7D32)),
                SizedBox(width: 4),
                Text(
                  'Call',
                  style: TextStyle(
                    color: Color(0xFF2E7D32),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  Widget _placeholder(BuildContext context, Widget body) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            widget.app.t('active_order'),
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
      final Uri androidUri =
          Uri.parse('google.navigation:q=$lat,$lng&mode=d');
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

class _RecallData {
  const _RecallData({
    required this.customerName,
    required this.customerPhone,
    required this.storeName,
    required this.storeAddress,
    required this.itemCount,
  });
  final String customerName;
  final String customerPhone;
  final String storeName;
  final String storeAddress;
  final int itemCount;
}
