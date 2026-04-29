import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/widgets/app_shell.dart';
import 'widgets/order_timer_widget.dart';

class OrderTrackingScreen extends StatefulWidget {
  const OrderTrackingScreen({super.key});

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  final MapController _mapController = MapController();
  Timer? _refreshTimer;
  bool _isLiveTracking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = AppScope.of(context);
      app.startLiveLocationTracking();
      _startRefreshTimer();
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    final app = AppScope.of(context);
    app.stopLiveLocationTracking();
    super.dispose();
  }

  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && _isLiveTracking) {
        setState(() {});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final order = app.activeOrder;

    if (order == null) {
      return AppShell(
        title: 'Order Tracking',
        subtitle: 'No active order',
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.track_changes, size: 64, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('No order to track'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.of(
                  context,
                ).pushReplacementNamed(AppRoutes.dashboard),
                child: const Text('Back to Dashboard'),
              ),
            ],
          ),
        ),
      );
    }

    final LatLng storeLocation = LatLng(order.latitude, order.longitude);
    final LatLng partnerLocation = app.partnerLiveLocation != null
        ? LatLng(
            app.partnerLiveLocation!.latitude,
            app.partnerLiveLocation!.longitude,
          )
        : (app.currentLatitude != null && app.currentLongitude != null
              ? LatLng(app.currentLatitude!, app.currentLongitude!)
              : storeLocation);

    return AppShell(
      title: 'Track Order ${order.orderId}',
      subtitle: 'Real-time tracking visible to customer & admin',
      actions: [
        if (app.isOrderTimerRunning)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: OrderTimerWidget(),
          ),
        IconButton(
          icon: Icon(_isLiveTracking ? Icons.gps_fixed : Icons.gps_off),
          onPressed: () {
            setState(() => _isLiveTracking = !_isLiveTracking);
            if (_isLiveTracking) {
              _startRefreshTimer();
            } else {
              _refreshTimer?.cancel();
            }
          },
        ),
      ],
      child: Column(
        children: [
          FrostCard(
            padding: EdgeInsets.zero,
            child: SizedBox(
              height: 300,
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: storeLocation,
                  initialZoom: 14.0,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.lyncspace.grozfygo',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: storeLocation,
                        width: 50,
                        height: 50,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.store,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const Text(
                              'Store',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Marker(
                        point: partnerLocation,
                        width: 50,
                        height: 50,
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.green.withValues(alpha: 0.5),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.delivery_dining,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const Text(
                              'You',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: [storeLocation, partnerLocation],
                        color: Colors.orange,
                        strokeWidth: 3,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FrostCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Order Status',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(order.orderStatus),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        order.orderStatus.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                _trackingInfo('Order ID', order.orderId, Icons.tag),
                _trackingInfo('Customer', order.customerName, Icons.person),
                _trackingInfo('Phone', order.customerPhone, Icons.phone),
                _trackingInfo(
                  'Delivery Address',
                  order.deliveryAddress,
                  Icons.home,
                ),
                const Divider(height: 24),
                const Text(
                  'Live Location Updates',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(
                      Icons.my_location,
                      color: Colors.green,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Partner: ${partnerLocation.latitude.toStringAsFixed(5)}, ${partnerLocation.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.store, color: Colors.blue, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Store: ${storeLocation.latitude.toStringAsFixed(5)}, ${storeLocation.longitude.toStringAsFixed(5)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                if (order.reachedStoreAt != null) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(
                        Icons.access_time,
                        color: Colors.orange,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Reached store at: ${_formatTime(order.reachedStoreAt!)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade100),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: Colors.blue),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'This tracking info is visible to customer and Grozfy Admin in real-time',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _buildStatusProgress(order.orderStatus),
        ],
      ),
    );
  }

  Widget _trackingInfo(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
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

  Widget _buildStatusProgress(OrderStatus status) {
    final List<OrderStatus> flow = <OrderStatus>[
      OrderStatus.accepted,
      OrderStatus.reachedPickup,
      OrderStatus.pickedUp,
      OrderStatus.outForDelivery,
      OrderStatus.delivered,
    ];

    final int currentIndex = flow.indexOf(status);

    return FrostCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Delivery Progress',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: flow.asMap().entries.map((entry) {
              final int index = entry.key;
              final OrderStatus stepStatus = entry.value;
              final bool isActive = index <= currentIndex;
              final bool isCurrent = index == currentIndex;

              return Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isActive ? Colors.green : Colors.grey.shade300,
                        shape: BoxShape.circle,
                        border: isCurrent
                            ? Border.all(color: Colors.green, width: 3)
                            : null,
                      ),
                      child: Icon(
                        isActive ? Icons.check : Icons.circle,
                        color: isActive ? Colors.white : Colors.grey,
                        size: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _getShortStatus(stepStatus),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isActive ? Colors.black87 : Colors.grey,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _getShortStatus(OrderStatus status) {
    switch (status) {
      case OrderStatus.accepted:
        return 'Accepted';
      case OrderStatus.reachedPickup:
        return 'Reached';
      case OrderStatus.pickedUp:
        return 'Picked';
      case OrderStatus.outForDelivery:
        return 'Out';
      case OrderStatus.delivered:
        return 'Delivered';
      default:
        return status.name;
    }
  }

  Color _getStatusColor(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return Colors.grey;
      case OrderStatus.accepted:
        return Colors.blue;
      case OrderStatus.reachedPickup:
        return Colors.orange;
      case OrderStatus.pickedUp:
        return Colors.purple;
      case OrderStatus.outForDelivery:
        return Colors.teal;
      case OrderStatus.delivered:
        return Colors.green;
      case OrderStatus.rejected:
      case OrderStatus.cancelled:
        return Colors.red;
    }
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}
