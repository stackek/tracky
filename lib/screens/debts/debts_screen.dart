import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/currency.dart';
import '../../core/dates.dart';
import '../../core/ui_utils.dart';
import '../../models/models.dart';
import '../../providers.dart';
import '../../widgets/search_picker.dart';

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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addDebt,
        icon: const Icon(Icons.add),
        label: const Text('New debt'),
      ),
      appBar: AppBar(
        title: Text(_showArchived ? 'Archived debts' : 'Debts'),
        actions: [
          IconButton(
            tooltip: _showArchived
                ? 'Show active debts'
                : 'Show archived debts',
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
                      : 'No debts yet.\nCreate a debt and assign transactions '
                            'to track what a payee owes you or what you owe them.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(debtsProvider),
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: visible.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) => _DebtTile(debt: visible[index]),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) =>
            Center(child: Text('Could not load debts:\n$error')),
      ),
    );
  }

  Future<void> _addDebt() async {
    final labelController = TextEditingController();
    final descriptionController = TextEditingController();
    final payees = ref.read(payeesProvider).value ?? const <Payee>[];
    final home = ref.read(settingsProvider).homeCurrency;
    int? payeeId;
    var date = DateTime.now();
    var error = '';
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final payee = payees.where((item) => item.id == payeeId).firstOrNull;
          return AlertDialog(
            title: const Text('New debt'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: labelController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                  const SizedBox(height: 8),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.person_outline),
                    title: const Text('Payee'),
                    subtitle: Text(payee?.name ?? 'None'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final value = await showSearchPicker<int>(
                        context: context,
                        title: 'Payee',
                        hint: 'Search payees',
                        selected: payeeId ?? -1,
                        allowNone: true,
                        noneValue: -1,
                        noneLabel: 'None',
                        entries: [
                          for (final item in payees)
                            PickerEntry(
                              value: item.id,
                              label: item.name,
                              subtitle: item.description,
                              icon: Icons.person_outline,
                            ),
                        ],
                      );
                      if (value == null) return;
                      setDialogState(
                        () => payeeId = value == -1 ? null : value,
                      );
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event),
                    title: const Text('Date'),
                    subtitle: Text(formatShortDate(date)),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setDialogState(() => date = picked);
                      }
                    },
                  ),
                  TextField(
                    controller: descriptionController,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Description'),
                  ),
                  if (error.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (labelController.text.trim().isEmpty) {
                    setDialogState(() => error = 'Enter a name.');
                    return;
                  }
                  Navigator.of(context).pop(true);
                },
                child: const Text('Create'),
              ),
            ],
          );
        },
      ),
    );
    final label = labelController.text.trim();
    final description = descriptionController.text.trim();
    disposeAfterDialog([labelController, descriptionController]);
    if (result != true || label.isEmpty) return;
    await ref
        .read(repositoryProvider)
        .insertDebt(
          payeeId: payeeId,
          label: label,
          description: description,
          amount: 0,
          date: date,
          currency: home,
        );
    ref.invalidate(debtsProvider);
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
