import 'package:flutter/material.dart';

import '../../core/models/app_models.dart';
import '../../core/navigation/app_routes.dart';
import '../../core/state/app_scope.dart';
import '../../core/widgets/app_shell.dart';

class OrderStatusScreen extends StatelessWidget {
  const OrderStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
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

    final List<OrderProgressStatus> flow = <OrderProgressStatus>[
      OrderProgressStatus.accepted,
      OrderProgressStatus.reachedPickup,
      OrderProgressStatus.pickedUp,
      OrderProgressStatus.outForDelivery,
      OrderProgressStatus.delivered,
    ];

    final int currentIndex = flow.indexOf(order.orderStatus);

    return AppShell(
      title: 'Order Progress',
      subtitle: 'Real-time status sync with customer app',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FrostCard(
      child: Column(
              children: flow.asMap().entries.map((entry) {
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
                        color: done ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          app.orderStatusLabel(status),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: done ? Colors.black87 : Colors.black45,
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
          OutlinedButton(
            onPressed: () => Navigator.of(context).pushNamed(AppRoutes.dashboard),
            child: const Text('Back to Dashboard'),
          ),
        ],
      ),
    );
  }
}
