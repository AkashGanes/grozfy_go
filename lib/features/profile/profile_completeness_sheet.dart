import 'package:flutter/material.dart';

import '../../core/models/app_models.dart';
import '../../core/state/app_scope.dart';

bool _isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
Color _sheetBg(BuildContext c) =>
    _isDark(c) ? const Color(0xFF12141C) : const Color(0xFFF7F8FA);
Color _cardBg(BuildContext c) =>
    _isDark(c) ? const Color(0xFF1B1E2A) : Colors.white;
Color _cardBorder(BuildContext c) =>
    _isDark(c) ? const Color(0xFF2A2F3D) : const Color(0xFFEFF1F4);
Color _textPrimary(BuildContext c) =>
    _isDark(c) ? const Color(0xFFF2F4F7) : const Color(0xFF101828);
Color _textSecondary(BuildContext c) =>
    _isDark(c) ? const Color(0xFFA4ABB8) : const Color(0xFF667085);
Color _textTertiary(BuildContext c) =>
    _isDark(c) ? const Color(0xFF98A2B3) : const Color(0xFF475467);
Color _grabber(BuildContext c) =>
    _isDark(c) ? const Color(0xFF3D4255) : const Color(0xFFD0D5DD);
Color _progressTrack(BuildContext c) =>
    _isDark(c) ? const Color(0xFF2A2F3D) : const Color(0xFFE9EDF1);
Color _bannerBg(BuildContext c) =>
    _isDark(c) ? const Color(0xFF14352A) : const Color(0xFFE7F7EE);
Color _supportBg(BuildContext c) =>
    _isDark(c) ? const Color(0xFF1B2A3F) : const Color(0xFFEAF1FB);
Color _iconChipBg(BuildContext c) =>
    _isDark(c) ? const Color(0xFF252A38) : Colors.white;

void showProfileCompletenessSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => const _ProfileCompletenessSheet(),
  );
}

class _ProfileCompletenessSheet extends StatelessWidget {
  const _ProfileCompletenessSheet();

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final completeness = app.profileCompleteness;
    final pct = (completeness.percentage.clamp(0.0, 1.0) * 100).round();
    final remaining = completeness.totalCount - completeness.completedCount;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: _sheetBg(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _grabber(context),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    _ProgressCard(
                      percent: pct,
                      completedCount: completeness.completedCount,
                      totalCount: completeness.totalCount,
                      remaining: remaining,
                      progress: completeness.percentage,
                    ),
                    const SizedBox(height: 14),
                    if (remaining > 0) const _UnlockBanner(),
                    if (remaining > 0) const SizedBox(height: 14),
                    ...List.generate(completeness.items.length, (i) {
                      final item = completeness.items[i];
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: i == completeness.items.length - 1 ? 0 : 10,
                        ),
                        child: _CompletenessItemRow(
                          item: item,
                          title: app.t(item.name),
                          description: app.t(item.description),
                          completeLabel: app.t('complete'),
                          onTap: item.route == null
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                  Navigator.of(context).pushNamed(item.route!);
                                },
                        ),
                      );
                    }),
                    const SizedBox(height: 14),
                    _SupportCard(onTap: () {}),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.percent,
    required this.completedCount,
    required this.totalCount,
    required this.remaining,
    required this.progress,
  });

  final int percent;
  final int completedCount;
  final int totalCount;
  final int remaining;
  final double progress;

  static const _accent = Color(0xFF1AB36A);

  @override
  Widget build(BuildContext context) {
    final isDark = _isDark(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg(context),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 72,
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 6,
                    backgroundColor: _progressTrack(context),
                    valueColor: const AlwaysStoppedAnimation<Color>(_accent),
                  ),
                ),
                Text(
                  '$percent%',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Complete Your Profile',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  remaining == 0
                      ? "You're all set — let's start delivering!"
                      : '$completedCount of $totalCount steps completed',
                  style: TextStyle(
                    fontSize: 13,
                    color: _textSecondary(context),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnlockBanner extends StatelessWidget {
  const _UnlockBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bannerBg(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _iconChipBg(context),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.card_giftcard_rounded,
              color: Color(0xFF118A52),
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Complete your profile to unlock all features',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Finish remaining steps to start accepting orders.',
                  style: TextStyle(fontSize: 12, color: _textTertiary(context)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CompletenessItemRow extends StatelessWidget {
  const _CompletenessItemRow({
    required this.item,
    required this.title,
    required this.description,
    required this.completeLabel,
    required this.onTap,
  });

  final ProfileCompletenessItem item;
  final String title;
  final String description;
  final String completeLabel;
  final VoidCallback? onTap;

  static const _doneColor = Color(0xFF1AB36A);
  static const _pendingColor = Color(0xFFF38B19);

  IconData _iconFor(String name) {
    switch (name) {
      case 'profile_basic_profile':
        return Icons.person_outline_rounded;
      case 'profile_photo':
        return Icons.photo_camera_outlined;
      case 'kyc_documents':
        return Icons.badge_outlined;
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

  @override
  Widget build(BuildContext context) {
    final completed = item.isCompleted;
    final tone = completed ? _doneColor : _pendingColor;

    final cardBg = _cardBg(context);
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _cardBorder(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_iconFor(item.name), color: tone, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        color: _textSecondary(context),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (completed)
                Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: _doneColor,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                )
              else
                _CompleteButton(label: completeLabel, onTap: onTap),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompleteButton extends StatelessWidget {
  const _CompleteButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  static const _color = Color(0xFFF38B19);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _cardBg(context),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _color, width: 1.4),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: _color,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                color: _color,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SupportCard extends StatelessWidget {
  const _SupportCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _supportBg(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _iconChipBg(context),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.headset_mic_outlined,
              color: Color(0xFF1F4FB6),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Need help?',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "We're here to help you 24/7",
                  style: TextStyle(fontSize: 12, color: _textTertiary(context)),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onTap,
            child: const Row(
              children: [
                Text(
                  'Contact Support',
                  style: TextStyle(
                    color: Color(0xFF1F4FB6),
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF1F4FB6),
                  size: 18,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
