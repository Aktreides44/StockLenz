// The Scores tab (v3): Quality and Value chips, the All / Strong / Weak / Cheap / Expensive buttons,
// sector filter and sorting.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stocklens/data_service.dart';
import 'package:stocklens/models.dart';
import 'package:stocklens/screener_page.dart';
import 'package:stocklens/scores_view.dart';

const metrics = [
  MetricDefinition(key: 'market_cap', label: 'Market cap', group: 'Valuation', formula: 'Price × Shares',
      unit: 'USD', higherIsBetter: true),
  MetricDefinition(key: 'quality_score', label: 'Quality (F-Score)', group: 'Scores', formula: 'Piotroski',
      unit: 'score', higherIsBetter: true),
  MetricDefinition(key: 'value_score', label: 'Value (vs sector)', group: 'Scores', formula: 'Sector rank',
      unit: 'score', higherIsBetter: true),
];

Company scored(String ticker, String sector, double? quality, String? qualityLabel, double? value, String? valueLabel) {
  return Company(
    ticker: ticker,
    name: '$ticker Corp.',
    sector: sector,
    price: 100,
    latestFiscalYear: 2025,
    latestFiscalYearEnd: '2025-12-31',
    qualityLabel: qualityLabel,
    valueLabel: valueLabel,
    metrics: {'market_cap': 1e9, 'quality_score': quality, 'value_score': value},
    missingReasons: {
      if (quality == null) 'quality_score': 'Not enough data: 6 of 9 checks can be calculated (needs 7)',
      if (value == null) 'value_score': 'Not enough data: fewer than 2 valuation ratios',
    },
    notApplicable: const [],
  );
}

ScreenerData scoredData() => ScreenerData(metrics: metrics, companies: [
      scored('AAA', 'Energy', 9.0, 'Strong', 8.0, 'Cheap'),
      scored('BBB', 'Energy', 4.5, 'Mixed', 2.0, 'Expensive'),
      scored('CCC', 'Utilities', 1.0, 'Weak', 7.5, 'Cheap'),
      scored('DDD', 'Utilities', 8.0, 'Strong', 5.0, 'Fair'),
      scored('BNK', 'Financials', null, null, null, null),
    ]);

Future<void> pumpScores(WidgetTester tester, {Size size = const Size(1400, 900)}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: ScreenerPage(loadData: () async => scoredData())));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scores'));
  await tester.pumpAndSettle();
}

/// The tickers in the order the Scores list shows them (top to bottom).
List<String> order(WidgetTester tester) {
  final rows = find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith('scores-row-');
  });
  final found = [
    for (final element in rows.evaluate())
      (
        ticker: (element.widget.key! as ValueKey<String>).value.replaceFirst('scores-row-', ''),
        top: tester.getTopLeft(find.byWidget(element.widget)).dy,
      ),
  ]..sort((a, b) => a.top.compareTo(b.top));
  return [for (final row in found) row.ticker];
}

void main() {
  testWidgets('the Scores tab lists every company with both chips, best quality first', (tester) async {
    await pumpScores(tester);
    expect(find.text('9.0 Strong'), findsOneWidget);
    expect(find.text('8.0 Cheap'), findsOneWidget);
    expect(find.text('1.0 Weak'), findsOneWidget);
    expect(find.text('5 of 5'), findsOneWidget);
    expect(order(tester), ['AAA', 'DDD', 'BBB', 'CCC', 'BNK']); // BNK has no score: at the bottom
  });

  testWidgets('a company without a score shows a dash with the reason', (tester) async {
    await pumpScores(tester);
    expect(find.byTooltip('Not enough data: 6 of 9 checks can be calculated (needs 7)'), findsOneWidget);
  });

  testWidgets('the buttons show only Strong, Weak, Cheap or Expensive companies', (tester) async {
    await pumpScores(tester);
    Future<List<String>> pick(String label) async {
      await tester.tap(find.widgetWithText(ChoiceChip, label));
      await tester.pumpAndSettle();
      return order(tester);
    }

    expect(await pick('Strong'), ['AAA', 'DDD']);
    expect(await pick('Weak'), ['CCC']);
    expect(await pick('Cheap'), ['AAA', 'CCC']);
    expect(await pick('Expensive'), ['BBB']);
    expect(await pick('All'), hasLength(5));
  });

  testWidgets('an empty Weak group explains why', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = scoredData();
    final noWeak = ScreenerData(metrics: data.metrics, companies: data.companies.where((c) => c.ticker != 'CCC').toList());
    await tester.pumpWidget(MaterialApp(home: ScreenerPage(loadData: () async => noWeak)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scores'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Weak'));
    await tester.pumpAndSettle();
    expect(find.textContaining('No company is Weak'), findsOneWidget);
  });

  testWidgets('sort by value, and filter by sector', (tester) async {
    await pumpScores(tester);
    await tester.tap(find.widgetWithText(SegmentedButton<ScoreSort>, 'Value'));
    await tester.pumpAndSettle();
    expect(order(tester), ['AAA', 'CCC', 'DDD', 'BBB', 'BNK']);

    await tester.tap(find.text('All sectors'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Utilities').last);
    await tester.pumpAndSettle();
    expect(order(tester), ['CCC', 'DDD']);
    expect(find.text('2 of 5'), findsOneWidget);
  });

  testWidgets('the screener keeps its search text when you switch tabs', (tester) async {
    await pumpScores(tester);
    await tester.tap(find.text('Screener'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'AAA');
    await tester.pump();
    expect(find.text('1 of 5 companies'), findsOneWidget);

    await tester.tap(find.text('Scores'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Screener'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 5 companies'), findsOneWidget);
    expect(find.descendant(of: find.byType(TextField), matching: find.text('AAA')), findsOneWidget);
  });

  testWidgets('phones: tabs in a bar at the bottom, nothing overflows', (tester) async {
    await pumpScores(tester, size: const Size(360, 780));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.text('9.0 Strong'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
