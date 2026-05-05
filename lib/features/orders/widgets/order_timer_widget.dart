import 'dart:async';
import 'package:flutter/material.dart';

import '../../../core/state/app_scope.dart';

class OrderTimerWidget extends StatefulWidget {
  const OrderTimerWidget({super.key});

  @override
  State<OrderTimerWidget> createState() => _OrderTimerWidgetState();
}

class _OrderTimerWidgetState extends State<OrderTimerWidget> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    
    if (!app.isOrderTimerRunning) {
      return const SizedBox.shrink();
    }

    final elapsed = app.orderElapsedTime;
    final totalSeconds = app.orderTotalSeconds;
    final hours = totalSeconds ~/ 3600;

    Color timerColor = Colors.green;
    if (hours > 1) {
      timerColor = Colors.orange;
    }
    if (hours > 2) {
      timerColor = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: timerColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: timerColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_rounded,
            color: timerColor,
            size: 22,
          ),
          const SizedBox(width: 8),
          Text(
            elapsed,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: timerColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}