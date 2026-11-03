// The "Filters" side panel: a min and max box for every metric.
import 'package:flutter/material.dart';

import 'models.dart';
import 'theme.dart';

/// A min/max range for one metric. Either end may be empty (null).
class RangeFilter {
  const RangeFilter({this.min, this.max});

  final double? min;
  final double? max;

  bool get isEmpty => min == null && max == null;

  /// A company with a missing value never passes an active filter.
  bool accepts(double? value) {
    if (isEmpty) return true;
    if (value == null) return false;
    if (min != null && value < min!) return false;
    if (max != null && value > max!) return false;
    return true;
  }
}

/// Dollar amounts are typed in billions; everything else in the unit shown in the table.
double inputScale(String unit) => unit == 'USD' ? 1e9 : 1;

String inputUnitLabel(String unit) => unit == 'USD' ? '\$B' : unit;

class FiltersPanel extends StatefulWidget {
  const FiltersPanel({
    super.key,
    required this.metrics,
    required this.filters,
    required this.onChanged,
    required this.onClearAll,
    required this.onClose,
  });

  final List<MetricDefinition> metrics;
  final Map<String, RangeFilter> filters;
  final void Function(String metricKey, RangeFilter filter) onChanged;
  final VoidCallback onClearAll;
  final VoidCallback onClose;

  @override
  State<FiltersPanel> createState() => _FiltersPanelState();
}

class _FiltersPanelState extends State<FiltersPanel> {
  final Map<String, TextEditingController> _minControllers = {};
  final Map<String, TextEditingController> _maxControllers = {};

  @override
  void initState() {
    super.initState();
    // Fill the boxes with filters that were set before the panel was (re)opened.
    for (final metric in widget.metrics) {
      final filter = widget.filters[metric.key];
      final scale = inputScale(metric.unit);
      _minControllers[metric.key] = TextEditingController(text: _toText(filter?.min, scale));
      _maxControllers[metric.key] = TextEditingController(text: _toText(filter?.max, scale));
    }
  }

  @override
  void dispose() {
    for (final controller in [..._minControllers.values, ..._maxControllers.values]) {
      controller.dispose();
    }
    super.dispose();
  }

  String _toText(double? value, double scale) {
    if (value == null) return '';
    final shown = value / scale;
    return shown == shown.roundToDouble() ? shown.toInt().toString() : shown.toString();
  }

  double? _parse(String text, double scale) {
    final number = double.tryParse(text.trim().replaceAll(',', ''));
    return number == null ? null : number * scale;
  }

  void _update(MetricDefinition metric) {
    final scale = inputScale(metric.unit);
    widget.onChanged(
      metric.key,
      RangeFilter(
        min: _parse(_minControllers[metric.key]!.text, scale),
        max: _parse(_maxControllers[metric.key]!.text, scale),
      ),
    );
  }

  void _clearAll() {
    for (final controller in [..._minControllers.values, ..._maxControllers.values]) {
      controller.clear();
    }
    widget.onClearAll();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <Widget>[];
    String? currentGroup;
    for (final metric in widget.metrics) {
      if (metric.group != currentGroup) {
        currentGroup = metric.group;
        rows.add(Padding(
          padding: const EdgeInsets.only(top: Space.md, bottom: Space.xs),
          child: Text(metric.group, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
        ));
      }
      rows.add(_filterRow(metric));
    }

    return Container(
      width: 340,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(left: BorderSide(color: theme.colorScheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.sm, 0),
            child: Row(
              children: [
                Text('Filters', style: theme.textTheme.titleMedium),
                const Spacer(),
                TextButton(onPressed: _clearAll, child: const Text('Clear all')),
                IconButton(onPressed: widget.onClose, icon: const Icon(Icons.close), tooltip: 'Close filters'),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.lg),
            child: Text(
              'Companies with a missing value (—) are hidden when that metric has a filter.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg), children: rows),
          ),
        ],
      ),
    );
  }

  Widget _filterRow(MetricDefinition metric) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        children: [
          Expanded(
            child: Tooltip(
              message: metric.formula,
              child: Text('${metric.label} (${inputUnitLabel(metric.unit)})', style: const TextStyle(fontSize: FontSizes.body)),
            ),
          ),
          _numberBox(_minControllers[metric.key]!, 'min', metric),
          const SizedBox(width: Space.sm),
          _numberBox(_maxControllers[metric.key]!, 'max', metric),
        ],
      ),
    );
  }

  Widget _numberBox(TextEditingController controller, String hint, MetricDefinition metric) {
    return SizedBox(
      width: 72,
      child: TextField(
        controller: controller,
        onChanged: (_) => _update(metric),
        textAlign: TextAlign.right,
        style: const TextStyle(fontSize: FontSizes.body),
        keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
        decoration: InputDecoration(
          hintText: hint,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.sm),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
