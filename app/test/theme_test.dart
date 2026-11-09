import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/screener_page.dart';
import 'package:stocklens/theme.dart';

import 'screener_page_test.dart' show fakeData;

void main() {
  for (final brightness in Brightness.values) {
    test('$brightness: green accent from the logo, negative numbers stay red', () {
      final colors = buildTheme(brightness).colorScheme;
      final accent = HSVColor.fromColor(colors.primary);
      final negative = HSVColor.fromColor(colors.error); // NumberText shows negative values in this colour

      expect(accent.hue, inInclusiveRange(100, 150)); // green (the logo's green has a hue of about 126°)
      expect(negative.hue < 40 || negative.hue > 340, isTrue); // red
      expect((accent.hue - negative.hue).abs(), greaterThan(60)); // clearly different colours
    });
  }

  testWidgets('the top bar shows the logo next to the name', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light), home: ScreenerPage(loadData: () async => fakeData())));
    await tester.pumpAndSettle();
    final logo = find.descendant(of: find.byType(AppBar), matching: find.byType(Image));
    expect(logo, findsOneWidget);
    expect((tester.widget<Image>(logo).image as AssetImage).assetName, logoAsset);
    expect(find.descendant(of: find.byType(AppBar), matching: find.text('StockLens')), findsOneWidget);
  });
}
