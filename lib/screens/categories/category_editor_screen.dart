import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons.dart';
import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/search_picker.dart';

class CategoryEditorScreen extends ConsumerStatefulWidget {
  const CategoryEditorScreen({
    super.key,
    this.categoryId,
    this.initialType = 1,
  });

  final int? categoryId;
  final int initialType;

  @override
  ConsumerState<CategoryEditorScreen> createState() =>
      _CategoryEditorScreenState();
}

class _CategoryEditorScreenState extends ConsumerState<CategoryEditorScreen> {
  final _labelController = TextEditingController();
  final _iconSearchController = TextEditingController();
  String _iconSearch = '';
  bool _loading = true;
  bool _dirty = false;
  int? _categoryId;
  int _type = 1;
  int? _parentId;
  int _color = categoryColorChoices.first;
  String _icon = 'category';

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _labelController.addListener(_markDirty);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _markDirty() => _dirty = true;

  @override
  void dispose() {
    _labelController.dispose();
    _iconSearchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.categoryId != null) {
      final category = await ref
          .read(repositoryProvider)
          .category(widget.categoryId!);
      if (category != null) {
        _categoryId = category.id;
        _labelController.text = category.label;
        _type = category.type == 0 ? widget.initialType : category.type;
        _parentId = category.parentId == category.id ? null : category.parentId;
        _color = category.color ?? categoryColorChoices.first;
        _icon = category.icon ?? 'category';
      }
    }
    _dirty = false;
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final categories =
        ref.watch(categoriesProvider).value ?? const <Category>[];
    final possibleParents = categories
        .where((category) => category.id != _categoryId)
        .where((category) => category.type == _type)
        .toList();
    final query = _iconSearch.trim().toLowerCase();
    final iconChoices = allCategoryIcons
        .where(
          (entry) =>
              query.isEmpty ||
              entry.key.toLowerCase().contains(query) ||
              iconSearchLabel(entry.key).toLowerCase().contains(query),
        )
        .toList();
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_categoryId == null ? 'New category' : 'Edit category'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
        children: [
          TextField(
            controller: _labelController,
            autofocus: _categoryId == null,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(Icons.label_outline),
            ),
          ),
          const SizedBox(height: 12),
          if (_parentId == null)
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 1,
                  label: Text('Expense'),
                  icon: Icon(Icons.north_east),
                ),
                ButtonSegment(
                  value: 2,
                  label: Text('Income'),
                  icon: Icon(Icons.south_west),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (value) => setState(() {
                _dirty = true;
                _type = value.first;
              }),
            ),
          const SizedBox(height: 12),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
            leading: const Icon(Icons.account_tree_outlined),
            title: const Text('Parent category'),
            subtitle: Text(
              _parentId == null
                  ? 'None (top level)'
                  : possibleParents
                            .where((category) => category.id == _parentId)
                            .firstOrNull
                            ?.displayPath ??
                        'None (top level)',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final value = await showSearchPicker<int>(
                context: context,
                title: 'Parent category',
                hint: 'Search categories',
                selected: _parentId ?? -1,
                allowNone: true,
                noneLabel: 'None (top level)',
                noneValue: -1,
                entries: [
                  for (final category in possibleParents)
                    PickerEntry(
                      value: category.id,
                      label: category.label,
                      subtitle: category.displayPath,
                      icon: iconForCategory(category.icon),
                      color: colorFromDb(category.color),
                    ),
                ],
              );
              if (value == null) return;
              setState(() {
                _dirty = true;
                _parentId = value == -1 ? null : value;
                final parent = possibleParents
                    .where((category) => category.id == _parentId)
                    .firstOrNull;
                if (parent != null) _type = parent.type;
              });
            },
          ),
          const SizedBox(height: 20),
          Text('Colour', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final color in categoryColorChoices)
                InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: () => setState(() {
                      _dirty = true;
                      _color = color;
                    }),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: colorFromDb(color),
                      shape: BoxShape.circle,
                      border: _color == color
                          ? Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 3,
                            )
                          : null,
                    ),
                    child: _color == color
                        ? const Icon(Icons.check, size: 18, color: Colors.white)
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Text('Icon', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(width: 8),
              Text(
                '${allCategoryIcons.length} icons',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _iconSearchController,
            decoration: InputDecoration(
              hintText: 'Search icons by name',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _iconSearch.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _iconSearchController.clear();
                        setState(() => _iconSearch = '');
                      },
                    ),
            ),
            onChanged: (value) => setState(() => _iconSearch = value),
          ),
          const SizedBox(height: 8),
          Container(
            height: 280,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
            ),
            child: iconChoices.isEmpty
                ? const Center(child: Text('No icons match your search'))
                : GridView.builder(
                    padding: const EdgeInsets.all(10),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                        ),
                    itemCount: iconChoices.length,
                    itemBuilder: (context, index) {
                      final entry = iconChoices[index];
                      final selected = entry.key == _icon;
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() {
                          _dirty = true;
                          _icon = entry.key;
                        }),
                        child: Container(
                          decoration: BoxDecoration(
                            color: selected
                                ? colorFromDb(_color).withValues(alpha: 0.22)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: selected
                                ? Border.all(
                                    color: colorFromDb(_color),
                                    width: 2,
                                  )
                                : null,
                          ),
                          child: Tooltip(
                            message: iconSearchLabel(entry.key),
                            child: Icon(
                              entry.value,
                              color: selected
                                  ? colorFromDb(_color)
                                  : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (_categoryId != null) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete category'),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _save,
            child: const Text('Save category'),
          ),
        ),
      ),
      ),
    );
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your changes have not been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      _dirty = false;
      context.pop();
    }
  }

  Future<void> _save() async {
    final label = _labelController.text.trim();
    if (label.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a category name.')));
      return;
    }
    final repo = ref.read(repositoryProvider);
    try {
      if (_categoryId == null) {
        await repo.insertCategory(
          label: label,
          type: _type,
          parentId: _parentId,
          color: _color,
          icon: _icon,
        );
      } else {
        await repo.updateCategory(
          _categoryId!,
          label: label,
          color: _color,
          icon: _icon,
          parentId: _parentId,
          type: _type,
          updateParent: true,
        );
      }
      ref.invalidate(categoriesProvider);
      ref.invalidate(categoryTreeProvider);
      ref.invalidate(transactionsProvider);
      ref.invalidate(statsProvider);
      _dirty = false;
      if (mounted) context.pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $error')));
      }
    }
  }

  Future<void> _delete() async {
    if (_categoryId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete category?'),
        content: const Text(
          'Transactions in this category will be moved to its parent or become '
          'uncategorized. Subcategories will also be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(repositoryProvider).deleteCategory(_categoryId!);
      ref.invalidate(categoriesProvider);
      ref.invalidate(categoryTreeProvider);
      ref.invalidate(transactionsProvider);
      ref.invalidate(statsProvider);
      _dirty = false;
      if (mounted) context.pop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not delete: $error')));
      }
    }
  }
}
