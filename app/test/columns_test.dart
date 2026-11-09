// "Columns": show or hide screener columns, saved on the device (shared_preferences, simulated here).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stocklens/device_settings.dart';
import 'package:stocklens/screener_page.dart';
import 'package:stocklens/screener_table.dart';

import 'screener_page_test.dart' show fakeData;

Future<void> pumpWide(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: ScreenerPage(loadData: () async => fakeData())));
  await tester.pumpAndSettle();
}

/// A column header in the table (the same label also appears in the Columns window).
Finder header(String label) => find.descendant(of: find.byType(ScreenerTable), matching: find.text(label));

Future<List<String>?> savedHidden() async => (await SharedPreferences.getInstance()).getStringList('hidden_columns');

void main() {
  test('hidden columns are saved and loaded again', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await loadHiddenColumns(), isEmpty);
    await saveHiddenColumns({'pe', 'roe'});
    expect(await loadHiddenColumns(), {'pe', 'roe'});
  });

  testWidgets('a saved choice is used when the app starts', (tester) async {
    SharedPreferences.setMockInitialValues({'hidden_columns': ['roe']});
    await pumpWide(tester);
    expect(header('ROE'), findsNothing);
    expect(header('P/E (FY)'), findsOneWidget);
    expect(find.text('1 hidden'), findsOneWidget); // the badge on the Columns button
  });

  testWidgets('unticking a column hides it and saves the choice; Show all brings everything back', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpWide(tester);
    await tester.tap(find.text('Columns'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(CheckboxListTile, 'P/E (FY)'));
    await tester.pumpAndSettle();
    expect(header('P/E (FY)'), findsNothing);
    expect(await savedHidden(), ['pe']);

    await tester.tap(find.text('Show all'));
    await tester.pumpAndSettle();
    expect(header('P/E (FY)'), findsOneWidget);
    expect(await savedHidden(), isEmpty);
  });

  testWidgets('hiding the column the table is sorted by goes back to sorting by market cap', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpWide(tester);
    double top(String ticker) => tester.getTopLeft(find.text(ticker)).dy;

    await tester.tap(header('ROE')); // sort by ROE, highest first: AAPL (171.4) before KO (45.0)
    await tester.pumpAndSettle();
    await tester.tap(header('ROE')); // lowest first: KO before AAPL
    await tester.pumpAndSettle();
    expect(top('KO') < top('AAPL'), isTrue);

    await tester.tap(find.text('Columns'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'ROE'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(top('AAPL') < top('KO'), isTrue); // market cap, highest first again
  });
}
