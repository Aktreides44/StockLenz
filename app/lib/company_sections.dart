// The sections of the company page: summary, analysis, peers and the financial tables.
import 'package:flutter/material.dart';

import 'format.dart';
import 'models.dart';
import 'widgets.dart';

/// Light grey page with white cards in light mode; dark cards on a darker page in dark mode.
Color pageBackground(ColorScheme colors) =>
    colors.brightness == Brightness.light ? const Color(0xFFF3F4F6) : colors.surface;

Color cardBackground(ColorScheme colors) =>
    colors.brightness == Brightness.light ? Colors.white : colors.surfaceContainer;

const Map<String, String> fieldLabels = {
  'revenue': 'Revenue',
  'net_income': 'Net income',
  'operating_income': 'Operating income',
  'eps_diluted': 'Diluted EPS',
  'total_assets': 'Total assets',
  'current_assets': 'Current assets',
  'current_liabilities': 'Current liabilities',
  'equity': "Shareholders' equity",
  'long_term_debt': 'Long-term debt',
  'operating_cash_flow': 'Operating cash flow',
  'capex': 'Capital expenditure',
  'dividends_paid': 'Dividends paid',
  'fcf': 'Free cash flow',
};

String edgarUrl(int cik) =>
    'https://www.sec.gov/cgi-bin/browse-edgar?action=getcompany&CIK=${cik.toString().padLeft(10, '0')}&type=10-K';

/// A white card with a title, used for every section.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBackground(theme.colorScheme),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              if (subtitle != null) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Small "i" icon that shows a formula when hovered.
class InfoIcon extends StatelessWidget {
  const InfoIcon(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      child: Icon(Icons.info_outline, size: 14, color: Theme.of(context).colorScheme.outline),
    );
  }
}

Widget _metricValue(Company company, String key, Map<String, MetricDefinition> metricsByKey, {bool bold = true}) {
  final value = company.metrics[key];
  if (value == null) return MissingValue(company.missingReason(key));
  return NumberText(formatMetric(value, metricsByKey[key]?.unit ?? 'x'), value: value, bold: bold);
}

// ---------------------------------------------------------------------------
// 1. Summary
// ---------------------------------------------------------------------------

class SummarySection extends StatelessWidget {
  const SummarySection({super.key, required this.company, required this.metricsByKey});

  final Company company;
  final Map<String, MetricDefinition> metricsByKey;

