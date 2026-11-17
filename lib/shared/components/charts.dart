import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/formatters.dart';
import '../../models/collection_model.dart';
import '../../models/enums.dart';
import '../../models/office_model.dart';

const _axisStyle = TextStyle(fontSize: 11, color: AppColors.textMuted, fontWeight: FontWeight.w500);

FlTitlesData _titles({
  required Widget Function(double value, TitleMeta meta) bottom,
  bool showLeft = true,
  double? leftInterval,
}) {
  return FlTitlesData(
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: showLeft,
        reservedSize: 30,
        interval: leftInterval,
        getTitlesWidget: (value, meta) {
          // Label only whole interval steps, not the padded axis maximum.
          final step = leftInterval ?? 1;
          if (value % step != 0) return const SizedBox.shrink();
          return SideTitleWidget(
            meta: meta,
            child: Text(value.toInt().toString(), style: _axisStyle),
          );
        },
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(showTitles: true, reservedSize: 26, getTitlesWidget: bottom),
    ),
  );
}

FlGridData _grid(double interval) => FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: interval,
      getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.border, strokeWidth: 1),
    );

double _niceInterval(double max) {
  if (max <= 5) return 1;
  if (max <= 10) return 2;
  if (max <= 25) return 5;
  if (max <= 50) return 10;
  return (max / 5).ceilToDouble();
}

/// Completed collections per day over the last 7 days.
class WeeklyCollectionsChart extends StatelessWidget {
  const WeeklyCollectionsChart({super.key, required this.collections});

  final List<CollectionRecord> collections;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final days = List.generate(7, (i) => today.subtract(Duration(days: 6 - i)));
    final counts = List<int>.filled(7, 0);
    final points = List<int>.filled(7, 0);
    for (final c in collections) {
      final d = c.effectiveDate;
      final idx = DateTime(d.year, d.month, d.day).difference(days.first).inDays;
      if (idx >= 0 && idx < 7) {
        counts[idx]++;
        points[idx] += c.pointsAwarded;
      }
    }
    final maxY = math.max(4, counts.reduce(math.max)).toDouble();
    final interval = _niceInterval(maxY);

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          maxY: maxY + interval * 0.5,
          minY: 0,
          gridData: _grid(interval),
          borderData: FlBorderData(show: false),
          titlesData: _titles(
            leftInterval: interval,
            bottom: (value, meta) => SideTitleWidget(
              meta: meta,
              child: Text(Fmt.weekday(days[value.toInt()]), style: _axisStyle),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => AppColors.textPrimary,
              getTooltipItem: (group, _, rod, _) => BarTooltipItem(
                '${counts[group.x]} collected\n${points[group.x]} pts',
                const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < 7; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: counts[i].toDouble(),
                    width: 18,
                    color: i == 6 ? AppColors.forestGreen : AppColors.lightGreen,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class DonutSegment {
  const DonutSegment(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;
}

/// Donut chart with a legend (e.g. schedule status distribution).
class DonutChartWithLegend extends StatelessWidget {
  const DonutChartWithLegend({super.key, required this.segments, this.centerLabel});

  final List<DonutSegment> segments;
  final String? centerLabel;

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<int>(0, (sum, s) => sum + s.value);
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          width: 120,
          height: 120,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 38,
                  startDegreeOffset: -90,
                  sections: total == 0
                      ? [
                          PieChartSectionData(
                            value: 1,
                            color: AppColors.border,
                            radius: 16,
                            showTitle: false,
                          ),
                        ]
                      : [
                          for (final s in segments.where((s) => s.value > 0))
                            PieChartSectionData(
                              value: s.value.toDouble(),
                              color: s.color,
                              radius: 16,
                              showTitle: false,
                            ),
                        ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$total', style: theme.textTheme.titleLarge),
                  if (centerLabel != null)
                    Text(centerLabel!, style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textMuted)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in segments)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: s.color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(s.label, style: theme.textTheme.bodySmall)),
                      Text('${s.value}', style: theme.textTheme.labelLarge),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Points earned per collection (oldest -> newest).
class PointsTrendChart extends StatelessWidget {
  const PointsTrendChart({super.key, required this.collections});

  /// Collections in any order; the chart sorts them chronologically.
  final List<CollectionRecord> collections;

  @override
  Widget build(BuildContext context) {
    final sorted = [...collections]..sort((a, b) => a.effectiveDate.compareTo(b.effectiveDate));
    if (sorted.isEmpty) return const SizedBox.shrink();
    final maxPoints = sorted.map((c) => math.max(c.pointsAwarded, c.maxPoints)).fold<int>(0, math.max);
    final maxY = math.max(10, maxPoints).toDouble();
    final interval = _niceInterval(maxY);
    final spots = [
      for (var i = 0; i < sorted.length; i++) FlSpot(i.toDouble(), sorted[i].pointsAwarded.toDouble()),
    ];
    final labelEvery = math.max(1, (sorted.length / 5).ceil());

    return SizedBox(
      height: 190,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY + interval * 0.5,
          minX: 0,
          maxX: math.max(1, sorted.length - 1).toDouble(),
          gridData: _grid(interval),
          borderData: FlBorderData(show: false),
          titlesData: _titles(
            leftInterval: interval,
            bottom: (value, meta) {
              final i = value.toInt();
              if (value != i.toDouble() || i < 0 || i >= sorted.length || i % labelEvery != 0) {
                return const SizedBox.shrink();
              }
              return SideTitleWidget(
                meta: meta,
                child: Text(Fmt.monthDay(sorted[i].effectiveDate), style: _axisStyle),
              );
            },
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppColors.textPrimary,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${Fmt.monthDay(sorted[s.x.toInt()].effectiveDate)}\n${s.y.toInt()} pts',
                    const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              preventCurveOverShooting: true,
              color: AppColors.forestGreen,
              barWidth: 3,
              dotData: FlDotData(show: sorted.length <= 20),
              belowBarData: BarAreaData(
                show: true,
                color: AppColors.tint(AppColors.forestGreen, 0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Proper-segregation rate per waste category, as horizontal bars.
class CategoryBreakdown extends StatelessWidget {
  const CategoryBreakdown({super.key, required this.office});

  final Office office;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (final category in WasteCategory.values)
          Builder(builder: (context) {
            final stat = office.statFor(category);
            final rate = stat.rate;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(category.icon, size: 18, color: category.color),
                      const SizedBox(width: 8),
                      Expanded(child: Text(category.label, style: theme.textTheme.bodyMedium)),
                      Text(
                        rate == null ? 'No data' : '${(rate * 100).round()}%',
                        style: theme.textTheme.labelLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: rate ?? 0,
                      minHeight: 8,
                      backgroundColor: AppColors.tint(category.color, 0.12),
                      valueColor: AlwaysStoppedAnimation(category.color),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${stat.proper} proper · ${stat.improper} improper',
                    style: theme.textTheme.labelSmall?.copyWith(color: AppColors.textMuted),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}
