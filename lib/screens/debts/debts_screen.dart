import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/currency.dart';
import '../../core/dates.dart';
import '../../models/models.dart';
import '../../providers.dart';

class DebtsScreen extends ConsumerStatefulWidget {
  const DebtsScreen({super.key});

  @override
  ConsumerState<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends ConsumerState<DebtsScreen> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final debts = ref.watch(debtsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived ? 'Archived debts' : 'Debts'),
        actions: [
          IconButton(
            tooltip: _showArchived ? 'Show active debts' : 'Show archived debts',
            icon: Icon(
              _showArchived ? Icons.inbox_outlined : Icons.archive_outlined,
            ),
            onPressed: () => setState(() => _showArchived = !_showArchived),
          ),
        ],
      ),
      body: debts.when(
        data: (items) {
          final visible = items
              .where((debt) => debt.isArchived == _showArchived)
              .toList();
          if (visible.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  _showArchived
                      ? 'No archived debts.'
                      : 'No debts yet.\nMark a transaction as written to debt '
                            'to track what a payee owes you or what you owe them.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(debtsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 32),
              itemCount: visible.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1),
              itemBuilder: (context, index) =>
                  _DebtTile(debt: visible[index]),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            Center(child: Text('Could not load debts:\n$error')),
      ),
    );
  }
}

class _DebtTile extends StatelessWidget {
  const _DebtTile({required this.debt});

  final Debt debt;

  @override
  Widget build(BuildContext context) {
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
        child: Icon(
          debt.isArchived ? Icons.archive_outlined : Icons.handshake_outlined,
          color: color,
        ),
      ),
      title: Text(
        debt.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${debt.payeeName ?? 'No payee'} • ${formatShortDate(debt.date)}'
        '${debt.isArchived ? ' • Archived' : ''}',
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
      onTap: () => context.push('/debt?id=${debt.id}'),
    );
  }
}