  static const _keyRatios = [
    'market_cap', 'price', 'pe', 'pb', 'ps', 'roe',
    'roa', 'net_margin', 'operating_margin', 'debt_to_equity', 'current_ratio', 'revenue_growth',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBackground(theme.colorScheme),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(company.name, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(company.ticker,
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimaryContainer)),
                        ),
                        Text(company.sector, style: muted),
                        if (company.cik != null)
                          TextButton.icon(
                            onPressed: () => openInBrowser(context, edgarUrl(company.cik!)),
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('SEC filings'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (company.price == null)
                    const MissingValue('No current share price available')
                  else
                    Text(formatPrice(company.price!),
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                  if (company.priceFetchedAt != null)
                    Text('as of ${formatDate(company.priceFetchedAt!)}', style: muted),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(builder: (context, constraints) {
            final columns = constraints.maxWidth > 720 ? 3 : (constraints.maxWidth > 460 ? 2 : 1);
            const gap = 32.0;
            final itemWidth = ((constraints.maxWidth - gap * (columns - 1)) / columns).floorToDouble();
            return Wrap(
              spacing: gap,
              children: [
                for (final key in _keyRatios) SizedBox(width: itemWidth, child: _ratioItem(context, key)),
              ],
            );
          }),
          const SizedBox(height: 12),
          Text(
            'Ratios use the FY${company.latestFiscalYear} 10-K (year ended ${company.latestFiscalYearEnd}) '
            'and the latest price. (FY) multiples are not trailing-12-month figures.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _ratioItem(BuildContext context, String key) {
    final colors = Theme.of(context).colorScheme;
    final String label;
    final String formula;
    final Widget value;
    if (key == 'price') {
      label = 'Price';
      formula = 'Latest share price from Yahoo Finance';
      value = company.price == null
          ? const MissingValue('No current share price available')
          : NumberText(formatPrice(company.price!), value: company.price!, bold: true);
    } else {
      label = metricsByKey[key]?.label ?? key;
      formula = metricsByKey[key]?.formula ?? '';
      value = _metricValue(company, key, metricsByKey);
    }

    return Container(
      height: 38,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)))),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
          const SizedBox(width: 4),
          InfoIcon(formula),
          const Spacer(),
          DefaultTextStyle.merge(style: const TextStyle(fontSize: 14), child: value),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Analysis: rule-based pros and cons (generated by the backend)
// ---------------------------------------------------------------------------

class AnalysisSection extends StatelessWidget {
  const AnalysisSection({super.key, required this.detail});

  final CompanyDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final pros = _box(context, 'Pros', detail.pros, colors.primary, colors.primaryContainer);
    final cons = _box(context, 'Cons', detail.cons, colors.error, colors.errorContainer);

    return SectionCard(
      title: 'Analysis',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth < 600) return Column(children: [pros, const SizedBox(height: 12), cons]);
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Expanded(child: pros), const SizedBox(width: 16), Expanded(child: cons)],
              ),
            );
          }),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: colors.outline),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Generated automatically from simple threshold rules on the numbers on this page '
                  '(for example "ROE above 15%"). Rules with missing data are skipped. This is not investment advice.',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _box(BuildContext context, String title, List<AnalysisPoint> items, Color accent, Color tint) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: tint.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(6)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: accent, fontSize: 15)),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text('No rule triggered.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
                  Expanded(
                    child: Tooltip(
                      message: 'Rule: ${item.id}',
                      waitDuration: const Duration(milliseconds: 600),
                      child: Text(item.text, style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Peers: other companies in the same sector
// ---------------------------------------------------------------------------

class PeersSection extends StatelessWidget {
  const PeersSection({
    super.key,
    required this.company,
    required this.allCompanies,
    required this.metricsByKey,
    required this.onOpen,
  });

  final Company company;
  final List<Company> allCompanies;
  final Map<String, MetricDefinition> metricsByKey;
  final void Function(String ticker) onOpen;

  static const _columns = ['price', 'market_cap', 'pe', 'roe', 'net_margin', 'revenue_growth'];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final peers = allCompanies.where((c) => c.sector == company.sector && c.ticker != company.ticker).toList()
      ..sort((a, b) => (b.metrics['market_cap'] ?? -1).compareTo(a.metrics['market_cap'] ?? -1));

    if (peers.isEmpty) {
      return SectionCard(
        title: 'Peers',
        child: Text('No other StockLens companies in ${company.sector}.'),
      );
    }

    String label(String key) => key == 'price' ? 'Price' : (metricsByKey[key]?.label ?? key);
    const headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 12);

    return SectionCard(
      title: 'Peers',
      subtitle: 'Other StockLens companies in ${company.sector}. Click one to open it.',
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontSize: 13),
        child: Column(
          children: [
            Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.outlineVariant))),
              child: Row(
                children: [
                  const Expanded(flex: 3, child: Text('Name', style: headerStyle)),
                  for (final key in _columns)
                    Expanded(
                      flex: 2,
                      child: Tooltip(
                        message: metricsByKey[key]?.formula ?? 'Latest share price from Yahoo Finance',
                        child: Text(label(key), textAlign: TextAlign.right, style: headerStyle),
                      ),
                    ),
                ],
              ),
            ),
            for (final peer in peers)
              InkWell(
                onTap: () => onOpen(peer.ticker),
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.4))),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 56,
                              child: Text(peer.ticker,
                                  style: TextStyle(fontWeight: FontWeight.bold, color: colors.primary)),
                            ),
                            Flexible(child: Text(peer.name, overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                      for (final key in _columns)
                        Expanded(
                          flex: 2,
                          child: Align(alignment: Alignment.centerRight, child: _peerCell(peer, key)),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _peerCell(Company peer, String key) {
    if (key == 'price') {
      return peer.price == null
          ? const MissingValue('No current share price available')
          : Text(formatPrice(peer.price!), style: numberStyle);
    }
    return _metricValue(peer, key, metricsByKey, bold: false);
  }
}

// ---------------------------------------------------------------------------
// 5. Financial tables: fiscal years as columns, line items as rows (like Screener.in)
// ---------------------------------------------------------------------------

class YearTableRow {
  const YearTableRow({required this.label, required this.cell, this.labelTooltip, this.bold = false});

  final String label;

  /// e.g. the formula of a ratio, shown with an info icon.
  final String? labelTooltip;

  /// Builds the cell for one fiscal year.
  final Widget Function(YearData year) cell;
  final bool bold;
}

class YearTable extends StatelessWidget {
  const YearTable({super.key, required this.years, required this.rows});

  final List<YearData> years;
  final List<YearTableRow> rows;

  static const double labelWidth = 220;
  static const double yearWidth = 110;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const cellPadding = EdgeInsets.symmetric(horizontal: 8, vertical: 7);

    final table = Table(
      columnWidths: const {0: FixedColumnWidth(labelWidth)},
      defaultColumnWidth: const FlexColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.outlineVariant))),
          children: [
            const SizedBox.shrink(),
            for (final year in years)
              Tooltip(
                message: 'Fiscal year ended ${year.endDate}',
                child: Padding(
                  padding: cellPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('FY${year.fiscalYear}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(formatMonthYear(year.endDate), style: TextStyle(fontSize: 11, color: colors.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        for (var i = 0; i < rows.length; i++)
          TableRow(
            decoration: BoxDecoration(
              color: i.isOdd ? colors.surfaceContainerHighest.withValues(alpha: 0.25) : null,
              border: Border(bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.4))),
            ),
            children: [
              Padding(
                padding: cellPadding,
                child: Row(
                  children: [
                    Flexible(
                      child: Text(rows[i].label,
                          style: TextStyle(fontWeight: rows[i].bold ? FontWeight.bold : FontWeight.normal)),
                    ),
                    if (rows[i].labelTooltip != null) ...[const SizedBox(width: 4), InfoIcon(rows[i].labelTooltip!)],
                  ],
                ),
              ),
              for (final year in years)
                Padding(
                  padding: cellPadding,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: DefaultTextStyle.merge(
                      style: TextStyle(fontWeight: rows[i].bold ? FontWeight.bold : FontWeight.normal),
                      child: rows[i].cell(year),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );

    final minWidth = labelWidth + yearWidth * years.length;
    return DefaultTextStyle.merge(
      style: const TextStyle(fontSize: 13),
      child: LayoutBuilder(
        builder: (context, constraints) => constraints.maxWidth >= minWidth
            ? table
            : SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: minWidth, child: table)),
      ),
    );
  }
}

String _missingFieldReason(YearData year, String field) {
  if (field == 'fcf') {
    final missing = year.values['operating_cash_flow'] == null ? 'operating_cash_flow' : 'capex';
    return '${fieldLabels[missing]} not reported in the FY${year.fiscalYear} 10-K, so FCF cannot be calculated';
  }
  return '${fieldLabels[field]} not reported in the FY${year.fiscalYear} 10-K';
}

/// A raw 10-K value in $ millions (or $ per share). Hover shows the XBRL tag it came from.
Widget rawValueCell(YearData year, String field, {bool perShare = false}) {
  final value = year.values[field];
  if (value == null) return MissingValue(_missingFieldReason(year, field));
  final tag = year.tags[field];
  return Tooltip(
    message: tag == null ? 'Operating cash flow − Capital expenditure' : 'XBRL tag: us-gaap:$tag',
    waitDuration: const Duration(milliseconds: 500),
    child: NumberText(perShare ? value.toStringAsFixed(2) : formatMillions(value), value: value),
  );
}

Widget ratioCell(YearData year, String key, String unit) {
  final value = year.ratios[key];
  if (value == null) return MissingValue(year.ratioMissingReasons[key] ?? 'Not available');
  return NumberText(formatMetric(value, unit), value: value);
}

List<YearTableRow> profitAndLossRows() => [
      YearTableRow(label: 'Revenue', cell: (y) => rawValueCell(y, 'revenue'), bold: true),
      YearTableRow(label: 'Operating income', cell: (y) => rawValueCell(y, 'operating_income')),
      YearTableRow(label: 'Net income', cell: (y) => rawValueCell(y, 'net_income'), bold: true),
      YearTableRow(label: 'Diluted EPS (\$ per share)', cell: (y) => rawValueCell(y, 'eps_diluted', perShare: true)),
    ];

List<YearTableRow> balanceSheetRows() => [
      YearTableRow(label: 'Total assets', cell: (y) => rawValueCell(y, 'total_assets'), bold: true),
      YearTableRow(label: 'Current assets', cell: (y) => rawValueCell(y, 'current_assets')),
      YearTableRow(label: 'Current liabilities', cell: (y) => rawValueCell(y, 'current_liabilities')),
      YearTableRow(label: 'Long-term debt', cell: (y) => rawValueCell(y, 'long_term_debt')),
      YearTableRow(label: "Shareholders' equity", cell: (y) => rawValueCell(y, 'equity'), bold: true),
    ];

List<YearTableRow> cashFlowRows() => [
      YearTableRow(label: 'Operating cash flow', cell: (y) => rawValueCell(y, 'operating_cash_flow')),
      YearTableRow(label: 'Capital expenditure', cell: (y) => rawValueCell(y, 'capex')),
      YearTableRow(
        label: 'Free cash flow',
        labelTooltip: 'Operating cash flow − Capital expenditure',
        cell: (y) => rawValueCell(y, 'fcf'),
        bold: true,
      ),
      YearTableRow(label: 'Dividends paid', cell: (y) => rawValueCell(y, 'dividends_paid')),
    ];

const yearlyRatioKeys = [
  'net_margin', 'operating_margin', 'roe', 'roa', 'debt_to_equity', 'current_ratio', 'fcf_margin',
];

List<YearTableRow> ratioRows(Map<String, MetricDefinition> metricsByKey) => [
      for (final key in yearlyRatioKeys)
        YearTableRow(
          label: metricsByKey[key]?.label ?? key,
          labelTooltip: metricsByKey[key]?.formula,
          cell: (y) => ratioCell(y, key, metricsByKey[key]?.unit ?? 'x'),
        ),
    ];

class StatementSection extends StatelessWidget {
  const StatementSection({
    super.key,
    required this.title,
    required this.years,
    required this.rows,
    this.subtitle = 'Figures in USD millions · source: SEC 10-K filings (XBRL). Hover a number to see its tag.',
    this.footer,
  });

  final String title;
  final String subtitle;
  final List<YearData> years;
  final List<YearTableRow> rows;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: title,
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          YearTable(years: years, rows: rows),
          if (footer != null) ...[const SizedBox(height: 16), footer!],
        ],
      ),
    );
  }
}

/// The small boxes under Profit & Loss: revenue CAGR 3y and ROE for the latest year.
class ProfitAndLossSummary extends StatelessWidget {
  const ProfitAndLossSummary({super.key, required this.company, required this.metricsByKey});

  final Company company;
  final Map<String, MetricDefinition> metricsByKey;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 12,
      children: [
        _box(context, 'Revenue CAGR 3y', 'revenue_cagr_3y'),
        _box(context, 'ROE last year (FY${company.latestFiscalYear})', 'roe'),
      ],
    );
  }

  Widget _box(BuildContext context, String label, String key) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: 250,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: Text(label, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant))),
              const SizedBox(width: 4),
              InfoIcon(metricsByKey[key]?.formula ?? ''),
            ],
          ),
          const SizedBox(height: 4),
          DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 18),
            child: _metricValue(company, key, metricsByKey),
          ),
        ],
      ),
    );
  }
}
