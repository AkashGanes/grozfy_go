import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../orders_by_location/model/external_delivery.dart';
import '../orders_by_location/repository/external_delivery_repository.dart';
import '../orders_by_location/ui/delivery_outcome_sheet.dart';
import '../orders_by_location/ui/delivery_proof_sheet.dart';
import '../orders_by_location/ui/failed_delivery_bottom_sheet.dart';
import '../orders_by_location/ui/recall_interstitial_sheet.dart';
import '../orders_by_location/ui/trip_stop_map_screen.dart';
import 'widgets/order_timer_widget.dart';

const Color _recallOrange = Color(0xFFE65100);

class OrderStatusScreen extends StatefulWidget {
  const OrderStatusScreen({super.key});

  @override
  State<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

class _OrderStatusScreenState extends State<OrderStatusScreen> {
  // ── Normal progress flow ─────────────────────────────────────────────────────
  bool _syncing = false;

  static const _flow = <OrderProgressStatus>[
    OrderStatus.pending,
    OrderStatus.accepted,
    OrderStatus.reachedPickup,
    OrderStatus.pickedUp,
    OrderStatus.outForDelivery,
    OrderStatus.delivered,
  ];

  // ── Recall flow ───────────────────────────────────────────────────────────────
  Timer? _pollTimer;
  String? _lastPolledOrderId;
  _RecallData? _recallData;

