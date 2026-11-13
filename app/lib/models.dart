// Data classes for what the API returns.

double? _toDouble(Object? value) => value == null ? null : (value as num).toDouble();

/// One indicator, e.g. ROE: its label, formula and unit, from GET /metrics.
class MetricDefinition {
  const MetricDefinition({
    required this.key,
    required this.label,
    required this.group,
    required this.formula,
    required this.unit,
    required this.higherIsBetter,
  });

  final String key;
  final String label;
  final String group;
  final String formula;

  /// "%", "x" (a ratio), "USD" or "score" (the v3 scores, 0–9 / 0–10).
  final String unit;
  final bool higherIsBetter;

  factory MetricDefinition.fromJson(Map<String, dynamic> json) {
    return MetricDefinition(
      key: json['key'] as String,
      label: json['label'] as String,
      group: json['group'] as String,
      formula: json['formula'] as String,
      unit: json['unit'] as String,
      higherIsBetter: json['higher_is_better'] as bool,
    );
  }
}

/// One row of the screener, from GET /companies.
class Company {
  const Company({
    required this.ticker,
    required this.name,
    required this.sector,
    this.cik,
    required this.price,
    this.priceFetchedAt,
    this.priceSource,
    this.sharesSource,
    this.sharesAsOf,
    required this.latestFiscalYear,
    required this.latestFiscalYearEnd,
    this.ttmEnd,
    this.qualityLabel,
    this.valueLabel,
    required this.metrics,
    required this.missingReasons,
    required this.notApplicable,
  });

  final String ticker;
  final String name;
  final String sector;

  /// The SEC's company number, used for the link to its filings.
  final int? cik;
  final double? price;

  /// The day of the price: the trading day for a Polygon close ("2026-11-03"),
  /// the download time for the Yahoo backup ("2026-11-04T09:04:12").
  final String? priceFetchedAt;

  /// Where the price comes from: "Polygon close" or "Yahoo Finance (backup)".
  final String? priceSource;

  /// Where the share count for the market cap comes from, e.g. "SEC cover page (10-Q)".
  final String? sharesSource;

  /// The date that share count refers to, e.g. "2026-07-17" (null for the Yahoo backup).
  final String? sharesAsOf;
  final int? latestFiscalYear;
  final String? latestFiscalYearEnd;

  /// Where the trailing 12 months of the (TTM) metrics end, e.g. "2026-06-27" (the latest 10-Q).
  final String? ttmEnd;

  /// v3 scores: "Strong" / "Mixed" / "Weak" (Piotroski F-Score) and "Cheap" / "Fair" / "Expensive" (vs the
  /// sector); null when there is not enough data. The numbers are in [metrics] ("quality_score", "value_score").
  final String? qualityLabel;
  final String? valueLabel;

  /// Metric key -> value. null means missing (shown as "—"), never 0.
  final Map<String, double?> metrics;

  /// Metric key -> plain-English reason why it is missing.
  final Map<String, String> missingReasons;

  /// Metric keys that are not meaningful for this company (e.g. current ratio for banks).
  final List<String> notApplicable;

  factory Company.fromJson(Map<String, dynamic> json, List<MetricDefinition> definitions) {
    final reasons = (json['missing_reasons'] as Map<String, dynamic>?) ?? {};
    return Company(
      ticker: json['ticker'] as String,
      name: json['name'] as String,
      sector: json['sector'] as String,
      cik: json['cik'] as int?,
      price: _toDouble(json['price']),
      priceFetchedAt: json['price_fetched_at'] as String?,
      priceSource: json['price_source'] as String?,
      sharesSource: json['shares_source'] as String?,
      sharesAsOf: json['shares_as_of'] as String?,
      latestFiscalYear: json['latest_fiscal_year'] as int?,
      latestFiscalYearEnd: json['latest_fiscal_year_end'] as String?,
      ttmEnd: json['ttm_end'] as String?,
      qualityLabel: json['quality_label'] as String?,
      valueLabel: json['value_label'] as String?,
      metrics: {for (final definition in definitions) definition.key: _toDouble(json[definition.key])},
      missingReasons: reasons.map((key, value) => MapEntry(key, value as String)),
      notApplicable: ((json['not_applicable'] as List<dynamic>?) ?? []).cast<String>(),
    );
  }

