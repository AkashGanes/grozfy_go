import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/app_models.dart';
import '../state/app_scope.dart';
import '../theme/app_theme.dart';

class ProfileCompletenessIndicator extends StatelessWidget {
  const ProfileCompletenessIndicator({
    super.key,
    required this.completeness,
    this.onItemTap,
    this.compact = false,
  });

  final ProfileCompleteness completeness;
  final void Function(ProfileCompletenessItem)? onItemTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompact(context);
    }
    return _buildFull(context);
  }

  Widget _buildCompact(BuildContext context) {
    final app = AppScope.of(context);
    final percentage = (completeness.percentage * 100).round();
    final color = _getProgressColor(completeness.percentage);
    final remaining = completeness.totalCount - completeness.completedCount;
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => _showDetailsBottomSheet(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '$percentage%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  remaining == 0
                      ? app.t('profile_complete')
                      : app.t('steps_left').replaceAll('{count}', '$remaining'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                SizedBox(
                  width: 100,
                  height: 4,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: completeness.percentage,
                      backgroundColor: color.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: scheme.onSurface.withValues(alpha: 0.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFull(BuildContext context) {
    final app = AppScope.of(context);
    final percentage = (completeness.percentage * 100).round();
    final color = _getProgressColor(completeness.percentage);
    final isComplete = completeness.percentage == 1.0;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => _showDetailsBottomSheet(context),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isComplete
                      ? [
                          const Color(0xFF1AB36A).withValues(alpha: 0.08),
                          const Color(0xFF1AB36A).withValues(alpha: 0.03),
                        ]
                      : [
                          color.withValues(alpha: 0.06),
                          color.withValues(alpha: 0.02),
                        ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: isDark ? scheme.surfaceContainerHighest : Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: color.withValues(alpha: 0.2),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            '$percentage%',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                        ),
                      )
                          .animate()
                          .fadeIn(duration: 400.ms)
                          .scale(begin: const Offset(0.8, 0.8)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isComplete
                                  ? app.t('all_done')
                                  : app.t('profile_progress'),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: scheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              completeness.localizedMessage(app.languageCode),
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          isComplete
                              ? Icons.check_circle_rounded
                              : Icons.arrow_forward_rounded,
                          color: color,
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildProgressBar(color),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        app.t('completed_steps')
                            .replaceAll(
                              '{completed}',
                              '${completeness.completedCount}',
                            )
                            .replaceAll('{total}', '${completeness.totalCount}'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      if (!isComplete)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            app.t('tap_to_complete'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: color,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (!isComplete)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: completeness.items
                      .where((item) => !item.isCompleted)
                      .take(3)
                      .map((item) => Expanded(
                            child: _buildPendingCard(context, item, color),
                          ))
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms)
        .slideY(begin: 0.1, end: 0, duration: 400.ms);
  }

  Widget _buildPendingCard(
    BuildContext context,
    ProfileCompletenessItem item,
    Color color,
  ) {
    final app = AppScope.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(
                _getItemIcon(item.name),
                size: 16,
                color: color,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  app.t('pending'),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            app.t(item.name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar(Color color) {
    return Container(
      height: 10,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Stack(
          children: [
            AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
              widthFactor: completeness.percentage,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [color, color.withValues(alpha: 0.8)],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getProgressColor(double percentage) {
    if (percentage >= 1.0) {
      return const Color(0xFF1AB36A);
    } else if (percentage >= 0.7) {
      return AppTheme.mint;
    } else if (percentage >= 0.4) {
      return AppTheme.mango;
    } else {
      return const Color(0xFFE8384F);
    }
  }

  IconData _getItemIcon(String name) {
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
        return Icons.security_outlined;
      default:
        return Icons.circle_outlined;
    }
  }

  void _showDetailsBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DetailsBottomSheet(
        completeness: completeness,
        onItemTap: (item) {
          Navigator.pop(context);
          if (item.route != null && onItemTap != null) {
            onItemTap!(item);
          }
        },
      ),
    );
  }
}

class _DetailsBottomSheet extends StatelessWidget {
  const _DetailsBottomSheet({
    required this.completeness,
    required this.onItemTap,
  });

  final ProfileCompleteness completeness;
  final void Function(ProfileCompletenessItem) onItemTap;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final percentage = (completeness.percentage * 100).round();
    final color = _getProgressColor(completeness.percentage);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 20),
            decoration: BoxDecoration(
              color: scheme.onSurface.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '$percentage%',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: color,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            app.t('profile_completeness'),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            app.t('completed_steps')
                                .replaceAll(
                                  '{completed}',
                                  '${completeness.completedCount}',
                                )
                                .replaceAll(
                                  '{total}',
                                  '${completeness.totalCount}',
                                ),
                            style: TextStyle(
                              fontSize: 14,
                              color: scheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Stack(
                      children: [
                        AnimatedFractionallySizedBox(
                          duration: const Duration(milliseconds: 600),
                          curve: Curves.easeOutCubic,
                          widthFactor: completeness.percentage,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [color, color.withValues(alpha: 0.8)],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              completeness.localizedMessage(app.languageCode),
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              itemCount: completeness.items.length,
              itemBuilder: (context, index) {
                final item = completeness.items[index];
                return _buildItemTile(context, item, color, index);
              },
            ),
          ),
        ],
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms)
        .slideY(begin: 0.1, end: 0, duration: 300.ms);
  }

  Widget _buildItemTile(
    BuildContext context,
    ProfileCompletenessItem item,
    Color color,
    int index,
  ) {
    final app = AppScope.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + (index * 50)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 10 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: item.route != null ? () => onItemTap(item) : null,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: item.isCompleted
                    ? const Color(0xFF1AB36A).withValues(alpha: 0.05)
                    : color.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: item.isCompleted
                      ? const Color(0xFF1AB36A).withValues(alpha: 0.15)
                      : color.withValues(alpha: 0.1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: item.isCompleted
                          ? const Color(0xFF1AB36A).withValues(alpha: 0.12)
                          : color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      item.isCompleted
                          ? Icons.check_rounded
                          : _getItemIcon(item.name),
                      size: 22,
                      color: item.isCompleted ? const Color(0xFF1AB36A) : color,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.t(item.name),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: item.isCompleted
                                ? const Color(0xFF1AB36A)
                                : scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          app.t(item.description),
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (item.isCompleted)
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1AB36A).withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: Color(0xFF1AB36A),
                      ),
                    )
                  else if (item.route != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        app.t('complete'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getProgressColor(double percentage) {
    if (percentage >= 1.0) {
      return const Color(0xFF1AB36A);
    } else if (percentage >= 0.7) {
      return AppTheme.mint;
    } else if (percentage >= 0.4) {
      return AppTheme.mango;
    } else {
      return const Color(0xFFE8384F);
    }
  }

  IconData _getItemIcon(String name) {
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
        return Icons.security_outlined;
      default:
        return Icons.circle_outlined;
    }
  }
}
