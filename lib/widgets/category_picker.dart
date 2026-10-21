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

  bool containsId(Category category, int? id) {
    if (id == null) return false;
    if (category.id == id) return true;
    return (children[category.id] ?? const []).any(
      (child) => containsId(child, id),
    );
  }

  Widget tile(Category category) {
    final selected = category.id == initialId;
    final leading = Icon(
      iconForCategory(category.icon),
      color: colorFromDb(category.color),
    );
    final title = Text(category.label);
    final trailing = selected ? const Icon(Icons.check) : null;
    final childCategories = children[category.id] ?? const <Category>[];
    if (childCategories.isEmpty) {
      return ListTile(
        selected: selected,
        leading: leading,
        title: title,
        trailing: trailing,
        onTap: () => Navigator.of(context).pop(category.id),
      );
    }
    return ExpansionTile(
      initiallyExpanded: containsId(category, initialId),
      leading: leading,
      title: title,
      trailing: trailing,
      shape: const Border(),
      collapsedShape: const Border(),
      childrenPadding: const EdgeInsets.only(left: 16),
      children: [
        ListTile(
          contentPadding: const EdgeInsets.only(left: 24, right: 16),
          leading: Icon(
            iconForCategory(category.icon),
            size: 20,
            color: colorFromDb(category.color),
          ),
          title: Text(category.label),
          trailing: selected ? const Icon(Icons.check) : null,
          selected: selected,
          onTap: () => Navigator.of(context).pop(category.id),
        ),
        for (final child in childCategories) tile(child),
      ],
    );
  }

  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
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
                        children: [for (final root in roots) tile(root)],
                      ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
