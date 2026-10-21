import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/currency.dart';
import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/search_picker.dart';
import 'transaction_editor_screen.dart' show noCategoryId, showCategoryPicker;

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  bool _showSearch = false;

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final filter = ref.watch(transactionFilterProvider);
    final transactions = ref.watch(transactionsProvider);
    final topCategory = ref.watch(topCategoryProvider).value;
    final periodTotals = ref.watch(periodTotalsProvider).value;
    final settings = ref.watch(settingsProvider);
    final selectedAccount = filter.accountId == null
        ? null
        : accounts.where((a) => a.id == filter.accountId).firstOrNull;
    final currency = selectedAccount?.currency ?? settings.homeCurrency;
    final periodLabel = filter.period == TransactionPeriod.custom
        ? '${filter.from == null ? '' : formatShortDate(filter.from!)}'
              '${filter.to == null ? '' : ' – ${formatShortDate(filter.to!)}'}'
        : filter.period.label;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          IconButton(
            tooltip: 'Search',
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () {
              final show = !_showSearch;
              setState(() => _showSearch = show);
              if (!show) {
                _searchController.clear();
                _searchFocus.unfocus();
                ref.read(transactionFilterProvider.notifier).setSearch('');
              } else {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _searchFocus.requestFocus();
                });
              }
            },
          ),
          IconButton(
            tooltip: 'Filter',
            icon: Badge(
              isLabelVisible:
                  filter.categoryId != null ||
                  filter.payeeId != null ||
                  filter.from != null ||
                  filter.includeArchived,
              child: const Icon(Icons.tune),
            ),
            onPressed: () => _showFilterSheet(context),
          ),
        ],
      ),
      floatingActionButton: accounts.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                final accountId = filter.accountId ?? accounts.first.id;
                context.push('/edit?type=expense&account=$accountId');
              },
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
      body: accounts.isEmpty
          ? EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'Create your first account',
              message:
                  'Accounts hold your transactions. You can create cash, bank '
                  'or credit card accounts.',
              actionLabel: 'Add account',
              onAction: () => context.push('/account/edit'),
            )
          : GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity.abs() < 250) return;
                final ids = <int?>[null, ...accounts.map((a) => a.id)];
                final current = ids.indexOf(filter.accountId);
                if (current < 0) return;
                final next = (current + (velocity < 0 ? 1 : -1)).clamp(
                  0,
                  ids.length - 1,
                );
                if (next != current) {
                  ref
                      .read(transactionFilterProvider.notifier)
                      .setAccount(ids[next]);
                }
              },
              child: Column(
                children: [
                  if (_showSearch)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocus,
                        autofocus: true,
                        decoration: const InputDecoration(
                          hintText: 'Search transactions',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: ref
                            .read(transactionFilterProvider.notifier)
                            .setSearch,
                      ),
                    ),
                  _AccountChips(accounts: accounts, selected: filter.accountId),
                  _PeriodBar(
                    period: filter.period,
                    onChanged: (value) => ref
                        .read(transactionFilterProvider.notifier)
                        .setPeriod(value),
                  ),
                  transactions.when(
                    data: (items) => Expanded(
                      child: _TransactionList(
                        items: items,
                        currency: periodTotals?.currency ?? currency,
                        periodLabel: filter.accountId == null
                            ? '$periodLabel • $currency'
                            : periodLabel,
                        periodTotals: periodTotals,
                        topCategory: topCategory,
                        onRefresh: () async =>
                            ref.invalidate(transactionsProvider),
                      ),
                    ),
                    loading: () => const Expanded(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, stack) => Expanded(
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('Could not load transactions:\n$error'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _showFilterSheet(BuildContext context) async {
    final categories = ref.read(categoriesProvider).value ?? const <Category>[];
    final payees = ref.read(payeesProvider).value ?? const <Payee>[];
    final filter = ref.read(transactionFilterProvider);
    var categoryId = filter.categoryId;
    var payeeId = filter.payeeId;
    var from = filter.from;
    var to = filter.to;
    var includeArchived = filter.includeArchived;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            0,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Filter transactions',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.category_outlined),
                title: const Text('Category'),
                subtitle: Text(
                  categoryId == null
                      ? 'Any category'
                      : categories
                                .where((category) => category.id == categoryId)
                                .firstOrNull
                                ?.displayPath ??
                            'Any category',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final selected = await showCategoryPicker(
                    context,
                    categories,
                    initialId: categoryId,
                    allowNone: true,
                  );
                  if (selected == null) return;
                  setModalState(
                    () =>
                        categoryId = selected == noCategoryId ? null : selected,
                  );
                },
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: const Text('Payee'),
                subtitle: Text(
                  payeeId == null
                      ? 'Any payee'
                      : payees
                                .where((payee) => payee.id == payeeId)
                                .firstOrNull
                                ?.name ??
                            'Any payee',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final selected = await showSearchPicker<int>(
                    context: context,
                    title: 'Payee',
                    hint: 'Search payees',
                    selected: payeeId ?? -1,
                    allowNone: true,
                    noneLabel: 'Any payee',
                    noneValue: -1,
                    entries: [
                      for (final payee in payees)
                        PickerEntry(
                          value: payee.id,
                          label: payee.name,
                          subtitle: payee.iban,
                          icon: Icons.person_outline,
                        ),
                    ],
                  );
                  if (selected == null) return;
                  setModalState(
                    () => payeeId = selected == -1 ? null : selected,
                  );
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event),
                      label: Text(
                        from == null ? 'From date' : formatShortDate(from!),
                      ),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: from ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setModalState(() => from = picked);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.event_available),
                      label: Text(
                        to == null ? 'To date' : formatShortDate(to!),
                      ),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: to ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) setModalState(() => to = picked);
                      },
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include archived'),
                value: includeArchived,
                onChanged: (value) =>
                    setModalState(() => includeArchived = value),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        ref.read(transactionFilterProvider.notifier).clear();
                        Navigator.of(context).pop();
                      },
                      child: const Text('Clear all'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final notifier = ref.read(
                          transactionFilterProvider.notifier,
                        );
                        notifier.setCategory(categoryId);
                        notifier.setPayee(payeeId);
                        notifier.setDates(from, to);
                        notifier.setIncludeArchived(includeArchived);
                        Navigator.of(context).pop();
                      },
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountChips extends ConsumerWidget {
  const _AccountChips({required this.accounts, required this.selected});

  final List<Account> accounts;
  final int? selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: const Text('All'),
              selected: selected == null,
              onSelected: (_) =>
                  ref.read(transactionFilterProvider.notifier).setAccount(null),
            ),
          ),
          for (final account in accounts)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(iconForAccountType(account.type), size: 18),
                label: Text(account.label),
                selected: selected == account.id,
                onSelected: (_) => ref
                    .read(transactionFilterProvider.notifier)
                    .setAccount(account.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _TransactionList extends ConsumerWidget {
  const _TransactionList({
    required this.items,
    required this.currency,
    required this.periodLabel,
    required this.periodTotals,
    required this.topCategory,
    required this.onRefresh,
  });

  final List<Transaction> items;
  final String currency;
  final String periodLabel;
  final PeriodTotals? periodTotals;
  final CategoryTotal? topCategory;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: const [
            SizedBox(height: 100),
            EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'No transactions yet',
              message: 'Tap Add to record your first expense or income.',
            ),
          ],
        ),
      );
    }
    final income = periodTotals?.income ?? 0;
    final expense = periodTotals?.expense ?? 0;
    final accountColors = {
      for (final account
          in ref.watch(accountsProvider).value ?? const <Account>[])
        account.id: account.color,
    };

    final grouped = <String, List<Transaction>>{};
    for (final item in items) {
      final key = sqlDate(item.date);
      grouped.putIfAbsent(key, () => []).add(item);
    }
    final keys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Column(
                children: [
                  _SummaryStrip(
                    income: income,
                    expense: expense,
                    currency: currency,
                    periodLabel: periodLabel,
                  ),
                  if (topCategory != null) ...[
                    const SizedBox(height: 10),
                    _TopCategoryCard(
                      category: topCategory!,
                      currency: currency,
                    ),
                  ],
                ],
              ),
            ),
          ),
          for (final key in keys) ...[
            SliverToBoxAdapter(child: _DayHeader(date: DateTime.parse(key))),
            SliverList.builder(
              itemCount: grouped[key]!.length,
              itemBuilder: (context, index) => _TransactionTile(
                transaction: grouped[key]![index],
                accountColor: accountColors[grouped[key]![index].accountId],
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }
}

class _PeriodBar extends StatelessWidget {
  const _PeriodBar({required this.period, required this.onChanged});

  final TransactionPeriod period;
  final ValueChanged<TransactionPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
      child: Row(
        children: [
          const SizedBox(width: 4),
          Icon(
            Icons.calendar_month_outlined,
            size: 18,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          DropdownButtonHideUnderline(
            child: DropdownButton<TransactionPeriod>(
              value: period,
              isDense: true,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
              items: [
                for (final value in TransactionPeriod.values)
                  if (value != TransactionPeriod.custom ||
                      period == TransactionPeriod.custom)
                    DropdownMenuItem(
                      value: value,
                      enabled: value != TransactionPeriod.custom,
                      child: Text(value.label),
                    ),
              ],
              onChanged: (value) {
                if (value != null) onChanged(value);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TopCategoryCard extends StatelessWidget {
  const _TopCategoryCard({required this.category, required this.currency});

  final CategoryTotal category;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = colorFromDb(category.color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withValues(alpha: 0.18),
            child: Icon(iconForCategory(category.icon), color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Top spending category',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  category.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatMoney(category.amount, currency),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.income,
    required this.expense,
    required this.currency,
    required this.periodLabel,
  });

  final int income;
  final int expense;
  final String currency;
  final String periodLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            periodLabel,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _SummaryItem(
                  label: 'Income',
                  value: formatMoney(income, currency),
                  color: theme.colorScheme.primary,
                ),
              ),
              Container(
                width: 1,
                height: 34,
                color: theme.colorScheme.outlineVariant,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: _SummaryItem(
                    label: 'Expenses',
                    value: formatMoney(expense, currency),
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        formatDayHeader(date),
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _TransactionTile extends ConsumerWidget {
  const _TransactionTile({required this.transaction, this.accountColor});

  final Transaction transaction;
  final int? accountColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isTransfer = transaction.isTransfer;
    final isIncome = transaction.amount > 0;
    final accountAccent = accountColor == null
        ? null
        : colorFromDb(accountColor);
    final color = isTransfer
        ? theme.colorScheme.tertiary
        : accountAccent ??
              (isIncome
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurface);
    final categoryColor = isTransfer
        ? theme.colorScheme.tertiary
        : accountAccent ?? colorFromDb(transaction.categoryColor);

    return Dismissible(
      key: ValueKey('tx-${transaction.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.error,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: theme.colorScheme.onError),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Delete transaction?'),
                content: Text(
                  isTransfer
                      ? 'Both sides of this transfer will be deleted.'
                      : 'This action cannot be undone.',
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
            ) ??
            false;
      },
      onDismissed: (_) async {
        try {
          await ref.read(repositoryProvider).deleteTransaction(transaction.id);
          invalidateTransactionData(ref);
        } catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Could not delete: $error')));
          }
        }
      },
      child: ListTile(
        onTap: () => context.push('/edit?tx=${transaction.id}'),
        leading: CircleAvatar(
          backgroundColor: isTransfer
              ? theme.colorScheme.tertiaryContainer
              : categoryColor.withValues(alpha: 0.18),
          child: Icon(
            isTransfer
                ? Icons.swap_horiz
                : iconForCategory(transaction.categoryIcon),
            color: isTransfer
                ? theme.colorScheme.onTertiaryContainer
                : categoryColor,
          ),
        ),
        title: Text(
          transaction.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            decoration: transaction.isVoid ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: transaction.subtitle.isEmpty
            ? null
            : Text(
                transaction.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatMoney(transaction.amount, transaction.currency),
              style: theme.textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                decoration: transaction.isVoid
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (transaction.attachmentCount > 0)
                  Icon(
                    Icons.attach_file,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                if (transaction.tagIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 3),
                    child: Icon(
                      Icons.sell_outlined,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (transaction.isSplit)
                  Padding(
                    padding: const EdgeInsets.only(left: 3),
                    child: Icon(
                      Icons.call_split,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (transaction.isArchived)
                  Padding(
                    padding: const EdgeInsets.only(left: 3),
                    child: Icon(
                      Icons.archive_outlined,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
