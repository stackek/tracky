import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/currency.dart';
import '../../core/dates.dart';
import '../../models/models.dart';
import '../../providers.dart';

class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debts = ref.watch(debtsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Debts')),
      body: debts.when(
        data: (items) => items.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'No debts yet.\nMark a transaction as written to debt '
                    'to track what a payee owes you or what you owe them.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(debtsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 32),
                  itemCount: items.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) =>
                      _DebtTile(debt: items[index]),
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            Center(child: Text('Could not load debts:\n$error')),
      ),
    );
  }
}

class _DebtTile extends ConsumerWidget {
  const _DebtTile({required this.debt});

  final Debt debt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final balance = debt.currentBalance;
    final color = balance == 0
        ? theme.colorScheme.onSurfaceVariant
        : balance > 0
        ? (theme.brightness == Brightness.dark
              ? const Color(0xFF81C784)
              : const Color(0xFF2E7D32))
        : theme.colorScheme.error;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.16),
        child: Icon(Icons.handshake_outlined, color: color),
      ),
      title: Text(
        debt.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${debt.payeeName ?? 'No payee'} • ${formatShortDate(debt.date)}'
        '${debt.sealed ? ' • Closed' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        formatMoney(balance, debt.currency),
        style: theme.textTheme.titleSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
      onTap: () => _showDetails(context, ref),
    );
  }

  Future<void> _showDetails(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(debt.label, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(debt.payeeName ?? 'No payee'),
              if (debt.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(debt.description),
              ],
              const SizedBox(height: 16),
              _DetailRow(
                label: 'Original amount',
                value: formatMoney(debt.amount, debt.currency),
              ),
              _DetailRow(
                label: 'Current balance',
                value: formatMoney(debt.currentBalance, debt.currency),
              ),
              _DetailRow(
                label: 'Date',
                value: formatShortDate(debt.date),
              ),
              _DetailRow(
                label: 'Status',
                value: debt.sealed
                    ? 'Closed'
                    : debt.currentBalance == 0
                    ? 'Settled'
                    : 'Open',
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete debt?'),
                      content: const Text(
                        'Transactions linked to this debt will be kept, '
                        'but will no longer resolve it.',
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
                  await ref.read(repositoryProvider).deleteDebt(debt.id);
                  ref.invalidate(debtsProvider);
                  ref.invalidate(transactionsProvider);
                  if (context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete debt'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
