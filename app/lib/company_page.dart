// The company page: one long scrolling page with a sticky section bar at the top.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'company_chart.dart';
import 'company_scores.dart';
import 'company_sections.dart';
import 'data_service.dart';
import 'models.dart';
import 'price_chart.dart';
import 'theme.dart';
import 'watchlist.dart';
import 'widgets.dart';

/// Open the page for [ticker]. [data] is the screener data (used for peers and metric labels).
void openCompanyPage(BuildContext context, String ticker, ScreenerData data) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => CompanyPage(ticker: ticker, screenerData: data)),
  );
}

class CompanyPage extends StatefulWidget {
  const CompanyPage({
    super.key,
    required this.ticker,
    required this.screenerData,
    this.loadDetail = loadCompanyDetail,
  });

  final String ticker;
  final ScreenerData screenerData;

  /// Where the details come from. Tests pass in fake data here.
  final Future<CompanyDetail> Function(String ticker, List<MetricDefinition> metrics) loadDetail;

  @override
  State<CompanyPage> createState() => _CompanyPageState();
}

class _CompanyPageState extends State<CompanyPage> {
  static const sections = [
    'Summary', 'Scores', 'Price', 'Chart', 'Analysis', 'Peers', 'Profit & Loss', 'Balance Sheet', 'Cash Flow', 'Ratios',
  ];

  // Each section gets a key, so we can find where it is and scroll to it.
  final Map<String, GlobalKey> _sectionKeys = {for (final section in sections) section: GlobalKey()};
  final GlobalKey _scrollViewKey = GlobalKey();
  final ScrollController _scroll = ScrollController();
  String _activeSection = sections.first;

  CompanyDetail? _detail;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_updateActiveSection);
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final detail = await widget.loadDetail(widget.ticker, widget.screenerData.metrics);
      if (!mounted) return;
      setState(() => _detail = detail);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  void _jumpTo(String section) {
    final sectionContext = _sectionKeys[section]!.currentContext;
    if (sectionContext == null) return;
    Scrollable.ensureVisible(sectionContext, duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
  }

  /// Highlight the section whose top has most recently scrolled past the top of the page.
  void _updateActiveSection() {
    final viewport = _scrollViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewport == null) return;

    var active = sections.first;
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 4) {
      active = sections.last; // at the very bottom, the last section can never reach the top
    } else {
      for (final section in sections) {
        final box = _sectionKeys[section]!.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) continue;
        final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
        if (top <= 40) active = section;
      }
    }
    if (active != _activeSection) setState(() => _activeSection = active);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final detail = _detail;
    return Scaffold(
      backgroundColor: pageBackground(colors),
      appBar: AppBar(
        backgroundColor: cardBackground(colors),
        title: Text(detail == null ? widget.ticker : '${detail.company.name} (${detail.company.ticker})'),
        actions: [WatchStar(ticker: widget.ticker), const SizedBox(width: Space.sm)],
      ),
      body: detail == null
          ? (_error == null ? const LoadingMessage() : ConnectionError(message: _error!, onRetry: _load))
          : _buildPage(detail),
    );
  }

  Widget _buildPage(CompanyDetail detail) {
    final metricsByKey = {for (final metric in widget.screenerData.metrics) metric.key: metric};
    final years = detail.history;

    Widget section(String name, Widget child) {
      return KeyedSubtree(
        key: _sectionKeys[name],
        child: Padding(padding: const EdgeInsets.only(bottom: Space.lg), child: child),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionBar(sections: sections, active: _activeSection, onTap: _jumpTo),
        Expanded(
          child: SingleChildScrollView(
            key: _scrollViewKey,
            controller: _scroll,
            padding: EdgeInsets.all(isPhone(context) ? Space.sm : Space.lg), // phones: more room for numbers
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    section('Summary', SummarySection(company: detail.company, metricsByKey: metricsByKey)),
                    section('Scores', ScoresSection(company: detail.company, scores: detail.scores)),
                    section(
                      'Price',
                      SectionCard(
                        title: 'Share price',
                        subtitle: 'Daily closing prices (Polygon), adjusted for stock splits',
                        child: PriceChart(history: detail.priceHistory),
                      ),
                    ),
                    section(
                      'Chart',
                      SectionCard(
                        title: 'Revenue and net income',
                        subtitle: 'Last ${math.min(5, years.length)} fiscal years',
                        child: RevenueIncomeChart(history: years),
                      ),
                    ),
                    section('Analysis', AnalysisSection(detail: detail)),
                    section(
                      'Peers',
                      PeersSection(
                        company: detail.company,
                        allCompanies: widget.screenerData.companies,
                        metricsByKey: metricsByKey,
                        onOpen: (ticker) => openCompanyPage(context, ticker, widget.screenerData),
                      ),
                    ),
                    section(
                      'Profit & Loss',
                      StatementSection(
                        title: 'Profit & Loss',
                        years: years,
                        rows: profitAndLossRows(),
                        footer: ProfitAndLossSummary(company: detail.company, metricsByKey: metricsByKey),
                      ),
                    ),
                    section('Balance Sheet', StatementSection(title: 'Balance Sheet', years: years, rows: balanceSheetRows())),
                    section('Cash Flow', StatementSection(title: 'Cash Flow', years: years, rows: cashFlowRows())),
                    section(
                      'Ratios',
                      StatementSection(
                        title: 'Ratios',
                        subtitle: "Calculated from each year's 10-K figures. Hover or press and hold a dash to see why it is missing.",
                        years: years,
                        rows: ratioRows(metricsByKey),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The sticky bar with links to each section. It sits above the scrolling area,
/// so it always stays visible.
class _SectionBar extends StatefulWidget {
  const _SectionBar({required this.sections, required this.active, required this.onTap});

  final List<String> sections;
  final String active;
  final void Function(String section) onTap;

  @override
  State<_SectionBar> createState() => _SectionBarState();
}

class _SectionBarState extends State<_SectionBar> {
  late final Map<String, GlobalKey> _tabKeys = {for (final section in widget.sections) section: GlobalKey()};

  @override
  void didUpdateWidget(_SectionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // On a phone the bar is wider than the screen: when the active section changes,
    // slide the bar so that its tab is visible (after this frame is drawn).
    if (oldWidget.active != widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final tabContext = _tabKeys[widget.active]?.currentContext;
        if (tabContext != null && tabContext.mounted) {
          Scrollable.ensureVisible(tabContext, alignment: 0.5, duration: const Duration(milliseconds: 200));
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections = widget.sections;
    final active = widget.active;
    final onTap = widget.onTap;
    final colors = Theme.of(context).colorScheme;
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: cardBackground(colors),
        border: Border(bottom: BorderSide(color: colors.outlineVariant)),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1132),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Space.sm),
            child: Row(
              children: [
                for (final section in sections)
                  InkWell(
                    key: _tabKeys[section],
                    onTap: () => onTap(section),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: Space.md),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: section == active ? colors.primary : Colors.transparent, width: 2),
                        ),
                      ),
                      child: Text(
                        section,
                        style: TextStyle(
                          fontSize: FontSizes.body,
                          fontWeight: section == active ? FontWeight.w600 : FontWeight.normal,
                          color: section == active ? colors.primary : colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
