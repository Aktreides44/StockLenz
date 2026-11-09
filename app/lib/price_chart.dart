// Line chart of the daily closing price (last month / 6 months / year), for the company page.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'format.dart';
import 'models.dart';
import 'theme.dart';

/// The time spans the user can pick.
enum PriceRange {
  oneMonth('1M', 'month', 31),
  sixMonths('6M', '6 months', 183),
  oneYear('1Y', 'year', 366);

  const PriceRange(this.label, this.description, this.days);

  final String label;
  final String description;
  final int days;
}

/// A trading day as a date in UTC. (In local time, "31 days back" can be off by one around the
/// change to or from daylight saving time, because a day then has 23 or 25 hours.)
DateTime _date(String day) => DateTime.parse('${day}T00:00:00Z');

/// The points of the last [days] calendar days, counted back from the newest point.
List<PricePoint> pointsInRange(List<PricePoint> history, int days) {
  if (history.isEmpty) return [];
  final oldestAllowed = _date(history.last.day).subtract(Duration(days: days));
  return [for (final point in history) if (!_date(point.day).isBefore(oldestAllowed)) point];
}

/// Change from the first to the last point in percent, e.g. 12.3 for +12.3 %; null with fewer than 2 points.
double? percentChange(List<PricePoint> points) {
  if (points.length < 2 || points.first.close == 0) return null;
  return (points.last.close - points.first.close) / points.first.close * 100;
}

class PriceChart extends StatefulWidget {
  const PriceChart({super.key, required this.history});

  /// Daily closes, oldest first.
  final List<PricePoint> history;

  @override
  State<PriceChart> createState() => _PriceChartState();
}

class _PriceChartState extends State<PriceChart> {
  PriceRange _range = PriceRange.oneYear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final muted = TextStyle(fontSize: FontSizes.small, color: colors.onSurfaceVariant);

    if (widget.history.isEmpty) {
      return Text('No price history yet. It is filled in by the daily data update.', style: muted);
    }

    final points = pointsInRange(widget.history, _range.days);
    final change = percentChange(points);
    // While the history is still being filled in, the chosen span may reach back further than the data.
    final wantedStart = _date(widget.history.last.day).subtract(Duration(days: _range.days - 3));
    final isShort = _date(points.first.day).isAfter(wantedStart);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: Space.lg,
          runSpacing: Space.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<PriceRange>(
              segments: [
                for (final range in PriceRange.values) ButtonSegment(value: range, label: Text(range.label)),
              ],
              selected: {_range},
              showSelectedIcon: false,
              onSelectionChanged: (selection) => setState(() => _range = selection.first),
            ),
            if (change != null)
              Text(
                '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}% over the last ${_range.description}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: change < 0 ? colors.error : null,
                ),
              ),
          ],
        ),
        if (isShort) ...[
          const SizedBox(height: Space.xs),
          Text(
            'Prices so far start on ${formatDate(points.first.day)}; the history grows with every daily update.',
            style: muted,
          ),
        ],
        const SizedBox(height: Space.lg),
        SizedBox(height: 240, child: _chart(context, points)),
      ],
    );
  }

  Widget _chart(BuildContext context, List<PricePoint> points) {
    final colors = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(fontSize: FontSizes.tiny, color: colors.onSurfaceVariant);
    final closes = [for (final point in points) point.close];
    final low = closes.reduce((a, b) => a < b ? a : b);
    final high = closes.reduce((a, b) => a > b ? a : b);
    final padding = (high - low) * 0.08 + 0.01; // a little room above and below the line
    // About 4 date labels along the bottom, whatever the span.
    final labelEvery = (points.length / 4).ceil().clamp(1, 1000);

    String dateLabel(String day) {
      if (_range == PriceRange.oneMonth) {
        final parts = formatDate(day).split(' '); // "6 Nov 2026" -> "6 Nov"
        return '${parts[0]} ${parts[1]}';
      }
      return formatMonthYear(day);
    }

    return LineChart(
      LineChartData(
        minY: low - padding,
        maxY: high + padding,
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].close)],
            color: colors.primary,
            barWidth: 2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: colors.primary.withValues(alpha: 0.10)),
          ),
        ],
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (value != index || index % labelEvery != 0 || index >= points.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: Space.sm),
                  child: Text(dateLabel(points[index].day), style: labelStyle),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 64,
              getTitlesWidget: (value, meta) {
                if (value == meta.max || value == meta.min) return const SizedBox.shrink(); // odd edge values
                return Text(formatPrice(value), style: labelStyle);
              },
            ),
          ),
        ),
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) => FlLine(color: colors.outlineVariant, strokeWidth: 0.6),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (spot) => colors.inverseSurface,
            getTooltipItems: (spots) => [
              for (final spot in spots)
                LineTooltipItem(
                  '${formatDate(points[spot.x.toInt()].day)}\n${formatPrice(spot.y)}',
                  TextStyle(color: colors.onInverseSurface, fontSize: FontSizes.small),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