  // ── Lifecycle ─────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartPolling());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  void _maybeStartPolling() {
    final app = AppScope.of(context);
    final order = app.activeOrder;
    if (order == null) return;
    _pollTimer?.cancel();
    _lastPolledOrderId = order.orderId;
    _pollForRecall();
    _pollTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _pollForRecall(),
    );
  }

  // ── Recall detection — checks trip stops first, then order status ─────────────

  static bool _isRecallPending(String status) =>
      status.trim().toLowerCase().replaceAll('_', ' ') == 'recall pending';

  Future<void> _pollForRecall() async {
    final app = AppScope.of(context);
    final order = app.activeOrder;
    if (order == null || !mounted) return;

    if (order.orderId != _lastPolledOrderId) {
      setState(() => _recallData = null);
      _maybeStartPolling();
      return;
    }

    _RecallData? found;

    // Primary: scan the active trip's stops for this order's recall status.
    final tripId = app.activeTripId;
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
            itemCount: 0,
            recallStop: recallStop,
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
              recallStop: recallStop,
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

  // ── Confirm recall ────────────────────────────────────────────────────────────

  Future<void> _handleConfirmRecall(DeliveryOrder order) async {
    // ignore: avoid_print
    print('[Recall] _handleConfirmRecall called — orderId=${order.orderId} recallData=${_recallData?.orderId} syncing=$_syncing');

    final data = _recallData;
    if (data == null || _syncing) {
      // ignore: avoid_print
      print('[Recall] early return — data=${data == null ? 'null' : 'ok'} syncing=$_syncing');
      return;
    }

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

    setState(() => _syncing = true);

    // Step 1: Call dedicated backend API — this updates the linked Recall doc
    // and sets status → Returned, store_notified=1 via server logic.
    // ignore: avoid_print
    print('[Recall] Step1 → confirm_recall_received_at_store order=${data.orderId}');
    try {
      await ExternalDeliveryRepository().confirmRecallReceivedAtStore(
        externalDelivery: data.orderId,
      );
      // ignore: avoid_print
      print('[Recall] Step1 ✓ API succeeded');
    } catch (e) {
      // ignore: avoid_print
      print('[Recall] Step1 ✗ API failed: ${e.toString().replaceFirst('Exception: ', '')}');
    }

    // Step 2: Always do direct field updates regardless of Step 1 outcome —
    // sets trip stop → Returned and order → Returned + store_notified=1
    // via frappe.client.set_value so it always reflects in ERPNext web.
    if (data.recallStop != null) {
      // ignore: avoid_print
      print('[Recall] Step2 → confirmRecallReturn stop=${data.recallStop!.rawFields['name']} order=${data.orderId}');
      try {
        await ExternalDeliveryRepository().confirmRecallReturn(
          stop: data.recallStop!,
          orderName: data.orderId,
        );
        // ignore: avoid_print
        print('[Recall] Step2 ✓ Direct update succeeded — status=Returned store_notified=1');
      } catch (e) {
        // ignore: avoid_print
        print('[Recall] Step2 ✗ Direct update failed: $e');
      }
    } else {
      // ignore: avoid_print
      print('[Recall] Step2 skipped — recallStop is null (no trip stop available)');
    }

    if (!mounted) return;
    AppToast.show(context, 'Recall confirmed — items returned to store.');
    final app = AppScope.of(context);
    app.clearActiveOrder();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.dashboard,
        (r) => false,
      );
    }
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

  // ── Normal flow helpers ───────────────────────────────────────────────────────

  static const _stepMeta = [
    (label: 'Accepted', icon: Icons.task_alt_rounded),
    (label: 'At Store', icon: Icons.store_rounded),
    (label: 'Picked', icon: Icons.inventory_2_rounded),
    (label: 'En Route', icon: Icons.delivery_dining_rounded),
    (label: 'Delivered', icon: Icons.home_rounded),
  ];

  OrderProgressStatus _nextStatus(OrderProgressStatus s) {
    if (s == OrderStatus.pending) return OrderStatus.accepted;
    if (s == OrderStatus.accepted) return OrderStatus.reachedPickup;
    if (s == OrderStatus.reachedPickup) return OrderStatus.pickedUp;
    if (s == OrderStatus.pickedUp) return OrderStatus.outForDelivery;
    if (s == OrderStatus.outForDelivery) return OrderStatus.delivered;
    return s;
  }

  String _actionLabel(OrderProgressStatus s) {
    if (s == OrderStatus.pending) return 'Accept Order';
    if (s == OrderStatus.accepted) return 'Mark Reached Pickup';
    if (s == OrderStatus.reachedPickup) return 'Mark Picked Up';
    if (s == OrderStatus.pickedUp) return 'Start Out for Delivery';
    if (s == OrderStatus.outForDelivery) return 'Mark Delivered';
    return '';
  }

  String _confirmTitle(OrderProgressStatus next) {
    if (next == OrderStatus.reachedPickup) return 'Reached Pickup?';
    if (next == OrderStatus.pickedUp) return 'Items Picked Up?';
    if (next == OrderStatus.outForDelivery) return 'Start Delivery?';
    if (next == OrderStatus.delivered) return 'Confirm Delivery?';
    return 'Confirm?';
  }

  String _confirmBody(OrderProgressStatus next) {
    if (next == OrderStatus.reachedPickup) {
      return "Confirm you've arrived at the pickup location.";
    }
    if (next == OrderStatus.pickedUp) {
      return "Confirm you've collected all items from the store.";
    }
    if (next == OrderStatus.outForDelivery) {
      return "Confirm you're heading to the customer with the order.";
    }
    if (next == OrderStatus.delivered) {
      return "Confirm the order has been handed to the customer.";
    }
    return 'Confirm status update.';
  }

  Color _statusColor(OrderProgressStatus s) {
    if (s == OrderStatus.reachedPickup) return const Color(0xFFE65100);
    if (s == OrderStatus.pickedUp) return const Color(0xFF6A1B9A);
    if (s == OrderStatus.outForDelivery) return AppTheme.oceanBlue;
    if (s == OrderStatus.delivered) return const Color(0xFF2E7D32);
    return AppTheme.oceanBlue;
  }

  IconData _statusIcon(OrderProgressStatus s) {
    if (s == OrderStatus.reachedPickup) return Icons.store_rounded;
    if (s == OrderStatus.pickedUp) return Icons.inventory_2_rounded;
    if (s == OrderStatus.outForDelivery) return Icons.delivery_dining_rounded;
    if (s == OrderStatus.delivered) return Icons.check_circle_rounded;
    return Icons.local_shipping_rounded;
  }

  Future<void> _advanceStatus(BuildContext context) async {
    final app = AppScope.of(context);
    final order = app.activeOrder;
    if (order == null || _syncing) return;
    final navigator = Navigator.of(context);

    final next = _nextStatus(order.orderStatus);
    if (next == order.orderStatus) return;

    setState(() => _syncing = true);

    if (next == OrderStatus.delivered) {
      // Optional proof photo
      final photoPath = await showDeliveryProofSheet(context);
      if (!mounted) { setState(() => _syncing = false); return; }
      if (photoPath != null) {
        await ExternalDeliveryRepository().uploadProofPhoto(
          orderName: order.orderId,
          filePath: photoPath,
        );
        if (!mounted) { setState(() => _syncing = false); return; }
      }

      // Fetch COD info, then show unified delivery outcome sheet
      bool isCod = order.paymentMode.toUpperCase() == 'COD';
      double codAmount = 0;
      try {
        final detail = await ExternalDeliveryRepository().fetchDetail(
          order.orderId,
          resolveAddress: false,
        );
        isCod = detail.isCod;
        codAmount = detail.codAmountToCollect ?? 0;
      } catch (_) {}
      if (!mounted) { setState(() => _syncing = false); return; }

      // Show unified sheet: COD form + Confirm Delivery + Mark as Failed
      final outcome = await showDeliveryOutcomeSheet(
        context,
        isCod: isCod,
        codAmount: codAmount,
      );
      if (!mounted) { setState(() => _syncing = false); return; }
      if (outcome == null) { setState(() => _syncing = false); return; }

      if (outcome.outcome == 'failed') {
        // Driver chose to mark as failed from within the delivery sheet
        setState(() => _syncing = false);
        await _onMarkFailed(context, order);
        return;
      }

      // Outcome is 'delivered' — save COD data if applicable
      if (isCod && outcome.codMode != null) {
        try {
          await ExternalDeliveryRepository().markDeliveredWithCod(
            order.orderId,
            codCollectionMode: outcome.codMode!,
            codUpiReference: outcome.codRef,
          );
        } catch (_) {}
        if (!mounted) return;
      }
    }

    final error = await app.updateOrderStatus(next);

    if (next == OrderStatus.delivered ||
        next == OrderStatus.cancelled ||
        next == OrderStatus.rejected) {
      app.stopOrderTimer();
    }

    if (!context.mounted) return;
    setState(() => _syncing = false);

    if (error != null) {
      AppToast.show(context, error);
      return;
    }

    if (next == OrderStatus.delivered) {
      AppToast.show(context, 'Order delivered and earnings updated');
      navigator.pushNamedAndRemoveUntil(AppRoutes.dashboard, (r) => false);
    }
  }

  Future<void> _onMarkFailed(BuildContext context, DeliveryOrder order) async {
    final bool isCod = order.paymentMode.toUpperCase() == 'COD';
    final result = await showFailedDeliverySheet(context, isCod: isCod);
    if (result == null || !mounted) return;
    setState(() => _syncing = true);
    try {
      await ExternalDeliveryRepository().markOrderFailed(
        orderName: order.orderId,
        reason: result.notes.isNotEmpty ? result.notes : result.reason,
        reasonCode: result.reasonCode,
        photoPath: result.photoPath,
      );
    } catch (_) {}
    if (!mounted) { setState(() => _syncing = false); return; }
    final app = AppScope.of(context);
    final error = await app.updateOrderStatus(OrderStatus.failed);
    app.stopOrderTimer();
    if (!context.mounted) return;
    setState(() => _syncing = false);
    if (error != null) {
      AppToast.show(context, error);
      return;
    }
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.dashboard, (r) => false);
  }

  Future<void> _onActionTap(BuildContext context, DeliveryOrder order) async {
    final next = _nextStatus(order.orderStatus);
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _StatusConfirmSheet(
        title: _confirmTitle(next),
        body: _confirmBody(next),
        actionLabel: _actionLabel(order.orderStatus),
        icon: _statusIcon(next),
        color: _statusColor(next),
      ),
    );
    if (confirmed == true && context.mounted) {
      await _advanceStatus(context);
    }
  }

  String _contextSubtitle(OrderProgressStatus s, DeliveryOrder order) {
    if (s == OrderStatus.pickedUp) {
      final name = order.customerName.isNotEmpty ? order.customerName : 'the customer';
      return 'Head to $name and start delivery';
    }
    if (s == OrderStatus.outForDelivery) {
      final addr = order.deliveryAddress.isNotEmpty ? order.deliveryAddress : 'the delivery address';
      return 'En route to $addr';
    }
    if (s == OrderStatus.delivered) return 'Order successfully delivered';
    if (s == OrderStatus.accepted) {
      return 'Navigate to ${order.storeName.isNotEmpty ? order.storeName : 'the store'} for pickup';
    }
    return '';
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final app = AppScope.of(context);
    final order = app.activeOrder;

    if (order == null) {
      return Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Expanded(child: Center(child: Text('No active delivery'))),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).pushNamedAndRemoveUntil(AppRoutes.dashboard, (r) => false),
                    child: const Text('Back to Dashboard'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── Recall mode ───────────────────────────────────────────────────────────
    if (_recallData != null) {
      return Scaffold(
        backgroundColor: scheme.surface,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: _buildRecallView(order, _recallData!),
          ),
        ),
      );
    }

    // ── Normal progress mode ──────────────────────────────────────────────────
    final int currentIndex = _flow.indexOf(order.orderStatus);
    final isDone =
        order.orderStatus == OrderStatus.delivered ||
        order.orderStatus == OrderStatus.cancelled ||
        order.orderStatus == OrderStatus.rejected;
    final color = _statusColor(order.orderStatus);

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        size: 20,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order #${order.orderId}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (order.storeName.isNotEmpty)
                          Text(
                            order.storeName,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (app.isOrderTimerRunning) const OrderTimerWidget(),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // ── Compact progress timeline ──────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _ProgressTimeline(
                steps: _stepMeta,
                currentIndex: currentIndex,
              ),
            ),

            const SizedBox(height: 24),
            Divider(height: 1, color: scheme.onSurface.withValues(alpha: 0.08)),
            const SizedBox(height: 24),

            // ── Status context ─────────────────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: color.withValues(alpha: 0.22),
                          width: 2,
                        ),
                      ),
                      child: Icon(_statusIcon(order.orderStatus), color: color, size: 46),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      app.orderStatusLabel(order.orderStatus),
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _contextSubtitle(order.orderStatus, order),
                      style: TextStyle(
                        fontSize: 14,
                        color: scheme.onSurface.withValues(alpha: 0.55),
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    // Item checklist shown only when driver is collecting items
                    if (order.orderStatus == OrderStatus.reachedPickup &&
                        order.orderItems.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.shopping_bag_outlined,
                                  size: 14,
                                  color: color,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'ITEMS TO COLLECT',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: color,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ...order.orderItems.take(5).map(
                              (item) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 5),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        item.name,
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                    Text(
                                      '×${item.quantity}',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (order.orderItems.length > 5) ...[
                              const SizedBox(height: 4),
                              Text(
                                '+${order.orderItems.length - 5} more',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),

            // ── Action button ──────────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                MediaQuery.of(context).padding.bottom + 16,
              ),
              child: isDone
                  ? _DeliveredBadge(
                      status: order.orderStatus,
                      onNavigateToStore: _navigateToStore,
                      onConfirmRecall: _recallData == null
                          ? null
                          : () => _handleConfirmRecall(order),
                      onCall: _launchCall,
                    )
                  : SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _syncing
                            ? null
                            : order.orderStatus == OrderStatus.outForDelivery
                                ? () => _advanceStatus(context)
                                : () => _onActionTap(context, order),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: color,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _syncing
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _actionLabel(order.orderStatus),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    size: 20,
                                  ),
                                ],
                              ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Recall view (restored from recall/archana) ────────────────────────────────

  Widget _buildRecallView(DeliveryOrder order, _RecallData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: _recallOrange,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: _recallOrange.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 4)),
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.u_turn_left_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Order Recalled — Return to Store',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                        SizedBox(height: 2),
                        Text('Return items and confirm at the dock',
                            style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .shimmer(duration: 1800.ms, color: Colors.white.withValues(alpha: 0.15)),
        const SizedBox(height: 12),
        Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _recallOrange.withValues(alpha: 0.5), width: 1.5),
                boxShadow: [
                  BoxShadow(color: _recallOrange.withValues(alpha: 0.1), blurRadius: 16, offset: const Offset(0, 5)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      color: _recallOrange,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 17),
                          const SizedBox(width: 8),
                          const Text('RECALL — RETURN TO STORE',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.6)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('Customer Cancelled',
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _recallInfoRow(Icons.receipt_long_outlined, order.orderId, bold: true),
                          const SizedBox(height: 8),
                          if (data.customerName.isNotEmpty) ...[
                            _recallInfoRow(Icons.person_outline, data.customerName),
                            const SizedBox(height: 6),
                          ],
                          if (data.customerPhone.isNotEmpty) ...[
                            _recallCallRow(data.customerPhone),
                            const SizedBox(height: 6),
                          ],
                          if (data.storeName.isNotEmpty) ...[
                            _recallInfoRow(Icons.store_outlined, data.storeName),
                            const SizedBox(height: 6),
                          ],
                          if (data.storeAddress.isNotEmpty) ...[
                            _recallInfoRow(Icons.location_on_outlined, data.storeAddress, label: 'Return to'),
                            const SizedBox(height: 10),
                          ],
                          if (data.storeAddress.isNotEmpty) ...[
                            GestureDetector(
                              onTap: () => _navigateToStore(data.storeAddress),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  color: _recallOrange.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: _recallOrange.withValues(alpha: 0.3)),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.store_rounded, size: 15, color: _recallOrange),
                                    SizedBox(width: 6),
                                    Text('Navigate to Store',
                                        style: TextStyle(color: _recallOrange, fontSize: 13, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                          const Divider(height: 1, color: Color(0xFFFFCC80)),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _recallOrange,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                              onPressed: () => _handleConfirmRecall(order),
                              icon: const Icon(Icons.store_rounded, size: 18),
                              label: const Text('Confirm Recall at Store',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
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
            .fadeIn(duration: 280.ms)
            .slideY(begin: 0.05, end: 0, duration: 280.ms),
      ],
    );
  }

  Widget _recallInfoRow(IconData icon, String text, {String? label, bool bold = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 14, color: Colors.black38)),
        const SizedBox(width: 7),
        if (label != null)
          Text('$label: ', style: const TextStyle(color: Colors.black38, fontSize: 12, fontWeight: FontWeight.w600)),
        Expanded(
          child: Text(text,
              style: TextStyle(
                  color: const Color(0xFF1B1E2A),
                  fontSize: 13,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.normal)),
        ),
      ],
    );
  }

  Widget _recallCallRow(String phone) {
    return Row(
      children: [
        const Icon(Icons.phone_outlined, size: 14, color: Colors.black38),
        const SizedBox(width: 7),
        Expanded(child: Text(phone, style: const TextStyle(color: Color(0xFF1B1E2A), fontSize: 13))),
        GestureDetector(
          onTap: () => _launchCall(phone),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.call_rounded, size: 13, color: Color(0xFF2E7D32)),
                SizedBox(width: 4),
                Text('Call', style: TextStyle(color: Color(0xFF2E7D32), fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// Compact horizontal progress timeline
// =============================================================================

class _ProgressTimeline extends StatelessWidget {
  const _ProgressTimeline({
    required this.steps,
    required this.currentIndex,
  });

  final List<({String label, IconData icon})> steps;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          // Connector line
          final stepIdx = i ~/ 2;
          final done = stepIdx < currentIndex;
          return Expanded(
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: done
                    ? const Color(0xFF2E7D32)
                    : scheme.onSurface.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          );
        }
        final idx = i ~/ 2;
        final step = steps[idx];
        final isDone = idx < currentIndex;
        final isCurrent = idx == currentIndex;
        final dotColor = isDone
            ? const Color(0xFF2E7D32)
            : isCurrent
            ? AppTheme.oceanBlue
            : scheme.onSurface.withValues(alpha: 0.15);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: AppTheme.oceanBlue.withValues(alpha: 0.35),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                isDone ? Icons.check_rounded : step.icon,
                size: 15,
                color: isDone || isCurrent
                    ? Colors.white
                    : scheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              step.label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.normal,
                color: isCurrent
                    ? scheme.onSurface
                    : scheme.onSurface.withValues(alpha: isDone ? 0.6 : 0.35),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        );
      }),
    );
  }
}

