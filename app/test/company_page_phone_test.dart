// The company page at phone size (Samsung S24: 384 × 832 logical pixels).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/company_page.dart';
import 'package:stocklens/company_sections.dart';
import 'package:stocklens/models.dart';

import 'company_page_test.dart' show appleDetail, screenerData, year;

/// Apple with five fiscal years (2021–2025), so the tables are too wide for a phone.
CompanyDetail appleFiveYears() {
  final detail = appleDetail();
  return CompanyDetail(
    company: detail.company,
    history: [for (var fy = 2021; fy <= 2025; fy++) year(fy, 300e9 + fy, 90e9)],
    pros: detail.pros,
    cons: detail.cons,
  );
}

Future<void> pumpPhonePage(WidgetTester tester, CompanyDetail detail) async {
  tester.view.physicalSize = const Size(384 * 3, 832 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: CompanyPage(ticker: 'AAPL', screenerData: screenerData, loadDetail: (ticker, metrics) async => detail),
  ));
  await tester.pumpAndSettle();
}

bool isOnScreen(WidgetTester tester, Finder finder) {
  final rect = tester.getRect(finder);
  return rect.left >= 0 && rect.right <= 384;
}

void main() {
  testWidgets('nothing overflows, from the top to the bottom of the page', (tester) async {
    await pumpPhonePage(tester, appleFiveYears());
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(YearTable).last); // scroll to the last table (Ratios)
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('year tables start at the newest year and keep the labels on screen', (tester) async {
    await pumpPhonePage(tester, appleFiveYears());
    // On a phone the section bar is wider than the screen, so scroll the page to the table directly.
    await tester.ensureVisible(find.byType(YearTable).first);
    await tester.pumpAndSettle();

    // Look inside the Profit & Loss table only (the chart also shows years).
    Finder inTable(String text) => find.descendant(of: find.byType(YearTable).first, matching: find.text(text));
    final newest = inTable('FY2025');
    final oldest = inTable('FY2021');
    expect(isOnScreen(tester, newest), isTrue);
    expect(isOnScreen(tester, oldest), isFalse); // swipe left to see it

    // Swipe the numbers to the right (towards the older years): the label "Revenue" stays put.
    final labelBefore = tester.getTopLeft(inTable('Revenue'));
    await tester.drag(newest, const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(inTable('Revenue')), labelBefore);
    expect(isOnScreen(tester, inTable('FY2021')), isTrue);
  });

  testWidgets('the section bar slides along so the current section stays visible', (tester) async {
    await pumpPhonePage(tester, appleFiveYears());
    final ratiosTab = find.text('Ratios').first; // the first "Ratios" is the tab in the section bar
    expect(isOnScreen(tester, ratiosTab), isFalse); // the bar is wider than a phone

    await tester.ensureVisible(find.byType(YearTable).last);
    await tester.drag(find.byType(YearTable).last, const Offset(0, -3000)); // swipe up: to the very bottom
    await tester.pumpAndSettle();
    expect(isOnScreen(tester, ratiosTab), isTrue);
  });

  testWidgets('peers show only market cap, P/E and ROE on a phone', (tester) async {
    await pumpPhonePage(tester, appleDetail());
    await tester.ensureVisible(find.byType(PeersSection));
    await tester.pumpAndSettle();
    Finder inPeers(String text) => find.descendant(of: find.byType(PeersSection), matching: find.text(text));
    expect(inPeers('MSFT'), findsOneWidget);
    expect(inPeers('Market cap'), findsOneWidget);
    expect(inPeers('ROE'), findsOneWidget);
    // Wide-screen-only columns (the test metrics have no label for revenue_growth, so its key is shown).
    expect(inPeers('Price'), findsNothing);
    expect(inPeers('revenue_growth'), findsNothing);
  });
}
