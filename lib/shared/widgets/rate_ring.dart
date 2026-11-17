import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'status_chip.dart';

/// Circular progress ring showing a 0..1 rate with the percentage inside.
class RateRing extends StatelessWidget {
  const RateRing({super.key, required this.rate, this.size = 84, this.label});

  final double? rate;
  final double size;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final color = RateChip.colorFor(rate);
    final theme = Theme.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CircularProgressIndicator(
            value: rate ?? 0,
            strokeWidth: size * 0.1,
            strokeCap: StrokeCap.round,
            backgroundColor: AppColors.tint(color, 0.15),
            valueColor: AlwaysStoppedAnimation(color),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  rate == null ? '—' : '${(rate! * 100).round()}%',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: size * 0.22,
                  ),
                ),
                if (label != null)
                  Text(label!, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
