// The company page: one long scrolling page with a sticky section bar at the top.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'company_chart.dart';
import 'company_sections.dart';
import 'data_service.dart';
import 'models.dart';

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
  final Future<CompanyDetail> Function(String ticker, List<MetricDefinition> metrics, {bool offline}) loadDetail;

  @override
  State<CompanyPage> createState() => _CompanyPageState();
}

class _CompanyPageState extends State<CompanyPage> {
  static const sections = [
    'Summary', 'Chart', 'Analysis', 'Peers', 'Profit & Loss', 'Balance Sheet', 'Cash Flow', 'Ratios',
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
    try {
      final detail = await widget.loadDetail(
        widget.ticker,
        widget.screenerData.metrics,
        offline: widget.screenerData.isOffline,
      );
      if (!mounted) return;
      setState(() => _detail = detail);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = 'Could not load ${widget.ticker}: $error');
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
      ),
      body: detail == null
          ? Center(child: _error == null ? const CircularProgressIndicator() : Text(_error!))
          : _buildPage(detail),
    );
  }

  Widget _buildPage(CompanyDetail detail) {
    final colors = Theme.of(context).colorScheme;
    final metricsByKey = {for (final metric in widget.screenerData.metrics) metric.key: metric};
    final years = detail.history;

    Widget section(String name, Widget child) {
      return KeyedSubtree(
        key: _sectionKeys[name],
        child: Padding(padding: const EdgeInsets.only(bottom: 16), child: child),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionBar(sections: sections, active: _activeSection, onTap: _jumpTo),
        if (detail.isOffline)
          Container(
            color: colors.tertiaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Text(
              'Offline snapshot — the API is not reachable, showing saved data.',
              style: TextStyle(color: colors.onTertiaryContainer),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            key: _scrollViewKey,
            controller: _scroll,
            padding: const EdgeInsets.all(16),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    section('Summary', SummarySection(company: detail.company, metricsByKey: metricsByKey)),
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
                        subtitle: "Calculated from each year's 10-K figures. Hover a dash to see why it is missing.",
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
class _SectionBar extends StatelessWidget {
  const _SectionBar({required this.sections, required this.active, required this.onTap});

  final List<String> sections;
  final String active;
  final void Function(String section) onTap;

  @override
  Widget build(BuildContext context) {
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
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                for (final section in sections)
                  InkWell(
                    onTap: () => onTap(section),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: section == active ? colors.primary : Colors.transparent, width: 2),
                        ),
                      ),
                      child: Text(
                        section,
                        style: TextStyle(
                          fontSize: 13,
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
