// Loads screener data from the StockLens API, or from the bundled snapshot if the API is down.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

const String snapshotAsset = 'assets/snapshot.json';

class ScreenerData {
  const ScreenerData({
    required this.companies,
    required this.metrics,
    required this.isOffline,
    this.snapshotDate,
  });

  final List<Company> companies;
  final List<MetricDefinition> metrics;

  /// True when the data comes from the bundled snapshot instead of the API.
  final bool isOffline;

  /// When the snapshot was created, e.g. "2026-10-27T10:12:00" (only set when offline).
  final String? snapshotDate;
}

/// Try the API first; if it is unreachable or returns an error, use the snapshot.
Future<ScreenerData> loadScreenerData() async {
  try {
    return await _loadFromApi();
  } catch (_) {
    return _loadFromSnapshot();
  }
}

Future<dynamic> _getJson(String path) async {
  final response = await http.get(Uri.parse('$apiBaseUrl$path')).timeout(apiTimeout);
  if (response.statusCode != 200) {
    throw Exception('GET $path failed with status ${response.statusCode}');
  }
  // Decode as UTF-8 ourselves: formulas contain characters like "−" and "≤".
  return jsonDecode(utf8.decode(response.bodyBytes));
}

Future<ScreenerData> _loadFromApi() async {
  final metricsJson = await _getJson('/metrics') as List<dynamic>;
  final companiesJson = await _getJson('/companies') as List<dynamic>;
  return _buildData(metricsJson, companiesJson, isOffline: false);
}

Map<String, dynamic>? _snapshotCache;

/// The snapshot file is read once and then kept in memory.
Future<Map<String, dynamic>> _snapshot() async {
  return _snapshotCache ??= jsonDecode(await rootBundle.loadString(snapshotAsset)) as Map<String, dynamic>;
}

/// Load one company's page. If the screener is already offline, go straight to the snapshot
/// instead of waiting for the API to time out again.
Future<CompanyDetail> loadCompanyDetail(String ticker, List<MetricDefinition> metrics, {bool offline = false}) async {
  if (!offline) {
    try {
      final json = await _getJson('/companies/$ticker') as Map<String, dynamic>;
      return CompanyDetail.fromJson(json, metrics, isOffline: false);
    } catch (_) {
      // fall through to the snapshot
    }
  }
  final details = (await _snapshot())['details'] as Map<String, dynamic>;
  final json = details[ticker] as Map<String, dynamic>?;
  if (json == null) throw Exception('$ticker is not in the offline snapshot');
  return CompanyDetail.fromJson(json, metrics, isOffline: true);
}

Future<ScreenerData> _loadFromSnapshot() async {
  final snapshot = await _snapshot();
  return _buildData(
    snapshot['metrics'] as List<dynamic>,
    snapshot['companies'] as List<dynamic>,
    isOffline: true,
    snapshotDate: snapshot['generated_at'] as String?,
  );
}

ScreenerData _buildData(
  List<dynamic> metricsJson,
  List<dynamic> companiesJson, {
  required bool isOffline,
  String? snapshotDate,
}) {
  final metrics = [for (final m in metricsJson) MetricDefinition.fromJson(m as Map<String, dynamic>)];
  final companies = [for (final c in companiesJson) Company.fromJson(c as Map<String, dynamic>, metrics)];
  return ScreenerData(companies: companies, metrics: metrics, isOffline: isOffline, snapshotDate: snapshotDate);
}
