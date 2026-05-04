import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/widgets/app_shell.dart';

class OrderRequestScreen extends StatefulWidget {
  const OrderRequestScreen({super.key});

  @override
  State<OrderRequestScreen> createState() => _OrderRequestScreenState();
}

class _OrderRequestScreenState extends State<OrderRequestScreen> {
  DeliveryOrder? _order;
  Timer? _timer;
  int _secondsLeft = 28;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = AppScope.of(context);
      _order = app.incomingOrder ?? app.generateIncomingOrder();
      _startCountdown();
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (Timer timer) {
      if (_secondsLeft <= 1) {
        timer.cancel();
        _resolveOrder(accept: false, timeout: true);
        return;
      }
      if (mounted) {
        setState(() => _secondsLeft--);
      }
    });
  }

  void _resolveOrder({required bool accept, bool timeout = false}) {
    final app = AppScope.of(context);
    _timer?.cancel();
    app.respondToOrderRequest(accept: accept);

    if (accept) {
      Navigator.of(context).pushReplacementNamed(AppRoutes.orderDetails);
      return;
    }

    showInfoSnack(
      context,
      timeout ? 'Order auto-rejected due to timeout' : 'Order rejected',
    );
    Navigator.of(context).pushReplacementNamed(AppRoutes.dashboard);
  }

  String _taskSummary(DeliveryOrder order) {
    final List<String> parts = <String>[
      if (order.storeName.trim().isNotEmpty) 'Store: ${order.storeName.trim()}',
      if (order.customerName.trim().isNotEmpty)
        'Customer: ${order.customerName.trim()}',
      if (order.deliveryAddress.trim().isNotEmpty)
        'Address: ${order.deliveryAddress.trim()}',
    ];
    return parts.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    if (_order == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return AppShell(
      title: 'Incoming Order Request',
      subtitle: 'Accept quickly to keep a healthy acceptance rate',
      child: FrostCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timer_outlined),
                const SizedBox(width: 8),
                Text(
                  '$_secondsLeft seconds remaining',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _detailRow('Task Summary', _taskSummary(_order!)),
            _detailRow(
              'Distance',
              '${_order!.distanceKm.toStringAsFixed(1)} km',
            ),
            _detailRow(
              'Estimated earnings',
              'Rs. ${_order!.estimatedEarnings.toStringAsFixed(0)}',
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _resolveOrder(accept: false),
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _resolveOrder(accept: true),
                    child: const Text('Accept'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: const TextStyle(color: Colors.black54)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w700, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
