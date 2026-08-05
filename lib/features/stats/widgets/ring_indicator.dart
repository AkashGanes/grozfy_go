import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'stats_theme.dart';

/// Circular progress ring for percentage-based metrics (e.g. On-Time Stops).
/// When [value] is null (no underlying data to compute a rate), renders a
/// dashed outline-only ring with a centered "—" instead of a misleading
/// 0%/100% arc. When [value] is present, a short [subLabel] (e.g. "on-time")
/// renders directly beneath the percentage, inside the ring — matching the
/// mockup's 72px ring with a 56px inner text area.
class RingIndicator extends StatelessWidget {
  const RingIndicator({
    super.key,
    required this.value,
    required this.color,
    this.size = 72,
    this.strokeWidth = 6,
    this.subLabel,
  });

  /// 0-100, or null when there's no data to compute a percentage from.
  final double? value;
  final Color color;
  final double size;
  final double strokeWidth;
  final String? subLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.statsTokens;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              value: value,
              color: color,
              trackColor: tokens.ringTrack,
              dashColor: tokens.ringMutedTrack,
              strokeWidth: strokeWidth,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value != null ? '${value!.toStringAsFixed(0)}%' : '—',
                style: StatsText.ringPercent.copyWith(color: tokens.textValue),
              ),
              if (value != null && subLabel != null)
                Text(
                  subLabel!,
                  style: StatsText.ringSubLabel.copyWith(color: tokens.textSecondary),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.color,
    required this.trackColor,
    required this.dashColor,
    required this.strokeWidth,
  });

  final double? value;
  final Color color;
  final Color trackColor;
  final Color dashColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    if (value == null) {
      const dashCount = 24;
      const gapFraction = 0.45;
      final sweepPerDash = (2 * math.pi) / dashCount;
      final dashPaint = Paint()
        ..color = dashColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      for (int i = 0; i < dashCount; i++) {
        canvas.drawArc(
          rect,
          i * sweepPerDash,
          sweepPerDash * (1 - gapFraction),
          false,
          dashPaint,
        );
      }
      return;
    }

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, trackPaint);

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final sweep = 2 * math.pi * (value!.clamp(0, 100) / 100);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, progressPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.dashColor != dashColor ||
      oldDelegate.strokeWidth != strokeWidth;
}
