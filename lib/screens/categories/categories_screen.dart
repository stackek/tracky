import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/icons.dart';
import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/empty_state.dart';

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(categoryTreeProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        actions: [
          IconButton(
            tooltip: 'Add category',
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/category/edit?type=1'),
          ),
        ],
      ),
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
                onAdd: () => context.push('/category/edit?type=1'),
              ),
              for (final category in expenses) _CategoryTile(category: category),
              if (incomes.isNotEmpty) ...[
                _SectionHeader(
                  title: 'Income',
                  icon: Icons.south_west,
                  onAdd: () => context.push('/category/edit?type=2'),
                ),
                for (final category in incomes)
                  _CategoryTile(category: category),
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
    required this.onAdd,
  });

  final String title;
  final IconData icon;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 8, 4),
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
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add $title category',
            onPressed: onAdd,
          ),
        ],
      ),
    );
  }
}

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({required this.category});

  final Category category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (category.children.isEmpty) {
      return _row(context, ref, category, 0);
    }
    return ExpansionTile(
      leading: _icon(category),
      title: _title(context, category),
      childrenPadding: const EdgeInsets.only(left: 16),
      children: [
        for (final child in category.children)
          _row(context, ref, child, 1),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    WidgetRef ref,
    Category item,
    int depth,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.only(left: 16 + depth * 28.0, right: 8),
      leading: _icon(item),
      title: _title(context, item),
      subtitle: item.usages == 0
          ? null
          : Text('${item.usages} transactions'),
      trailing: PopupMenuButton<String>(
        onSelected: (value) async {
          if (value == 'edit') {
            context.push('/category/edit?id=${item.id}');
          } else if (value == 'delete') {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('Delete ${item.label}?'),
                content: const Text(
                  'Transactions in this category will be moved to its parent '
                  'or become uncategorized.',
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
            if (confirmed == true) {
              try {
                await ref.read(repositoryProvider).deleteCategory(item.id);
                ref.invalidate(categoriesProvider);
                ref.invalidate(categoryTreeProvider);
                ref.invalidate(transactionsProvider);
                ref.invalidate(statsProvider);
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not delete: $error')),
                  );
                }
              }
            }
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
      onTap: () => context.push('/category/edit?id=${item.id}'),
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

  Widget _title(BuildContext context, Category item) {
    return Text(
      item.label,
      style: const TextStyle(fontWeight: FontWeight.w500),
    );
  }
}
