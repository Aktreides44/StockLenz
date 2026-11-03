// The dense screener table. Ticker and name stay frozen on the left while the
// other columns scroll horizontally; both parts scroll vertically together.
import 'package:flutter/material.dart';

import 'format.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets.dart';

const double rowHeight = 32;
const double headerHeight = 48;

class ScreenerColumn {
  const ScreenerColumn({
    required this.key,
    required this.label,
    required this.width,
    this.tooltip,
    this.numeric = true,
  });

  /// "ticker", "name", "sector", "fy", "price" or a metric key.
  final String key;
  final String label;
  final double width;

  /// Shown when hovering the header (e.g. the metric formula).
  final String? tooltip;

  /// Numbers are right-aligned, text is left-aligned.
  final bool numeric;
}

const List<ScreenerColumn> frozenColumns = [
  ScreenerColumn(key: 'ticker', label: 'Ticker', width: 76, numeric: false),
  ScreenerColumn(key: 'name', label: 'Name', width: 200, numeric: false),
];

class ScreenerTable extends StatefulWidget {
  const ScreenerTable({
    super.key,
    required this.companies,
    required this.columns,
    required this.metricsByKey,
    required this.sortKey,
    required this.sortAscending,
    required this.onSort,
    this.onCompanyTap,
  });

  final List<Company> companies;

  /// The columns to the right of the frozen ticker and name columns.
  final List<ScreenerColumn> columns;
  final Map<String, MetricDefinition> metricsByKey;
  final String sortKey;
  final bool sortAscending;
  final void Function(String columnKey) onSort;

  /// Called when a row is clicked (opens the company page).
  final void Function(Company company)? onCompanyTap;

  @override
  State<ScreenerTable> createState() => _ScreenerTableState();
}

class _ScreenerTableState extends State<ScreenerTable> {
  // The frozen part and the scrolling part each have their own vertical list.
  // We keep the two lists at the same scroll position.
  final ScrollController _frozenVertical = ScrollController();
  final ScrollController _bodyVertical = ScrollController();
  final ScrollController _horizontal = ScrollController();
  bool _syncing = false;
  int? _hoveredRow;

  @override
  void initState() {
    super.initState();
    _frozenVertical.addListener(() => _syncVertical(_frozenVertical, _bodyVertical));
    _bodyVertical.addListener(() => _syncVertical(_bodyVertical, _frozenVertical));
  }

  void _syncVertical(ScrollController source, ScrollController target) {
    if (_syncing || !target.hasClients) return;
    _syncing = true;
    if (target.offset != source.offset) target.jumpTo(source.offset);
    _syncing = false;
  }

  @override
  void dispose() {
    _frozenVertical.dispose();
    _bodyVertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  double _totalWidth(List<ScreenerColumn> columns) => columns.fold(0, (sum, column) => sum + column.width);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    // We draw our own scrollbars, so turn off the automatic desktop ones.
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      // One vertical scrollbar on the right edge of the whole table.
      child: Scrollbar(
        controller: _frozenVertical,
        thumbVisibility: true,
        notificationPredicate: (notification) => notification.metrics.axis == Axis.vertical,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Frozen part: ticker + name
            Container(
              width: _totalWidth(frozenColumns) + 1, // + 1 for the border line on the right

              decoration: BoxDecoration(border: Border(right: BorderSide(color: colors.outlineVariant))),
              child: Column(
                children: [
                  _headerRow(frozenColumns),
                  Expanded(child: _rows(frozenColumns, _frozenVertical)),
                ],
              ),
            ),
            // Scrolling part: everything else
            Expanded(
              child: Scrollbar(
                controller: _horizontal,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _horizontal,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: _totalWidth(widget.columns),
                    child: Column(
                      children: [
                        _headerRow(widget.columns),
                        Expanded(child: _rows(widget.columns, _bodyVertical)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerRow(List<ScreenerColumn> columns) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: headerHeight,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(children: [for (final column in columns) _headerCell(column)]),
    );
  }

  Widget _headerCell(ScreenerColumn column) {
    final theme = Theme.of(context);
    final isSorted = widget.sortKey == column.key;
    final label = Flexible(
      child: Text(
        column.label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: column.numeric ? TextAlign.right : TextAlign.left,
        style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
    final arrow = isSorted
        ? Icon(widget.sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
            size: 14, color: theme.colorScheme.primary)
        : const SizedBox(width: Space.md);

    Widget cell = InkWell(
      onTap: () => widget.onSort(column.key),
      child: SizedBox(
        width: column.width,
        height: headerHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.sm),
          child: Row(
            mainAxisAlignment: column.numeric ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: column.numeric ? [arrow, label] : [label, arrow],
          ),
        ),
      ),
    );
    if (column.tooltip != null) {
      cell = Tooltip(message: column.tooltip!, waitDuration: const Duration(milliseconds: 400), child: cell);
    }
    return cell;
  }

  Widget _rows(List<ScreenerColumn> columns, ScrollController controller) {
    return ListView.builder(
      controller: controller,
      itemExtent: rowHeight,
      itemCount: widget.companies.length,
      itemBuilder: (context, index) => _row(index, columns),
    );
  }

  Widget _row(int index, List<ScreenerColumn> columns) {
    final colors = Theme.of(context).colorScheme;
    final Color background;
    if (_hoveredRow == index) {
      background = colors.secondaryContainer.withValues(alpha: 0.5);
    } else if (index.isOdd) {
      background = colors.surfaceContainerLowest;
    } else {
      background = colors.surface;
    }

    final company = widget.companies[index];
    return MouseRegion(
      cursor: widget.onCompanyTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hoveredRow = index),
      onExit: (_) => setState(() => _hoveredRow = null),
      child: GestureDetector(
        onTap: widget.onCompanyTap == null ? null : () => widget.onCompanyTap!(company),
        child: Container(
          decoration: BoxDecoration(
            color: background,
            border: Border(bottom: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.4))),
          ),
          child: Row(children: [for (final column in columns) _cell(company, column)]),
        ),
      ),
    );
  }

  Widget _cell(Company company, ScreenerColumn column) {
    final theme = Theme.of(context);
    final Widget content = switch (column.key) {
      'ticker' => Text(company.ticker,
          style: TextStyle(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
      'name' => Tooltip(
          message: company.name,
          waitDuration: const Duration(milliseconds: 600),
          child: Text(company.name, overflow: TextOverflow.ellipsis),
        ),
      'sector' => Text(company.sector, overflow: TextOverflow.ellipsis),
      'fy' => company.latestFiscalYear == null
          ? const MissingValue('No 10-K data')
          : Tooltip(
              message: 'Fiscal year ended ${company.latestFiscalYearEnd}',
              child: Text('${company.latestFiscalYear}', style: numberStyle),
            ),
      'price' => company.price == null
          ? const MissingValue('No current share price available')
          : Text(formatPrice(company.price!), style: numberStyle),
      _ => _metricCell(company, column.key),
    };

    return SizedBox(
      width: column.width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm),
        child: Align(
          alignment: column.numeric ? Alignment.centerRight : Alignment.centerLeft,
          child: DefaultTextStyle.merge(style: const TextStyle(fontSize: FontSizes.body), child: content),
        ),
      ),
    );
  }

  Widget _metricCell(Company company, String metricKey) {
    final value = company.metrics[metricKey];
    if (value == null) return MissingValue(company.missingReason(metricKey));
    final unit = widget.metricsByKey[metricKey]?.unit ?? 'x';
    return NumberText(formatMetric(value, unit), value: value);
  }
}
