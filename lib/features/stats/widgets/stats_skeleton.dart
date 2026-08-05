import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/widgets/skeleton_loader.dart';
import 'stats_theme.dart';

/// Single shimmer wrapper reused by every skeleton shape below, so loading
/// states are shape-matched to their destination content instead of a
/// centered spinner that causes a layout jump once data arrives. Highlight
/// color is theme-resolved — a highlight calibrated for a dark background is
/// invisible on light, and vice versa.
Widget shimmerWrap(BuildContext context, Widget child) {
  return child
      .animate(onPlay: (controller) => controller.repeat())
      .shimmer(duration: 1200.ms, color: context.statsTokens.shimmerHighlight);
}

/// Skeleton shaped like the Today hero: a big centered number, a caption,
/// a divider, and two stat-pair columns underneath.
class HeroStatsSkeleton extends StatelessWidget {
  const HeroStatsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: shimmerWrap(
            context,
            const SkeletonLine(width: 150, height: 34, borderRadius: 10),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: shimmerWrap(
            context,
            const SkeletonLine(width: 110, height: 12, borderRadius: 6),
          ),
        ),
        const StatsDivider(marginTop: 16, marginBottom: 14),
        Row(
          children: [
            Expanded(child: shimmerWrap(context, _statColumnSkeleton())),
            const StatsVerticalDivider(),
            Expanded(child: shimmerWrap(context, _statColumnSkeleton())),
          ],
        ),
      ],
    );
  }

  Widget _statColumnSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const SkeletonCircle(size: 34),
        const SizedBox(height: 8),
        const SkeletonLine(width: 48, height: 16, borderRadius: 6),
        const SizedBox(height: 6),
        const SkeletonLine(width: 64, height: 10, borderRadius: 6),
      ],
    );
  }
}

/// Skeleton shaped like the Month card: headline number + caption on the
/// left, a ring on the right, then a single list row below.
class MonthStatsSkeleton extends StatelessWidget {
  const MonthStatsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  shimmerWrap(
                    context,
                    const SkeletonLine(width: 70, height: 30, borderRadius: 8),
                  ),
                  const SizedBox(height: 8),
                  shimmerWrap(
                    context,
                    const SkeletonLine(width: 100, height: 12, borderRadius: 6),
                  ),
                  const SizedBox(height: 6),
                  shimmerWrap(
                    context,
                    const SkeletonLine(width: 120, height: 12, borderRadius: 6),
                  ),
                ],
              ),
            ),
            shimmerWrap(context, const SkeletonCircle(size: 72)),
          ],
        ),
        const StatsDivider(),
        shimmerWrap(
          context,
          const SkeletonLine(width: double.infinity, height: 16, borderRadius: 6),
        ),
      ],
    );
  }
}

/// Skeleton shaped like the All Time card: two stat-pair columns, then a
/// badge row.
class LifetimeSkeleton extends StatelessWidget {
  const LifetimeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: shimmerWrap(context, _statColumnSkeleton(40))),
            const StatsVerticalDivider(),
            Expanded(child: shimmerWrap(context, _statColumnSkeleton(40))),
          ],
        ),
        const StatsDivider(),
        Row(
          children: [
            Expanded(
              child: shimmerWrap(
                context,
                const SkeletonLine(height: 64, borderRadius: 16),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: shimmerWrap(
                context,
                const SkeletonLine(height: 64, borderRadius: 16),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statColumnSkeleton(double chipSize) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SkeletonCircle(size: chipSize),
        const SizedBox(height: 8),
        const SkeletonLine(width: 56, height: 22, borderRadius: 6),
        const SizedBox(height: 6),
        const SkeletonLine(width: 64, height: 10, borderRadius: 6),
      ],
    );
  }
}
