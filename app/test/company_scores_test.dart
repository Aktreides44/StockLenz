// The Scores section of the company page (v3): every check with ✓ / ✗ / — and the sector comparison.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/company_scores.dart';
import 'package:stocklens/models.dart';

/// Shaped like the API's "scores" (backend/pipeline/scores.py), with Apple-like numbers.
final scoresJson = <String, dynamic>{
  'quality': {
    'score': 7.9,
    'label': 'Mixed',
    'points': 7,
    'checkable': 8,
    'checks': [
      {'key': 'roa_positive', 'label': 'Profitable (ROA > 0)', 'passed': true, 'values': {'now': 0.368}, 'skip_reason': null},
      {'key': 'ocf_positive', 'label': 'Cash from operations > 0', 'passed': true, 'values': {'now': 145.1e9}, 'skip_reason': null},
      {'key': 'roa_up', 'label': 'ROA higher than last year', 'passed': false, 'values': {'now': 0.25, 'before': 0.281},
       'skip_reason': null},
      {'key': 'accruals', 'label': 'Cash from operations > net income', 'passed': true,
       'values': {'cash_from_operations': 145.1e9, 'net_income': 112.0e9}, 'skip_reason': null},
      {'key': 'leverage_down', 'label': 'Less long-term debt (vs assets)', 'passed': true,
       'values': {'now': 0.21, 'before': 0.25}, 'skip_reason': null},
      {'key': 'current_ratio_up', 'label': 'Current ratio higher', 'passed': true, 'values': {'now': 0.89, 'before': 0.87},
       'skip_reason': null},
      {'key': 'no_new_shares', 'label': 'No new shares (diluted shares not up)', 'passed': null,
       'values': {'now': null, 'before': 15.4e9}, 'skip_reason': 'Numbers missing'},
      {'key': 'gross_margin_up', 'label': 'Gross margin higher', 'passed': true, 'values': {'now': 0.469, 'before': 0.462},
       'skip_reason': null},
      {'key': 'asset_turnover_up', 'label': 'Asset turnover higher', 'passed': true, 'values': {'now': 1.15, 'before': 1.09},
       'skip_reason': null},
    ],
  },
  'value': {
    'score': 2.3,
    'label': 'Expensive',
    'ratios': {
      'pe': {'label': 'P/E', 'value': 39.6, 'percentile': 0.629, 'sector_median': 29.81, 'sector_count': 71,
             'skip_reason': null},
      'pb': {'label': 'P/B', 'value': 44.4, 'percentile': 0.97, 'sector_median': 8.2, 'sector_count': 70,
             'skip_reason': null},
      'ps': {'label': 'P/S (TTM)', 'value': null, 'percentile': null, 'sector_median': 6.1, 'sector_count': 71,
             'skip_reason': 'No positive value (e.g. a loss)'},
    },
  },
  'combined': null,
};

const apple = Company(
  ticker: 'AAPL',
  name: 'Apple Inc.',
  sector: 'Information Technology',
  price: 340,
  latestFiscalYear: 2025,
  latestFiscalYearEnd: '2025-09-27',
  metrics: {'quality_score': 7.9, 'value_score': 2.3},
  missingReasons: {},
  notApplicable: [],
);

Future<void> pumpSection(WidgetTester tester, CompanyScores? scores, {Size size = const Size(1200, 1600)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: ScoresSection(company: apple, scores: scores))),
  ));
}

void main() {
  test('the API JSON is read into CompanyScores', () {
    final scores = CompanyScores.fromJson(scoresJson);
    expect(scores.qualityScore, 7.9);
    expect((scores.points, scores.checkable), (7, 8));
    expect(scores.checks, hasLength(9));
    expect(scores.checks[2].passed, isFalse);
    expect(scores.checks[6].passed, isNull);
    expect(scores.ratios.map((r) => r.key), ['pe', 'pb', 'ps']);
    expect(scores.ratios.first.sectorCount, 71);
    expect(scores.combined, isNull);
  });

  test('each check describes its numbers in a fitting unit', () {
    final checks = {for (final c in CompanyScores.fromJson(scoresJson).checks) c.key: c};
    expect(describeCheck(checks['roa_up']!), '25.0% now · 28.1% the year before');
    expect(describeCheck(checks['accruals']!), r'Cash from operations $145.1B vs net income $112.0B');
    expect(describeCheck(checks['current_ratio_up']!), '0.89 now · 0.87 the year before');
    expect(describeCheck(checks['roa_positive']!), startsWith('ROA 36.8%'));
  });

  testWidgets('shows both scores, every check with its symbol, and the sector comparison', (tester) async {
    await pumpSection(tester, CompanyScores.fromJson(scoresJson));
    expect(find.text('7.9 Mixed'), findsOneWidget);
    expect(find.text('2.3 Expensive'), findsOneWidget);
    expect(find.text('7 of 8 checks passed'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNWidgets(7));
    expect(find.byIcon(Icons.cancel), findsOneWidget);
    expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
    expect(find.text('Numbers missing'), findsOneWidget); // the skipped check says why
    // P/E: percentile 0.629 → more expensive than 63 %, cheaper than 37 %
    expect(find.text('sector median 29.81 · cheaper than 37% of 71 companies'), findsOneWidget);
    expect(find.text('No positive value (e.g. a loss)'), findsOneWidget);
    expect(find.textContaining('Piotroski (2000)'), findsOneWidget);
  });

  testWidgets('the combined sentence is shown when there is one', (tester) async {
    final json = Map<String, dynamic>.from(scoresJson)..['combined'] = 'Strong finances, but the market already prices that in';
    await pumpSection(tester, CompanyScores.fromJson(json));
    expect(find.text('Strong finances, but the market already prices that in'), findsOneWidget);
  });

  testWidgets('without scores from the server it says so', (tester) async {
    await pumpSection(tester, null);
    expect(find.textContaining('Scores are not available yet'), findsOneWidget);
  });

  testWidgets('phones: nothing overflows', (tester) async {
    await pumpSection(tester, CompanyScores.fromJson(scoresJson), size: const Size(360, 2000));
    expect(tester.takeException(), isNull);
  });
}
