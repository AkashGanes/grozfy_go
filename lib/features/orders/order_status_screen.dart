import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/app_toast.dart';
import '../orders_by_location/model/external_delivery.dart';
import '../orders_by_location/repository/external_delivery_repository.dart';
import '../orders_by_location/ui/delivery_proof_sheet.dart';
import '../orders_by_location/ui/recall_interstitial_sheet.dart';
import '../orders_by_location/ui/trip_stop_map_screen.dart';
import 'widgets/order_timer_widget.dart';

class OrderStatusScreen extends StatefulWidget {
  const OrderStatusScreen({super.key});

  @override
  State<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

class _OrderStatusScreenState extends State<OrderStatusScreen> {
  static const Color _recallOrange = Color(0xFFE65100);

  // ── Normal progress flow ─────────────────────────────────────────────────────
  bool _syncing = false;

  static const List<OrderProgressStatus> _flow = <OrderProgressStatus>[
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

    AppToast.show(context, 'Recall confirmed — items returned to store.');
    final app = AppScope.of(context);
    app.clearActiveOrder();
    if (mounted) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRoutes.dashboard, (r) => false);
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

  Future<void> _advanceStatus(BuildContext context) async {
    final app = AppScope.of(context);
    final order = app.activeOrder;
    if (order == null || _syncing) return;
    final navigator = Navigator.of(context);

    final OrderProgressStatus next = _nextStatus(order.orderStatus);
    if (next == order.orderStatus) return;

    setState(() => _syncing = true);

    if (next == OrderStatus.delivered) {
      final photoPath = await showDeliveryProofSheet(context);
      if (!mounted) return;
      if (photoPath != null) {
        await ExternalDeliveryRepository().uploadProofPhoto(
          orderName: order.orderId,
          filePath: photoPath,
        );
        if (!mounted) return;
      }
    }

    final String? error = await app.updateOrderStatus(next);

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
      navigator.pushNamedAndRemoveUntil(AppRoutes.dashboard, (route) => false);
    }
  }

  OrderProgressStatus _nextStatus(OrderProgressStatus current) {
    switch (current) {
      case OrderStatus.pending:
        return OrderStatus.accepted;
      case OrderStatus.accepted:
        return OrderStatus.reachedPickup;
      case OrderStatus.rejected:
        return OrderStatus.rejected;
      case OrderStatus.reachedPickup:
        return OrderStatus.pickedUp;
      case OrderStatus.pickedUp:
        return OrderStatus.outForDelivery;
      case OrderStatus.outForDelivery:
        return OrderStatus.delivered;
      case OrderStatus.delivered:
        return OrderStatus.delivered;
      case OrderStatus.cancelled:
        return OrderStatus.cancelled;
      case OrderStatus.returned:
        return OrderStatus.returned;
    }
  }

