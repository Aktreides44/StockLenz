// The watchlist: ☆ next to every company, "Watchlist" shows only those, saved on the device (simulated here).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stocklens/company_page.dart';
import 'package:stocklens/device_settings.dart';
import 'package:stocklens/screener_page.dart';

import 'screener_page_test.dart' show fakeData;

Future<void> pumpScreener(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: ScreenerPage(loadData: () async => fakeData())));
  await tester.pumpAndSettle();
}

void main() {
  test('the watchlist is saved and loaded again', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await loadWatchlist(), isEmpty);
    await saveWatchlist({'KO', 'AAPL'});
    expect(await loadWatchlist(), {'AAPL', 'KO'});
  });

  testWidgets('wide screen: star a company, show only the watchlist, remove it again', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpScreener(tester, const Size(1600, 900));
    expect(find.text('Watchlist (0)'), findsOneWidget);

    await tester.tap(find.byTooltip('Add AAPL to watchlist'));
    await tester.pumpAndSettle();
    expect(await loadWatchlist(), {'AAPL'});
    expect(find.text('Watchlist (1)'), findsOneWidget);
    expect(find.byTooltip('Remove AAPL from watchlist'), findsOneWidget);

    await tester.tap(find.text('Watchlist (1)'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 3 companies'), findsOneWidget);
    expect(find.text('KO'), findsNothing);

    await tester.tap(find.byTooltip('Remove AAPL from watchlist'));
    await tester.pumpAndSettle();
    expect(find.text('0 of 3 companies'), findsOneWidget);
    expect(find.textContaining('Your watchlist is empty'), findsOneWidget);
    expect(await loadWatchlist(), isEmpty);
  });

  testWidgets('a saved watchlist is used when the app starts; tapping a star does not open the company', (tester) async {
    SharedPreferences.setMockInitialValues({'watchlist': ['KO']});
    await pumpScreener(tester, const Size(1600, 900));
    expect(find.text('Watchlist (1)'), findsOneWidget);
    expect(find.byTooltip('Remove KO from watchlist'), findsOneWidget);

    await tester.tap(find.byTooltip('Add MCD to watchlist'));
    await tester.pumpAndSettle();
    expect(find.byType(CompanyPage), findsNothing); // the star took the tap, not the row
  });

  testWidgets('phones: star on the card and a watchlist button next to the sector', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpScreener(tester, const Size(390, 844));

    await tester.tap(find.byTooltip('Add KO to watchlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Show only my watchlist (1)'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 3'), findsOneWidget);
    expect(find.text('AAPL'), findsNothing);
    expect(tester.takeException(), isNull); // nothing overflows

    await tester.tap(find.byTooltip('Show all companies'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 3'), findsOneWidget);
  });

  testWidgets('the company page has the same star, and the screener sees the change', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpScreener(tester, const Size(1600, 900));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(MaterialPageRoute<void>(
      builder: (_) => CompanyPage(
        ticker: 'MCD',
        screenerData: fakeData(),
        loadDetail: (ticker, metrics) async => throw Exception('not needed here'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Add MCD to watchlist'));
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();

    expect(find.text('Watchlist (1)'), findsOneWidget);
    expect(find.byTooltip('Remove MCD from watchlist'), findsOneWidget);
    expect(await loadWatchlist(), {'MCD'});
  });
}
