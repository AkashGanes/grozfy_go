import 'package:flutter/material.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/widgets/app_shell.dart';
import '../orders_by_location/repository/external_delivery_repository.dart';
import '../orders_by_location/ui/delivery_proof_sheet.dart';

class OrderStatusScreen extends StatefulWidget {
  const OrderStatusScreen({super.key});

  @override
  State<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

class _OrderStatusScreenState extends State<OrderStatusScreen> {
  bool _syncing = false;

  static const List<OrderProgressStatus> _flow = <OrderProgressStatus>[
    OrderStatus.accepted,
    OrderStatus.reachedPickup,
    OrderStatus.pickedUp,
    OrderStatus.outForDelivery,
    OrderStatus.delivered,
  ];

  Future<void> _advanceStatus(BuildContext context) async {
    final app = AppScope.of(context);
    final order = app.activeOrder;
    if (order == null || _syncing) return;
    final messenger = ScaffoldMessenger.of(context);
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

    app.updateOrderStatus(next);

    if (!mounted) return;
    setState(() => _syncing = false);

    if (next == OrderStatus.delivered) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Order delivered and earnings updated')),
      );
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
    }
  }

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

    final int currentIndex = _flow.indexOf(order.orderStatus);

    return AppShell(
      title: 'Order Progress',
      subtitle: 'Real-time status sync with customer app',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
}
