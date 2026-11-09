// Small settings saved on this device with the shared_preferences package: in the browser's local storage
// on the web, in the app's settings on Android, in a file in the user folder on Windows.
// Nothing here is sent to the server.
import 'package:shared_preferences/shared_preferences.dart';

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
