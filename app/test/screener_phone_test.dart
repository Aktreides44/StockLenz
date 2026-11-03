// The screener at phone size (Samsung S24: 384 × 832 logical pixels): cards, sort menu,
// sector ✕ button and the filters bottom sheet.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/screener_cards.dart';
import 'package:stocklens/screener_page.dart';

import 'screener_page_test.dart' show fakeData;

Future<void> pumpPhone(WidgetTester tester) async {
  tester.view.physicalSize = const Size(384 * 3, 832 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: ScreenerPage(loadData: () async => fakeData())));
  await tester.pumpAndSettle();
}

double top(WidgetTester tester, String ticker) => tester.getTopLeft(find.text(ticker)).dy;

void main() {
  testWidgets('phones get cards with three key numbers and nothing overflows', (tester) async {
    await pumpPhone(tester);
    expect(tester.takeException(), isNull); // e.g. "A RenderFlex overflowed"
    expect(find.byType(ScreenerCards), findsOneWidget);
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text('Apple Inc.'), findsOneWidget);
    expect(find.text(r'$5.00T'), findsOneWidget);
    expect(find.text('171.4%'), findsOneWidget);
    expect(find.text('3 of 3'), findsOneWidget);
    // The missing ROE of McDonald's is a dash with the reason, not 0.
    expect(find.byTooltip("Average shareholders' equity is zero or negative"), findsOneWidget);
  });

  testWidgets('the ✕ next to a chosen sector goes back to all sectors', (tester) async {
    await pumpPhone(tester);
    expect(find.byTooltip('Show all sectors'), findsNothing);

    await tester.tap(find.text('All sectors'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consumer Staples').last);
    await tester.pumpAndSettle();
    expect(find.text('1 of 3'), findsOneWidget);

    await tester.tap(find.byTooltip('Show all sectors'));
    await tester.pumpAndSettle();
    expect(find.text('3 of 3'), findsOneWidget);
    expect(find.text('All sectors'), findsOneWidget);
    expect(find.byTooltip('Show all sectors'), findsNothing);
  });

  testWidgets('the Sort menu sorts, and picking the same column again reverses it', (tester) async {
    await pumpPhone(tester);
    expect(top(tester, 'AAPL') < top(tester, 'KO'), isTrue); // default: market cap, highest first

    await tester.tap(find.byTooltip('Sort by'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name').last);
    await tester.pumpAndSettle();
    expect(top(tester, 'AAPL') < top(tester, 'MCD'), isTrue); // Apple, McDonald's, The Coca-Cola Company
    expect(top(tester, 'MCD') < top(tester, 'KO'), isTrue);

    await tester.tap(find.byTooltip('Sort by'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name').last);
    await tester.pumpAndSettle();
    expect(top(tester, 'KO') < top(tester, 'AAPL'), isTrue); // Z→A now
  });

  testWidgets('Filters opens a bottom sheet and its filters apply', (tester) async {
    await pumpPhone(tester);
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The ROE row is the second metric: its "min" box is the 3rd text field in the sheet.
    final sheetFields = find.descendant(of: find.byType(BottomSheet), matching: find.byType(TextField));
    await tester.enterText(sheetFields.at(2), '100');
    await tester.pump();

    await tester.tap(find.byTooltip('Close filters'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('1 of 3'), findsOneWidget); // only Apple has ROE ≥ 100%
    expect(find.text('1'), findsOneWidget); // the badge on the Filters button
  });
}
