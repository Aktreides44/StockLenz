import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/company_page.dart';
import 'package:stocklens/data_service.dart';
import 'package:stocklens/models.dart';

const metrics = [
  MetricDefinition(key: 'market_cap', label: 'Market cap', group: 'Valuation', formula: 'Price × Shares',
      unit: 'USD', higherIsBetter: true),
  MetricDefinition(key: 'roe', label: 'ROE', group: 'Profitability', formula: 'NI / avg equity × 100',
      unit: '%', higherIsBetter: true),
  MetricDefinition(key: 'net_margin', label: 'Net margin', group: 'Profitability', formula: 'NI / Rev × 100',
      unit: '%', higherIsBetter: true),
  MetricDefinition(key: 'operating_margin', label: 'Operating margin', group: 'Profitability',
      formula: 'OpInc / Rev × 100', unit: '%', higherIsBetter: true),
  MetricDefinition(key: 'pe', label: 'P/E (FY)', group: 'Valuation', formula: 'Price / EPS of the latest fiscal year',
      unit: 'x', higherIsBetter: false),
];

Company company(String ticker, String name, String sector, double marketCap) {
  return Company(
    ticker: ticker,
    name: name,
    sector: sector,
    cik: 320193,
    price: 343.91,
    priceFetchedAt: '2026-10-27T09:04:12',
    latestFiscalYear: 2025,
    latestFiscalYearEnd: '2025-09-27',
    metrics: {'market_cap': marketCap, 'roe': 171.4, 'net_margin': 26.9, 'operating_margin': null, 'pe': 46.1},
    missingReasons: const {'operating_margin': 'Operating income not reported in the FY2025 10-K'},
    notApplicable: const [],
  );
}

YearData year(int fiscalYear, double revenue, double? netIncome) {
  return YearData(
    fiscalYear: fiscalYear,
    endDate: '$fiscalYear-09-27',
    values: {'revenue': revenue, 'net_income': netIncome, 'operating_income': null, 'fcf': -5e9},
    tags: const {'revenue': 'Revenues', 'net_income': 'NetIncomeLoss', 'operating_income': null},
    ratios: const {'net_margin': 25.0, 'roe': null},
    ratioMissingReasons: const {'roe': 'No 10-K data for FY2023'},
  );
}

final screenerData = ScreenerData(
  metrics: metrics,
  companies: [
    company('AAPL', 'Apple Inc.', 'Information Technology', 5e12),
    company('MSFT', 'Microsoft Corporation', 'Information Technology', 4e12),
    company('KO', 'The Coca-Cola Company', 'Consumer Staples', 3e11),
  ],
);

CompanyDetail appleDetail() {
  return CompanyDetail(
    company: screenerData.companies.first,
    history: [year(2024, 391035e6, 93736e6), year(2025, 416161e6, null)],
    pros: const [AnalysisPoint(id: 'high_roe', text: 'Strong return on equity: ROE of 171.4% (above 15%)')],
    cons: const [AnalysisPoint(id: 'high_pe', text: 'Expensive on earnings: P/E (FY) of 46.1 (above 40)')],
    );
}

Future<void> pumpApplePage(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: CompanyPage(
      ticker: 'AAPL',
      screenerData: screenerData,
      loadDetail: (ticker, metrics) async => appleDetail(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('summary shows name, price with date, SEC link and key ratios', (tester) async {
    await pumpApplePage(tester);
    expect(find.text('Apple Inc.'), findsOneWidget);
    expect(find.text('as of 27 Oct 2026'), findsOneWidget);
    expect(find.text('SEC filings'), findsOneWidget);
    expect(find.text('P/E (FY)'), findsWidgets);
    expect(find.text('46.10'), findsWidgets); // key ratios (and MSFT in peers has the same fake P/E)
    // Missing operating margin: dash with the reason as tooltip
    expect(find.byTooltip('Operating income not reported in the FY2025 10-K'), findsWidgets);
  });

  testWidgets('section bar has all sections', (tester) async {
    await pumpApplePage(tester);
    for (final name in ['Summary', 'Chart', 'Analysis', 'Peers', 'Balance Sheet', 'Cash Flow', 'Ratios']) {
      expect(find.text(name), findsWidgets, reason: name);
    }
  });

  testWidgets('pros and cons with the not-advice note', (tester) async {
    await pumpApplePage(tester);
    expect(find.text('Pros'), findsOneWidget);
    expect(find.text('Cons'), findsOneWidget);
    expect(find.text('Strong return on equity: ROE of 171.4% (above 15%)'), findsOneWidget);
    expect(find.textContaining('not investment advice'), findsOneWidget);
  });

  testWidgets('peers show other companies in the same sector only', (tester) async {
    await pumpApplePage(tester);
    expect(find.text('MSFT'), findsOneWidget);
    expect(find.text('KO'), findsNothing);
  });

  testWidgets('financial tables: years as columns, millions, missing as dash', (tester) async {
    await pumpApplePage(tester);
    expect(find.text('FY2024'), findsWidgets);
    expect(find.text('391,035'), findsOneWidget);
    expect(find.text('416,161'), findsOneWidget);
    expect(find.text('-5,000'), findsWidgets); // negative FCF
    expect(find.byTooltip('Net income not reported in the FY2025 10-K'), findsOneWidget);
    expect(find.byTooltip('No 10-K data for FY2023'), findsWidgets); // yearly ROE
  });

  testWidgets('no layout overflow in a small window', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: CompanyPage(
        ticker: 'AAPL',
        screenerData: screenerData,
        loadDetail: (ticker, metrics) async => appleDetail(),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('clicking a section in the bar scrolls to it', (tester) async {
    await pumpApplePage(tester);
    await tester.tap(find.text('Ratios').first);
    await tester.pumpAndSettle();
    expect(find.text('Calculated from each year\'s 10-K figures. Hover or press and hold a dash to see why it is missing.'),
        findsOneWidget);
  });
}
