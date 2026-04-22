import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/models/app_models.dart';
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
  final MapController _mapController = MapController();
  DeliveryOrder? _selectedOrder;
  bool _showMap = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = AppScope.of(context);
      app.fetchAvailableOrders();
    });
  }

  void _centerOnOrder(DeliveryOrder order) {
    _mapController.move(LatLng(order.latitude, order.longitude), 15.0);
  }

  Future<void> _acceptOrder(DeliveryOrder order) async {
    final app = AppScope.of(context);
    final String? error = await app.acceptOrder(order.orderId);
    if (!mounted) return;
    if (error != null) {
      showInfoSnack(context, error);
      return;
    }
    showInfoSnack(context, 'Order accepted successfully!');
    Navigator.of(context).pushNamed(AppRoutes.orderDetails);
  }

  void _rejectOrder(DeliveryOrder order) {
    final app = AppScope.of(context);
    app.rejectOrder(order.orderId);
    showInfoSnack(context, 'Order rejected');
    if (_selectedOrder?.orderId == order.orderId) {
      setState(() => _selectedOrder = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);

    return AppShell(
      title: 'Available Orders',
      subtitle: 'Accept orders to start delivering',
      actions: [
        IconButton(
          icon: Icon(_showMap ? Icons.list : Icons.map),
          onPressed: () => setState(() => _showMap = !_showMap),
        ),
      ],
      child: Column(
        children: [
          if (_showMap)
            SizedBox(
              height: 200,
              child: FrostCard(
                child: Padding(
                  padding: EdgeInsets.zero,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: const LatLng(28.6139, 77.2090),
                        initialZoom: 12.0,
                        onTap: (_, __) {},
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName:
                              'com.lyncspace.grozfygo',
                        ),
                        MarkerLayer(
                          markers: app.availableOrders.map((order) {
                            return Marker(
                              point: LatLng(order.latitude, order.longitude),
                              width: 40,
                              height: 40,
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _selectedOrder = order),
                                child: Icon(
                                  Icons.location_on,
                                  color:
                                      _selectedOrder?.orderId == order.orderId
                                      ? Colors.green
                                      : Colors.blue,
                                  size: 36,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Expanded(child: _buildOrderList(app)),
          if (_selectedOrder != null) _buildOrderActions(_selectedOrder!),
        ],
      ),
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
        final isSelected = _selectedOrder?.orderId == order.orderId;
        return FrostCard(
          child: InkWell(
            onTap: () {
              setState(() => _selectedOrder = order);
              if (_showMap) {
                _centerOnOrder(order);
              }
            },
            child: Container(
              decoration: isSelected
                  ? BoxDecoration(
                      border: Border.all(color: Colors.green, width: 2),
                      borderRadius: BorderRadius.circular(22),
                    )
                  : null,
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
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _rejectOrder(order),
                          child: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _acceptOrder(order),
                          child: const Text('Accept'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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

  Widget _buildOrderActions(DeliveryOrder order) {
    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Selected Order Details',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _detailRow('Order ID', order.orderId),
          _detailRow('Customer', order.customerName),
          _detailRow('Phone', order.customerPhone),
          _detailRow('Store', order.storeName),
          _detailRow('Address', order.deliveryAddress),
          _detailRow('Total', 'Rs. ${order.totalAmount.toStringAsFixed(0)}'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _rejectOrder(order),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _acceptOrder(order),
                  child: const Text('Accept Order'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
