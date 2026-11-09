// Filter presets: a named set of filters (and optionally a sector) that is filled in with one tap.
// A few examples come with the app; the user can save their own, which are kept on this device
// (see device_settings.dart). Presets are just filters — facts about the numbers, not advice.
import 'package:flutter/material.dart';

import 'filters_panel.dart';
import 'theme.dart';

class FilterPreset {
  const FilterPreset({required this.name, this.sector, required this.filters});

  final String name;

  /// null means "all sectors".
  final String? sector;

  /// Metric key → min/max, in the same units the filters use (dollar amounts in plain dollars).
  final Map<String, RangeFilter> filters;

  /// Short description for the menu, e.g. "ROE ≥ 15 · P/E (TTM) ≤ 15".
  String summary(Map<String, String> labels) {
    final parts = <String>[
      ?sector, // only added when a sector is set
      for (final entry in filters.entries) _describe(labels[entry.key] ?? entry.key, entry.value),
    ];
    return parts.join(' · ');
  }

  static String _describe(String label, RangeFilter filter) {
    String number(double value) => value == value.roundToDouble() ? value.toInt().toString() : '$value';
    if (filter.min != null && filter.max != null) return '$label ${number(filter.min!)}–${number(filter.max!)}';
    if (filter.min != null) return '$label ≥ ${number(filter.min!)}';
    return '$label ≤ ${number(filter.max!)}';
  }

  // Stored as JSON, e.g. {"name": "My picks", "sector": null, "filters": {"roe": {"min": 15, "max": null}}}
  Map<String, Object?> toJson() => {
        'name': name,
        'sector': sector,
        'filters': {
          for (final entry in filters.entries) entry.key: {'min': entry.value.min, 'max': entry.value.max},
        },
      };

  factory FilterPreset.fromJson(Map<String, dynamic> json) {
    final filters = <String, RangeFilter>{};
    (json['filters'] as Map<String, dynamic>? ?? {}).forEach((key, value) {
      final range = value as Map<String, dynamic>;
      filters[key] = RangeFilter(min: (range['min'] as num?)?.toDouble(), max: (range['max'] as num?)?.toDouble());
    });
    return FilterPreset(name: json['name'] as String, sector: json['sector'] as String?, filters: filters);
  }
}

/// Examples that come with the app. Common rules of thumb, explained in the README.
const examplePresets = [
  FilterPreset(name: 'Profitable & low debt', filters: {
    'net_margin': RangeFilter(min: 0),
    'debt_to_equity': RangeFilter(max: 0.5),
  }),
  FilterPreset(name: 'High return on equity', filters: {'roe': RangeFilter(min: 15)}),
  FilterPreset(name: 'Growing revenue', filters: {'revenue_cagr_3y': RangeFilter(min: 10)}),
  FilterPreset(name: 'Low P/E', filters: {'pe_ttm': RangeFilter(min: 0, max: 15)}),
];

/// The "Presets" button and its menu: examples, the user's own presets (with a delete button)
/// and "Save current filters…".
class PresetsMenu extends StatelessWidget {
  const PresetsMenu({
    super.key,
    required this.saved,
    required this.labels,
    required this.onApply,
    required this.onSaveCurrent,
    required this.onDelete,
    this.iconOnly = false,
  });

  final List<FilterPreset> saved;

  /// Metric key → label, for the short descriptions.
  final Map<String, String> labels;
  final void Function(FilterPreset preset) onApply;

  /// null while no filter is set (then there is nothing to save).
  final VoidCallback? onSaveCurrent;
  final void Function(FilterPreset preset) onDelete;

  /// Phones: only the icon, to save space.
  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.xs),
          child: Text(text, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.primary)),
        );
    Widget item(FilterPreset preset, {Widget? trailing}) => MenuItemButton(
          onPressed: () => onApply(preset),
          trailingIcon: trailing,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(preset.name, overflow: TextOverflow.ellipsis),
                Text(
                  preset.summary(labels),
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        );

    return MenuAnchor(
      menuChildren: [
        heading('Examples'),
        for (final preset in examplePresets) item(preset),
        const Divider(),
        heading('My presets'),
        if (saved.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs),
            child: Text('None yet', style: theme.textTheme.bodySmall),
          ),
        for (final preset in saved)
          item(
            preset,
            trailing: IconButton(
              onPressed: () => onDelete(preset),
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Delete "${preset.name}"',
              visualDensity: VisualDensity.compact,
            ),
          ),
        const Divider(),
        MenuItemButton(
          onPressed: onSaveCurrent,
          leadingIcon: const Icon(Icons.bookmark_add_outlined),
          child: const Text('Save current filters…'),
        ),
      ],
      builder: (context, controller, _) {
        void toggle() => controller.isOpen ? controller.close() : controller.open();
        if (iconOnly) {
          return IconButton.outlined(onPressed: toggle, icon: const Icon(Icons.bookmarks_outlined), tooltip: 'Presets');
        }
        return OutlinedButton.icon(onPressed: toggle, icon: const Icon(Icons.bookmarks_outlined), label: const Text('Presets'));
      },
    );
  }
}

/// Asks for a name for the new preset. Returns null if the user cancels.
Future<String?> askPresetName(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) {
      void save() {
        final name = controller.text.trim();
        if (name.isNotEmpty) Navigator.of(context).pop(name);
      }

      return AlertDialog(
        title: const Text('Save filters as a preset'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. My dividend ideas'),
          onSubmitted: (_) => save(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: save, child: const Text('Save')),
        ],
      );
    },
  );
  // The controller is not disposed here: the dialog still shows it during its closing animation.
  // It holds no resources, so the garbage collector cleans it up.
}
