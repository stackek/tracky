import 'package:flutter/material.dart';

class PickerEntry<T> {
  const PickerEntry({
    required this.value,
    required this.label,
    this.subtitle,
    this.icon,
    this.color,
  });

  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
  final Color? color;
}

Future<T?> showSearchPicker<T>({
  required BuildContext context,
  required String title,
  required List<PickerEntry<T>> entries,
  T? selected,
  String hint = 'Search',
  bool allowNone = false,
  String noneLabel = 'None',
  T? noneValue,
}) {
  var query = '';
  final filtered = <PickerEntry<T>>[];

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final term = query.trim().toLowerCase();
        filtered
          ..clear()
          ..addAll(
            term.isEmpty
                ? entries
                : entries.where(
                    (entry) =>
                        entry.label.toLowerCase().contains(term) ||
                        (entry.subtitle?.toLowerCase().contains(term) ?? false),
                  ),
          );
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (context, controller) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: hint,
                    prefixIcon: const Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => query = value),
                ),
              ),
              if (allowNone && term.isEmpty)
                ListTile(
                  leading: const Icon(Icons.block),
                  title: Text(noneLabel),
                  selected: selected == noneValue,
                  trailing: selected == noneValue
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => Navigator.of(context).pop(noneValue),
                ),
              Expanded(
                child: filtered.isEmpty
                    ? const Center(child: Text('No matches'))
                    : ListView.builder(
                        controller: controller,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final entry = filtered[index];
                          final isSelected = entry.value == selected;
                          return ListTile(
                            selected: isSelected,
                            leading: entry.icon == null
                                ? null
                                : Icon(entry.icon, color: entry.color),
                            title: Text(entry.label),
                            subtitle: entry.subtitle == null
                                ? null
                                : Text(entry.subtitle!),
                            trailing: isSelected
                                ? const Icon(Icons.check)
                                : null,
                            onTap: () => Navigator.of(context).pop(entry.value),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class SheetAction<T> {
  const SheetAction({
    required this.value,
    required this.label,
    required this.icon,
    this.destructive = false,
  });

  final T value;
  final String label;
  final IconData icon;
  final bool destructive;
}

Future<T?> showActionSheet<T>(
  BuildContext context, {
  required String title,
  required List<SheetAction<T>> actions,
}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          for (final action in actions)
            ListTile(
              leading: Icon(
                action.icon,
                color: action.destructive
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
              title: Text(
                action.label,
                style: action.destructive
                    ? TextStyle(color: Theme.of(context).colorScheme.error)
                    : null,
              ),
              onTap: () => Navigator.of(context).pop(action.value),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
