import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/models.dart';
import 'package:stocklens/price_chart.dart';

/// One point per calendar day, ending on 6 Nov 2026, the price rising by 1 each day from [start].
List<PricePoint> daily(int days, {double start = 100}) {
  final last = DateTime.utc(2026, 11, 6);
  return [
    for (var i = days - 1; i >= 0; i--)
      PricePoint(
        day: last.subtract(Duration(days: i)).toIso8601String().substring(0, 10),
        close: start + (days - 1 - i),
      ),
  ];
}

Future<void> pumpChart(WidgetTester tester, List<PricePoint> history, {double width = 900}) async {
  tester.view.physicalSize = Size(width, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(child: PriceChart(history: history)))));
  await tester.pumpAndSettle();
}

void main() {
  test('pointsInRange counts back from the newest day', () {
    final history = daily(400);
    expect(pointsInRange(history, 31).length, 32); // 6 Oct .. 6 Nov
    expect(pointsInRange(history, 31).first.day, '2026-10-06');
    expect(pointsInRange(history, 366).length, 367);
    expect(pointsInRange([], 31), isEmpty);
  });

  test('percentChange from the first to the last point', () {
    expect(percentChange(const [PricePoint(day: 'a', close: 100), PricePoint(day: 'b', close: 112.5)]), 12.5);
    expect(percentChange(const [PricePoint(day: 'a', close: 100), PricePoint(day: 'b', close: 80)]), -20);
    expect(percentChange(const [PricePoint(day: 'a', close: 100)]), isNull); // one point: no change
    expect(percentChange(const [PricePoint(day: 'a', close: 0), PricePoint(day: 'b', close: 5)]), isNull);
  });

  testWidgets('without data it says so instead of drawing an empty chart', (tester) async {
    await pumpChart(tester, const []);
    expect(find.textContaining('No price history yet'), findsOneWidget);
  });

  testWidgets('shows the change for the chosen span and switches spans', (tester) async {
    await pumpChart(tester, daily(400));
    // 1Y: from 6 Nov 2025 (close 133) to 6 Nov 2026 (close 499): +275.2 %
    expect(find.text('+275.2% over the last year'), findsOneWidget);
    expect(find.textContaining('Prices so far start on'), findsNothing);

    await tester.tap(find.text('1M'));
    await tester.pumpAndSettle();
    // 1M: from 6 Oct (close 468) to 6 Nov (close 499): +6.6 %
    expect(find.text('+6.6% over the last month'), findsOneWidget);
  });

  testWidgets('while the history is still short, it says where it starts', (tester) async {
    await pumpChart(tester, daily(20));
    expect(find.text('Prices so far start on 18 Oct 2026; the history grows with every daily update.'), findsOneWidget);
  });

  testWidgets('fits a phone screen', (tester) async {
    await pumpChart(tester, daily(400), width: 360);
    expect(tester.takeException(), isNull);
  });
}
