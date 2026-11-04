// The sections of the company page: summary, analysis, peers and the financial tables.
import 'package:flutter/material.dart';

import 'format.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets.dart';

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
    final phone = isPhone(context);
    final titleText = Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600));
    final subtitleText = subtitle == null
        ? null
        : Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant));
    return Container(
      padding: EdgeInsets.all(phone ? Space.md : Space.lg),
      decoration: BoxDecoration(
        color: cardBackground(theme.colorScheme),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(Radii.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wide screens: title and explanation on one line. Phones: the explanation goes below.
          if (phone) ...[
            titleText,
            if (subtitleText != null) ...[const SizedBox(height: Space.xxs), subtitleText],
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                titleText,
                if (subtitleText != null) ...[const SizedBox(width: Space.sm), Flexible(child: subtitleText)],
              ],
            ),
          const SizedBox(height: Space.md),
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
    'market_cap', 'price', 'pe', 'pe_ttm', 'pb', 'ps', 'ps_ttm',
    'roe', 'roa', 'net_margin', 'operating_margin', 'debt_to_equity', 'current_ratio', 'revenue_growth',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Container(
      padding: EdgeInsets.all(isPhone(context) ? Space.md : Space.xl),
      decoration: BoxDecoration(
        color: cardBackground(theme.colorScheme),
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(Radii.medium),
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
                    const SizedBox(height: Space.sm),
                    Wrap(
                      spacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xxs),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(Radii.small),
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
          const SizedBox(height: Space.lg),
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
          const SizedBox(height: Space.md),
          Text(
            'Ratios use the FY${company.latestFiscalYear} 10-K (year ended ${company.latestFiscalYearEnd}) '
            'and the latest price. (FY) multiples are not trailing-12-month figures'
            '${company.ttmEnd == null ? '.' : '; (TTM) multiples cover the 12 months to ${formatDate(company.ttmEnd!)}.'}',
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
      formula = company.priceSource == null
          ? 'Latest share price'
          : 'Latest share price: ${company.priceSource}'
              '${company.priceFetchedAt == null ? '' : ', ${formatDate(company.priceFetchedAt!)}'}';
      value = company.price == null
          ? const MissingValue('No current share price available')
          : NumberText(formatPrice(company.price!), value: company.price!, bold: true);
    } else {
      label = metricsByKey[key]?.label ?? key;
      final definition = metricsByKey[key]?.formula ?? '';
      // Market cap: also say where the number of shares comes from.
      if (key == 'market_cap' && company.sharesSource != null) {
        final asOf = company.sharesAsOf == null ? '' : ', ${formatDate(company.sharesAsOf!)}';
        formula = '$definition\nShares: ${company.sharesSource}$asOf';
      } else if (key.endsWith('_ttm') && company.ttmEnd != null) {
        // (TTM) metrics: say which 12 months they cover.
        formula = '$definition\nLast 12 months to ${formatDate(company.ttmEnd!)}';
      } else {
        formula = definition;
      }
      value = _metricValue(company, key, metricsByKey);
    }

    return Container(
      height: 38,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)))),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: FontSizes.body, color: colors.onSurfaceVariant)),
          const SizedBox(width: Space.xs),
          InfoIcon(formula),
          const Spacer(),
          DefaultTextStyle.merge(style: const TextStyle(fontSize: FontSizes.medium), child: value),
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
            if (constraints.maxWidth < 600) return Column(children: [pros, const SizedBox(height: Space.md), cons]);
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [Expanded(child: pros), const SizedBox(width: Space.lg), Expanded(child: cons)],
              ),
            );
          }),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: colors.outline),
              const SizedBox(width: Space.sm),
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
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(color: tint.withValues(alpha: 0.35), borderRadius: BorderRadius.circular(Radii.medium)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: accent, fontSize: FontSizes.title)),
          const SizedBox(height: Space.sm),
          if (items.isEmpty)
            Text('No rule triggered.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('•  ', style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
                  Expanded(
                    child: Tooltip(
                      message: 'Rule: ${item.id}',
                      waitDuration: const Duration(milliseconds: 600),
                      child: Text(item.text, style: const TextStyle(fontSize: FontSizes.body)),
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

  /// Phones have room for fewer columns: the same three numbers as the screener cards.
  static const _phoneColumns = ['market_cap', 'pe', 'roe'];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final columns = isPhone(context) ? _phoneColumns : _columns;
    final peers = allCompanies.where((c) => c.sector == company.sector && c.ticker != company.ticker).toList()
      ..sort((a, b) => (b.metrics['market_cap'] ?? -1).compareTo(a.metrics['market_cap'] ?? -1));

    if (peers.isEmpty) {
      return SectionCard(
        title: 'Peers',
        child: Text('No other StockLens companies in ${company.sector}.'),
      );
    }

    String label(String key) => key == 'price' ? 'Price' : (metricsByKey[key]?.label ?? key);
    const headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: FontSizes.small);

    return SectionCard(
      title: 'Peers',
      subtitle: 'Other StockLens companies in ${company.sector}. Tap one to open it.',
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontSize: FontSizes.body),
        child: Column(
          children: [
            Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: Space.sm),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.outlineVariant))),
              child: Row(
                children: [
                  const Expanded(flex: 3, child: Text('Name', style: headerStyle)),
                  for (final key in columns)
                    Expanded(
                      flex: 2,
                      child: Tooltip(
                        message: metricsByKey[key]?.formula ?? 'Latest closing price (Polygon; Yahoo Finance as backup)',
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
                  padding: const EdgeInsets.symmetric(horizontal: Space.sm),
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
                      for (final key in columns)
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

  // Sizes when the table does not fit (phones). Every row gets the same fixed height,
  // so the fixed labels on the left line up with the scrolling numbers on the right.
  static const double narrowLabelWidth = 136;
  static const double narrowYearWidth = 96;
  static const double narrowHeaderHeight = 44;
  static const double narrowRowHeight = 40;

  static const cellPadding = EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.sm);

  @override
  Widget build(BuildContext context) {
    final minWidth = labelWidth + yearWidth * years.length;
    return DefaultTextStyle.merge(
      style: const TextStyle(fontSize: FontSizes.body),
      child: LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth >= minWidth ? _fullTable(context) : _tableWithFixedLabels(context),
      ),
    );
  }

  /// Wide screens: one table, all years visible.
  Widget _fullTable(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Table(
      columnWidths: const {0: FixedColumnWidth(labelWidth)},
      defaultColumnWidth: const FlexColumnWidth(),
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: _headerDecoration(colors),
          children: [
            const SizedBox.shrink(),
            for (final year in years) Padding(padding: cellPadding, child: _yearHeader(context, year)),
          ],
        ),
        for (var i = 0; i < rows.length; i++)
          TableRow(
            decoration: _rowDecoration(colors, i),
            children: [
              Padding(padding: cellPadding, child: _label(rows[i])),
              for (final year in years) Padding(padding: cellPadding, child: _value(rows[i], year)),
            ],
          ),
      ],
    );
  }

  /// Narrow screens: the labels stay on the left while the years scroll sideways.
  /// `reverse: true` starts the scrolling part at its right end, so the newest year is visible first.
  Widget _tableWithFixedLabels(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const sidePadding = EdgeInsets.symmetric(horizontal: Space.sm);

    final labels = Container(
      width: narrowLabelWidth,
      decoration: BoxDecoration(border: Border(right: BorderSide(color: colors.outlineVariant))),
      child: Column(
        children: [
          Container(height: narrowHeaderHeight, decoration: _headerDecoration(colors)),
          for (var i = 0; i < rows.length; i++)
            Container(
              height: narrowRowHeight,
              padding: sidePadding,
              alignment: Alignment.centerLeft,
              decoration: _rowDecoration(colors, i),
              child: _label(rows[i], maxLines: 2),
            ),
        ],
      ),
    );

    final numbers = Column(
      children: [
        Container(
          height: narrowHeaderHeight,
          decoration: _headerDecoration(colors),
          child: Row(
            children: [
              for (final year in years)
                SizedBox(width: narrowYearWidth, child: Padding(padding: sidePadding, child: _yearHeader(context, year))),
            ],
          ),
        ),
        for (var i = 0; i < rows.length; i++)
          Container(
            height: narrowRowHeight,
            decoration: _rowDecoration(colors, i),
            child: Row(
              children: [
                for (final year in years)
                  SizedBox(width: narrowYearWidth, child: Padding(padding: sidePadding, child: _value(rows[i], year))),
              ],
            ),
          ),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        labels,
        Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true, child: numbers)),
      ],
    );
  }

  BoxDecoration _headerDecoration(ColorScheme colors) =>
      BoxDecoration(border: Border(bottom: BorderSide(color: colors.outlineVariant)));

  /// Every other row is slightly tinted, which makes long rows easier to follow.
  BoxDecoration _rowDecoration(ColorScheme colors, int index) => BoxDecoration(
        color: index.isOdd ? colors.surfaceContainerHighest.withValues(alpha: 0.25) : null,
        border: Border(bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.4))),
      );

  /// "FY2025" with the month the fiscal year ended under it.
  Widget _yearHeader(BuildContext context, YearData year) {
    return Tooltip(
      message: 'Fiscal year ended ${year.endDate}',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // maxLines: 1 keeps each line on one line, so the heading always fits its height.
          Text('FY${year.fiscalYear}', maxLines: 1, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(
            formatMonthYear(year.endDate),
            maxLines: 1,
            style: TextStyle(fontSize: FontSizes.tiny, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _label(YearTableRow row, {int? maxLines}) {
    return Row(
      children: [
        Flexible(
          child: Text(
            row.label,
            maxLines: maxLines,
            overflow: maxLines == null ? null : TextOverflow.ellipsis,
            style: TextStyle(fontWeight: row.bold ? FontWeight.bold : FontWeight.normal),
          ),
        ),
        if (row.labelTooltip != null) ...[const SizedBox(width: Space.xs), InfoIcon(row.labelTooltip!)],
      ],
    );
  }

  Widget _value(YearTableRow row, YearData year) {
    return Align(
      alignment: Alignment.centerRight,
      child: DefaultTextStyle.merge(
        style: TextStyle(fontWeight: row.bold ? FontWeight.bold : FontWeight.normal),
        child: row.cell(year),
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
    this.subtitle = 'Figures in USD millions · source: SEC 10-K filings (XBRL). '
        'Hover or press and hold a number to see its tag.',
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
          if (footer != null) ...[const SizedBox(height: Space.lg), footer!],
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
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(Radii.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: Text(label, style: TextStyle(fontSize: FontSizes.small, color: colors.onSurfaceVariant))),
              const SizedBox(width: Space.xs),
              InfoIcon(metricsByKey[key]?.formula ?? ''),
            ],
          ),
          const SizedBox(height: Space.xs),
          DefaultTextStyle.merge(
            style: const TextStyle(fontSize: FontSizes.large),
            child: _metricValue(company, key, metricsByKey),
          ),
        ],
      ),
    );
  }
}
