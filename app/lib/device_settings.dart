// Small settings saved on this device with the shared_preferences package: in the browser's local storage
// on the web, in the app's settings on Android, in a file in the user folder on Windows.
// Nothing here is sent to the server.
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'presets.dart';

const _hiddenColumnsKey = 'hidden_columns';

/// The screener columns the user switched off (column keys such as "pb").
/// We store the hidden ones, not the visible ones, so a metric added in a later version shows up by itself.
/// If the storage can't be read (e.g. blocked in the browser), nothing is hidden.
Future<Set<String>> loadHiddenColumns() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_hiddenColumnsKey) ?? []).toSet();
  } catch (_) {
    return {};
  }
}

/// Save the hidden columns. If saving fails, the choice still works until the app is closed.
Future<void> saveHiddenColumns(Set<String> keys) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_hiddenColumnsKey, keys.toList()..sort());
  } catch (_) {
    // Not saved; nothing else to do.
  }
}

const _presetsKey = 'filter_presets';

/// The user's own filter presets, oldest first. Each one is stored as a small JSON text.
/// A preset that can't be read (e.g. from a newer app version) is skipped.
Future<List<FilterPreset>> loadPresets() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final presets = <FilterPreset>[];
    for (final text in prefs.getStringList(_presetsKey) ?? <String>[]) {
      try {
        presets.add(FilterPreset.fromJson(jsonDecode(text) as Map<String, dynamic>));
      } catch (_) {
        // Skip this one.
      }
    }
    return presets;
  } catch (_) {
    return [];
  }
}

Future<void> savePresets(List<FilterPreset> presets) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_presetsKey, [for (final preset in presets) jsonEncode(preset.toJson())]);
  } catch (_) {
    // Not saved; the presets still work until the app is closed.
  }
}

const _watchlistKey = 'watchlist';

/// The tickers on the user's watchlist.
Future<Set<String>> loadWatchlist() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_watchlistKey) ?? []).toSet();
  } catch (_) {
    return {};
  }
}

Future<void> saveWatchlist(Set<String> tickers) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_watchlistKey, tickers.toList()..sort());
  } catch (_) {
    // Not saved; the watchlist still works until the app is closed.
  }
}
