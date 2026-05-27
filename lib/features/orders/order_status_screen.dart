import 'package:flutter/material.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/app_toast.dart';
import '../orders_by_location/repository/external_delivery_repository.dart';
import '../orders_by_location/ui/delivery_proof_sheet.dart';
import 'widgets/order_timer_widget.dart';

class OrderStatusScreen extends StatefulWidget {
  const OrderStatusScreen({super.key});

  @override
  State<OrderStatusScreen> createState() => _OrderStatusScreenState();
}

class _OrderStatusScreenState extends State<OrderStatusScreen> {
  bool _syncing = false;

  static const _flow = <OrderProgressStatus>[
    OrderStatus.accepted,
    OrderStatus.reachedPickup,
    OrderStatus.pickedUp,
    OrderStatus.outForDelivery,
    OrderStatus.delivered,
  ];

  static const _stepMeta = [
    (label: 'Accepted', icon: Icons.task_alt_rounded),
    (label: 'At Store', icon: Icons.store_rounded),
    (label: 'Picked', icon: Icons.inventory_2_rounded),
    (label: 'En Route', icon: Icons.delivery_dining_rounded),
    (label: 'Delivered', icon: Icons.home_rounded),
  ];

  OrderProgressStatus _nextStatus(OrderProgressStatus s) {
    if (s == OrderStatus.accepted) return OrderStatus.reachedPickup;
    if (s == OrderStatus.reachedPickup) return OrderStatus.pickedUp;
    if (s == OrderStatus.pickedUp) return OrderStatus.outForDelivery;
    if (s == OrderStatus.outForDelivery) return OrderStatus.delivered;
    return s;
  }

  String _actionLabel(OrderProgressStatus s) {
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

    final currentIndex = _flow.indexOf(order.orderStatus);
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
                  ? _DeliveredBadge(status: order.orderStatus)
                  : SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _syncing
                            ? null
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
  const _DeliveredBadge({required this.status});
  final OrderProgressStatus status;

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
