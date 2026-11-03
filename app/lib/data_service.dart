// Loads data from the StockLens API (its address is in config.dart).
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'models.dart';

class ScreenerData {
  const ScreenerData({required this.companies, required this.metrics});

  final List<Company> companies;
  final List<MetricDefinition> metrics;
}

/// The API could not be reached, or answered with an error. [message] is shown to the user.
class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

Future<dynamic> _getJson(String path) async {
  final http.Response response;
  try {
    response = await http.get(Uri.parse('$apiBaseUrl$path')).timeout(apiTimeout);
  } catch (_) {
    // No internet, server down, or no answer within apiTimeout.
    throw const ApiException("Can't connect to the StockLens server. Check your internet connection.");
  }
  if (response.statusCode == 404) {
    throw const ApiException('Not found on the StockLens server.');
  }
  if (response.statusCode != 200) {
    throw ApiException('The StockLens server answered with an error (status ${response.statusCode}).');
  }
  // Decode as UTF-8 ourselves: formulas contain characters like "−" and "≤".
  return jsonDecode(utf8.decode(response.bodyBytes));
}

/// Everything the screener needs: the metric definitions and all companies.
Future<ScreenerData> loadScreenerData() async {
  final metricsJson = await _getJson('/metrics') as List<dynamic>;
  final companiesJson = await _getJson('/companies') as List<dynamic>;
  final metrics = [for (final m in metricsJson) MetricDefinition.fromJson(m as Map<String, dynamic>)];
  final companies = [for (final c in companiesJson) Company.fromJson(c as Map<String, dynamic>, metrics)];
  return ScreenerData(companies: companies, metrics: metrics);
}

/// One company's page.
Future<CompanyDetail> loadCompanyDetail(String ticker, List<MetricDefinition> metrics) async {
  final json = await _getJson('/companies/$ticker') as Map<String, dynamic>;
  return CompanyDetail.fromJson(json, metrics);
}
