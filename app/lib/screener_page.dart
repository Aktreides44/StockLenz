// Screen 1: the screener. Search, sector filter, min/max filters and a sortable list of companies.
// Wide screens get the dense table with a filter panel on the right; phones get cards,
// a "Sort" menu and the filters in a bottom sheet.
import 'package:flutter/material.dart';

import 'company_page.dart';
import 'company_search.dart';
import 'data_service.dart';
import 'filters_panel.dart';
import 'models.dart';
import 'screener_cards.dart';
import 'screener_table.dart';
import 'theme.dart';
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
      const ScreenerColumn(key: 'price', label: 'Price', width: 90, tooltip: 'Latest closing price (Polygon; Yahoo Finance as backup)'),
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
          // Jump straight to a company (only once the list of companies has loaded).
          if (_data != null)
            CompanySearchButton(
              companies: _data!.companies,
              onSelected: (company) => openCompanyPage(context, company.ticker, _data!),
            ),
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'Reload data'),
          if (widget.onToggleTheme != null)
            IconButton(
              onPressed: () => widget.onToggleTheme!(Theme.of(context).brightness),
              icon: const Icon(Icons.brightness_6),
              tooltip: 'Light / dark mode',
            ),
          const SizedBox(width: Space.sm),
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
    final metricsByKey = {for (final m in data.metrics) m.key: m};
    final columns = _scrollingColumns(data.metrics);

    if (isPhone(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _phoneToolbar(data, visible.length, columns),
          Expanded(
            child: visible.isEmpty
                ? const Center(child: Text('No companies match the search and filters.'))
                : ScreenerCards(
                    companies: visible,
                    metricsByKey: metricsByKey,
                    onCompanyTap: (company) => openCompanyPage(context, company.ticker, data),
                  ),
          ),
        ],
      );
    }

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
                        columns: columns,
                        metricsByKey: metricsByKey,
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

  /// Wide screens: everything on one line (it wraps if the window is narrow).
  Widget _toolbar(ScreenerData data, int visibleCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.lg, Space.md),
      child: Wrap(
        spacing: Space.md,
        runSpacing: Space.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(width: 280, child: _searchBox()),
          _sectorPicker(data, expand: false),
          _filtersButton(onPressed: () => setState(() => _showFilters = !_showFilters)),
          _countText('$visibleCount of ${data.companies.length} companies'),
        ],
      ),
    );
  }

  /// Phones: search, sector and "Filters / Sort / count" each get their own line.
  Widget _phoneToolbar(ScreenerData data, int visibleCount, List<ScreenerColumn> columns) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.md, Space.md, Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _searchBox(),
          const SizedBox(height: Space.sm),
          _sectorPicker(data, expand: true),
          const SizedBox(height: Space.sm),
          Row(
            children: [
              _filtersButton(onPressed: () => _openFiltersSheet(data)),
              const SizedBox(width: Space.sm),
              // The Sort button may use all the free space; a long label ends with "…".
              Expanded(child: Align(alignment: Alignment.centerLeft, child: _sortMenu(columns))),
              const SizedBox(width: Space.sm),
              _countText('$visibleCount of ${data.companies.length}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _searchBox() {
    return TextField(
      onChanged: (text) => setState(() => _search = text),
      decoration: const InputDecoration(
        hintText: 'Filter list by ticker or name',
        prefixIcon: Icon(Icons.search),
        isDense: true,
        border: OutlineInputBorder(),
      ),
    );
  }

  /// The sector dropdown. Once a sector is chosen, a ✕ button next to it goes back to all sectors.
  Widget _sectorPicker(ScreenerData data, {required bool expand}) {
    final theme = Theme.of(context);
    final sectors = data.companies.map((c) => c.sector).toSet().toList()..sort();
    final dropdown = DropdownButtonHideUnderline(
      child: DropdownButton<String?>(
        value: _sector,
        isExpanded: expand,
        onChanged: (sector) => setState(() => _sector = sector),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('All sectors')),
          for (final sector in sectors) DropdownMenuItem<String?>(value: sector, child: Text(sector)),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.only(left: Space.md),
      decoration: BoxDecoration(
        // The border turns to the brand colour while a sector is chosen, so you can see a filter is on.
        border: Border.all(color: _sector == null ? theme.colorScheme.outline : theme.colorScheme.primary),
        borderRadius: BorderRadius.circular(Radii.small),
      ),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          if (expand) Expanded(child: dropdown) else dropdown,
          if (_sector != null)
            IconButton(
              onPressed: () => setState(() => _sector = null),
              icon: const Icon(Icons.close),
              tooltip: 'Show all sectors',
              visualDensity: VisualDensity.compact,
            )
          else
            const SizedBox(width: Space.md),
        ],
      ),
    );
  }

  Widget _filtersButton({required VoidCallback onPressed}) {
    return Badge(
      isLabelVisible: _activeFilterCount > 0,
      label: Text('$_activeFilterCount'),
      child: OutlinedButton.icon(onPressed: onPressed, icon: const Icon(Icons.filter_list), label: const Text('Filters')),
    );
  }

  Widget _countText(String text) {
    final theme = Theme.of(context);
    return Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant));
  }

  /// Phones have no column headers to click, so sorting is a menu. Picking the column that is
  /// already sorted reverses the order, just like clicking a header twice.
  Widget _sortMenu(List<ScreenerColumn> columns) {
    final options = [...frozenColumns, ...columns];
    final current = options.firstWhere((o) => o.key == _sortKey, orElse: () => options.first);
    return MenuAnchor(
      menuChildren: [
        for (final option in options)
          MenuItemButton(
            onPressed: () => _onSort(option.key),
            // A tick in front of the column that is sorted now.
            leadingIcon: option.key == _sortKey ? const Icon(Icons.check) : const SizedBox(width: 24),
            child: Text(option.label),
          ),
      ],
      // The button looks like "Filters": an arrow for the direction and the column name.
      builder: (context, controller, _) => Tooltip(
        message: 'Sort by',
        child: OutlinedButton.icon(
          onPressed: () => controller.isOpen ? controller.close() : controller.open(),
          icon: Icon(_sortAscending ? Icons.arrow_upward : Icons.arrow_downward),
          label: Text(current.label, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }

  /// Phones: the filters slide up from the bottom instead of opening on the side.
  void _openFiltersSheet(ScreenerData data) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true, // lets the sheet be taller than half the screen
      useSafeArea: true,
      clipBehavior: Clip.antiAlias,
      builder: (sheetContext) => Padding(
        // Move up when the keyboard opens, so the boxes stay visible.
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
        child: FractionallySizedBox(
          heightFactor: 0.85,
          child: FiltersPanel(
            asSheet: true,
            metrics: data.metrics,
            filters: _filters,
            onChanged: (key, filter) => setState(() => _filters[key] = filter),
            onClearAll: () => setState(_filters.clear),
            onClose: () => Navigator.of(sheetContext).pop(),
          ),
        ),
      ),
    );
  }
}
