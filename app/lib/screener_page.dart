// Screen 1: the screener. Search, sector filter, min/max filters and a sortable table.
import 'package:flutter/material.dart';

import 'company_page.dart';
import 'data_service.dart';
import 'filters_panel.dart';
import 'models.dart';
import 'screener_table.dart';
import 'widgets.dart';

class ScreenerPage extends StatefulWidget {
  const ScreenerPage({super.key, this.loadData = loadScreenerData, this.onToggleTheme});

  /// Where the data comes from. Tests pass in fake data here.
  final Future<ScreenerData> Function() loadData;

  /// Switches between light and dark mode; receives the current brightness.
  final void Function(Brightness current)? onToggleTheme;

  @override
  State<ScreenerPage> createState() => _ScreenerPageState();
}

class _ScreenerPageState extends State<ScreenerPage> {
  ScreenerData? _data;
  bool _loading = true;
  String? _error;

  String _search = '';
  String? _sector; // null means all sectors
  final Map<String, RangeFilter> _filters = {};
  bool _showFilters = false;

  String _sortKey = 'market_cap';
  bool _sortAscending = false;

  static const _textColumns = {'ticker', 'name', 'sector'};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.loadData();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
      // A reload failed, but the data loaded earlier is still on screen: just say so.
      if (_data != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error Showing the data loaded earlier.')),
        );
      }
    }
  }

  void _onSort(String columnKey) {
    setState(() {
      if (_sortKey == columnKey) {
        _sortAscending = !_sortAscending;
      } else {
        _sortKey = columnKey;
        // Text sorts A→Z first; numbers sort highest first, like Screener.in.
        _sortAscending = _textColumns.contains(columnKey);
      }
    });
  }

  Object? _sortValue(Company company, String key) {
    return switch (key) {
      'ticker' => company.ticker,
      'name' => company.name.toLowerCase(),
      'sector' => company.sector,
      'fy' => company.latestFiscalYear?.toDouble(),
      'price' => company.price,
      _ => company.metrics[key],
    };
  }

  int _compareCompanies(Company a, Company b) {
    final valueA = _sortValue(a, _sortKey);
    final valueB = _sortValue(b, _sortKey);
    // Missing values always go to the bottom, whatever the sort direction.
    if (valueA == null && valueB == null) return a.ticker.compareTo(b.ticker);
    if (valueA == null) return 1;
    if (valueB == null) return -1;
    final result = (valueA as Comparable).compareTo(valueB);
    return _sortAscending ? result : -result;
  }

  List<Company> _visibleCompanies(List<Company> all) {
    final query = _search.trim().toLowerCase();
    final visible = all.where((company) {
      if (query.isNotEmpty &&
          !company.ticker.toLowerCase().contains(query) &&
          !company.name.toLowerCase().contains(query)) {
        return false;
      }
      if (_sector != null && company.sector != _sector) return false;
      for (final entry in _filters.entries) {
        if (!entry.value.accepts(company.metrics[entry.key])) return false;
      }
      return true;
    }).toList();
    visible.sort(_compareCompanies);
    return visible;
  }

  /// Sector, FY and price, then market cap, then the other metrics in /metrics order.
  List<ScreenerColumn> _scrollingColumns(List<MetricDefinition> metrics) {
    final ordered = [
      ...metrics.where((m) => m.key == 'market_cap'),
      ...metrics.where((m) => m.key != 'market_cap'),
    ];
    return [
      const ScreenerColumn(key: 'sector', label: 'Sector', width: 170, numeric: false),
      const ScreenerColumn(
        key: 'fy',
        label: 'FY',
        width: 64,
        tooltip: 'Latest fiscal year: all 10-K figures in this row come from it.\n'
            'Hover a year to see the fiscal year end date.',
      ),
      const ScreenerColumn(key: 'price', label: 'Price', width: 90, tooltip: 'Latest share price (Yahoo Finance)'),
      for (final metric in ordered)
        ScreenerColumn(key: metric.key, label: metric.label, width: 104, tooltip: '${metric.label}\n${metric.formula}'),
    ];
  }

  int get _activeFilterCount => _filters.values.where((f) => !f.isEmpty).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('StockLens'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'Reload data'),
          if (widget.onToggleTheme != null)
            IconButton(
              onPressed: () => widget.onToggleTheme!(Theme.of(context).brightness),
              icon: const Icon(Icons.brightness_6),
              tooltip: 'Light / dark mode',
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final data = _data;
    if (data == null) {
      if (_loading) return const LoadingMessage();
      return ConnectionError(message: _error ?? 'No data', onRetry: _load);
    }

    final visible = _visibleCompanies(data.companies);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar(data, visible.length),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: visible.isEmpty
                    ? const Center(child: Text('No companies match the search and filters.'))
                    : ScreenerTable(
                        companies: visible,
                        columns: _scrollingColumns(data.metrics),
                        metricsByKey: {for (final m in data.metrics) m.key: m},
                        sortKey: _sortKey,
                        sortAscending: _sortAscending,
                        onSort: _onSort,
                        onCompanyTap: (company) => openCompanyPage(context, company.ticker, data),
                      ),
              ),
              if (_showFilters)
                FiltersPanel(
                  metrics: data.metrics,
                  filters: _filters,
                  onChanged: (key, filter) => setState(() => _filters[key] = filter),
                  onClearAll: () => setState(_filters.clear),
                  onClose: () => setState(() => _showFilters = false),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toolbar(ScreenerData data, int visibleCount) {
    final theme = Theme.of(context);
    final sectors = data.companies.map((c) => c.sector).toSet().toList()..sort();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              onChanged: (text) => setState(() => _search = text),
              decoration: const InputDecoration(
                hintText: 'Search ticker or name',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: theme.colorScheme.outline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _sector,
                onChanged: (sector) => setState(() => _sector = sector),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('All sectors')),
                  for (final sector in sectors) DropdownMenuItem<String?>(value: sector, child: Text(sector)),
                ],
              ),
            ),
          ),
          Badge(
            isLabelVisible: _activeFilterCount > 0,
            label: Text('$_activeFilterCount'),
            child: OutlinedButton.icon(
              onPressed: () => setState(() => _showFilters = !_showFilters),
              icon: const Icon(Icons.filter_list),
              label: const Text('Filters'),
            ),
          ),
          Text(
            '$visibleCount of ${data.companies.length} companies',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
