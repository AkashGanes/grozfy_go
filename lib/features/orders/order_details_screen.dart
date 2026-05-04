import 'package:flutter/material.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/utils/call_utils.dart';
import '../../core/widgets/app_shell.dart';

class OrderDetailsScreen extends StatefulWidget {
  const OrderDetailsScreen({super.key, this.order});

  final DeliveryOrder? order;

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  DeliveryOrder? _currentOrder;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _currentOrder ??= AppScope.of(context).activeOrder;
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final DeliveryOrder? order = _currentOrder ?? app.activeOrder;

    if (order == null) {
      return AppShell(
        title: 'Order Details',
        subtitle: 'No active order found',
        child: ElevatedButton(
          onPressed: () =>
              Navigator.of(context).pushReplacementNamed(AppRoutes.dashboard),
          child: const Text('Back to Dashboard'),
        ),
      );
    }

    final bool isPending = order.orderStatus == OrderStatus.pending;
    final bool showNavigate =
        !isPending &&
        (order.orderStatus == OrderStatus.accepted ||
            order.orderStatus == OrderStatus.reachedPickup);
    final bool showTrackOrder =
        order.orderStatus == OrderStatus.pickedUp ||
        order.orderStatus == OrderStatus.outForDelivery ||
        order.orderStatus == OrderStatus.delivered;

    return AppShell(
      title: 'Order ${order.orderId}',
      subtitle: isPending
          ? 'Review and accept this order'
          : 'Active order details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FrostCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Customer Details',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Divider(),
                _info('Name', order.customerName),
                _info('Phone', order.customerPhone),
                _info('Address', order.deliveryAddress),
                _info('Order ID', order.orderId),
                _info('Status', app.orderStatusLabel(order.orderStatus)),
                if (order.deliveryInstructions.isNotEmpty)
                  _info('Instructions', order.deliveryInstructions),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FrostCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Store Details',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Divider(),
                _info('Store Name', order.storeName),
                _info('Store ID', order.storeId),
                _info('Contact', order.storeContact),
                _info('Address', order.storeAddress),
                _info('Distance', '${order.distanceKm} km'),
                _info(
                  'Earnings',
                  'Rs. ${order.estimatedEarnings.toStringAsFixed(0)}',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FrostCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Order Items',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Divider(),
                ...order.orderItems.map(
                  (item) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(child: Text('${item.name} x${item.quantity}')),
                        Text(
                          'Rs. ${(item.price * item.quantity).toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Total Amount',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Rs. ${order.totalAmount.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _info('Payment Mode', order.paymentMode),
              ],
            ),
          ),
          const SizedBox(height: 12),
          CallButtonRow(
            calls: [
              CallEntry(
                phoneNumber: order.customerPhone,
                label: 'Customer',
                icon: Icons.person_rounded,
              ),
              CallEntry(
                phoneNumber: order.storeContact,
                label: 'Store',
                icon: Icons.store_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isPending) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _rejectPendingOrder(context, order),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _busy
                        ? null
                        : () => _acceptPendingOrder(context, order),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Accept Order'),
                  ),
                ),
              ],
            ),
          ] else ...[
            if (showNavigate)
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pushNamed(AppRoutes.navigation);
                },
                icon: const Icon(Icons.navigation_rounded),
                label: const Text('Navigate'),
              ),
            if (showTrackOrder) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pushNamed(AppRoutes.orderTracking);
                },
                icon: const Icon(Icons.track_changes_rounded),
                label: const Text('Track Order'),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _acceptPendingOrder(
    BuildContext context,
    DeliveryOrder order,
  ) async {
    final app = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    final error = await app.acceptOrder(order.orderId);
    if (!context.mounted) {
      return;
    }
    setState(() => _busy = false);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    setState(() {
      _currentOrder = order.copyWith(
        orderStatus: OrderStatus.accepted,
        assignmentStatus: OrderAssignmentStatus.assigned,
      );
    });
    messenger.showSnackBar(
      const SnackBar(content: Text('Order accepted successfully!')),
    );
    Navigator.of(context).pushNamed(AppRoutes.navigation);
  }

  Future<void> _rejectPendingOrder(
    BuildContext context,
    DeliveryOrder order,
  ) async {
    final app = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    final error = await app.rejectOrder(order.orderId);
    if (!context.mounted) {
      return;
    }
    setState(() => _busy = false);
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    messenger.showSnackBar(const SnackBar(content: Text('Order rejected')));
    navigator.pushNamedAndRemoveUntil(AppRoutes.orderListing, (route) => false);
  }

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
