import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons.dart';
import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/category_picker.dart';
import '../../widgets/empty_state.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  bool _expensesExpanded = true;
  bool _incomeExpanded = true;

  @override
  Widget build(BuildContext context) {
    final tree = ref.watch(categoryTreeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Categories')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/category/edit?type=1'),
        child: const Icon(Icons.add),
      ),
      body: tree.when(
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.category_outlined,
              title: 'No categories',
              message: 'Create categories to organise your spending.',
            );
          }
          final expenses = items
              .where((category) => category.type == 1)
              .toList();
          final incomes = items
              .where((category) => category.type == 2)
              .toList();
          return ListView(
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              _SectionHeader(
                title: 'Expenses',
                icon: Icons.north_east,
                expanded: _expensesExpanded,
                onToggle: () => setState(
                  () => _expensesExpanded = !_expensesExpanded,
                ),
              ),
              if (_expensesExpanded)
                for (final category in expenses)
                  _CategoryTile(category: category, depth: 0),
              if (incomes.isNotEmpty) ...[
                _SectionHeader(
                  title: 'Income',
                  icon: Icons.south_west,
                  expanded: _incomeExpanded,
                  onToggle: () => setState(
                    () => _incomeExpanded = !_incomeExpanded,
                  ),
                ),
                if (_incomeExpanded)
                  for (final category in incomes)
                    _CategoryTile(category: category, depth: 0),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            Center(child: Text('Could not load categories:\n$error')),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.icon,
    required this.expanded,
    required this.onToggle,
  });

  final String title;
  final IconData icon;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 4),
        child: Row(
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 8),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            AnimatedRotation(
              turns: expanded ? 0 : -0.25,
              duration: const Duration(milliseconds: 180),
              child: Icon(
                Icons.expand_more,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends ConsumerStatefulWidget {
  const _CategoryTile({required this.category, required this.depth});

  final Category category;
  final int depth;

  @override
  ConsumerState<_CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends ConsumerState<_CategoryTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final category = widget.category;
    final hasChildren = category.children.isNotEmpty;
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.only(
            left: 16 + widget.depth * 28.0,
            right: 8,
          ),
          leading: _icon(category),
          title: _title(category),
          subtitle: category.usages == 0
              ? null
              : Text('${category.usages} transactions'),
          onTap: () => context.push('/category/edit?id=${category.id}'),
          onLongPress: () => context.push(
            '/category/edit?type=${category.type}&parent=${category.id}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Delete category',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteCategory(context, category),
              ),
              if (hasChildren)
                IconButton(
                  tooltip: _expanded ? 'Collapse' : 'Expand',
                  icon: AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.expand_more),
                  ),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
            ],
          ),
        ),
        if (_expanded)
          for (final child in category.children)
            _CategoryTile(category: child, depth: widget.depth + 1),
      ],
    );
  }

  Widget _icon(Category item) {
    final color = colorFromDb(item.color);
    return CircleAvatar(
      radius: 18,
      backgroundColor: color.withValues(alpha: 0.18),
      child: Icon(iconForCategory(item.icon), size: 18, color: color),
    );
  }

  Widget _title(Category item) {
    return Text(
      item.label,
      style: const TextStyle(fontWeight: FontWeight.w500),
    );
  }

  Future<void> _deleteCategory(BuildContext context, Category item) async {
    final repo = ref.read(repositoryProvider);
    final count = await repo.categoryTransactionCount(item.id);
    if (!context.mounted) return;

    if (count == 0) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete ${item.label}?'),
          content: const Text('This cannot be undone.'),
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
      await repo.deleteCategoryWithTransactions(
        item.id,
        deleteTransactions: false,
      );
      _refresh();
      return;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${item.label}?'),
        content: Text(
          '$count transactions are assigned to this category. '
          'What should happen to them?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('move'),
            child: const Text('Assign category'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop('delete'),
            child: const Text('Delete transactions'),
          ),
        ],
      ),
    );
    if (action == null || !context.mounted) return;

    if (action == 'delete') {
      await repo.deleteCategoryWithTransactions(
        item.id,
        deleteTransactions: true,
      );
      _refresh();
      return;
    }

    final categories = ref.read(categoriesProvider).value ?? const <Category>[];
    final descendants = (await repo.categoryDescendants(item.id)).toSet();
    final possible = categories
        .where((category) => !descendants.contains(category.id))
        .toList();
    if (!context.mounted) return;
    final target = await showCategoryPicker(
      context,
      possible,
      initialId: item.parentId,
      allowNone: true,
    );
    if (target == null) return;
    await repo.deleteCategoryWithTransactions(
      item.id,
      deleteTransactions: false,
      targetCategoryId: target == noCategoryId ? null : target,
    );
    _refresh();
  }

  void _refresh() {
    ref.invalidate(categoriesProvider);
    ref.invalidate(categoryTreeProvider);
    invalidateTransactionData(ref);
  }
}
