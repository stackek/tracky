import 'package:collection/collection.dart';
import 'package:flutter/material.dart';

import '../core/icons.dart';
import '../models/models.dart';

const int noCategoryId = -1;
const int cancelCategoryId = -2;

Future<int?> showCategoryPicker(
  BuildContext context,
  List<Category> categories, {
  int? initialId,
  bool allowNone = false,
}) {
  var query = '';
  final ids = categories.map((category) => category.id).toSet();
  final roots =
      categories
          .where(
            (category) =>
                category.parentId == null ||
                category.parentId == 0 ||
                category.parentId == category.id ||
                !ids.contains(category.parentId),
          )
          .toList()
        ..sort(
          (a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()),
        );
  final children = <int, List<Category>>{};
  for (final category in categories) {
    final parent = category.parentId;
    if (parent != null &&
        parent != 0 &&
        parent != category.id &&
        ids.contains(parent)) {
      children.putIfAbsent(parent, () => []).add(category);
    }
  }
  for (final list in children.values) {
    list.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
  }

  final expanded = <int>{};
  var current = initialId;
  var guard = 0;
  while (current != null && guard++ < 50) {
    final category = categories.where((item) => item.id == current).firstOrNull;
    if (category == null) break;
    final parent = category.parentId;
    if (parent == null || parent == 0 || parent == category.id) break;
    expanded.add(parent);
    current = parent;
  }

  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        Widget tile(Category category, int depth) {
          final selected = category.id == initialId;
          final childCategories = children[category.id] ?? const <Category>[];
          final isExpanded = expanded.contains(category.id);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                selected: selected,
                contentPadding: EdgeInsets.only(
                  left: 16.0 + depth * 20,
                  right: 8,
                ),
                leading: Icon(
                  iconForCategory(category.icon),
                  color: colorFromDb(category.color),
                ),
                title: Text(category.label),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected) const Icon(Icons.check),
                    if (childCategories.isNotEmpty)
                      IconButton(
                        tooltip: isExpanded ? 'Collapse' : 'Expand',
                        icon: AnimatedRotation(
                          turns: isExpanded ? 0.5 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: const Icon(Icons.expand_more),
                        ),
                        onPressed: () => setState(() {
                          if (!expanded.remove(category.id)) {
                            expanded.add(category.id);
                          }
                        }),
                      ),
                  ],
                ),
                onTap: () => Navigator.of(context).pop(category.id),
              ),
              if (isExpanded)
                for (final child in childCategories) tile(child, depth + 1),
            ],
          );
        }

        final searching = query.trim().isNotEmpty;
        final filtered = categories
            .where(
              (category) => category.displayPath.toLowerCase().contains(
                query.toLowerCase(),
              ),
            )
            .toList();
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          builder: (context, controller) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: false,
                  decoration: const InputDecoration(
                    hintText: 'Search categories',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) => setState(() => query = value),
                ),
              ),
              if (allowNone && !searching)
                ListTile(
                  leading: const Icon(Icons.block),
                  title: const Text('No category'),
                  onTap: () => Navigator.of(context).pop(noCategoryId),
                ),
              Expanded(
                child: searching
                    ? ListView.builder(
                        controller: controller,
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final category = filtered[index];
                          final selected = category.id == initialId;
                          return ListTile(
                            selected: selected,
                            leading: Icon(
                              iconForCategory(category.icon),
                              color: colorFromDb(category.color),
                            ),
                            title: Text(category.label),
                            subtitle: category.parentId == null
                                ? null
                                : Text(category.displayPath),
                            trailing: selected ? const Icon(Icons.check) : null,
                            onTap: () => Navigator.of(context).pop(category.id),
                          );
                        },
                      )
                    : ListView(
                        controller: controller,
                        children: [for (final root in roots) tile(root, 0)],
                      ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
