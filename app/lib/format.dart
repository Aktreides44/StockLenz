// Number formatting rules from CLAUDE.md:
// percentages with 1 decimal place, large numbers as $1.2B / $340M.

/// Shown instead of a number when a value is missing. Never 0.
const String missingValue = '—';

/// Format a metric value for display, based on its unit ("%", "x" or "USD").
String formatMetric(double value, String unit) {
  switch (unit) {
    case '%':
      return '${value.toStringAsFixed(1)}%';
    case 'USD':
      return formatMoney(value);
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

/// Share price: $343.91, $1,279.14
String formatPrice(double price) {
  final parts = price.toStringAsFixed(2).split('.');
  // Put a comma before every group of 3 digits, counted from the right.
  final whole = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '\$$whole.${parts[1]}';
}
