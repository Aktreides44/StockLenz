// Bar chart of revenue and net income for the last 5 fiscal years (fl_chart).
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'format.dart';
import 'models.dart';
import 'theme.dart';

class RevenueIncomeChart extends StatelessWidget {
  const RevenueIncomeChart({super.key, required this.history});

  /// Oldest year first. Only the last 5 years are drawn.
  final List<YearData> history;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final years = history.length > 5 ? history.sublist(history.length - 5) : history;
    final revenueColor = colors.primary;
    final incomeColor = colors.primary.withValues(alpha: 0.45);

    // The chart works in billions of dollars.
    double? billions(YearData year, String field) {
      final value = year.values[field];
      return value == null ? null : value / 1e9;
    }

    final present = [
      for (final year in years) ...[billions(year, 'revenue'), billions(year, 'net_income')],
    ].whereType<double>().toList();
    var maxY = present.isEmpty ? 1.0 : math.max(0.0, present.reduce(math.max)) * 1.15;
    final minY = present.isEmpty ? 0.0 : math.min(0.0, present.reduce(math.min)) * 1.15;
    if (maxY == 0 && minY == 0) maxY = 1;

    // A missing value gets an invisible bar, so nothing is drawn (never a fake 0 bar),
    // and the tooltip says it is not reported.
    BarChartRodData bar(double? value, Color color) {
      return BarChartRodData(
        toY: value ?? 0,
        color: value == null ? Colors.transparent : color,
        width: 22,
        borderRadius: BorderRadius.circular(2),
      );
    }

    final labelStyle = TextStyle(fontSize: FontSizes.tiny, color: colors.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _LegendItem(color: revenueColor, label: 'Revenue'),
            const SizedBox(width: Space.lg),
            _LegendItem(color: incomeColor, label: 'Net income'),
            const Spacer(),
            Text('USD billions', style: labelStyle),
          ],
        ),
        const SizedBox(height: Space.lg),
        SizedBox(
          height: 260,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              minY: minY,
              barGroups: [
                for (var i = 0; i < years.length; i++)
                  BarChartGroupData(
                    x: i,
                    barsSpace: 6,
                    barRods: [
                      bar(billions(years[i], 'revenue'), revenueColor),
                      bar(billions(years[i], 'net_income'), incomeColor),
                    ],
                  ),
              ],
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    getTitlesWidget: (value, meta) => Padding(
                      padding: const EdgeInsets.only(top: Space.sm),
                      child: Text('FY${years[value.toInt()].fiscalYear}', style: labelStyle),
                    ),
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 60,
                    getTitlesWidget: (value, meta) {
                      // Skip the top and bottom edge labels; they are odd numbers like 449.7.
                      if (value == meta.max || (value == meta.min && value != 0)) return const SizedBox.shrink();
                      return Text(formatMoney(value * 1e9), style: labelStyle);
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (value) => FlLine(color: colors.outlineVariant, strokeWidth: 0.6),
              ),
              borderData: FlBorderData(show: false),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (group) => colors.inverseSurface,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final year = years[groupIndex];
                    final field = rodIndex == 0 ? 'revenue' : 'net_income';
                    final label = rodIndex == 0 ? 'Revenue' : 'Net income';
                    final value = year.values[field];
                    return BarTooltipItem(
                      'FY${year.fiscalYear} $label\n${value == null ? '— not reported' : formatMoney(value)}',
                      TextStyle(color: colors.onInverseSurface, fontSize: FontSizes.small),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: Space.sm),
        Text(label, style: const TextStyle(fontSize: FontSizes.small)),
      ],
    );
  }
}
