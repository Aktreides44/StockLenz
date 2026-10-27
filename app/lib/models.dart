// Data classes for what the API (or the offline snapshot) returns.

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

  /// "%", "x" (a ratio) or "USD".
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
    required this.price,
    required this.latestFiscalYear,
    required this.latestFiscalYearEnd,
    required this.metrics,
    required this.missingReasons,
    required this.notApplicable,
  });

  final String ticker;
  final String name;
  final String sector;
  final double? price;
  final int? latestFiscalYear;
  final String? latestFiscalYearEnd;

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
      price: _toDouble(json['price']),
      latestFiscalYear: json['latest_fiscal_year'] as int?,
      latestFiscalYearEnd: json['latest_fiscal_year_end'] as String?,
      metrics: {for (final definition in definitions) definition.key: _toDouble(json[definition.key])},
      missingReasons: reasons.map((key, value) => MapEntry(key, value as String)),
      notApplicable: ((json['not_applicable'] as List<dynamic>?) ?? []).cast<String>(),
    );
  }

  /// Why a metric has no value, for the tooltip on "—".
  String missingReason(String metricKey) => missingReasons[metricKey] ?? 'Not available';
}
