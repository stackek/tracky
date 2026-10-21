import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_expenses_open/core/ui_utils.dart';

import '../../core/currency.dart';
import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../models/models.dart';
import '../../providers.dart';
import '../transactions/transaction_editor_screen.dart'
    show showCategoryPicker, noCategoryId;

class BudgetDetailScreen extends ConsumerStatefulWidget {
  const BudgetDetailScreen({super.key, required this.budgetId});

  final int budgetId;

  @override
  ConsumerState<BudgetDetailScreen> createState() => _BudgetDetailScreenState();
}

class _BudgetDetailScreenState extends ConsumerState<BudgetDetailScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  Widget build(BuildContext context) {
    final budgets = ref.watch(budgetsProvider).value ?? const <Budget>[];
    final budget = budgets.where((b) => b.id == widget.budgetId).firstOrNull;
    if (budget == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Budget')),
        body: const Center(child: Text('Budget not found.')),
      );
    }
    final period = BudgetPeriod(budget.id, _month.year, _month.month);
    final allocations = ref.watch(budgetAllocationsProvider(period));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(budget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add category allocation',
            onPressed: () => _addAllocation(budget),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () =>
                    setState(() => _month = DateTime(_month.year, _month.month - 1, 1)),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  formatMonth(_month),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                onPressed: () =>
                    setState(() => _month = DateTime(_month.year, _month.month + 1, 1)),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 8),
          allocations.when(
            data: (items) {
              final planned =
                  items.fold<int>(0, (sum, item) => sum + item.budget);
              final spent = items.fold<int>(0, (sum, item) => sum + item.spent);
              final remaining = planned - spent;
              final progress = planned <= 0 ? 0.0 : (spent / planned).clamp(0.0, 1.0);
              return Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          remaining >= 0 ? 'Left to spend' : 'Over budget',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          formatMoney(remaining.abs(), budget.currency),
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: LinearProgressIndicator(
                            value: progress.toDouble(),
                            minHeight: 8,
                            backgroundColor: theme.colorScheme.surface
                                .withValues(alpha: 0.35),
                            color: remaining >= 0
                                ? theme.colorScheme.primary
                                : theme.colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${formatMoney(spent, budget.currency)} of '
                          '${formatMoney(planned, budget.currency)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          const Icon(Icons.category_outlined, size: 48),
                          const SizedBox(height: 10),
                          const Text('No category allocations yet.'),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () => _addAllocation(budget),
                            child: const Text('Add category'),
                          ),
                        ],
                      ),
                    )
                  else
                    for (final allocation in items)
                      _AllocationTile(
                        allocation: allocation,
                        currency: budget.currency,
                        onEdit: () => _editAllocation(budget, allocation),
                        onDelete: () async {
                          await ref
                              .read(repositoryProvider)
                              .deleteBudgetAllocation(
                                budget.id,
                                allocation.categoryId,
                                year: _month.year,
                                month: _month.month,
                              );
                          ref.invalidate(budgetAllocationsProvider(period));
                          ref.invalidate(budgetsProvider);
                        },
                      ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) =>
                Center(child: Text('Could not load budget:\n$error')),
          ),
        ],
      ),
    );
  }

  Future<void> _addAllocation(Budget budget) async {
    final categories =
        ref.read(categoriesProvider).value ?? const <Category>[];
    final selected = await showCategoryPicker(
      context,
      categories.where((category) => category.type == 1).toList(),
    );
    if (selected == null || selected == noCategoryId) return;
    final category = categories.where((c) => c.id == selected).firstOrNull;
    if (category == null) return;
    await _editAllocation(
      budget,
      BudgetAllocation(
        budgetId: budget.id,
        categoryId: category.id,
        budget: 0,
        rollOverPrevious: 0,
        rollOverNext: 0,
        oneTime: false,
        spent: 0,
        categoryLabel: category.label,
        categoryIcon: category.icon,
        categoryColor: category.color,
      ),
    );
  }

  Future<void> _editAllocation(
    Budget budget,
    BudgetAllocation allocation,
  ) async {
    final controller = TextEditingController(
      text: allocation.budget == 0
          ? ''
          : formatMoneyPlain(allocation.budget, budget.currency),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(allocation.categoryLabel),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(
            labelText: 'Monthly budget',
            suffixText: budget.currency,
          ),
          onSubmitted: (_) => Navigator.of(context).pop(1),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(1),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final parsed = parseAmountToMinor(controller.text, budget.currency);
    disposeAfterDialog([controller]);
    if (result == null || parsed == null) return;
    await ref.read(repositoryProvider).saveBudgetAllocation(
          budgetId: budget.id,
          categoryId: allocation.categoryId,
          year: _month.year,
          month: _month.month,
          budget: parsed,
        );
    ref.invalidate(budgetAllocationsProvider(
      BudgetPeriod(budget.id, _month.year, _month.month),
    ));
    ref.invalidate(budgetsProvider);
  }
}

class _AllocationTile extends StatelessWidget {
  const _AllocationTile({
    required this.allocation,
    required this.currency,
    required this.onEdit,
    required this.onDelete,
  });

  final BudgetAllocation allocation;
  final String currency;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = allocation.budget <= 0
        ? 0.0
        : (allocation.spent / allocation.budget).clamp(0.0, 1.0);
    final over = allocation.spent > allocation.budget;
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    colorFromDb(allocation.categoryColor).withValues(alpha: 0.18),
                child: Icon(
                  iconForCategory(allocation.categoryIcon),
                  color: colorFromDb(allocation.categoryColor),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      allocation.categoryLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress.toDouble(),
                        minHeight: 6,
                        color: over
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatMoney(allocation.spent, currency)} of '
                      '${formatMoney(allocation.budget, currency)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
