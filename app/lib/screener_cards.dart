// The screener on phones: one card per company instead of the wide table.
// Each card shows ticker, name, sector and three key numbers; tapping it opens the company page.
import 'package:flutter/material.dart';

import 'format.dart';
import 'models.dart';
import 'theme.dart';
import 'watchlist.dart';
import 'widgets.dart';

/// The three numbers shown on every card.
const List<String> cardMetricKeys = ['market_cap', 'pe', 'roe'];

class ScreenerCards extends StatelessWidget {
  const ScreenerCards({super.key, required this.companies, required this.metricsByKey, this.onCompanyTap});

  final List<Company> companies;
  final Map<String, MetricDefinition> metricsByKey;
  final void Function(Company company)? onCompanyTap;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.lg),
      itemCount: companies.length,
      itemBuilder: (context, index) => _card(context, companies[index]),
    );
  }

  Widget _card(BuildContext context, Company company) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: Space.sm),
      clipBehavior: Clip.antiAlias, // keeps the tap ripple inside the rounded corners
      child: InkWell(
        onTap: onCompanyTap == null ? null : () => onCompanyTap!(company),
        child: Padding(
          padding: const EdgeInsets.all(Space.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    company.ticker,
                    style: TextStyle(fontWeight: FontWeight.bold, color: colors.primary, fontSize: FontSizes.title),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(child: Text(company.name, overflow: TextOverflow.ellipsis)),
                  WatchStar(ticker: company.ticker),
                ],
              ),
              const SizedBox(height: Space.xxs),
              Text(
                company.sector,
                style: TextStyle(fontSize: FontSizes.small, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: Space.sm),
              Row(
                children: [
                  for (final key in cardMetricKeys) Expanded(child: _keyNumber(context, company, key)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A small label ("P/E (FY)") with the value under it.
  Widget _keyNumber(BuildContext context, Company company, String key) {
    final metric = metricsByKey[key];
    final value = company.metrics[key];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          metric?.label ?? key,
          style: TextStyle(fontSize: FontSizes.tiny, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        DefaultTextStyle.merge(
          style: const TextStyle(fontSize: FontSizes.medium, fontWeight: FontWeight.w500),
          child: value == null
              ? MissingValue(company.missingReason(key))
              : NumberText(formatMetric(value, metric?.unit ?? 'x'), value: value),
        ),
      ],
    );
  }
}