// =============================================================================
// Status confirmation bottom sheet
// =============================================================================

class _StatusConfirmSheet extends StatelessWidget {
  const _StatusConfirmSheet({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.icon,
    required this.color,
  });

  final String title;
  final String body;
  final String actionLabel;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        16,
        24,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 28),
          // Icon
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 38),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              fontSize: 14,
              color: scheme.onSurface.withValues(alpha: 0.55),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                actionLabel,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Not Yet',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Delivered / completed badge shown at the bottom when no action available
// =============================================================================

class _DeliveredBadge extends StatelessWidget {
  const _DeliveredBadge({
    required this.status,
    this.onNavigateToStore,
    this.onConfirmRecall,
    this.onCall,
  });
  final OrderProgressStatus status;
  final void Function(String address)? onNavigateToStore;
  final VoidCallback? onConfirmRecall;
  final void Function(String phone)? onCall;

  @override
  Widget build(BuildContext context) {
    final (Color color, IconData icon, String label) = switch (status) {
      OrderStatus.delivered => (
        const Color(0xFF2E7D32),
        Icons.check_circle_rounded,
        'Delivered Successfully',
      ),
      OrderStatus.cancelled => (
        const Color(0xFFC62828),
        Icons.cancel_rounded,
        'Order Cancelled',
      ),
      _ => (
        Colors.grey,
        Icons.info_outline_rounded,
        'Order Closed',
      ),
    };

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
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
    this.recallStop,
  });
  final String orderId;
  final String customerName;
  final String customerPhone;
  final String storeName;
  final String storeAddress;
  final int itemCount;
  final ExternalDeliveryTripStop? recallStop;
}

