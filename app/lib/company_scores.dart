// The "Scores" section of the company page (v3): both scores and every reason behind them.
// Quality: the nine Piotroski checks with ✓ / ✗ / — and the numbers each one compared.
// Value: P/E, P/B and P/S next to the sector median, and where the company ranks in its sector.
import 'package:flutter/material.dart';

import 'company_sections.dart';
import 'format.dart';
import 'models.dart';
import 'scores_view.dart';
import 'theme.dart';
import 'widgets.dart';

class ScoresSection extends StatelessWidget {
  const ScoresSection({super.key, required this.company, required this.scores});

  final Company company;

  /// null when the server's database was built before v3.
  final CompanyScores? scores;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final scores = this.scores;
    if (scores == null) {
      return const SectionCard(title: 'Scores', child: Text('Scores are not available yet — they are added with the next data update.'));
    }

    return SectionCard(
      title: 'Scores',
      subtitle: 'Published rules applied to the latest 10-K and today\'s price — not investment advice',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: Space.xl,
            runSpacing: Space.md,
            children: [
              _headline(context, 'Quality (Piotroski F-Score)', scores.qualityScore, scores.qualityLabel,
                  company.missingReason('quality_score'),
                  scores.qualityScore == null ? null : '${scores.points} of ${scores.checkable} checks passed'),
              _headline(context, 'Value (vs ${company.sector})', scores.valueScore, scores.valueLabel,
                  company.missingReason('value_score'), 'Higher = cheaper than similar companies'),
            ],
          ),
          if (scores.combined != null) ...[
            const SizedBox(height: Space.md),
            Text(scores.combined!, style: theme.textTheme.titleSmall?.copyWith(fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: Space.lg),
          _heading(context, 'Quality: 9 checks (latest fiscal year vs the year before)'),
          for (final check in scores.checks) _checkRow(context, check),
          const SizedBox(height: Space.lg),
          _heading(context, 'Value: compared with ${company.sector}'),
          for (final ratio in scores.ratios) _ratioRow(context, ratio),
          const SizedBox(height: Space.md),
          Text(
            'Sources: Piotroski (2000), Journal of Accounting Research 38 — the F-Score. Comparing multiples within '
            'the same sector: Damodaran, Investment Valuation (relative valuation). A check with missing numbers '
            'is skipped (—) and the score is scaled to the checks that could be calculated.',
            style: small,
          ),
        ],
      ),
    );
  }

  Widget _headline(BuildContext context, String title, double? score, String? label, String reason, String? note) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.labelLarge),
        const SizedBox(height: Space.xs),
        ScoreChip(score: score, label: label, missingReason: reason),
        const SizedBox(height: Space.xxs),
        Text(score == null ? reason : (note ?? ''),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _heading(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
    );
  }

  /// ✓ / ✗ / — , the check's name, and below it the numbers it compared.
  Widget _checkRow(BuildContext context, ScoreCheck check) {
    final colors = Theme.of(context).colorScheme;
    final (IconData icon, Color color, String tooltip) = switch (check.passed) {
      true => (Icons.check_circle, colors.primary, 'Passed: 1 point'),
      false => (Icons.cancel, colors.error, 'Not passed: 0 points'),
      null => (Icons.remove_circle_outline, colors.outline, 'Skipped'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(message: tooltip, child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(check.label, style: const TextStyle(fontSize: FontSizes.body)),
                Text(
                  check.passed == null ? (check.skipReason ?? 'Skipped') : describeCheck(check),
                  style: TextStyle(fontSize: FontSizes.small, color: colors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "P/E   39.6 · sector median 29.8 · cheaper than 37% of 71 companies"
  Widget _ratioRow(BuildContext context, ValueRatio ratio) {
    final colors = Theme.of(context).colorScheme;
    final String details;
    if (ratio.percentile == null) {
      details = ratio.skipReason ?? 'Not ranked';
    } else {
      final cheaperThan = ((1 - ratio.percentile!) * 100).round();
      details = 'sector median ${_twoDecimals(ratio.sectorMedian)} · '
          'cheaper than $cheaperThan% of ${ratio.sectorCount} companies';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 80, child: Text(ratio.label, style: const TextStyle(fontSize: FontSizes.body))),
          SizedBox(
            width: 64,
            child: Text(_twoDecimals(ratio.value), style: numberStyle.copyWith(fontWeight: FontWeight.w600)),
          ),
          Expanded(child: Text(details, style: TextStyle(fontSize: FontSizes.small, color: colors.onSurfaceVariant))),
        ],
      ),
    );
  }
}

String _twoDecimals(double? value) => value == null ? missingValue : value.toStringAsFixed(2);

String _percent(double? ratio) => ratio == null ? missingValue : '${(ratio * 100).toStringAsFixed(1)}%';

String _shares(double? shares) => shares == null ? missingValue : '${formatMillions(shares)}M shares';

/// The numbers behind one check, in the unit that fits it, e.g. "36.8% now · 28.1% the year before".
String describeCheck(ScoreCheck check) {
  final v = check.values;
  String nowBefore(String Function(double?) format) => '${format(v['now'])} now · ${format(v['before'])} the year before';
  return switch (check.key) {
    'roa_positive' => 'ROA ${_percent(v['now'])} (net income ÷ assets at the start of the year)',
    'ocf_positive' => 'Cash from operations ${v['now'] == null ? missingValue : formatMoney(v['now']!)}',
    'accruals' => 'Cash from operations ${v['cash_from_operations'] == null ? missingValue : formatMoney(v['cash_from_operations']!)}'
        ' vs net income ${v['net_income'] == null ? missingValue : formatMoney(v['net_income']!)}',
    'roa_up' || 'gross_margin_up' => nowBefore(_percent),
    'leverage_down' => '${nowBefore(_twoDecimals)} (long-term debt ÷ average assets)',
    'no_new_shares' => nowBefore(_shares),
    _ => nowBefore(_twoDecimals), // current ratio, asset turnover
  };
}
