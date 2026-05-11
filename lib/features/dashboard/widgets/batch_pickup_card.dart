import 'package:flutter/material.dart';

import 'dashboard_colors.dart';
import 'section_card.dart';

class BatchPickupCard extends StatelessWidget {
  const BatchPickupCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.heading,
    required this.selectOrdersLabel,
    required this.viewTripsLabel,
    required this.onSelectOrders,
    required this.onViewTrips,
  });

  final String title;
  final String subtitle;
  final String heading;
  final String selectOrdersLabel;
  final String viewTripsLabel;
  final VoidCallback onSelectOrders;
  final VoidCallback onViewTrips;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            heading,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: DashColors.textPrimary(context),
            ),
          ),
        ),
        SectionCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF2D6CDF), Color(0xFF1F4FB6)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Image.asset(
                      'assets/images/multi_order_boxes.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: DashColors.textPrimary(context),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: DashColors.textSecondary(context),
                            fontSize: 12,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _BatchActionButton(
                      label: selectOrdersLabel,
                      icon: Icons.list_alt_rounded,
                      filled: true,
                      onTap: onSelectOrders,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _BatchActionButton(
                      label: viewTripsLabel,
                      icon: Icons.alt_route_rounded,
                      filled: false,
                      onTap: onViewTrips,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BatchActionButton extends StatelessWidget {
  const _BatchActionButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = const Color(0xFF1F4FB6);
    return Material(
      color: filled ? primary : DashColors.cardBg(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: primary, width: filled ? 0 : 1.4),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 18,
                color: filled ? Colors.white : primary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: filled ? Colors.white : primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