  /// Why a metric has no value, for the tooltip on "—".
  String missingReason(String metricKey) => missingReasons[metricKey] ?? 'Not available';
}

/// One fiscal year of a company's history, from GET /companies/{ticker}.
class YearData {
  const YearData({
    required this.fiscalYear,
    required this.endDate,
    required this.values,
    required this.tags,
    required this.ratios,
    required this.ratioMissingReasons,
  });

  final int fiscalYear;
  final String endDate;

  /// Raw 10-K fields ("revenue", "net_income", ...) plus "fcf". null = not reported.
  final Map<String, double?> values;

  /// Field -> the us-gaap XBRL tag the value came from.
  final Map<String, String?> tags;

  /// Ratios for this year ("net_margin", "roe", ...), and why missing ones are missing.
  final Map<String, double?> ratios;
  final Map<String, String> ratioMissingReasons;

  static const _notValues = {'fiscal_year', 'end_date', 'tags', 'ratios', 'ratio_missing_reasons'};

  factory YearData.fromJson(Map<String, dynamic> json) {
    return YearData(
      fiscalYear: json['fiscal_year'] as int,
      endDate: json['end_date'] as String,
      values: {
        for (final entry in json.entries)
          if (!_notValues.contains(entry.key)) entry.key: _toDouble(entry.value),
      },
      tags: (json['tags'] as Map<String, dynamic>).map((key, value) => MapEntry(key, value as String?)),
      ratios: (json['ratios'] as Map<String, dynamic>).map((key, value) => MapEntry(key, _toDouble(value))),
      ratioMissingReasons:
          (json['ratio_missing_reasons'] as Map<String, dynamic>).map((key, value) => MapEntry(key, value as String)),
    );
  }
}

/// One rule-based pro or con, e.g. {"id": "high_roe", "text": "Strong return on equity ..."}.
class AnalysisPoint {
  const AnalysisPoint({required this.id, required this.text});

  final String id;
  final String text;

  factory AnalysisPoint.fromJson(Map<String, dynamic> json) {
    return AnalysisPoint(id: json['id'] as String, text: json['text'] as String);
  }
}

/// One day of the price chart.
class PricePoint {
  const PricePoint({required this.day, required this.close});

  /// Trading day, e.g. "2026-11-06".
  final String day;

  /// Closing price that day (adjusted for stock splits).
  final double close;

  factory PricePoint.fromJson(Map<String, dynamic> json) {
    return PricePoint(day: json['day'] as String, close: (json['close'] as num).toDouble());
  }
}

/// Everything on the company page.
class CompanyDetail {
  const CompanyDetail({
    required this.company,
    required this.history,
    required this.pros,
    required this.cons,
    this.priceHistory = const [],
    this.scores,
  });

  final Company company;

  /// Oldest fiscal year first.
  final List<YearData> history;
  final List<AnalysisPoint> pros;
  final List<AnalysisPoint> cons;

  /// Daily closing prices of the last year, oldest first (empty if the server has none yet).
  final List<PricePoint> priceHistory;

  /// v3: every Quality check and Value ratio; null if the server's database has no scores yet.
  final CompanyScores? scores;

