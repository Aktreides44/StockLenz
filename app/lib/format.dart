// Number formatting rules from CLAUDE.md:
// percentages with 1 decimal place, large numbers as $1.2B / $340M.

/// Shown instead of a number when a value is missing. Never 0.
const String missingValue = '—';

/// Format a metric value for display, based on its unit ("%", "x", "USD" or "score").
String formatMetric(double value, String unit) {
  switch (unit) {
    case '%':
      return '${value.toStringAsFixed(1)}%';
    case 'USD':
      return formatMoney(value);
    case 'score': // Quality 0–9, Value 0–10
      return value.toStringAsFixed(1);
    default: // ratios such as P/E or current ratio
      return value.toStringAsFixed(2);
  }
}

/// $5.02T, $1.2B, $340M, $950
String formatMoney(double value) {
  final sign = value < 0 ? '-' : '';
  final amount = value.abs();
  if (amount >= 1e12) return '$sign\$${(amount / 1e12).toStringAsFixed(2)}T';
  if (amount >= 1e9) return '$sign\$${(amount / 1e9).toStringAsFixed(1)}B';
  if (amount >= 1e6) return '$sign\$${(amount / 1e6).toStringAsFixed(0)}M';
  return '$sign\$${amount.toStringAsFixed(0)}';
}

/// Put a comma before every group of 3 digits, counted from the right: "1234567" -> "1,234,567".
String _withCommas(String digits) => digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

/// Share price: $343.91, $1,279.14
String formatPrice(double price) {
  final parts = price.toStringAsFixed(2).split('.');
  return '\$${_withCommas(parts[0])}.${parts[1]}';
}

/// A dollar amount in millions, for the financial statement tables: 391,035 or -1,234
String formatMillions(double value) {
  final millions = (value / 1e6).round();
  final sign = millions < 0 ? '-' : '';
  return '$sign${_withCommas(millions.abs().toString())}';
}

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "2026-10-27T09:04:12" -> "27 Oct 2026"
String formatDate(String isoDate) {
  final date = DateTime.tryParse(isoDate);
  if (date == null) return isoDate;
  return '${date.day} ${_months[date.month - 1]} ${date.year}';
}

/// "2025-09-27" -> "Sep 2025" (column headers of the financial tables)
String formatMonthYear(String isoDate) {
  final date = DateTime.tryParse(isoDate);
  if (date == null) return isoDate;
  return '${_months[date.month - 1]} ${date.year}';
}
