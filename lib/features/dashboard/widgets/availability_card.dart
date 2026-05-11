import 'package:flutter/material.dart';

import 'dashboard_colors.dart';
import 'section_card.dart';
import 'status_pill.dart';

class AvailabilityCard extends StatelessWidget {
  const AvailabilityCard({
    super.key,
    required this.title,
    required this.isOnline,
    required this.onlineLabel,
    required this.offlineLabel,
    required this.onlineDescription,
    required this.offlineDescription,
    required this.onChanged,
    this.syncing = false,
  });

  final String title;
  final bool isOnline;
  final String onlineLabel;
  final String offlineLabel;
  final String onlineDescription;
  final String offlineDescription;
  final ValueChanged<bool>? onChanged;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 16, 16),
      child: SizedBox(
        height: 110,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              right: -8,
              top: -8,
              bottom: -8,
              width: 200,
              child: Image.asset(
                'assets/images/scooter_delivery.png',
                fit: BoxFit.contain,
                alignment: Alignment.centerRight,
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: DashColors.textPrimary(context),
                      ),
                    ),
                    const SizedBox(width: 10),
                    StatusPill(
                      label: isOnline ? onlineLabel : offlineLabel,
                      tone: isOnline
                          ? StatusPillTone.success
                          : StatusPillTone.neutral,
                      icon: Icons.circle,
                      dense: true,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: 200,
                  child: Text(
                    isOnline ? onlineDescription : offlineDescription,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: DashColors.textSecondary(context),
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              top: 0,
              right: 0,
              child: syncing
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : Switch(
                      value: isOnline,
                      onChanged: onChanged,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
