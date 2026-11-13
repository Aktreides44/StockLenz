// The "Scores" tab (v3): every company with its Quality and Value score as coloured chips.
// Quality = Piotroski F-Score (0–9): is the company financially healthy and improving?
// Value = P/E, P/B and P/S ranked within the company's own sector (0–10): is it cheap or expensive vs similar companies?
// The scores are calculated by the pipeline (backend/pipeline/scores.py); this screen only shows and filters them.
import 'package:flutter/material.dart';

import 'format.dart';
import 'models.dart';
import 'theme.dart';

/// The buttons at the top of the tab.
enum ScoreFilter {
  all('All'),
  strong('Strong'),
  weak('Weak'),
  cheap('Cheap'),
  expensive('Expensive');

  const ScoreFilter(this.label);
  final String label;

  bool accepts(Company company) => switch (this) {
        ScoreFilter.all => true,
        ScoreFilter.strong => company.qualityLabel == 'Strong',
        ScoreFilter.weak => company.qualityLabel == 'Weak',
        ScoreFilter.cheap => company.valueLabel == 'Cheap',
        ScoreFilter.expensive => company.valueLabel == 'Expensive',
      };
}

/// Which score the list is sorted by (highest first).
enum ScoreSort { quality, value }

/// A small coloured box with a score and its label, e.g. "8.0 Strong".
/// Green for Strong / Cheap, red for Weak / Expensive, grey in between, "—" when there is not enough data.
class ScoreChip extends StatelessWidget {
  const ScoreChip({super.key, required this.score, required this.label, this.missingReason});

  final double? score;
  final String? label;

  /// Tooltip when there is no score.
  final String? missingReason;

  static const double width = 104;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (Color background, Color foreground) = switch (label) {
      'Strong' || 'Cheap' => (colors.primaryContainer, colors.onPrimaryContainer),
      'Weak' || 'Expensive' => (colors.errorContainer, colors.onErrorContainer),
      _ => (colors.surfaceContainerHighest, colors.onSurfaceVariant),
    };
    final chip = Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(Radii.medium)),
      child: Text(
        score == null ? missingValue : '${formatMetric(score!, 'score')} $label',
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: foreground, fontSize: FontSizes.body, fontWeight: FontWeight.w600),
      ),
    );
    if (score == null && missingReason != null) return Tooltip(message: missingReason!, child: chip);
    return chip;
  }
}

class ScoresView extends StatefulWidget {
  const ScoresView({super.key, required this.companies, required this.onCompanyTap});

  final List<Company> companies;
  final void Function(Company company) onCompanyTap;

  @override
  State<ScoresView> createState() => _ScoresViewState();
}

class _ScoresViewState extends State<ScoresView> {
  ScoreFilter _filter = ScoreFilter.all;
  ScoreSort _sort = ScoreSort.quality;
  String? _sector; // null = all sectors

  /// Highest first; companies without that score go to the bottom. Ties: the other score, then the ticker.
  int _compare(Company a, Company b) {
    final first = _sort == ScoreSort.quality ? 'quality_score' : 'value_score';
    final second = _sort == ScoreSort.quality ? 'value_score' : 'quality_score';
    for (final key in [first, second]) {
      final valueA = a.metrics[key];
      final valueB = b.metrics[key];
      if (valueA == valueB) continue;
      if (valueA == null) return 1;
      if (valueB == null) return -1;
      return valueB.compareTo(valueA);
    }
    return a.ticker.compareTo(b.ticker);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = isPhone(context);
    final visible = widget.companies
        .where((c) => _filter.accepts(c) && (_sector == null || c.sector == _sector))
        .toList()
      ..sort(_compare);
    final sectors = widget.companies.map((c) => c.sector).toSet().toList()..sort();
    final small = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(phone ? Space.md : Space.lg, Space.md, phone ? Space.md : Space.lg, Space.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final filter in ScoreFilter.values)
                    ChoiceChip(
                      label: Text(filter.label),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                    ),
                ],
              ),
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.md,
                runSpacing: Space.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DropdownButton<String?>(
                    value: _sector,
                    onChanged: (sector) => setState(() => _sector = sector),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('All sectors')),
                      for (final sector in sectors) DropdownMenuItem<String?>(value: sector, child: Text(sector)),
                    ],
                  ),
                  SegmentedButton<ScoreSort>(
                    segments: const [
                      ButtonSegment(value: ScoreSort.quality, label: Text('Quality')),
                      ButtonSegment(value: ScoreSort.value, label: Text('Value')),
                    ],
                    selected: {_sort},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) => setState(() => _sort = selection.first),
                  ),
                  Text('${visible.length} of ${widget.companies.length}', style: small),
                ],
              ),
              const SizedBox(height: Space.sm),
              Text(
                'Quality: Piotroski F-Score, 9 checks of the latest 10-K (0–9; Strong ≥ 8, Weak ≤ 1). '
                'Value: P/E, P/B and P/S compared with the same sector (0–10; Cheap ≥ 7, Expensive ≤ 3). '
                'Facts and published rules, not investment advice.',
                style: small,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.lg),
                    child: Text(
                      _filter == ScoreFilter.weak
                          ? 'No company is Weak (0–1 of 9 checks) right now. That is rare among the large, '
                              'established companies of the S&P 500.'
                          : 'No companies in this group.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) => _row(visible[index], phone),
                ),
        ),
      ],
    );
  }

  Widget _row(Company company, bool phone) {
    final theme = Theme.of(context);
    final chips = [
      ScoreChip(
        score: company.metrics['quality_score'],
        label: company.qualityLabel,
        missingReason: company.missingReason('quality_score'),
      ),
      const SizedBox(width: Space.sm, height: Space.xs),
      ScoreChip(
        score: company.metrics['value_score'],
        label: company.valueLabel,
        missingReason: company.missingReason('value_score'),
      ),
    ];
    return InkWell(
      key: ValueKey('scores-row-${company.ticker}'),
      onTap: () => widget.onCompanyTap(company),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: phone ? Space.md : Space.lg, vertical: Space.sm),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: company.ticker,
                        style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                      ),
                      TextSpan(text: '  ${company.name}'),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    company.sector,
                    style: TextStyle(fontSize: FontSizes.small, color: theme.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Space.sm),
            // Phones: the two chips on top of each other; wide screens: side by side.
            if (phone) Column(children: chips) else Row(children: chips),
          ],
        ),
      ),
    );
  }
}
