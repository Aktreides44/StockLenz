import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/company_page.dart';
import 'package:stocklens/company_search.dart';
import 'package:stocklens/models.dart';
import 'package:stocklens/screener_page.dart';

import 'screener_page_test.dart' show company, fakeData;

void main() {
  final companies = [
    company('KVUE', 'Kenvue Inc.', 'Consumer Staples'),
    company('KO', 'The Coca-Cola Company', 'Consumer Staples'),
    company('AMZN', 'Amazon.com Inc.', 'Consumer Discretionary'),
    company('AMD', 'Advanced Micro Devices', 'Information Technology'),
    company('AAPL', 'Apple Inc.', 'Information Technology'),
  ];
  List<String> tickers(List<Company> found) => [for (final c in found) c.ticker];

  test('an exact ticker comes first, then tickers that start with the query', () {
    expect(tickers(findCompanies(companies, 'ko')), ['KO']);
    expect(tickers(findCompanies(companies, 'K')), ['KO', 'KVUE']); // both start with K, A→Z
    expect(tickers(findCompanies(companies, 'am')), ['AMD', 'AMZN']);
  });

  test('names are found too, upper/lower case does not matter', () {
    expect(tickers(findCompanies(companies, 'APPLE')), ['AAPL']);
    expect(tickers(findCompanies(companies, 'coca')), ['KO']);
    // "a" starts the tickers AAPL, AMD, AMZN; Kenvue and Coca-Cola only contain an "a" in the name.
    expect(tickers(findCompanies(companies, 'a')), ['AAPL', 'AMD', 'AMZN', 'KO']);
  });

  test('empty or unknown queries give no matches; at most `limit` results', () {
    expect(findCompanies(companies, '   '), isEmpty);
    expect(findCompanies(companies, 'xyz'), isEmpty);
    expect(findCompanies(companies, 'a', limit: 2), hasLength(2));
  });

  testWidgets('the search in the top bar opens the company page', (tester) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: ScreenerPage(loadData: () async => fakeData())));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Find a company'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'coca');
    await tester.pumpAndSettle();
    expect(find.text('The Coca-Cola Company'), findsWidgets); // in the list and as a suggestion

    await tester.tap(find.widgetWithText(ListTile, 'The Coca-Cola Company'));
    await tester.pump(); // start the page transition
    await tester.pump(const Duration(seconds: 1)); // finish it
    expect(find.byType(CompanyPage), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'KO'), findsOneWidget); // the title shows the ticker while loading
  });
}
