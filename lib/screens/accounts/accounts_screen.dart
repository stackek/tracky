import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/currency.dart';
import '../../core/icons.dart';
import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/search_picker.dart';

enum _AccountSort {
  nameAsc('Name (A–Z)'),
  nameDesc('Name (Z–A)'),
  lastDesc('Last transaction (newest)'),
  lastAsc('Last transaction (oldest)'),
  amountDesc('Amount left (high to low)'),
  amountAsc('Amount left (low to high)');

  const _AccountSort(this.label);

  final String label;
}

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  _AccountSort _sort = _AccountSort.nameAsc;

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider);
    final lastTransactions =
        ref.watch(accountLastTransactionProvider).value ??
        const <int, DateTime>{};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            tooltip: 'Sort accounts',
            icon: const Icon(Icons.sort),
            onPressed: () => _pickSort(context),
          ),
          IconButton(
            tooltip: 'Add account',
            icon: const Icon(Icons.add),
            onPressed: () => context.push('/account/edit'),
          ),
        ],
      ),
      body: accounts.when(
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No accounts yet',
              message:
                  'Create a cash, bank or credit card account to start tracking.',
              actionLabel: 'Add account',
              onAction: () => context.push('/account/edit'),
            );
          }
          final sorted = [...items]..sort((a, b) {
            switch (_sort) {
              case _AccountSort.nameAsc:
                return a.label.toLowerCase().compareTo(b.label.toLowerCase());
              case _AccountSort.nameDesc:
                return b.label.toLowerCase().compareTo(a.label.toLowerCase());
              case _AccountSort.lastDesc:
                return _lastSeen(lastTransactions, b).compareTo(
                  _lastSeen(lastTransactions, a),
                );
              case _AccountSort.lastAsc:
                return _lastSeen(lastTransactions, a).compareTo(
                  _lastSeen(lastTransactions, b),
                );
              case _AccountSort.amountDesc:
                return b.balance.compareTo(a.balance);
              case _AccountSort.amountAsc:
                return a.balance.compareTo(b.balance);
            }
          });
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(accountsProvider);
              ref.invalidate(accountLastTransactionProvider);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                for (final account in sorted) ...[
                  _AccountCard(account: account),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            Center(child: Text('Could not load accounts:\n$error')),
      ),
    );
  }

  int _lastSeen(Map<int, DateTime> values, Account account) =>
      values[account.id]?.millisecondsSinceEpoch ?? 0;

  Future<void> _pickSort(BuildContext context) async {
    final value = await showSearchPicker<_AccountSort>(
      context: context,
      title: 'Sort accounts by',
      hint: 'Search sorting options',
      selected: _sort,
      entries: [
        for (final sort in _AccountSort.values)
          PickerEntry(
            value: sort,
            label: sort.label,
            icon: Icons.sort,
          ),
      ],
    );
    if (value != null) setState(() => _sort = value);
  }
}

class _AccountCard extends ConsumerWidget {
  const _AccountCard({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final color = colorFromDb(account.color);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/account/edit?id=${account.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: color.withValues(alpha: 0.18),
                child: Icon(iconForAccountType(account.type), color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            account.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (account.isFavorite)
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.star, size: 16, color: Colors.amber),
                          ),
                        if (account.isArchived)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Archived',
                                style: theme.textTheme.labelSmall,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${account.typeDisplayName} • ${account.currency}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(account.balance, account.currency),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: account.balance < 0
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    'Balance',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              IconButton(
                tooltip: 'Delete account',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _deleteAccount(context, ref),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${account.label}?'),
        content: const Text(
          'All transactions in this account will be deleted. '
          'This cannot be undone.',
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
      await ref.read(repositoryProvider).deleteAccount(account.id);
      invalidateTransactionData(ref);
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $error')),
        );
      }
    }
  }
}