  factory CompanyDetail.fromJson(
    Map<String, dynamic> json,
    List<MetricDefinition> definitions,
  ) {
    final analysis = json['analysis'] as Map<String, dynamic>;
    return CompanyDetail(
      company: Company.fromJson(json, definitions),
      history: [for (final year in json['history'] as List<dynamic>) YearData.fromJson(year as Map<String, dynamic>)],
      pros: [for (final item in analysis['pros'] as List<dynamic>) AnalysisPoint.fromJson(item as Map<String, dynamic>)],
      cons: [for (final item in analysis['cons'] as List<dynamic>) AnalysisPoint.fromJson(item as Map<String, dynamic>)],
      priceHistory: [
        for (final point in (json['price_history'] as List<dynamic>?) ?? [])
          PricePoint.fromJson(point as Map<String, dynamic>),
      ],
      scores: json['scores'] == null ? null : CompanyScores.fromJson(json['scores'] as Map<String, dynamic>),
    );
  }
}

/// One of the nine Piotroski checks, e.g. "Cash from operations > 0".
class ScoreCheck {
  const ScoreCheck({required this.key, required this.label, required this.passed, required this.values, this.skipReason});

  final String key;
  final String label;

  /// true = passed (1 point), false = failed, null = skipped (numbers missing or not meaningful).
  final bool? passed;

  /// The numbers the check compared, e.g. {"now": 0.37, "before": 0.28}.
  final Map<String, double?> values;
  final String? skipReason;

  factory ScoreCheck.fromJson(Map<String, dynamic> json) {
    return ScoreCheck(
      key: json['key'] as String,
      label: json['label'] as String,
      passed: json['passed'] as bool?,
      values: (json['values'] as Map<String, dynamic>).map((key, value) => MapEntry(key, _toDouble(value))),
      skipReason: json['skip_reason'] as String?,
    );
  }
}

/// One valuation ratio compared with the company's sector.
class ValueRatio {
  const ValueRatio({
    required this.key,
    required this.label,
    this.value,
    this.percentile,
    this.sectorMedian,
    required this.sectorCount,
    this.skipReason,
  });

  final String key;
  final String label;
  final double? value;

  /// 0 = the cheapest in the sector, 1 = the most expensive; null when not ranked.
  final double? percentile;
  final double? sectorMedian;

  /// How many companies in the sector have this ratio.
  final int sectorCount;
  final String? skipReason;

  factory ValueRatio.fromJson(String key, Map<String, dynamic> json) {
    return ValueRatio(
      key: key,
      label: json['label'] as String,
      value: _toDouble(json['value']),
      percentile: _toDouble(json['percentile']),
      sectorMedian: _toDouble(json['sector_median']),
      sectorCount: json['sector_count'] as int,
      skipReason: json['skip_reason'] as String?,
    );
  }
}

/// Both v3 scores of one company with all their reasons (backend/pipeline/scores.py).
class CompanyScores {
  const CompanyScores({
    this.qualityScore,
    this.qualityLabel,
    required this.points,
    required this.checkable,
    required this.checks,
    this.valueScore,
    this.valueLabel,
    required this.ratios,
    this.combined,
  });

  final double? qualityScore;
  final String? qualityLabel;

  /// Checks passed, and checks that could be calculated (the score is points ÷ checkable × 9).
  final int points;
  final int checkable;
  final List<ScoreCheck> checks;

  final double? valueScore;
  final String? valueLabel;
  final List<ValueRatio> ratios;

  /// One sentence for the clear cases (e.g. Strong + Cheap), otherwise null.
  final String? combined;

  factory CompanyScores.fromJson(Map<String, dynamic> json) {
    final quality = json['quality'] as Map<String, dynamic>;
    final value = json['value'] as Map<String, dynamic>;
    return CompanyScores(
      qualityScore: _toDouble(quality['score']),
      qualityLabel: quality['label'] as String?,
      points: quality['points'] as int,
      checkable: quality['checkable'] as int,
      checks: [for (final check in quality['checks'] as List<dynamic>) ScoreCheck.fromJson(check as Map<String, dynamic>)],
      valueScore: _toDouble(value['score']),
      valueLabel: value['label'] as String?,
      ratios: [
        for (final entry in (value['ratios'] as Map<String, dynamic>).entries)
          ValueRatio.fromJson(entry.key, entry.value as Map<String, dynamic>),
      ],
      combined: json['combined'] as String?,
    );
  }
}
