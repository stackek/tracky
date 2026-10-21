import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/currency.dart';
import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../core/ui_utils.dart';
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
  final Set<int> _selectedIds = {};
  bool get _selectionMode => _selectedIds.isNotEmpty;

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
    final rates = ref.watch(exchangeRatesProvider).value ?? const <String, double>{};
    final activeAccounts = accounts.where((a) => !a.isArchived).toList();
    final totalHome = activeAccounts.fold<int>(
      0,
      (sum, account) =>
          sum +
          (account.excludeFromTotals
              ? 0
              : (account.balance * (rates[account.currency] ?? 1)).round()),
    );
    final headerCurrency = selectedAccount?.currency ?? settings.homeCurrency;
    final allItems = transactions.value ?? const <Transaction>[];
    final selectedItems = allItems
        .where((item) => _selectedIds.contains(item.id))
        .toList();
    final selectedTotal = selectedItems.fold<int>(0, (sum, item) {
      final rate = item.currency == headerCurrency
          ? 1.0
          : rates[item.currency] ?? 1.0;
      return sum + (item.amount * rate).round();
    });
    final headerBalance = _selectionMode
        ? selectedTotal
        : (selectedAccount?.balance ?? totalHome);
    final headerLabel = _selectionMode
        ? '${selectedItems.length} selected'
        : (selectedAccount?.label ?? 'All accounts');
    final periodLabel = filter.period == TransactionPeriod.custom
        ? '${filter.from == null ? '' : formatShortDate(filter.from!)}'
              '${filter.to == null ? '' : ' – ${formatShortDate(filter.to!)}'}'
        : filter.period.label;

    return PopScope(
      canPop: !_showSearch && !_selectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_showSearch) {
          _closeSearch();
        } else if (_selectionMode) {
          setState(_selectedIds.clear);
        }
      },
      child: Scaffold(
        appBar: AppBar(
        title: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _selectionMode
              ? null
              : () => _showFundsSheet(context, selectedAccount),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  headerLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  formatMoney(headerBalance, headerCurrency),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: _selectionMode
            ? [
                IconButton(
                  tooltip: 'Clear selection',
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(_selectedIds.clear),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Actions',
                  onSelected: (value) {
                    if (value == 'delete') {
                      _deleteSelected();
                    } else if (value == 'remap') {
                      _showRemapSheet(context);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'delete',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline),
                        title: Text('Delete'),
                      ),
                    ),
                    PopupMenuItem(
                      value: 'remap',
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.edit_outlined),
                        title: Text('Remap'),
                      ),
                    ),
                  ],
                ),
              ]
            : [
                IconButton(
                  tooltip: 'Search',
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () {
              if (_showSearch) {
                _closeSearch();
              } else {
                setState(() => _showSearch = true);
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
      floatingActionButton: accounts.isEmpty || _selectionMode
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
                        selectedIds: _selectedIds,
                        onToggleSelection: (id) => setState(() {
                          if (!_selectedIds.remove(id)) {
                            _selectedIds.add(id);
                          }
                        }),
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
      ),
    );
  }

  void _closeSearch() {
    setState(() => _showSearch = false);
    _searchController.clear();
    _searchFocus.unfocus();
    ref.read(transactionFilterProvider.notifier).setSearch('');
  }

  Future<void> _deleteSelected() async {
    final ids = Set<int>.from(_selectedIds);
    if (ids.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${ids.length} transactions?'),
        content: const Text('This action cannot be undone.'),
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
    final repo = ref.read(repositoryProvider);
    for (final id in ids) {
      await repo.deleteTransaction(id);
    }
    if (!mounted) return;
    setState(_selectedIds.clear);
    invalidateTransactionData(ref);
  }

  Future<void> _showRemapSheet(BuildContext context) async {
    if (_selectedIds.isEmpty) return;
    final accounts =
        (await ref.read(repositoryProvider).activeAccounts());
    if (!context.mounted) return;
    final payees = ref.read(payeesProvider).value ?? const <Payee>[];
    final methods =
        ref.read(paymentMethodsProvider).value ?? const <PaymentMethod>[];
    final categories =
        ref.read(categoriesProvider).value ?? const <Category>[];
    final settings = ref.read(settingsProvider);
    final home = settings.homeCurrency;
    int? accountId;
    int? categoryId;
    var clearCategory = false;
    int? payeeId;
    var clearPayee = false;
    int? methodId;
    var clearMethod = false;
    DateTime? date;
    String? status;
    var clearComment = false;
    final noteController = TextEditingController();
    final amountController = TextEditingController();
    var applied = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          String labelForAccount() {
            if (accountId == null) return 'Leave unchanged';
            return accounts
                    .where((account) => account.id == accountId)
                    .firstOrNull
                    ?.label ??
                'Leave unchanged';
          }

          String labelForCategory() {
            if (clearCategory) return 'Clear category';
            if (categoryId == null) return 'Leave unchanged';
            return categories
                    .where((category) => category.id == categoryId)
                    .firstOrNull
                    ?.displayPath ??
                'Leave unchanged';
          }

          String labelForPayee() {
            if (clearPayee) return 'Clear payee';
            if (payeeId == null) return 'Leave unchanged';
            return payees
                    .where((payee) => payee.id == payeeId)
                    .firstOrNull
                    ?.name ??
                'Leave unchanged';
          }

          String labelForMethod() {
            if (clearMethod) return 'Clear payment method';
            if (methodId == null) return 'Leave unchanged';
            return methods
                    .where((method) => method.id == methodId)
                    .firstOrNull
                    ?.displayName ??
                'Leave unchanged';
          }

          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Remap ${_selectedIds.length} transactions',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: const Text('Account'),
                    subtitle: Text(labelForAccount()),
                    onTap: () async {
                      final value = await showSearchPicker<int>(
                        context: context,
                        title: 'Account',
                        hint: 'Search accounts',
                        selected: accountId ?? -1,
                        allowNone: true,
                        noneValue: -1,
                        noneLabel: 'Leave unchanged',
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
                      setSheetState(
                        () => accountId = value == -1 ? null : value,
                      );
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.category_outlined),
                    title: const Text('Category'),
                    subtitle: Text(labelForCategory()),
                    onTap: () async {
                      final value = await showSearchPicker<int>(
                        context: context,
                        title: 'Category',
                        hint: 'Search categories',
                        selected: clearCategory ? -2 : (categoryId ?? -1),
                        entries: [
                          const PickerEntry(
                            value: -1,
                            label: 'Leave unchanged',
                            icon: Icons.remove_circle_outline,
                          ),
                          const PickerEntry(
                            value: -2,
                            label: 'Clear category',
                            icon: Icons.block,
                          ),
                          for (final category in categories)
                            PickerEntry(
                              value: category.id,
                              label: category.displayPath,
                              icon: iconForCategory(category.icon),
                              color: colorFromDb(category.color),
                            ),
                        ],
                      );
                      if (value == null) return;
                      setSheetState(() {
                        if (value == -1) {
                          categoryId = null;
                          clearCategory = false;
                        } else if (value == -2) {
                          categoryId = null;
                          clearCategory = true;
                        } else {
                          categoryId = value;
                          clearCategory = false;
                        }
                      });
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: const Text('Payee'),
                    subtitle: Text(labelForPayee()),
                    onTap: () async {
                      final value = await showSearchPicker<int>(
                        context: context,
                        title: 'Payee',
                        hint: 'Search payees',
                        selected: clearPayee ? -2 : (payeeId ?? -1),
                        entries: [
                          const PickerEntry(
                            value: -1,
                            label: 'Leave unchanged',
                            icon: Icons.remove_circle_outline,
                          ),
                          const PickerEntry(
                            value: -2,
                            label: 'Clear payee',
                            icon: Icons.block,
                          ),
                          for (final payee in payees)
                            PickerEntry(
                              value: payee.id,
                              label: payee.name,
                              subtitle: payee.iban,
                              icon: Icons.person_outline,
                            ),
                        ],
                      );
                      if (value == null) return;
                      setSheetState(() {
                        if (value == -1) {
                          payeeId = null;
                          clearPayee = false;
                        } else if (value == -2) {
                          payeeId = null;
                          clearPayee = true;
                        } else {
                          payeeId = value;
                          clearPayee = false;
                        }
                      });
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.payment),
                    title: const Text('Payment method'),
                    subtitle: Text(labelForMethod()),
                    onTap: () async {
                      final value = await showSearchPicker<int>(
                        context: context,
                        title: 'Payment method',
                        hint: 'Search payment methods',
                        selected: clearMethod ? -2 : (methodId ?? -1),
                        entries: [
                          const PickerEntry(
                            value: -1,
                            label: 'Leave unchanged',
                            icon: Icons.remove_circle_outline,
                          ),
                          const PickerEntry(
                            value: -2,
                            label: 'Clear payment method',
                            icon: Icons.block,
                          ),
                          for (final method in methods)
                            PickerEntry(
                              value: method.id,
                              label: method.displayName,
                              icon: iconForPaymentMethod(method.icon),
                            ),
                        ],
                      );
                      if (value == null) return;
                      setSheetState(() {
                        if (value == -1) {
                          methodId = null;
                          clearMethod = false;
                        } else if (value == -2) {
                          methodId = null;
                          clearMethod = true;
                        } else {
                          methodId = value;
                          clearMethod = false;
                        }
                      });
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event),
                    title: const Text('Date'),
                    subtitle: Text(
                      date == null ? 'Leave unchanged' : formatShortDate(date!),
                    ),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setSheetState(() => date = picked);
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.check_circle_outline),
                    title: const Text('Status'),
                    subtitle: Text(status ?? 'Leave unchanged'),
                    onTap: () async {
                      final value = await showActionSheet<String>(
                        context,
                        title: 'Status',
                        actions: const [
                          SheetAction(
                            value: 'KEEP',
                            label: 'Leave unchanged',
                            icon: Icons.remove_circle_outline,
                          ),
                          SheetAction(
                            value: 'UNRECONCILED',
                            label: 'Unreconciled',
                            icon: Icons.radio_button_unchecked,
                          ),
                          SheetAction(
                            value: 'CLEARED',
                            label: 'Cleared',
                            icon: Icons.check_circle_outline,
                          ),
                          SheetAction(
                            value: 'RECONCILED',
                            label: 'Reconciled',
                            icon: Icons.verified_outlined,
                          ),
                          SheetAction(
                            value: 'VOID',
                            label: 'Void',
                            icon: Icons.cancel_outlined,
                          ),
                        ],
                      );
                      if (value == null) return;
                      setSheetState(
                        () => status = value == 'KEEP' ? null : value,
                      );
                    },
                  ),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Note',
                      helperText: 'Leave empty to keep existing notes',
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Clear notes'),
                    value: clearComment,
                    onChanged: (value) =>
                        setSheetState(() => clearComment = value ?? false),
                  ),
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: InputDecoration(
                      labelText: 'Amount',
                      helperText:
                          'Leave empty to keep amounts. Applied per '
                          'transaction in its own currency.',
                      suffixText: home,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () async {
                            final amount = amountController.text.trim().isEmpty
                                ? null
                                : parseAmountToMinor(
                                    amountController.text,
                                    home,
                                  );
                            await ref
                                .read(repositoryProvider)
                                .remapTransactions(
                                  _selectedIds,
                                  accountId: accountId,
                                  categoryId: categoryId,
                                  clearCategory: clearCategory,
                                  payeeId: payeeId,
                                  clearPayee: clearPayee,
                                  methodId: methodId,
                                  clearMethod: clearMethod,
                                  date: date,
                                  crStatus: status,
                                  comment: noteController.text.trim().isEmpty
                                      ? null
                                      : noteController.text.trim(),
                                  clearComment: clearComment,
                                  amount: amount,
                                );
                            if (!context.mounted) return;
                            applied = true;
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
          );
        },
      ),
    );
    if (mounted && applied) {
      setState(_selectedIds.clear);
      invalidateTransactionData(ref);
    }
    disposeAfterDialog([noteController, amountController]);
  }

  Future<void> _showFundsSheet(
    BuildContext context,
    Account? selectedAccount,
  ) async {
    final settings = ref.read(settingsProvider);
    final home = settings.homeCurrency;
    final rates =
        (await ref.read(repositoryProvider).exchangeRatesTo(home));
    final accounts = (await ref.read(repositoryProvider).accounts())
        .where((account) => !account.isArchived)
        .toList();
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        if (selectedAccount != null) {
          final rate = rates[selectedAccount.currency] ?? 1;
          final homeBalance = (selectedAccount.balance * rate).round();
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    selectedAccount.label,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Current funds',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    formatMoney(
                      selectedAccount.balance,
                      selectedAccount.currency,
                    ),
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 16),
                  if (selectedAccount.currency != home) ...[
                    _FundsRow(
                      label: 'Exchange rate',
                      value:
                          '1 ${selectedAccount.currency} = '
                          '${formatRate(rate)} $home',
                    ),
                    const SizedBox(height: 8),
                    _FundsRow(
                      label: 'In $home',
                      value: formatMoney(homeBalance, home),
                      emphasize: true,
                    ),
                  ] else
                    _FundsRow(
                      label: 'Default currency',
                      value: home,
                    ),
                ],
              ),
            ),
          );
        }
        final active = accounts;
        final total = active.fold<int>(
          0,
          (sum, account) =>
              sum +
              (account.excludeFromTotals
                  ? 0
                  : (account.balance * (rates[account.currency] ?? 1)).round()),
        );
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.92,
          builder: (context, controller) => SafeArea(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text(
                  'Account funds',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Total in $home',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  formatMoney(total, home),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                for (final account in active) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: colorFromDb(
                        account.color,
                      ).withValues(alpha: 0.18),
                      child: Icon(
                        iconForAccountType(account.type),
                        color: colorFromDb(account.color),
                      ),
                    ),
                    title: Text(account.label),
                    subtitle: Text(account.typeDisplayName),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatMoney(account.balance, account.currency),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (account.currency != home)
                          Text(
                            '≈ ${formatMoney((account.balance * (rates[account.currency] ?? 1)).round(), home)}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                ],
              ],
            ),
          ),
        );
      },
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
    var period = filter.period;
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
              DropdownButtonFormField<TransactionPeriod>(
                initialValue: period,
                decoration: const InputDecoration(
                  labelText: 'Period',
                  prefixIcon: Icon(Icons.calendar_month_outlined),
                ),
                items: [
                  for (final value in TransactionPeriod.values)
                    DropdownMenuItem(value: value, child: Text(value.label)),
                ],
                onChanged: (value) {
                  if (value != null) setModalState(() => period = value);
                },
              ),
              const SizedBox(height: 8),
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
                        if (picked != null) {
                          setModalState(() {
                            from = picked;
                            period = TransactionPeriod.custom;
                          });
                        }
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
                        if (picked != null) {
                          setModalState(() {
                            to = picked;
                            period = TransactionPeriod.custom;
                          });
                        }
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
                        if (period == TransactionPeriod.custom) {
                          notifier.setDates(from, to);
                        } else {
                          notifier.setPeriod(period);
                        }
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

