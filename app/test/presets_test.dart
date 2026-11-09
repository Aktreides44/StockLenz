// Filter presets: examples that come with the app, and the user's own (saved on the device, simulated here).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stocklens/device_settings.dart';
import 'package:stocklens/filters_panel.dart';
import 'package:stocklens/presets.dart';
import 'package:stocklens/screener_page.dart';

import 'screener_page_test.dart' show fakeData;

Future<void> pumpWide(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: ScreenerPage(loadData: () async => fakeData())));
  await tester.pumpAndSettle();
}

Future<void> openPresets(WidgetTester tester) async {
  await tester.tap(find.text('Presets'));
  await tester.pumpAndSettle();
}

/// The text field in the filter panel: 0 = search box, then min/max per metric (market cap, ROE, P/E).
Finder box(int index) => find.byType(TextField).at(index);

void main() {
  test('a preset is saved as JSON and read back the same', () async {
    SharedPreferences.setMockInitialValues({});
    const preset = FilterPreset(name: 'Mine', sector: 'Energy', filters: {'roe': RangeFilter(min: 15)});
    await savePresets([preset]);

    final stored = (await SharedPreferences.getInstance()).getStringList('filter_presets')!;
    expect(jsonDecode(stored.single), {
      'name': 'Mine',
      'sector': 'Energy',
      'filters': {'roe': {'min': 15.0, 'max': null}},
    });

    final loaded = (await loadPresets()).single;
    expect(loaded.name, 'Mine');
    expect(loaded.sector, 'Energy');
    expect(loaded.filters['roe']!.min, 15);
    expect(loaded.filters['roe']!.max, isNull);
    expect(loaded.summary({'roe': 'ROE'}), 'Energy · ROE ≥ 15');
  });

  test('a broken stored preset is skipped, the others still load', () async {
    SharedPreferences.setMockInitialValues({
      'filter_presets': ['not json', jsonEncode({'name': 'Good', 'sector': null, 'filters': {}})],
    });
    expect([for (final p in await loadPresets()) p.name], ['Good']);
  });

  testWidgets('choosing an example preset filters the list and fills in the filter boxes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpWide(tester);
    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();

    await openPresets(tester);
    await tester.tap(find.text('High return on equity'));
    await tester.pumpAndSettle();

    expect(find.text('2 of 3 companies'), findsOneWidget); // MCD has no ROE, so it is hidden
    expect(find.text('MCD'), findsNothing);
    expect(tester.widget<TextField>(box(3)).controller!.text, '15'); // ROE min
    expect(find.text('Preset "High return on equity" applied'), findsOneWidget);
  });

  testWidgets('save the current filters as a preset, use it later, then delete it', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await pumpWide(tester);

    // Nothing to save while no filter is set.
    await openPresets(tester);
    expect(tester.widget<MenuItemButton>(find.widgetWithText(MenuItemButton, 'Save current filters…')).onPressed, isNull);
    await tester.tapAt(const Offset(800, 600)); // close the menu
    await tester.pumpAndSettle();

    await tester.tap(find.text('Filters'));
    await tester.pumpAndSettle();
    await tester.enterText(box(3), '100'); // ROE at least 100 %: only Apple
    await tester.pump();
    expect(find.text('1 of 3 companies'), findsOneWidget);

    await openPresets(tester);
    await tester.tap(find.text('Save current filters…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Super ROE');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = await loadPresets();
    expect(saved.single.name, 'Super ROE');
    expect(saved.single.filters.keys, ['roe']);

    await tester.tap(find.text('Clear all'));
    await tester.pump();
    expect(find.text('3 of 3 companies'), findsOneWidget);

    await openPresets(tester);
    await tester.tap(find.text('Super ROE'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 3 companies'), findsOneWidget);
    expect(tester.widget<TextField>(box(3)).controller!.text, '100');

    await openPresets(tester);
    await tester.tap(find.byTooltip('Delete "Super ROE"'));
    await tester.pumpAndSettle();
    expect(await loadPresets(), isEmpty);
  });

  testWidgets('phones show the presets as an icon button next to the sector', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: ScreenerPage(loadData: () async => fakeData())));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Presets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('High return on equity'));
    await tester.pumpAndSettle();
    expect(find.text('2 of 3'), findsOneWidget);
    expect(tester.takeException(), isNull); // nothing overflows
  });
}
