import 'package:flutter/material.dart';

import '../../core/navigation/app_routes.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/app_scope.dart';
import '../../core/widgets/app_shell.dart';

class OrderListingScreen extends StatefulWidget {
  const OrderListingScreen({super.key});

  @override
  State<OrderListingScreen> createState() => _OrderListingScreenState();
}

class _OrderListingScreenState extends State<OrderListingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = AppScope.of(context);
      app.fetchAvailableOrders();
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    return AppShell(
      title: 'Available Orders',
      subtitle: 'Browse nearby orders before accepting',
      scrollable: false,
      child: _buildOrderList(app),
    );
  }

  Widget _buildOrderList(AppController app) {
    if (app.isLoadingOrders) {
      return const Center(child: CircularProgressIndicator());
    }

    if (app.orderLoadingError != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(app.orderLoadingError!),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => app.fetchAvailableOrders(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (app.availableOrders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.local_shipping_outlined,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 12),
            const Text('No available orders'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => app.fetchAvailableOrders(),
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: app.availableOrders.length,
      itemBuilder: (context, index) {
        final order = app.availableOrders[index];
        return FrostCard(
          child: Container(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      order.orderId,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        order.assignmentStatus.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.orange.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _infoRow(Icons.store, 'Store: ${order.storeName}'),
                _infoRow(Icons.person, 'Customer: ${order.customerName}'),
                _infoRow(Icons.location_on, 'Drop: ${order.deliveryAddress}'),
                _infoRow(Icons.route, 'Distance: ${order.distanceKm} km'),
                _infoRow(
                  Icons.currency_rupee,
                  'Earnings: Rs. ${order.estimatedEarnings.toStringAsFixed(0)}',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Items:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                ...order.orderItems.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(left: 8, top: 4),
                    child: Text(
                      '${item.name} x${item.quantity} - Rs. ${(item.price * item.quantity).toStringAsFixed(0)}',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(
                        context,
                      ).pushNamed(AppRoutes.orderDetails, arguments: order);
                    },
                    child: const Text('View Details'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
