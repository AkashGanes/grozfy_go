import 'package:flutter/material.dart';

import '../../../core/theme/context_colors.dart';
import 'dashboard_colors.dart';
import 'section_card.dart';

class AvailableDeliveriesCard extends StatelessWidget {
  const AvailableDeliveriesCard({
    super.key,
    required this.heading,
    required this.viewAllLabel,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onViewAll,
    required this.onAction,
  });

  final String heading;
  final String viewAllLabel;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onViewAll;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10, right: 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  heading,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: DashColors.textPrimary(context),
                  ),
                ),
              ),
              GestureDetector(
                onTap: onViewAll,
                child: Row(
                  children: [
                    Text(
                      viewAllLabel,
                      style: TextStyle(
                        color: context.scheme.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: context.scheme.primary,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFF1AB36A).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.local_shipping_rounded,
                  color: Color(0xFF1AB36A),
                  size: 28,
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
              const SizedBox(width: 8),
              Material(
                color: const Color(0xFF1AB36A).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onAction,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Text(
                      actionLabel,
                      style: TextStyle(
                        color: context.success,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
