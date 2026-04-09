import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
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
  int _selectedTab = 0;
  bool _hasFetchedOrders = false;

  @override
  void initState() {
    super.initState();
  }

  void _fetchOrders(AppController app) {
    if (!_hasFetchedOrders) {
      _hasFetchedOrders = true;
      debugPrint('[OrderListing] Fetching orders...');
      app.fetchAvailableOrders();
    }
  }

  void _centerOnOrder(DeliveryOrder order) {
    _mapController.move(LatLng(order.latitude, order.longitude), 15.0);
  }

  void _acceptOrder(DeliveryOrder order) {
    final app = AppScope.of(context);
    final error = app.acceptOrder(order.orderId);
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
    _fetchOrders(app);

    return AppShell(
      title: 'Orders',
      subtitle: 'Manage your deliveries',
      actions: [
        IconButton(
          icon: Icon(_showMap ? Icons.list : Icons.map),
          onPressed: () => setState(() => _showMap = !_showMap),
        ),
      ],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(child: _buildTab('Available', 0)),
                const SizedBox(width: 12),
                Expanded(child: _buildTab('Active', 1)),
                const SizedBox(width: 12),
                Expanded(child: _buildTab('Completed', 2)),
                if (_selectedTab == 0)
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: () => app.fetchAvailableOrders(),
                  ),
              ],
            ),
          ),
          if (_showMap && _selectedTab == 0)
            SizedBox(
              height: 180,
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
                              'com.example.delivery_partner_app',
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
          Expanded(child: _buildOrderList(app)),
          if (_selectedOrder != null) _buildOrderActions(_selectedOrder!),
        ],
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isSelected = _selectedTab == index;
    return GestureDetector(
      onTap: () => setState(() {
        _selectedTab = index;
        _selectedOrder = null;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? AppColors.onPrimary : AppColors.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildOrderList(AppController app) {
    debugPrint(
      '[OrderListing] _buildOrderList called, tab: $_selectedTab, available: ${app.availableOrders.length}, active: ${app.activeOrder != null}, accepted: ${app.acceptedOrders.length}',
    );
    List<DeliveryOrder> orders = [];
    String emptyMessage = '';
    IconData emptyIcon = Icons.local_shipping_outlined;

    switch (_selectedTab) {
      case 0:
        orders = app.availableOrders;
        emptyMessage = 'No available orders';
        break;
      case 1:
        if (app.activeOrder != null) {
          orders = [app.activeOrder!];
        }
        emptyMessage = 'No active order';
        emptyIcon = Icons.delivery_dining;
        break;
      case 2:
        orders = app.acceptedOrders
            .where(
              (o) =>
                  o.orderStatus == OrderStatus.delivered ||
                  o.orderStatus == OrderStatus.cancelled,
            )
            .toList();
        emptyMessage = 'No completed orders';
        emptyIcon = Icons.check_circle_outline;
        break;
    }

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

    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(emptyIcon, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            Text(emptyMessage),
            if (_selectedTab == 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ElevatedButton(
                  onPressed: () => app.fetchAvailableOrders(),
                  child: const Text('Refresh'),
                ),
              ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: orders.length,
      itemBuilder: (context, index) {
        final order = orders[index];
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
                      if (_selectedTab == 0) ...[
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
                      ] else ...[
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(
                                context,
                              ).pushNamed(AppRoutes.orderDetails);
                            },
                            child: Text(
                              _selectedTab == 1 ? 'View Details' : 'View',
                            ),
                          ),
                        ),
                      ],
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
