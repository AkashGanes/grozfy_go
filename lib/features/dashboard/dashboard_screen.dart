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
import '../stats/providers/stats_providers.dart';
import 'widgets/active_order_card.dart';
import 'widgets/availability_card.dart';
import 'widgets/available_deliveries_card.dart';
import 'widgets/batch_pickup_card.dart';
import 'widgets/current_location_card.dart';
import 'widgets/dashboard_colors.dart';
import 'widgets/dashboard_greeting_header.dart';
import 'widgets/status_pill.dart';
import 'widgets/profile_progress_card.dart';
import '../stats/widgets/daily_summary_card.dart';
import '../pickup_jobs/model/pickup_job.dart';
import '../pickup_jobs/repository/pickup_job_repository.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen>
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
    _app.onTimingEvent = () {
      if (mounted) ref.invalidate(dailySummaryProvider);
    };
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
    _app.onTimingEvent = null;
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
        ref.invalidate(dailySummaryProvider);
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
          const _ActivePickupJobSection(),
          const SizedBox(height: 14),
          CurrentLocationCard(
            title: app.t('current_location'),
            changeLabel: app.hasSelectedLocation ? 'Change' : 'Select',
            address:
                _firstLine(app.currentLocationLabel) ??
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
            onViewTrips: () => Navigator.of(
              context,
            ).pushNamed(AppRoutes.externalDeliveryTripList),
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
    return parts
        .sublist(1)
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
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
  // Recall uses the app's warm "warning" family (mango #F6A623 / tertiary),
  // in a deeper shade that stays legible under white text in light & dark.
  static const Color _recallAccent = Color(0xFFB26A06);

  Timer? _pollTimer;
  String? _lastPolledOrderId;
  _RecallData? _recallData;
  bool _recallCardExpanded = false;
  // Guards against re-surfacing a recall after the driver confirms it.
  // Server keeps the stop as "recall pending" until it processes the return,
  // so without this set the 45s poll would re-detect and resurface repeatedly.
  final Set<String> _confirmedRecallOrderIds = {};

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

    // Already confirmed this session — never resurface it.
    if (_confirmedRecallOrderIds.contains(order.orderId)) {
      if (_recallData != null) setState(() => _recallData = null);
      return;
    }

    _RecallData? found;

    // Primary: scan the active trip's stops for this order's recall status.
    final tripId = widget.app.activeTripId;
    if (tripId != null && tripId.isNotEmpty) {
      try {
        final trip = await ExternalDeliveryRepository().fetchTripDetails(
          tripId,
        );
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
          final storeAddress = (recallStop.rawFields['drop_address'] ?? '')
              .toString()
              .trim();
          found = _RecallData(
            orderId: order.orderId,
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
            final detail = await ExternalDeliveryRepository().fetchDetail(
              order.orderId,
              resolveAddress: false,
            );
            found = _RecallData(
              orderId: order.orderId,
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
        final detail = await ExternalDeliveryRepository().fetchDetail(
          order.orderId,
          resolveAddress: false,
        );
        if (!mounted) return;
        if (_isRecallPending(detail.status)) {
          found = _RecallData(
            orderId: order.orderId,
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
        orderId: data.orderId,
        itemCount: data.itemCount,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.store_rounded, color: _recallAccent),
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
              backgroundColor: _recallAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    showInfoSnack(context, 'Recall confirmed — items returned to store.');
    _confirmedRecallOrderIds.add(_recallData!.orderId);
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
        date: AppDateFormat.date(order.acceptedAt),
        time: AppDateFormat.time(order.acceptedAt),
        phone: order.customerPhone.isNotEmpty
            ? order.customerPhone
            : (order.contactNumber.isNotEmpty ? order.contactNumber : null),
        email: app.profile?.email,
      ),
      actions: [
        ActiveOrderAction(
          label: app.t('view_order'),
          icon: Icons.receipt_long_outlined,
          onTap: () => Navigator.of(
            context,
          ).pushNamed(AppRoutes.orderDetails, arguments: order),
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
          onTap: () => Navigator.of(
            context,
          ).pushNamed(AppRoutes.orderTracking, arguments: order),
        ),
      ],
      onTrackOrder: () => Navigator.of(
        context,
      ).pushNamed(AppRoutes.orderTracking, arguments: order),
      primaryActionLabel: transition?.label,
      onPrimaryAction: transition == null
          ? null
          : () => _runTransition(context, app, order, transition),
    );
  }

  // ── Recall card ───────────────────────────────────────────────────────────────

  Widget _buildRecallCard(DeliveryOrder order, _RecallData data) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color surface = DashColors.cardBg(context);
    final Color divider = DashColors.cardBorder(context);

    // 2026 palette — vivid red accent for cancellation status.
    const Color cancelRed = Color(0xFFE8384F);
    final Color cancelRedDark = Color(0xFFFF6370); // bright red for dark mode
    final Color cancelRedBg = isDark
        ? const Color(0xFF4A1A28)
        : const Color(0xFFFEF0F0);
    final Color cancelRedBorder = isDark
        ? const Color(0xFF7A2E40)
        : const Color(0xFFFCD6D6);
    final Color cancelRedFg = isDark ? cancelRedDark : cancelRed;

    final String itemLabel = data.itemCount > 0
        ? '${data.itemCount} item${data.itemCount == 1 ? '' : 's'} to return'
        : 'Return items to store';

    // Format current time for display.
    final now = DateTime.now();
    final h = now.hour;
    final period = h >= 12 ? 'PM' : 'AM';
    final hour12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    final minute = now.minute.toString().padLeft(2, '0');
    final timeStamp = '$hour12:$minute $period';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section heading + status chip.
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10, right: 4),
          child: Row(
            children: [
              Text(
                'Active Order',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: DashColors.textPrimary(context),
                ),
              ),
              const SizedBox(width: 8),
              const StatusPill(
                label: 'Recall',
                tone: StatusPillTone.danger,
                icon: Icons.circle,
                dense: true,
              ),
            ],
          ),
        ),

        // ── Main card ─────────────────────────────────────────────────────
        Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: divider),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.06),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Status header — soft red tint — Tappable for expansion ─────
                    InkWell(
                      onTap: () => setState(
                        () => _recallCardExpanded = !_recallCardExpanded,
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        decoration: BoxDecoration(
                          color: cancelRedBg,
                          border: Border(
                            bottom: BorderSide(
                              color: cancelRedBorder,
                              width: 0.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Pulsing cancel icon.
                            Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: cancelRedFg.withValues(
                                      alpha: isDark ? 0.28 : 0.14,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.cancel_rounded,
                                    color: cancelRedFg,
                                    size: 18,
                                  ),
                                )
                                .animate(onPlay: (c) => c.repeat(reverse: true))
                                .scaleXY(
                                  begin: 1,
                                  end: 1.08,
                                  duration: 1200.ms,
                                  curve: Curves.easeInOut,
                                ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Order Cancelled',
                                style: TextStyle(
                                  color: cancelRedFg,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  letterSpacing: -0.1,
                                ),
                              ),
                            ),
                            // Expand/Collapse icon.
                            Icon(
                              _recallCardExpanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 20,
                              color: cancelRedFg.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 8),
                            // Timestamp badge.
                            Text(
                              timeStamp,
                              style: TextStyle(
                                color: DashColors.textSecondary(context),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Body message — Always shown ──────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.customerName.isNotEmpty
                                ? 'Customer cancelled the order'
                                : 'This order has been cancelled',
                            style: TextStyle(
                              color: DashColors.textPrimary(context),
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'while you were out for delivery.',
                                  style: TextStyle(
                                    color: DashColors.textSecondary(context),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                              Text(
                                '#${order.orderId}',
                                style: TextStyle(
                                  color: DashColors.textTertiary(context),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // ── Expandable "Order Details" ───────────────────────────
                    if (_recallCardExpanded)
                      // ── "Order Details" section ─────────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Section label with info icon.
                            Row(
                              children: [
                                Text(
                                  'Order Details',
                                  style: TextStyle(
                                    color: DashColors.textSecondary(context),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Icon(
                                  Icons.info_outline_rounded,
                                  size: 13,
                                  color: DashColors.textSecondary(
                                    context,
                                  ).withValues(alpha: 0.55),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Divider(height: 1, color: divider),
                            const SizedBox(height: 14),

                            // Store row — icon + name + order ID + items badge.
                            Row(
                              children: [
                                // Store avatar.
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: DashColors.subtleFill(context),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: divider,
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.store_rounded,
                                    size: 20,
                                    color: DashColors.textSecondary(context),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Store name + Order ID.
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        data.storeName.isNotEmpty
                                            ? data.storeName
                                            : 'Store',
                                        style: TextStyle(
                                          color: DashColors.textPrimary(
                                            context,
                                          ),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Order ID: #${order.orderId}',
                                        style: TextStyle(
                                          color: DashColors.textSecondary(
                                            context,
                                          ),
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Items badge.
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: DashColors.subtleFill(context),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    itemLabel,
                                    style: TextStyle(
                                      color: DashColors.textPrimary(context),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // Address row.
                            if (data.storeAddress.isNotEmpty) ...[
                              const SizedBox(height: 14),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Icon(
                                      Icons.location_on,
                                      size: 16,
                                      color: cancelRedFg,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          data.storeAddress,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: DashColors.textTertiary(
                                              context,
                                            ),
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w500,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],

                            // Customer phone row.
                            if (data.customerPhone.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Icon(
                                    Icons.phone_outlined,
                                    size: 15,
                                    color: DashColors.textSecondary(context),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      data.customerName.isNotEmpty
                                          ? '${data.customerName} · ${data.customerPhone}'
                                          : data.customerPhone,
                                      style: TextStyle(
                                        color: DashColors.textSecondary(
                                          context,
                                        ),
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () =>
                                        _launchCall(data.customerPhone),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF1AB36A,
                                        ).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.call_rounded,
                                            size: 12,
                                            color: isDark
                                                ? const Color(0xFF4ADE80)
                                                : const Color(0xFF16A34A),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Call',
                                            style: TextStyle(
                                              color: isDark
                                                  ? const Color(0xFF4ADE80)
                                                  : const Color(0xFF16A34A),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),

                    // ── Action buttons ──────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                      child: Row(
                        children: [
                          // Navigate button.
                          if (data.storeAddress.isNotEmpty)
                            Expanded(
                              child: SizedBox(
                                height: 46,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: DashColors.textPrimary(
                                      context,
                                    ),
                                    side: BorderSide(color: divider),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                  ),
                                  onPressed: () =>
                                      _navigateToStore(data.storeAddress),
                                  icon: Icon(
                                    Icons.navigation_rounded,
                                    size: 16,
                                    color: isDark
                                        ? const Color(0xFF93C5FD)
                                        : const Color(0xFF2563EB),
                                  ),
                                  label: Text(
                                    'Navigate',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: DashColors.textPrimary(context),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (data.storeAddress.isNotEmpty)
                            const SizedBox(width: 10),
                          // Confirm Recall button.
                          Expanded(
                            child: SizedBox(
                              height: 46,
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isDark
                                      ? const Color(0xFF2563EB)
                                      : const Color(0xFF1C4E80),
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                ),
                                onPressed: () => _handleConfirmRecall(order),
                                icon: const Icon(
                                  Icons.check_circle_outline_rounded,
                                  size: 17,
                                ),
                                label: const Text(
                                  'Confirm Recall',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
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
            .fadeIn(duration: 350.ms)
            .slideY(begin: 0.04, end: 0, duration: 350.ms),
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
              color: isDark ? const Color(0xFFF2F4F7) : const Color(0xFF101828),
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
      case OrderStatus.returned:
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
      navigator.pushNamedAndRemoveUntil(AppRoutes.dashboard, (route) => false);
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
    final bool launched = await launchUrl(
      webUri,
      mode: LaunchMode.externalApplication,
    );
    if (!context.mounted) return;
    if (!launched) {
      showInfoSnack(context, app.t('unable_open_maps'));
    }
  }

}

// ── Active pickup job card ────────────────────────────────────────────────────

class _ActivePickupJobSection extends StatefulWidget {
  const _ActivePickupJobSection();

  @override
  State<_ActivePickupJobSection> createState() =>
      _ActivePickupJobSectionState();
}

class _ActivePickupJobSectionState extends State<_ActivePickupJobSection> {
  PickupJob? _job;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final job = await PickupJobRepository().loadActivePickupJob();
    if (mounted) setState(() => _job = job);
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    if (job == null) return const SizedBox.shrink();

    final statusNorm = job.status.trim().toLowerCase();
    final statusColor = statusNorm == 'picked up'
        ? const Color(0xFF35C2B5)
        : AppTheme.oceanBlue;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: GestureDetector(
        onTap: () => Navigator.of(context)
            .pushNamed(AppRoutes.pickupJobDetail, arguments: job.name)
            .then((_) => _load()),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: AppTheme.oceanBlue.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppTheme.oceanBlue.withValues(alpha: 0.20),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.oceanBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  size: 16,
                  color: AppTheme.oceanBlue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.name,
                      style: const TextStyle(
                        color: AppTheme.nightBlue,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (job.customerName.isNotEmpty)
                      Text(
                        job.customerName,
                        style: const TextStyle(
                          color: Colors.black45,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  job.status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: Colors.black26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecallData {
  const _RecallData({
    required this.orderId,
    required this.customerName,
    required this.customerPhone,
    required this.storeName,
    required this.storeAddress,
    required this.itemCount,
  });
  final String orderId;
  final String customerName;
  final String customerPhone;
  final String storeName;
  final String storeAddress;
  final int itemCount;
}
