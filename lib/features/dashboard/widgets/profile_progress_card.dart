import 'package:flutter/material.dart';

import '../../../core/models/app_models.dart';
import 'status_pill.dart';

class ProfileProgressCard extends StatelessWidget {
  const ProfileProgressCard({
    super.key,
    required this.completeness,
    required this.progressTitle,
    required this.subtitleBuilder,
    required this.progressLabel,
    required this.tapToCompleteLabel,
    required this.pendingLabel,
    required this.verifiedLabel,
    required this.itemLabel,
    required this.onTapComplete,
    required this.onItemTap,
  });

  final ProfileCompleteness completeness;
  final String progressTitle;
  final String Function(int completed, int total) subtitleBuilder;
  final String Function(int completed, int total) progressLabel;
  final String tapToCompleteLabel;
  final String pendingLabel;
  final String verifiedLabel;
  final String Function(ProfileCompletenessItem item) itemLabel;
  final VoidCallback onTapComplete;
  final void Function(ProfileCompletenessItem item) onItemTap;

  @override
  Widget build(BuildContext context) {
    final pct = (completeness.percentage.clamp(0.0, 1.0) * 100).round();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1A3FA6).withValues(alpha: 0.28),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Stack(
          children: [
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF2563EB), Color(0xFF1E40AF)],
                  ),
                ),
              ),
            ),
            Positioned(
              right: -50,
              top: -40,
              child: _decorCircle(160, 0.10),
            ),
            Positioned(
              right: 80,
              bottom: -60,
              child: _decorCircle(120, 0.08),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _CircularPercent(percent: pct),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              progressTitle,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 19,
                                height: 1.15,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitleBuilder(
                                completeness.completedCount,
                                completeness.totalCount,
                              ),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.92),
                                fontSize: 13,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: completeness.percentage,
                      minHeight: 8,
                      backgroundColor: Colors.white.withValues(alpha: 0.22),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF1AB36A),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        progressLabel(
                          completeness.completedCount,
                          completeness.totalCount,
                        ),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      _CompleteButton(
                        label: tapToCompleteLabel,
                        onTap: onTapComplete,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ItemsStrip(
                    items: completeness.items,
                    pendingLabel: pendingLabel,
                    verifiedLabel: verifiedLabel,
                    itemLabel: itemLabel,
                    onItemTap: onItemTap,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _decorCircle(double size, double alpha) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: alpha),
      ),
    );
  }
}

class _CircularPercent extends StatelessWidget {
  const _CircularPercent({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 88,
            height: 88,
            child: CircularProgressIndicator(
              value: percent / 100,
              strokeWidth: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.22),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF1AB36A)),
            ),
          ),
          Text(
            '$percent%',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompleteButton extends StatelessWidget {
  const _CompleteButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF1F4FB6),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Color(0xFF1F4FB6),
                size: 16,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ItemsStrip extends StatelessWidget {
  const _ItemsStrip({
    required this.items,
    required this.pendingLabel,
    required this.verifiedLabel,
    required this.itemLabel,
    required this.onItemTap,
  });

  final List<ProfileCompletenessItem> items;
  final String pendingLabel;
  final String verifiedLabel;
  final String Function(ProfileCompletenessItem) itemLabel;
  final void Function(ProfileCompletenessItem) onItemTap;

  IconData _iconFor(String name) {
    switch (name) {
      case 'profile_basic_profile':
        return Icons.person_outline_rounded;
      case 'profile_photo':
        return Icons.photo_camera_outlined;
      case 'kyc_documents':
        return Icons.shield_outlined;
      case 'vehicle_details':
        return Icons.two_wheeler_rounded;
      case 'bank_account':
        return Icons.account_balance_outlined;
      case 'delivery_zone':
        return Icons.location_on_outlined;
      case 'permissions':
        return Icons.lock_outline_rounded;
      default:
        return Icons.check_circle_outline_rounded;
    }
  }

  Color _iconColorFor(String name) {
    switch (name) {
      case 'profile_photo':
        return const Color(0xFF2D6CDF);
      case 'vehicle_details':
        return const Color(0xFF1AB36A);
      case 'bank_account':
        return const Color(0xFF2D6CDF);
      case 'kyc_documents':
        return const Color(0xFF7C3AED);
      default:
        return const Color(0xFF2D6CDF);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shown = items.take(4).toList();
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (int i = 0; i < shown.length; i++) ...[
            Expanded(
              child: _ItemChip(
                icon: _iconFor(shown[i].name),
                iconColor: _iconColorFor(shown[i].name),
                label: itemLabel(shown[i]),
                completed: shown[i].isCompleted,
                pendingLabel: pendingLabel,
                verifiedLabel: verifiedLabel,
                onTap: () => onItemTap(shown[i]),
              ),
            ),
            if (i != shown.length - 1) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _ItemChip extends StatelessWidget {
  const _ItemChip({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.completed,
    required this.pendingLabel,
    required this.verifiedLabel,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final bool completed;
  final String pendingLabel;
  final String verifiedLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101828),
                ),
              ),
              const SizedBox(height: 6),
              StatusPill(
                label: completed ? verifiedLabel : pendingLabel,
                tone: completed
                    ? StatusPillTone.success
                    : StatusPillTone.warning,
                icon: completed
                    ? Icons.check_circle_rounded
                    : Icons.access_time_rounded,
                dense: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
