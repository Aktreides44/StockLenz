// The "Columns" window: tick boxes to show or hide screener columns (wide screens only).
import 'package:flutter/material.dart';

import 'models.dart';
import 'screener_table.dart';
import 'theme.dart';

/// Opens the window. [onChanged] is called after every tick with the new set of hidden column keys,
/// so the table behind the window changes right away.
Future<void> showColumnsDialog(
  BuildContext context, {
  required List<ScreenerColumn> columns,
  required List<MetricDefinition> metrics,
  required Set<String> hidden,
  required void Function(Set<String> hidden) onChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => _ColumnsDialog(columns: columns, metrics: metrics, hidden: hidden, onChanged: onChanged),
  );
}

class _ColumnsDialog extends StatefulWidget {
  const _ColumnsDialog({required this.columns, required this.metrics, required this.hidden, required this.onChanged});

  final List<ScreenerColumn> columns;
  final List<MetricDefinition> metrics;
  final Set<String> hidden;
  final void Function(Set<String> hidden) onChanged;

  @override
  State<_ColumnsDialog> createState() => _ColumnsDialogState();
}

class _ColumnsDialogState extends State<_ColumnsDialog> {
  late Set<String> _hidden = {...widget.hidden};

  void _set(Set<String> hidden) {
    setState(() => _hidden = hidden);
    widget.onChanged(hidden);
  }

  /// Show or hide one column. Builds a new set, so the old one is never changed in place.
  void _toggle(String key, bool shown) {
    _set(shown ? ({..._hidden}..remove(key)) : ({..._hidden}..add(key)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groupOf = {for (final metric in widget.metrics) metric.key: metric.group};

    // Same groups as the filters; sector, FY and price form a "Company" group at the top.
    final groups = <String, List<ScreenerColumn>>{};
    for (final column in widget.columns) {
      groups.putIfAbsent(groupOf[column.key] ?? 'Company', () => []).add(column);
    }

    return AlertDialog(
      title: const Text('Columns'),
      content: SizedBox(
        width: 360,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text('Ticker and name always stay. Your choice is saved on this device.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            for (final entry in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: Space.md, bottom: Space.xs),
                child: Text(entry.key, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
              ),
              for (final column in entry.value)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(column.label),
                  value: !_hidden.contains(column.key),
                  onChanged: (shown) => _toggle(column.key, shown == true),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _hidden.isEmpty ? null : () => _set(<String>{}), child: const Text('Show all')),
        FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ],
    );
  }
}
