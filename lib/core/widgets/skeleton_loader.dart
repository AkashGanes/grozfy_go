import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/context_colors.dart';

class SkeletonLine extends StatelessWidget {
  const SkeletonLine({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.surfaceContainer,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

class SkeletonCircle extends StatelessWidget {
  const SkeletonCircle({
    super.key,
    this.size = 40,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: context.surfaceContainer,
        shape: BoxShape.circle,
      ),
    );
  }
}

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({
    super.key,
    this.padding = const EdgeInsets.all(16),
    this.child,
  });

  final EdgeInsets padding;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? scheme.outline.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.7),
        ),
        boxShadow: [
          BoxShadow(
            color: context.shadowColor,
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class SkeletonLoader extends StatelessWidget {
  const SkeletonLoader({
    super.key,
    this.itemCount = 3,
    this.spacing = 12,
    this.shimmerColor,
  });

  final int itemCount;
  final double spacing;
  final Color? shimmerColor;

  @override
  Widget build(BuildContext context) {
    // Column instead of a shrinkWrap ListView. The shrinkWrap form is a
    // RenderShrinkWrappingViewport, which fails the intrinsic-height query
    // that infinite_scroll_pagination's SliverFillRemaining performs on the
    // first-page indicator — that assertion was detaching the debugger when
    // the screen first rendered.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(itemCount, (index) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: index == itemCount - 1 ? 0 : spacing,
          ),
          child: _SkeletonItem(
            index: index,
            shimmerColor: shimmerColor,
          ),
        );
      }),
    );
  }
}

class _SkeletonItem extends StatelessWidget {
  const _SkeletonItem({
    required this.index,
    this.shimmerColor,
  });

  final int index;
  final Color? shimmerColor;

  @override
  Widget build(BuildContext context) {
    final highlightColor = shimmerColor ?? context.fillMuted;

    return SkeletonCard(
      child: Row(
        children: [
          SkeletonCircle(size: 40)
              .animate(onPlay: (controller) => controller.repeat())
              .shimmer(
                duration: (1000 + (index * 150)).ms,
                color: highlightColor,
              ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(
                  width: 150 + (index * 20).toDouble(),
                  height: 14,
                  borderRadius: 6,
                )
                    .animate(onPlay: (controller) => controller.repeat())
                    .shimmer(
                      duration: (1000 + (index * 150)).ms,
                      color: highlightColor,
                    ),
                const SizedBox(height: 8),
                SkeletonLine(
                  width: 100 + (index * 15).toDouble(),
                  height: 10,
                  borderRadius: 6,
                )
                    .animate(onPlay: (controller) => controller.repeat())
                    .shimmer(
                      duration: (1000 + (index * 150)).ms,
                      color: highlightColor,
                    ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate(onPlay: (controller) => controller.repeat())
        .shimmer(
          duration: (1000 + (index * 150)).ms,
          color: highlightColor,
        );
  }
}

class SkeletonListTile extends StatelessWidget {
  const SkeletonListTile({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const SkeletonCircle(size: 48),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(
                  width: double.infinity,
                  height: 16,
                  borderRadius: 6,
                ),
                const SizedBox(height: 8),
                SkeletonLine(
                  width: 180,
                  height: 12,
                  borderRadius: 6,
                ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate(onPlay: (controller) => controller.repeat())
        .shimmer(
          duration: 1200.ms,
          color: context.fillMuted,
        );
  }
}

class SkeletonFormField extends StatelessWidget {
  const SkeletonFormField({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonLine(
            width: 80,
            height: 12,
            borderRadius: 4,
          ),
          const SizedBox(height: 8),
          SkeletonCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: SkeletonLine(
              width: double.infinity,
              height: 20,
              borderRadius: 4,
            ),
          ),
        ],
      ),
    )
        .animate(onPlay: (controller) => controller.repeat())
        .shimmer(
          duration: 1200.ms,
          color: context.fillMuted,
        );
  }
}

class SkeletonStatsGrid extends StatelessWidget {
  const SkeletonStatsGrid({super.key, this.itemCount = 4});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _skeletonStatTile(context)),
            const SizedBox(width: 10),
            Expanded(child: _skeletonStatTile(context)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _skeletonStatTile(context)),
            const SizedBox(width: 10),
            Expanded(child: _skeletonStatTile(context)),
          ],
        ),
      ],
    );
  }

  Widget _skeletonStatTile(BuildContext context) {
    return SkeletonCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonLine(
            width: 60,
            height: 12,
            borderRadius: 4,
          ),
          const SizedBox(height: 8),
          SkeletonLine(
            width: 80,
            height: 20,
            borderRadius: 4,
          ),
        ],
      ),
    )
        .animate(onPlay: (controller) => controller.repeat())
        .shimmer(
          duration: 1200.ms,
          color: context.fillMuted,
        );
  }
}

class SkeletonDetailCard extends StatelessWidget {
  const SkeletonDetailCard({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SkeletonCircle(size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonLine(
                      width: 180,
                      height: 18,
                      borderRadius: 6,
                    ),
                    const SizedBox(height: 8),
                    SkeletonLine(
                      width: 120,
                      height: 12,
                      borderRadius: 6,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Divider(height: 1),
          const SizedBox(height: 20),
          SkeletonLine(
            width: double.infinity,
            height: 14,
            borderRadius: 6,
          ),
          const SizedBox(height: 10),
          SkeletonLine(
            width: 250,
            height: 14,
            borderRadius: 6,
          ),
          const SizedBox(height: 10),
          SkeletonLine(
            width: 200,
            height: 14,
            borderRadius: 6,
          ),
        ],
      ),
    )
        .animate(onPlay: (controller) => controller.repeat())
        .shimmer(
          duration: 1200.ms,
          color: context.fillMuted,
        );
  }
}
