import 'package:flutter/material.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/utils/call_utils.dart';
import '../../core/widgets/app_shell.dart';
import 'widgets/order_timer_widget.dart';

class OrderDetailsScreen extends StatelessWidget {
  const OrderDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final order = app.activeOrder;

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

    return AppShell(
      title: 'Order ${order.orderId}',
      subtitle: 'Customer + Store details',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (app.isOrderTimerRunning) ...[
              const Center(child: OrderTimerWidget()),
              const SizedBox(height: 12),
            ],
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
                  _info('Status', order.orderStatus.label),
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
                          Expanded(
                            child: Text('${item.name} x${item.quantity}'),
                          ),
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
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamed(AppRoutes.navigation);
              },
              icon: const Icon(Icons.navigation_rounded),
              label: const Text('Navigate'),
            ),
            const SizedBox(height: 12),
            if (order.orderStatus == OrderStatus.accepted)
              ElevatedButton(
                onPressed: () => _markReachedPickup(context, order),
                child: const Text('Mark Reached Store (Pickup)'),
              ),
            if (order.orderStatus == OrderStatus.reachedPickup)
              ElevatedButton(
                onPressed: () {
                  app.updateOrderStatus(OrderStatus.pickedUp);
                  showInfoSnack(context, 'Order picked up successfully!');
                  Navigator.of(context).pushNamed(AppRoutes.orderStatus);
                },
                child: const Text('Mark Picked Up'),
              ),
            if (order.orderStatus == OrderStatus.pickedUp)
              ElevatedButton(
                onPressed: () {
                  app.updateOrderStatus(OrderStatus.outForDelivery);
                  showInfoSnack(context, 'Order out for delivery!');
                  Navigator.of(context).pushNamed(AppRoutes.orderStatus);
                },
                child: const Text('Start Delivery'),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pushNamed(AppRoutes.orderTracking);
              },
              icon: const Icon(Icons.track_changes_rounded),
              label: const Text('Track Order'),
            ),
          ],
        ),
      ),
    );
  }

  void _markReachedPickup(BuildContext context, DeliveryOrder order) {
    final app = AppScope.of(context);
    final error = app.reachedPickup(order.orderId);
    if (error != null) {
      showInfoSnack(context, error);
      return;
    }
    showInfoSnack(context, 'Store notified: You have arrived for pickup!');
    app.updateOrderStatus(OrderStatus.reachedPickup);
    Navigator.of(context).pushNamed(AppRoutes.orderStatus);
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
