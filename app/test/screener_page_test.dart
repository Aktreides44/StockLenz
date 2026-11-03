import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/data_service.dart';
import 'package:stocklens/models.dart';
import 'package:stocklens/screener_page.dart';

const metrics = [
  MetricDefinition(key: 'market_cap', label: 'Market cap', group: 'Valuation', formula: 'Price × Shares',
      unit: 'USD', higherIsBetter: true),
  MetricDefinition(key: 'roe', label: 'ROE', group: 'Profitability', formula: 'NI / avg equity × 100',
      unit: '%', higherIsBetter: true),
  MetricDefinition(key: 'pe', label: 'P/E (FY)', group: 'Valuation', formula: 'Price / EPS of the latest fiscal year',
      unit: 'x', higherIsBetter: false),
];

Company company(String ticker, String name, String sector, {double? marketCap, double? roe, String? roeReason}) {
  return Company(
    ticker: ticker,
    name: name,
    sector: sector,
    price: 100,
    latestFiscalYear: 2025,
    latestFiscalYearEnd: '2025-12-31',
    metrics: {'market_cap': marketCap, 'roe': roe, 'pe': 20},
    missingReasons: {'roe': ?roeReason},
    notApplicable: const [],
  );
}

ScreenerData fakeData() {
  return ScreenerData(
    metrics: metrics,
    companies: [
      company('AAPL', 'Apple Inc.', 'Information Technology', marketCap: 5e12, roe: 171.4),
      company('KO', 'The Coca-Cola Company', 'Consumer Staples', marketCap: 3e11, roe: 45.0),
      company('MCD', "McDonald's Corporation", 'Consumer Discretionary',
          marketCap: 1.8e11, roeReason: 'Average shareholders\' equity is zero or negative'),
    ],
  );
}

Future<void> pumpPage(WidgetTester tester, ScreenerData data) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: ScreenerPage(loadData: () async => data)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows all companies with formatted values and the (FY) label', (tester) async {
    await pumpPage(tester, fakeData());
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('MCD'), findsOneWidget);
    expect(find.text('3 of 3 companies'), findsOneWidget);
    expect(find.text(r'$5.00T'), findsOneWidget);
    expect(find.text('171.4%'), findsOneWidget);
    expect(find.text('P/E (FY)'), findsOneWidget);
    expect(find.text('2025'), findsNWidgets(3));
  });

  testWidgets('missing value shows a dash with the reason as tooltip', (tester) async {
    await pumpPage(tester, fakeData());
    expect(find.text('—'), findsOneWidget);
    expect(find.byTooltip("Average shareholders' equity is zero or negative"), findsOneWidget);
  });

  testWidgets('search filters by ticker or name', (tester) async {
    await pumpPage(tester, fakeData());
    await tester.enterText(find.byType(TextField), 'coca');
    await tester.pump();
    expect(find.text('KO'), findsOneWidget);
    expect(find.text('AAPL'), findsNothing);
    expect(find.text('1 of 3 companies'), findsOneWidget);
  });

  testWidgets('clicking a header sorts, missing values stay at the bottom', (tester) async {
    await pumpPage(tester, fakeData());
    double top(String ticker) => tester.getTopLeft(find.text(ticker)).dy;

    // Default: market cap, highest first
    expect(top('AAPL') < top('KO'), isTrue);

    await tester.tap(find.text('ROE'));
    await tester.pump();
    expect(top('AAPL') < top('KO'), isTrue); // highest ROE first
    expect(top('KO') < top('MCD'), isTrue); // MCD has no ROE

    await tester.tap(find.text('ROE'));
    await tester.pump();
    expect(top('KO') < top('AAPL'), isTrue); // lowest first now
    expect(top('AAPL') < top('MCD'), isTrue); // missing still at the bottom
  });

  testWidgets("server can't be reached: shows Can't connect, Retry loads the data", (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var calls = 0;
    Future<ScreenerData> load() async {
      calls++;
      if (calls == 1) throw const ApiException('No connection.');
      return fakeData();
    }

    await tester.pumpWidget(MaterialApp(home: ScreenerPage(loadData: load)));
    await tester.pumpAndSettle();
    expect(find.text("Can't connect"), findsOneWidget);
    expect(find.text('No connection.'), findsOneWidget);

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text("Can't connect"), findsNothing);
    expect(find.text('AAPL'), findsOneWidget);
  });

  testWidgets('slow server: "Waking up the server…" appears after a few seconds', (tester) async {
    final answer = Completer<ScreenerData>();
    await tester.pumpWidget(MaterialApp(home: ScreenerPage(loadData: () => answer.future)));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Waking up the server…'), findsNothing);

    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Waking up the server…'), findsOneWidget);

    answer.complete(fakeData());
    await tester.pumpAndSettle();
    expect(find.text('Waking up the server…'), findsNothing);
  });
}
