import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dashboard_colors.dart';
import 'section_card.dart';
import 'status_pill.dart';

class ActiveOrderMeta {
  const ActiveOrderMeta({
    this.date,
    this.time,
    this.phone,
    this.email,
  });

  final String? date;
  final String? time;
  final String? phone;
  final String? email;

  bool get isEmpty =>
      (date == null || date!.isEmpty) &&
      (time == null || time!.isEmpty) &&
      (phone == null || phone!.isEmpty) &&
      (email == null || email!.isEmpty);
}

class ActiveOrderAction {
  const ActiveOrderAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class ActiveOrderCard extends StatelessWidget {
  const ActiveOrderCard({
    super.key,
    required this.heading,
    required this.statusLabel,
    required this.orderId,
    required this.meta,
    required this.actions,
    required this.onAddOrder,
    this.customerName,
    this.customerPhone,
    this.address,
    this.trackOrderAction,
    this.primaryActionLabel,
    this.onPrimaryAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.showHeading = true,
  });

  final String heading;
  final String statusLabel;
  final String orderId;
  final ActiveOrderMeta meta;
  final List<ActiveOrderAction> actions;
  final VoidCallback onAddOrder;
  final String? customerName;
  final String? customerPhone;
  final String? address;
  final ActiveOrderAction? trackOrderAction;
  final String? primaryActionLabel;
  final VoidCallback? onPrimaryAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeading)
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10, right: 4),
            child: Row(
              children: [
                Text(
                  heading,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: DashColors.textPrimary(context),
                  ),
                ),
                const SizedBox(width: 8),
                StatusPill(
                  label: statusLabel,
                  tone: StatusPillTone.success,
                  dense: true,
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onAddOrder,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F4FB6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_rounded, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Add Another Order',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        SectionCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1AB36A),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              orderId,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: DashColors.textPrimary(context),
                              ),
                            ),
                          ),
                          if (address != null && address!.isNotEmpty)
                            GestureDetector(
                              onTap: () => _showAddressPopup(context, address!),
                              child: Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: Text(
                                  '📍',
                                  style: const TextStyle(fontSize: 20),
                                ),
                              ),
                            ),
                          if (customerPhone != null && customerPhone!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: GestureDetector(
                                onTap: () => _callCustomer(customerPhone!),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1AB36A).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.phone_rounded,
                                    size: 18,
                                    color: Color(0xFF1AB36A),
                                  ),
                                ),
                              ),
                            ),
                          if (trackOrderAction != null)
                            SizedBox(
                              width: 32,
                              height: 32,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: trackOrderAction!.onTap,
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      trackOrderAction!.icon,
                                      size: 18,
                                      color: const Color(0xFF1F4FB6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (customerName != null && customerName!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Icon(
                              Icons.person_rounded,
                              size: 16,
                              color: const Color(0xFF1AB36A),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                customerName!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: DashColors.textSecondary(context),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 14),
                      _ActionGrid(actions: actions),
                      if (primaryActionLabel != null &&
                          onPrimaryAction != null) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 50,
                                child: ElevatedButton.icon(
                                  onPressed: onPrimaryAction,
                                  icon: const Icon(
                                    Icons.check_circle_outline_rounded,
                                    size: 20,
                                  ),
                                  label: Text(
                                    primaryActionLabel!,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1F4FB6),
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            if (secondaryActionLabel != null &&
                                onSecondaryAction != null) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: SizedBox(
                                  height: 50,
                                  child: ElevatedButton.icon(
                                    onPressed: onSecondaryAction,
                                    icon: const Icon(
                                      Icons.cancel_outlined,
                                      size: 20,
                                    ),
                                    label: Text(
                                      secondaryActionLabel!,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFD32F2F),
                                      foregroundColor: Colors.white,
                                      elevation: 0,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({required this.actions});
  final List<ActiveOrderAction> actions;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        for (int i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _ActionTile(action: actions[i])),
        ],
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action});
  final ActiveOrderAction action;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DashColors.cardBg(context),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 16, color: const Color(0xFF1F4FB6)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  action.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1F4FB6),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showAddressPopup(BuildContext context, String address) {
  showDialog(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Row(
          children: [
            const Icon(
              Icons.location_on_rounded,
              size: 24,
              color: Color(0xFF1AB36A),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Delivery Address',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        content: Text(
          address,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

Future<void> _callCustomer(String phoneNumber) async {
  final Uri telUri = Uri(scheme: 'tel', path: phoneNumber);
  if (await canLaunchUrl(telUri)) {
    await launchUrl(telUri);
  }
}

