import 'package:flutter_test/flutter_test.dart';
import 'package:stocklens/filters_panel.dart';
import 'package:stocklens/format.dart';

void main() {
  group('formatMetric', () {
    test('percentages have 1 decimal place', () {
      expect(formatMetric(12.345, '%'), '12.3%');
      expect(formatMetric(-5.0, '%'), '-5.0%');
    });

    test('ratios have 2 decimal places', () {
      expect(formatMetric(1.5, 'x'), '1.50');
    });

    test('dollar amounts use T / B / M', () {
      expect(formatMetric(5.019e12, 'USD'), r'$5.02T');
      expect(formatMetric(1.23e9, 'USD'), r'$1.2B');
      expect(formatMetric(340e6, 'USD'), r'$340M');
      expect(formatMetric(-2.5e9, 'USD'), r'-$2.5B');
    });
  });

  test('formatPrice', () {
    expect(formatPrice(343.914), r'$343.91');
    expect(formatPrice(1279.14), r'$1,279.14');
    expect(formatPrice(1234567.5), r'$1,234,567.50');
  });

  test('formatMillions', () {
    expect(formatMillions(391035000000), '391,035');
    expect(formatMillions(-1234e6), '-1,234');
    expect(formatMillions(400e3), '0');
  });

  test('dates', () {
    expect(formatDate('2026-10-27T09:04:12'), '27 Oct 2026');
    expect(formatMonthYear('2025-09-27'), 'Sep 2025');
  });

  group('RangeFilter', () {
    test('empty filter accepts everything, including missing values', () {
      expect(const RangeFilter().accepts(null), isTrue);
      expect(const RangeFilter().accepts(-100), isTrue);
    });

    test('min and max are inclusive', () {
      const filter = RangeFilter(min: 10, max: 20);
      expect(filter.accepts(10), isTrue);
      expect(filter.accepts(20), isTrue);
      expect(filter.accepts(9.9), isFalse);
      expect(filter.accepts(20.1), isFalse);
    });

    test('missing value never passes an active filter', () {
      expect(const RangeFilter(min: 0).accepts(null), isFalse);
    });
  });
}