  String _nextButtonLabel(OrderProgressStatus current) {
    switch (current) {
      case OrderStatus.pending:
        return 'Accept Order';
      case OrderStatus.accepted:
        return 'Mark Reached Pickup';
      case OrderStatus.rejected:
        return 'Rejected';
      case OrderStatus.reachedPickup:
        return 'Mark Picked Up';
      case OrderStatus.pickedUp:
        return 'Start Out for Delivery';
      case OrderStatus.outForDelivery:
        return 'Mark Delivered';
      case OrderStatus.delivered:
        return 'Completed';
      case OrderStatus.cancelled:
        return 'Cancelled';
      case OrderStatus.returned:
        return 'Returned';
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final app = AppScope.of(context);
    final order = app.activeOrder;

    if (order == null) {
      return AppShell(
        title: 'Order Status',
        subtitle: 'No active delivery',
        child: ElevatedButton(
          onPressed: () => Navigator.of(
            context,
          ).pushNamedAndRemoveUntil(AppRoutes.dashboard, (route) => false),
          child: const Text('Back to Dashboard'),
        ),
      );
    }

    // ── Recall mode ───────────────────────────────────────────────────────────
    if (_recallData != null) {
      return AppShell(
        title: 'Order Progress',
        subtitle: 'Action required',
        child: _buildRecallView(order, _recallData!),
      );
    }

    // ── Normal progress mode ──────────────────────────────────────────────────
    final int currentIndex = _flow.indexOf(order.orderStatus);

    return AppShell(
      title: 'Order Progress',
      subtitle: 'Real-time status sync with customer app',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (app.isOrderTimerRunning) ...[
            const Center(child: OrderTimerWidget()),
            const SizedBox(height: 14),
          ],
          FrostCard(
            child: Column(
              children: _flow.asMap().entries.map((entry) {
                final int index = entry.key;
                final OrderProgressStatus status = entry.value;
                final bool done = index <= currentIndex;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(
                        done
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked,
                        color: done
                            ? Colors.green
                            : scheme.onSurface.withValues(alpha: 0.4),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          app.orderStatusLabel(status),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: done
                                ? scheme.onSurface
                                : scheme.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),
          if (order.orderStatus != OrderProgressStatus.delivered)
            ElevatedButton(
              onPressed: _syncing ? null : () => _advanceStatus(context),
              child: _syncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(_nextButtonLabel(order.orderStatus)),
            ),
        ],
      ),
    );
  }

  // ── Recall view ───────────────────────────────────────────────────────────────

  Widget _buildRecallView(DeliveryOrder order, _RecallData data) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Orange recall banner (shimmer) ────────────────────────────────────
        Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              decoration: BoxDecoration(
                color: _recallOrange,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _recallOrange.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.u_turn_left_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order Recalled — Return to Store',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Return items and confirm at the dock',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .shimmer(
              duration: 1800.ms,
              color: Colors.white.withValues(alpha: 0.15),
            ),

        const SizedBox(height: 12),

        // ── Recall detail card ────────────────────────────────────────────────
        Container(
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _recallOrange.withValues(alpha: 0.5),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _recallOrange.withValues(alpha: 0.1),
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                  ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Colors.white,
                            size: 17,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'RECALL — RETURN TO STORE',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 12,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Customer Cancelled',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _infoRow(
                            Icons.receipt_long_outlined,
                            order.orderId,
                            bold: true,
                          ),
                          const SizedBox(height: 8),

                          if (data.customerName.isNotEmpty) ...[
                            _infoRow(Icons.person_outline, data.customerName),
                            const SizedBox(height: 6),
                          ],

                          if (data.customerPhone.isNotEmpty) ...[
                            _callRow(data.customerPhone),
                            const SizedBox(height: 6),
                          ],

                          if (data.storeName.isNotEmpty) ...[
                            _infoRow(Icons.store_outlined, data.storeName),
                            const SizedBox(height: 6),
                          ],

                          if (data.storeAddress.isNotEmpty) ...[
                            _infoRow(
                              Icons.location_on_outlined,
                              data.storeAddress,
                              label: 'Return to',
                            ),
                            const SizedBox(height: 10),
                          ],

                          if (data.storeAddress.isNotEmpty) ...[
                            GestureDetector(
                              onTap: () => _navigateToStore(data.storeAddress),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: _recallOrange.withValues(alpha: 0.07),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: _recallOrange.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.store_rounded,
                                      size: 15,
                                      color: _recallOrange,
                                    ),
                                    SizedBox(width: 6),
                                    Text(
                                      'Navigate to Store',
                                      style: TextStyle(
                                        color: _recallOrange,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
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
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () => _handleConfirmRecall(order),
                              icon: const Icon(Icons.store_rounded, size: 18),
                              label: const Text(
                                'Confirm Recall at Store',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
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
            .fadeIn(duration: 280.ms)
            .slideY(begin: 0.05, end: 0, duration: 280.ms),
      ],
    );
  }

  Widget _infoRow(
    IconData icon,
    String text, {
    String? label,
    bool bold = false,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 14, color: Colors.black38),
        ),
        const SizedBox(width: 7),
        if (label != null) ...[
          Text(
            '$label: ',
            style: const TextStyle(
              color: Colors.black38,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: const Color(0xFF1B1E2A),
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
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
          child: Text(
            phone,
            style: const TextStyle(color: Color(0xFF1B1E2A), fontSize: 13),
          ),
        ),
        GestureDetector(
          onTap: () => _launchCall(phone),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.3),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.call_rounded, size: 13, color: Color(0xFF2E7D32)),
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
