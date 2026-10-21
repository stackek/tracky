import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:my_expenses_open/core/ui_utils.dart';
import 'package:go_router/go_router.dart';

import '../../core/currency.dart';
import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/search_picker.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Budgets'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addBudget(context, ref),
          ),
        ],
      ),
      body: budgets.when(
        data: (items) => items.isEmpty
            ? EmptyState(
                icon: Icons.savings_outlined,
                title: 'No budgets yet',
                message: 'Create a monthly budget and allocate amounts to categories.',
                actionLabel: 'Create budget',
                onAction: () => _addBudget(context, ref),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  for (final budget in items) ...[
                    _BudgetCard(budget: budget),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            Center(child: Text('Could not load budgets:\n$error')),
      ),
    );
  }

  Future<void> _addBudget(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final description = TextEditingController();
    final accounts =
        ref.read(activeAccountsProvider).value ?? const <Account>[];
    int? accountId = accounts.firstOrNull?.id;
    final settings = ref.read(settingsProvider);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('New budget'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('Account'),
                  subtitle: Text(
                    accountId == null
                        ? 'All accounts'
                        : accounts
                                  .where((account) => account.id == accountId)
                                  .firstOrNull
                                  ?.label ??
                              'All accounts',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final value = await showSearchPicker<int>(
                      context: context,
                      title: 'Account',
                      hint: 'Search accounts',
                      selected: accountId ?? -1,
                      allowNone: true,
                      noneLabel: 'All accounts',
                      noneValue: -1,
                      entries: [
                        for (final account in accounts)
                          PickerEntry(
                            value: account.id,
                            label: account.label,
                            subtitle: account.currency,
                            icon: iconForAccountType(account.type),
                          ),
                      ],
                    );
                    if (value == null) return;
                    setState(() => accountId = value == -1 ? null : value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    final savedTitle = title.text.trim();
    final savedDescription = description.text.trim();
    disposeAfterDialog([title, description]);
    if (result != true || savedTitle.isEmpty) return;
    final account = accounts.where((a) => a.id == accountId).firstOrNull;
    final id = await ref
        .read(repositoryProvider)
        .insertBudget(
          title: savedTitle,
          description: savedDescription,
          accountId: accountId,
          currency: account?.currency ?? settings.homeCurrency,
        );
    ref.invalidate(budgetsProvider);
    if (context.mounted) context.push('/budget?id=$id');
  }
}

class _BudgetCard extends ConsumerWidget {
  const _BudgetCard({required this.budget});

  final Budget budget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/budget?id=${budget.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(
                  Icons.savings_outlined,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      budget.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatMonth(DateTime(now.year, now.month))} • '
                      '${formatMoney(budget.totalBudget, budget.currency)} planned',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'More',
                icon: const Icon(Icons.more_vert),
                onPressed: () async {
                  final action = await showActionSheet<String>(
                    context,
                    title: budget.title,
                    actions: const [
                      SheetAction(
                        value: 'delete',
                        label: 'Delete',
                        icon: Icons.delete_outline,
                        destructive: true,
                      ),
                    ],
                  );
                  if (action != 'delete' || !context.mounted) return;
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: Text('Delete ${budget.title}?'),
                      content: const Text(
                        'The budget and its allocations will be deleted.',
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
                    await ref.read(repositoryProvider).deleteBudget(budget.id);
                    ref.invalidate(budgetsProvider);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
