import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../models/enums.dart';

/// Small coloured pill with optional icon.
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.tint(color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status, this.overdue = false});

  final ScheduleStatus status;
  final bool overdue;

  @override
  Widget build(BuildContext context) {
    if (overdue) {
      return const TagChip(label: 'Overdue', color: AppColors.danger, icon: Icons.schedule);
    }
    return TagChip(label: status.label, color: status.color, icon: status.icon);
  }
}

class SegregationChip extends StatelessWidget {
  const SegregationChip({super.key, required this.result, this.short = true});

  final SegregationResult result;
  final bool short;

  @override
  Widget build(BuildContext context) => TagChip(
        label: short ? result.shortLabel : result.label,
        color: result.color,
        icon: result.icon,
      );
}

/// Colour-coded proper-segregation rate indicator.
class RateChip extends StatelessWidget {
  const RateChip({super.key, required this.rate});

  final double? rate;

  static Color colorFor(double? rate) {
    if (rate == null) return AppColors.textMuted;
    if (rate >= 0.8) return AppColors.success;
    if (rate >= 0.5) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) => TagChip(
        label: rate == null ? 'No data' : '${(rate! * 100).round()}% proper',
        color: colorFor(rate),
        icon: Icons.eco_outlined,
      );
}
