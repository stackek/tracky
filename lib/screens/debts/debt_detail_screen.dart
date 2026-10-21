import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/currency.dart';
import '../../core/dates.dart';
import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/search_picker.dart';

class DebtDetailScreen extends ConsumerStatefulWidget {
  const DebtDetailScreen({super.key, required this.debtId});

  final int debtId;

  @override
  ConsumerState<DebtDetailScreen> createState() => _DebtDetailScreenState();
}

class _DebtDetailScreenState extends ConsumerState<DebtDetailScreen> {
  Debt? _debt;
  bool _loading = true;
  List<Transaction> _transactions = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(repositoryProvider);
    final debt = await repo.debt(widget.debtId);
    final transactions = debt == null
        ? const <Transaction>[]
        : await repo.debtTransactions(debt.id);
    if (!mounted) return;
    setState(() {
      _debt = debt;
      _transactions = transactions;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final debt = _debt;
    return Scaffold(
      appBar: AppBar(
        title: Text(debt?.label ?? 'Debt'),
        actions: [
          if (debt != null)
            IconButton(
              tooltip: debt.isArchived ? 'Unarchive debt' : 'Archive debt',
              icon: Icon(
                debt.isArchived
                    ? Icons.unarchive_outlined
                    : Icons.archive_outlined,
              ),
              onPressed: _toggleArchive,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : debt == null
          ? const Center(child: Text('Debt not found'))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                children: [
                  Card(
                    elevation: 0,
                    color: theme.colorScheme.surfaceContainerLow,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (debt.payeeName != null)
                            Text(
                              debt.payeeName!,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          if (debt.description.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(debt.description),
                          ],
                          const SizedBox(height: 16),
                          _DetailRow(
                            label: 'Current balance',
                            value: formatMoney(
                              debt.currentBalance,
                              debt.currency,
                            ),
                          ),
                          _DetailRow(
                            label: 'Date',
                            value: formatShortDate(debt.date),
                          ),
                          _DetailRow(
                            label: 'Status',
                            value: debt.isArchived
                                ? 'Archived'
                                : debt.currentBalance == 0
                                ? 'Settled'
                                : 'Open',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Transactions',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const SizedBox(height: 8),
                  if (_transactions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: Text(
                          'No transactions assigned to this debt.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  else
                    for (final transaction in _transactions)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.receipt_long_outlined),
                        title: Text(transaction.title),
                        subtitle: Text(
                          transaction.subtitle.isEmpty
                              ? formatShortDate(transaction.date)
                              : '${formatShortDate(transaction.date)} • '
                                    '${transaction.subtitle}',
                        ),
                        trailing: Text(
                          formatMoney(transaction.amount, transaction.currency),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        onTap: () async {
                          await context.push('/edit?tx=${transaction.id}');
                          if (mounted) _load();
                        },
                      ),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                    onPressed: _removeDebt,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Delete debt'),
                  ),
                ],
              ),
            ),
    );
  }

  Future<void> _toggleArchive() async {
    final debt = _debt;
    if (debt == null) return;
    await ref
        .read(repositoryProvider)
        .setDebtArchived(debt.id, !debt.isArchived);
    ref.invalidate(debtsProvider);
    if (mounted) _load();
  }

  Future<void> _removeDebt() async {
    final debt = _debt;
    if (debt == null) return;
    final repo = ref.read(repositoryProvider);
    final transactions = await repo.debtTransactions(debt.id);
    if (!mounted) return;

    if (transactions.isEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete ${debt.label}?'),
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
      await _completeRemoval(DebtRemovalAction.detach, message: 'Debt deleted');
      return;
    }

    final action = await showActionSheet<DebtRemovalAction>(
      context,
      title:
          'Delete ${debt.label}? What about its ${transactions.length} transactions?',
      actions: const [
        SheetAction(
          value: DebtRemovalAction.deleteTransactions,
          label: 'Delete transactions',
          icon: Icons.delete_outline,
          destructive: true,
        ),
        SheetAction(
          value: DebtRemovalAction.reassign,
          label: 'Reassign to another debt',
          icon: Icons.swap_horiz,
        ),
        SheetAction(
          value: DebtRemovalAction.detach,
          label: 'Leave transactions, remove debt',
          icon: Icons.link_off,
        ),
      ],
    );
    if (action == null || !mounted) return;

    if (action == DebtRemovalAction.deleteTransactions) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete ${transactions.length} transactions?'),
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
      await _completeRemoval(
        DebtRemovalAction.deleteTransactions,
        message: 'Debt and transactions deleted',
      );
      return;
    }

    if (action == DebtRemovalAction.reassign) {
      final debts = await repo.debts();
      if (!mounted) return;
      final target = await showSearchPicker<int>(
        context: context,
        title: 'Reassign to debt',
        hint: 'Search debts',
        selected: -1,
        entries: [
          for (final item in debts)
            if (item.id != debt.id)
              PickerEntry(
                value: item.id,
                label: item.label,
                subtitle: item.payeeName,
                icon: Icons.handshake_outlined,
              ),
        ],
      );
      if (target == null) return;
      await _completeRemoval(
        DebtRemovalAction.reassign,
        targetDebtId: target,
        message: 'Transactions reassigned',
      );
      return;
    }

    await _completeRemoval(
      DebtRemovalAction.detach,
      message: 'Debt removed, transactions kept',
    );
  }

  Future<void> _completeRemoval(
    DebtRemovalAction action, {
    int? targetDebtId,
    required String message,
  }) async {
    await ref
        .read(repositoryProvider)
        .removeDebt(widget.debtId, action: action, targetDebtId: targetDebtId);
    ref.invalidate(debtsProvider);
    invalidateTransactionData(ref);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).pop();
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