class _FundsRow extends StatelessWidget {
  const _FundsRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ],
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
    required this.selectedIds,
    required this.onToggleSelection,
    required this.onRefresh,
  });

  final List<Transaction> items;
  final String currency;
  final String periodLabel;
  final PeriodTotals? periodTotals;
  final CategoryTotal? topCategory;
  final Set<int> selectedIds;
  final ValueChanged<int> onToggleSelection;
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
              itemBuilder: (context, index) {
                final transaction = grouped[key]![index];
                return _TransactionTile(
                  transaction: transaction,
                  accountColor: accountColors[transaction.accountId],
                  selectionMode: selectedIds.isNotEmpty,
                  selected: selectedIds.contains(transaction.id),
                  onToggleSelection: () => onToggleSelection(transaction.id),
                );
              },
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
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
  const _TransactionTile({
    required this.transaction,
    this.accountColor,
    required this.selectionMode,
    required this.selected,
    required this.onToggleSelection,
  });

  final Transaction transaction;
  final int? accountColor;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onToggleSelection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isTransfer = transaction.isTransfer;
    final accountAccent = accountColor == null
        ? null
        : colorFromDb(accountColor);
    final amountColor = isTransfer
        ? theme.colorScheme.tertiary
        : transaction.amount < 0
        ? theme.colorScheme.error
        : theme.brightness == Brightness.dark
        ? const Color(0xFF81C784)
        : const Color(0xFF2E7D32);
    final categoryColor = isTransfer
        ? theme.colorScheme.tertiary
        : colorFromDb(transaction.categoryColor);

    return ListTile(
        selected: selected,
        selectedTileColor: theme.colorScheme.primaryContainer.withValues(
          alpha: 0.35,
        ),
        onTap: selectionMode
            ? onToggleSelection
            : () => context.push('/edit?tx=${transaction.id}'),
        onLongPress: onToggleSelection,
        leading: CircleAvatar(
          backgroundColor: isTransfer
              ? theme.colorScheme.tertiaryContainer
              : categoryColor.withValues(alpha: 0.18),
          child: Icon(
            selected
                ? Icons.check
                : isTransfer
                ? Icons.swap_horiz
                : iconForCategory(transaction.categoryIcon),
            color: selected
                ? theme.colorScheme.primary
                : isTransfer
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
            color: isTransfer ? null : accountAccent,
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
                color: amountColor,
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
      );
  }
}
